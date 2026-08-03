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
    ctx.response.headers.add("Access-Control-Allow-Methods", "PUT")
    ctx.response.headers.add("Access-Control-Allow-Headers", "*")

  let  
    impl = newFileService ctx.getPathParams("garage_name")
    meta = await ctx.getMeta("put")

  || impl

  let
    contentLength = ctx.request.headers.table["content-length"][0].parseInt()
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
