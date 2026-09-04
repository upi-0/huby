import
  prologue, context, json,
  strutils, asyncdispatch

import
  models/all, db

import  
  s3presign/main,
  service/hf/[uploadHf, resolveHf],
  service/file/[main, adapter],
  service/owner/main,
  service/storage_repo/main,
  service/[types, implement],
  service/presigned/[utils, general, types]

proc getFileStorageConfig*(impl: FileService, key: string, file: var FileModel): ServiceValue[tuple[s3conf: S3Config, bucket: string, address: string]] =
  let sel = impl.select(key, file)
  if sel.isNone:
    return result.none(404, "File not found")

  if file.storage_repo.isNil:
    return result.none(500, "Storage repository is not assigned to file")

  if file.storage_repo.access_key.len == 0 and file.storage_repo.id > 0:
    let r = impl.conn.selectRepo(file.storage_repo.id, file.storage_repo)
    if r.isNone:
      return result.none(500, "Storage repository not found in database")

  let
    s3conf = file.storage_repo.toS3Config()
    bucket = file.storage_repo.bucket
    address = file.address
  
  implement.some((s3conf: s3conf, bucket: bucket, address: address))

proc handlePutObject*(
    impl: FileService,
    url: string,
    key: string,
    contentLength: int
): ServiceValue[string] =
  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpPut)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  let record = loadRequestRecord(key.split("/")[^1])
  var s3conf: S3Config
  let addrRes = impl.putFile(
    key = key,
    contentLength = contentLength,
    record = record,
    replace = true,
    uploaded = true,
    s3conf = s3conf
  )
  if addrRes.isNone:
    return result.none(addrRes.status, addrRes.errorReason)

  var file = emptyFile()
  let
    cfgRes = impl.getFileStorageConfig(key, file)
    bucket = if cfgRes.isSome: cfgRes.get.bucket else: "exx"
    targetUrl = s3conf.presignPut(bucket, addrRes.get)
  
  implement.some(targetUrl)

proc handleGetObject*(
    impl: FileService,
    url: string,
    key: string
): ServiceValue[string] =
  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpGet)
  
  >> resolve

  var
    file = emptyFile()
    cfgRes = impl.getFileStorageConfig(key, file)
  
  if cfgRes.isNone:
    return result.none(cfgRes.status, cfgRes.errorReason)

  if not file.isUploaded:
    return result.none(404)

  let targetUrl = file.resolve.get.httpUrl
  implement.some(targetUrl)

proc handleHeadObject*(
    impl: FileService,
    url: string,
    key: string
): ServiceValue[string] =
  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpHead)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)
  if cfgRes.isNone:
    return result.none(cfgRes.status, cfgRes.errorReason)

  let targetUrl = cfgRes.get.s3conf.presignHead(cfgRes.get.bucket, cfgRes.get.address)
  implement.some(targetUrl)

proc handleDeleteObject*(
    impl: FileService,
    url: string,
    key: string
): Future[ServiceValue[string]] {.async.} =
  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpDelete)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)
  if cfgRes.isNone:
    return result.none(cfgRes.status, cfgRes.errorReason)

  discard await impl.delete(key)

  let targetUrl = cfgRes.get.s3conf.presignDelete(cfgRes.get.bucket, cfgRes.get.address)
  return implement.some(targetUrl)

proc handleCreateMultipartUpload*(
    impl: FileService,
    url: string,
    key: string,
    contentLength: int
): ServiceValue[string] =
  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpPost)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  let record = loadRequestRecord(key.split("/")[^1])
  var s3conf: S3Config
  let addrRes = impl.putFile(
    key = key,
    contentLength = contentLength,
    record = record,
    replace = true,
    uploaded = false,
    s3conf = s3conf
  )
  if addrRes.isNone:
    return result.none(addrRes.status, addrRes.errorReason)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)
  let bucket = if cfgRes.isSome: cfgRes.get.bucket else: "exx"
  let targetUrl = s3conf.presignCreateMultipartUpload(bucket, addrRes.get)
  implement.some(targetUrl)

proc handlePutPart*(
    impl: FileService,
    url: string,
    key: string,
    uploadId: string,
    partNumber: int
): ServiceValue[string] =
  if uploadId.len == 0:
    return result.none(400, "Missing uploadId parameter")
  if partNumber < 1 or partNumber > MaxParts:
    return result.none(400, "Invalid partNumber: must be between 1 and " & $MaxParts)

  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpPut)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)
  if cfgRes.isNone:
    return result.none(cfgRes.status, cfgRes.errorReason)

  let targetUrl = cfgRes.get.s3conf.presignUploadPart(
    cfgRes.get.bucket,
    cfgRes.get.address,
    uploadId,
    partNumber
  )
  implement.some(targetUrl)

proc handleCompleteMultipartUpload*(
    impl: FileService,
    url: string,
    key: string,
    uploadId: string
): ServiceValue[string] =
  if uploadId.len == 0:
    return result.none(400, "Missing uploadId parameter")

  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpPost)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)
  if cfgRes.isNone:
    return result.none(cfgRes.status, cfgRes.errorReason)

  file.isUploaded = true
  try:
    impl.conn.update(file)
  except DbError:
    return result.none(500, "Failed to update file record")

  let targetUrl = cfgRes.get.s3conf.presignCompleteMultipartUpload(
    cfgRes.get.bucket,
    cfgRes.get.address,
    uploadId
  )
  implement.some(targetUrl)

