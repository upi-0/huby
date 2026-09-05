import
  prologue, context, json,
  strutils, asyncdispatch

import
  models/all, db

import  
  service/owner/main,
  service/s3/all,
  service/[types, implement],
  service/presigned/[utils, general, types],
  service/cfcors

template closeDb =
  impl.get.conn.stop()

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

  if ctx.request.reqMethod == HttpOptions and ctx.getQueryParams("url").len == 0:
    await ctx.send("", Http204)
    return

  var payload: JsonNode
  try:
    payload = %*{
      "url": ctx.getQueryParams("url"),
      "contentLength": ctx.getQueryParams("contentLength"),
      "method": ctx.getQueryParams("method"),
      "origin": ctx.getQueryParams("origin"),
      "requestMethod": ctx.getQueryParams("requestMethod"),
      "requestHeaders": ctx.getQueryParams("requestHeaders")
    }
    echo "QUERY_PARAMS: " & $payload

  except Exception:
    await ctx.send(%*{"error": getCurrentExceptionMsg()}, Http400)
    return

  if not payload.hasKey("url") or payload["url"].getStr().len == 0:
    await ctx.send(%*{"error": "Missing 'url' field in payload"}, Http400)
    return

  let
    url = payload["url"].str
    rawMethod = if payload.hasKey("method") and payload["method"].getStr().len > 0:
                  payload["method"].getStr()
                elif ctx.request.reqMethod == HttpOptions:
                  "OPTIONS"
                else:
                  "GET"
    reqMethod = rawMethod.toUpperAscii()
    cleanUrl = url.replace("http://").replace("https://").split("?")[0]
    path = cleanUrl.split("/")

  if path.len < 3:
    await ctx.send(%*{"error": "Invalid URL format: expected http://host/owner/bucket/key"}, Http400)
    return

  let
    owner = path[1]
    bucket = path[2]
    id = owner.ownerId()
    re = newJObject()
    impl = await newFileService(id.get, bucket)

  defer:
    closeDb()

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
  of "OPTIONS":
    let
      headerTable = ctx.request.headers.table
      origin = block:
        if headerTable.hasKey("origin") and headerTable["origin"].len > 0: headerTable["origin"][0]
        else: ""

      requestMethod = block:
        if headerTable.hasKey("access-control-request-method") and headerTable["access-control-request-method"].len > 0: headerTable["access-control-request-method"][0]
        else: ""

      requestHeadersRaw = block:
        if headerTable.hasKey("access-control-request-headers") and headerTable["access-control-request-headers"].len > 0: headerTable["access-control-request-headers"][0]
        else: ""
                
      requestHeaders = block:
        if requestHeadersRaw.len > 0: requestHeadersRaw.split(",")
        else: @[]

    let
      corsRes = impl.get.handleOptions(origin, requestMethod, requestHeaders)
      match = corsRes.get
    
    ctx.response.headers["access-control-allow-origin"] = @[match.allowOrigin]
    ctx.response.headers["access-control-allow-methods"] = @[match.allowMethods.join(", ")]
    if match.allowHeaders.len > 0:
      ctx.response.headers["access-control-allow-headers"] = @[match.allowHeaders.join(", ")]
    if match.exposeHeaders.len > 0:
      ctx.response.headers["access-control-expose-headers"] = @[match.exposeHeaders.join(", ")]
    if match.maxAgeSeconds > 0:
      ctx.response.headers["access-control-max-age"] = @[$match.maxAgeSeconds]

    re["status"] = %204
    re["headers"] = match.toHeadersJson()

    return ctx.send(re)

  of "POST":
    if hasUploads:
      opResult = impl.get.handleCreateMultipartUpload(url, key, contentLength)
    elif uploadId.len > 0:
      opResult = await impl.get.handleCompleteMultipartUpload(url, key, uploadId)
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
      opResult = impl.get.handlePutPart(url, key, uploadId, partNumber, contentLength)
    else:
      opResult = impl.get.handlePutObject(url, key, contentLength)

  of "GET":
    if uploadId.len > 0:
      opResult = impl.get.handleListParts(url, key, uploadId)
    else:
      opResult = impl.get.handleGetObject(url, key)
    re["cached_secret_access_key"] = %impl.get.garage.owner.secret_access_key

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

  re["url"] = %opResult.get

  await ctx.send(re)
