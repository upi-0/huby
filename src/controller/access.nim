import
  prologue, tables, context, json, strutils

import
  service/[multipart, implement],
  service/presigned/general,
  service/file/[main, adapter, migrate]

import
  s3presign/main,  
  models/s3/file,
  webhook

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  var
    (impl, meta, _) = await ctx.retrieve("resolve")
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
    (impl, meta, _) = await ctx.retrieve("check-status")

  ctx.send impl.get.status(meta.key)    

proc uppyEndpoint*(ctx: Context) {.async.} =
  ## Meta:
  ##    key: string
  ##    config: {
  ##        contentLength: int
  ##        fileName: string
  ##    }

  block:
    ctx.response.headers.add("Access-Control-Allow-Methods", "PUT, OPTIONS")
    ctx.response.headers.add("Access-Control-Allow-Headers", "*")
    ctx.response.headers["Access-Control-Allow-Origin"] = @["http://localhost:5500"]

  if ctx.request.reqMethod == HttpOptions:
    return ctx.send("", Http204)

  let
    (impl, meta, _) = await ctx.retrieve("uppy")
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
      else:
        let data: MigrateData = (
          key: meta.key,
          filename: meta.config["fileName"].getStr("binary"),
          contentLength: meta.config["contentLength"].getInt())
        >> await impl.get.requestMigrate(key, data)
        multipart.completeUrl(uploadId.str) # Complete Multipart

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