proc handleAbortMultipartUpload*(
    impl: FileService,
    url: string,
    key: string,
    uploadId: string
): ServiceValue[string] =
  if uploadId.len == 0:
    return result.none(400, "Missing uploadId parameter")

  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpDelete)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)
  if cfgRes.isNone:
    return result.none(cfgRes.status, cfgRes.errorReason)

  file.isDeleted = true
  file.isUploaded = false
  try:
    impl.conn.update(file)
  except DbError:
    discard

  let targetUrl = cfgRes.get.s3conf.presignAbortMultipartUpload(
    cfgRes.get.bucket,
    cfgRes.get.address,
    uploadId
  )
  implement.some(targetUrl)

proc handleListParts*(
    impl: FileService,
    url: string,
    key: string,
    uploadId: string
): ServiceValue[string] =
  if uploadId.len == 0:
    return result.none(400, "Missing uploadId parameter")

  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpGet)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)
  if cfgRes.isNone:
    return result.none(cfgRes.status, cfgRes.errorReason)

  let targetUrl = cfgRes.get.s3conf.presignListParts(
    cfgRes.get.bucket,
    cfgRes.get.address,
    uploadId
  )
  implement.some(targetUrl)

proc s3handler*(ctx: Context) {.async.} =
  ## Worker Proxy S3 Bridge Handler
  ##
  ## Expected payload forwarded by Worker Proxy:
  ## {
  ##    "method": "GET" | "PUT" | "POST" | "DELETE" | "HEAD",
  ##    "url": "http://localhost:6868/<OWNER>/<BUCKET_NAME>/<FILE_KEY>?...",
  ##    "contentLength": "1048576"
  ## }
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Allow-Methods", "GET, PUT, POST, DELETE, HEAD, OPTIONS")
    ctx.response.headers.add("Access-Control-Allow-Headers", "*")

  if ctx.request.reqMethod == HttpOptions:
    await ctx.send("", Http204)
    return

  var payload: JsonNode
  try:
    payload = %*{
      "url": ctx.getQueryParams("url"),
      "contentLength": ctx.getQueryParams("contentLength"),
      "method": ctx.getQueryParams("method")
    }
    echo "QUERY_PARAMS: " & $payload

  except Exception:
    await ctx.send(%*{"error": getCurrentExceptionMsg()}, Http400)
    return

  if not payload.hasKey("url"):
    await ctx.send(%*{"error": "Missing 'url' field in payload"}, Http400)
    return

  let
    url = payload["url"].str
    reqMethod = payload.getOrDefault("method").getStr("GET").toUpperAscii()
    cleanUrl = url.replace("http://").replace("https://").split("?")[0]
    path = cleanUrl.split("/")

  if path.len < 3:
    await ctx.send(%*{"error": "Invalid URL format: expected http://host/owner/bucket/key"}, Http400)
    return

  let
    owner = path[1]
    bucket = path[2]
    id = owner.ownerId()
    impl = newFileService(id.get, bucket)

  discard owner

  if impl.isNone:
    await ctx.send(%*{"error": "Bucket/Garage not found"}, Http404)
    return

  let query = if url.contains("?"): url.split("?")[^1].loadQuery() else: newJObject()

  let uploadId = if query.hasKey("uploadId"): query["uploadId"].getStr()
                 elif payload.hasKey("uploadId"): payload["uploadId"].getStr()
                 else: ""

  let partNumberStr = if query.hasKey("partNumber"): query["partNumber"].getStr()
                      elif payload.hasKey("partNumber"): payload["partNumber"].getStr()
                      else: ""

  let hasUploads = query.hasKey("uploads") or payload.hasKey("uploads")

  let contentLength = block:
    if payload.hasKey("contentLength"):
      try: payload["contentLength"].getStr().parseInt()
      except Exception:
        try: payload["contentLength"].getInt()
        except Exception: 0
    else: 0

  let key = block:
    if path.len > 3:
      path[3 .. ^1].join("/")
    else:
      url.split("/")[^1].split("?")[0]

  var opResult: ServiceValue[string]

  case reqMethod
  of "POST":
    if hasUploads:
      opResult = impl.get.handleCreateMultipartUpload(url, key, contentLength)
    elif uploadId.len > 0:
      opResult = impl.get.handleCompleteMultipartUpload(url, key, uploadId)
    else:
      await ctx.send(%*{"error": "POST request must specify 'uploads' or 'uploadId'"}, Http400)
      return

  of "PUT":
    if partNumberStr.len > 0 and uploadId.len > 0:
      var partNumber = 0
      try:
        partNumber = parseInt(partNumberStr)
      except ValueError:
        await ctx.send(%*{"error": "Invalid partNumber format"}, Http400)
        return
      opResult = impl.get.handlePutPart(url, key, uploadId, partNumber)
    else:
      opResult = impl.get.handlePutObject(url, key, contentLength)

  of "GET":
    if uploadId.len > 0:
      opResult = impl.get.handleListParts(url, key, uploadId)
    else:
      opResult = impl.get.handleGetObject(url, key)

  of "DELETE":
    if uploadId.len > 0:
      opResult = impl.get.handleAbortMultipartUpload(url, key, uploadId)
    else:
      opResult = await impl.get.handleDeleteObject(url, key)

  of "HEAD":
    opResult = impl.get.handleHeadObject(url, key)

  else:
    await ctx.send(%*{"error": "Unsupported HTTP method: " & reqMethod}, Http405)
    return

  if opResult.isNone:
    await ctx.send(%*{"error": opResult.errorReason}, HttpCode(opResult.status))
    return

  await ctx.send %*{"url": opResult.get}
