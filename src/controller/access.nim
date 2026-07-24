import
  prologue, tables, context, json, strutils

import
  service/[types, fileHandler, presignedurl],
  service/file/[main, adapter]

const
  AvailableActions = ["put", "resolve", "look"]

type
  GeneralValidation = tuple
    meta: MetaTuple
    publicKey: string  

proc resolveMeta(ctx: Context; handler: string) : Future[GeneralValidation] {.async.} =
  let
    meta = ctx.getQueryParams("meta")
    hash = ctx.getQueryParams("hash")
    publicKey = ctx.getPathParams("public_key")
    metaTupleP = resolveMeta(meta, hash, handler)

  block:
    ?? metaTupleP
    (metaTupleP.get, publicKey)

proc put*(ctx: Context) {.async.} =
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Request-Method", "OPTIONS, PUT")

  let
    (meta, _) = await ctx.resolveMeta("put")
    file = ctx.getUploadFile("file")
    fileLength = ctx.request.headers.table["content-length"][0].parseInt()
    record = loadRequestRecord(file.filename)
    impl = newFileService ctx.getPathParams("garage_name")
    
  ?? impl

  block:
    file.save(record.dname, record.fname)
    ctx.send impl.get.upload(record, meta.key, fileLength, true)
