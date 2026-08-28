import
  prologue, tables, context, json, strutils

import
  service/[multipart, implement],
  service/presigned/general,
  service/file/[main, adapter]

import
  s3presign/main,  
  models/file,
  webhook

proc put*(ctx: Context) {.async.} =
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Allow-Methods", "PUT")
    ctx.response.headers.add("Access-Control-Allow-Headers", "*")

  let
    (impl, meta, hook) = ctx.retrieve("put")

  || impl

  let
    replace = block:
      if meta.config.hasKey("replace"): meta.config["replace"].bval
      else: false  
    contentLength = ctx.request.headers.table["content-length"][0].parseInt()
    file = ctx.getUploadFile("file")
    record = loadRequestRecord(file.filename)

  block:
    file.save(record.dname, record.fname)
    ctx.send impl.get.upload(
      record, meta.key, contentLength, replace, hook)

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  var
    (impl, meta, _) = ctx.retrieve("resolve")
    file = newFile impl.get.garage
    
  || impl.get.select(meta.key, file)

  block:
    let
      download = meta.config.getOrDefault("download").getBool(false)
      redirectTarget = await impl.get.resolveRedirectFile(file[].key, download)
    resp redirect(redirectTarget.get, Http302)

proc checkStatus*(ctx: Context) {.async.} =
  block:
    ctx.json()

  let
    (impl, meta, _) = ctx.retrieve("check-status")

  ctx.send impl.get.status(meta.key)    

proc setPersistAccess*(ctx: Context) {.async.} =
  ctx.json()

  let (impl, meta, _) = ctx.retrieve("set-persist-access")

  if not meta.config.hasKey("persist_access"):
    return ctx.send("Bad Request", Http400)   
    
  ctx.send impl.get.setPersistAccess(
    meta.key,
    meta.config["persist_access"].bval
  )

proc rename*(ctx: Context) {.async.} =
  ctx.json()

  let (impl, meta, hook) = ctx.retrieve("rename")

  if not meta.config.hasKey("new_name"):
    return ctx.send("Bad Request", Http400)

  ctx.send impl.get.rename(
    meta.key,
    meta.config["new_name"].str,
    hook
  )

proc uppyEndpoint*(ctx: Context) {.async.} =
  ## Meta:
  ##    key: string
  ##    config: {
  ##        contentLength: int
  ##    }

  block:
    ctx.response.headers.add("Access-Control-Allow-Methods", "PUT, OPTIONS")
    ctx.response.headers.add("Access-Control-Allow-Headers", "*")
    ctx.response.headers["Access-Control-Allow-Origin"] = @["http://localhost:5500"]

  if ctx.request.reqMethod == HttpOptions:
    return ctx.send("", Http204)

  let
    (impl, meta, _) = ctx.retrieve("uppy")
    s3conf = r2GenerateConf()
    hash = ctx.getQueryParams("hash")
    key = ["temp", impl.get.garage.name, hash, meta.key].join("/")
    multipart = MultipartClient(
      conf: s3conf,
      bucket: "test-yonopod",
      key: key,
      contentLength: meta.config["contentLength"].num)

  var
    body: JsonNode
    url: string

  try:
    body = parseJson ctx.request.body

  except Exception:
    return ctx.send("400", Http400)  

  let
    uploadId = body.getOrDefault("uploadId")
    partNumber = body.getOrDefault("partNumber")
    mthod = body.getOrDefault("method").getStr("DAP")

  if mthod == "POST":
    url = block:
      if uploadId.isNil: multipart.createUrl()  # Create Multipart
      else: multipart.completeUrl(uploadId.str) # Complete Multipart

  elif mthod == "PUT":
    if uploadId.isNil or partNumber.isNil:
      return ctx.respond(Http403, "Not for tiny object")

    url = multipart.putPartUrl(
      uploadId.str,
      partNumber.num
    ) # Put Part

  elif mthod == "GET":
    if not (uploadId.isNil):
      url = multipart.listPartsUrl(uploadId.str) # List Parts

  else:
    return ctx.respond(Http500, "Uncatched Event.")

  ctx.send %*{"url": url}
