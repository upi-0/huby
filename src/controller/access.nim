import
  prologue, tables, context, json, strutils

import
  service/types,
  service/presigned/general,
  service/file/[main, adapter],
  models/file

proc getMeta(ctx: Context; action: string): Future[MetaObj] {.async.} =
  let hasil = resolve(
    ctx.request.query,
    ctx.getPathParams("garage_name"),
    action
  )

  ?? hasil
  get hasil

proc put*(ctx: Context) {.async.} =
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Request-Method", "OPTIONS, PUT")

  let
    impl = newFileService ctx.getPathParams("garage_name")

  if impl.isNone:
    return ctx.send("Garage Not Found", Http404)

  let  
    meta = await ctx.getMeta("put")
    file = ctx.getUploadFile("file")
    fileLength = ctx.request.headers.table["content-length"][0].parseInt()
    record = loadRequestRecord(file.filename)

  block:
    file.save(record.dname, record.fname)
    ctx.send impl.get.upload(record, meta.key, fileLength, true)

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  var
    meta = await ctx.getMeta("resolve")
    impl = newFileService ctx.getPathParams("garage_name")
    file = newFile impl.get.garage
    pox = impl.get.select(meta.key, file)

  ?? pox

  block:
    let redirectTarget = await impl.get.resolveRedirectFile file[].key
    ?? redirectTarget
  
    resp redirect(redirectTarget.get, Http302)
