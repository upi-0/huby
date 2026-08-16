import
  prologue, tables, context, json, strutils

import
  service/types,
  service/presigned/general,
  service/file/[main, adapter],
  models/file

proc getMeta(ctx: Context; privateKey: string; action: string): Future[MetaObj] {.async.} =
  resolve(
    ctx.request.query,
    privateKey,
    action
  ).get()

proc put*(ctx: Context) {.async.} =
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Allow-Methods", "PUT")
    ctx.response.headers.add("Access-Control-Allow-Headers", "*")

  let  
    impl = newFileService ctx.getPathParams("garage_name")
    meta = await ctx.getMeta(impl.get.garage.key, "put")

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
      record, meta.key, contentLength, replace)

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  var
    impl = newFileService ctx.getPathParams("garage_name")
    meta = await ctx.getMeta(impl.get.garage.key, "resolve")
    file = newFile impl.get.garage
    
  || impl.get.select(meta.key, file)

  block:
    let redirectTarget = await impl.get.resolveRedirectFile file[].key  
    resp redirect(redirectTarget.get, Http302)

proc checkStatus*(ctx: Context) {.async.} =
  block:
    ctx.json()

  let
    impl = newFileService ctx.getPathParams("garage_name")
    meta = await ctx.getMeta(impl.get.garage.key, "check-status")

  ctx.send impl.get.status(meta.key)    

proc setPersistAccess*(ctx: Context) {.async.} =
  ctx.json()

  var
    impl = newFileService ctx.getPathParams("garage_name")
    meta = await ctx.getMeta(impl.get.garage.key, "set-persist-access")

  if not meta.config.hasKey("persist_access"):
    return ctx.send("Bad Request", Http400)   
    
  ctx.send impl.get.setPersistAccess(
    meta.key,
    meta.config["persist_access"].bval
  )
