import
  prologue, tables, context, json, strutils

import
  service/[types, fileHandler],
  service/presigned/general,
  models/file/[main, adapter]

proc cut(path: string): string =
  path.split("?")[1]

proc getMeta(ctx: Context; action: string): Future[MetaObj] {.async.} =
  let hasil = resolve(
    ctx.request.path.cut,
    ctx.getPathParams("public_key"),
    "put"
  )

  ?? hasil
  get hasil

proc put*(ctx: Context) {.async.} =
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Request-Method", "OPTIONS, PUT")

  let
    meta = await ctx.getMeta("put")
    file = ctx.getUploadFile("file")
    fileLength = ctx.request.headers.table["content-length"][0].parseInt()
    record = loadRequestRecord(file.filename)
    impl = newFileService ctx.getPathParams("garage_name")
    
  ?? impl

  block:
    file.save(record.dname, record.fname)
    ctx.send upload(record, meta.key, fileLength, true)

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  var
    meta = await ctx.getMeta("resolve")
    file = new FileModel
    pox = file.select(meta.key)

  ?? pox

  block:
    let redirectTarget = await resolveRedirectFile file[].signature
    ?? redirectTarget
  
    resp redirect(redirectTarget.get, Http302)
