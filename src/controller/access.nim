import
  prologue, tables, context, json, strutils

import
  service/types,
  service/presigned/general,
  service/file/[main, adapter],
  models/file

proc getMeta(ctx: Context; action: string): Future[MetaObj] {.async.} =
  resolve(
    ctx.request.query,
    ctx.getPathParams("garage_name"),
    action
  ).get()

proc put*(ctx: Context) {.async.} =
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Request-Method", "OPTIONS, PUT")

  let  
    impl = newFileService ctx.getPathParams("garage_name")
    meta = await ctx.getMeta("put")
    contentLength = ctx.request.headers.table["content-length"][0].parseInt()

  || impl

  let  
    file = ctx.getUploadFile("file")
    record = loadRequestRecord(file.filename)

  block:
    file.save(record.dname, record.fname)
    ctx.send impl.get.upload(record, meta.key, contentLength, true)

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  var
    meta = await ctx.getMeta("resolve")
    impl = newFileService ctx.getPathParams("garage_name")
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
    meta = await ctx.getMeta("check-status")

  ctx.send impl.get.status(meta.key)    

proc setPersistAccess*(ctx: Context) {.async.} =
  ctx.json()

  var
    meta = await ctx.getMeta "set-persist-access"
    impl = newFileService ctx.getPathParams("garage_name")

  if not meta.config.hasKey("persist_access"):
    return ctx.send("Bad Request", Http400)   
    
  ctx.send impl.get.setPersistAccess(
    meta.key,
    meta.config["persist_access"].bval
  )
