import
  prologue, tables, context, json, strutils

import
  service/[types, fileHandler, presignedurl],
  models/file # Tar fileHandler benerin lagi anjim.

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
    (get metaTupleP, publicKey)

proc put*(ctx: Context) {.async.} =
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Request-Method", "OPTIONS, PUT")

  let
    (meta, _) = await ctx.resolveMeta("put")
    file = ctx.getUploadFile("file")
    fileLength = ctx.request.headers.table["content-length"][0].parseInt()
    record = loadRequestRecord(file.filename)

  block:
    file.save(record.dname, record.fname)
    ctx.send upload(record, meta.key, fileLength, true)

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  let (meta, _) = await ctx.resolveMeta("resolve")
  var
    file = new FileModel
    pox = file.select(meta.key)

  ?? pox

  block:
    let redirectTarget = await resolveRedirectFile file[].signature
    ?? redirectTarget
  
    resp redirect(redirectTarget.get, Http302)
