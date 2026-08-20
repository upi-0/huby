import
  prologue, tables, context, json, strutils

import
  service/implement,
  service/presigned/general,
  service/file/[main, adapter],
  models/file,
  webhook

proc getMeta(ctx: Context; privateKey: string; action: string): MetaObj =
  resolve(
    ctx.request.query,
    privateKey,
    action
  ).get()

proc retrieve(ctx: Context; actionName: string) : tuple[
  impl: ServiceValue[FileService],
  meta: MetaObj,
  hook: ServiceValue[WebhookConnection]
] =
  block:
    result.impl = newFileService ctx.getPathParams("garage_name")
    result.meta = ctx.getMeta(result.impl.get.garage.key, actionName)
    result.hook = none(WebhookConnection, 0)

  let
    webhookConf = result.meta.config.getOrDefault("webhook")
    useHook = webhookConf.getOrDefault("use").getBool(false)
    requestOrigin = ctx.request.headers.table.getOrDefault("origin", @[""])

  if useHook:
    let
      endpoint = webhookConf.getOrDefault("endpoint").getStr("/webhook/huby")
      origin = webhookConf.getOrDefault("origin").getStr requestOrigin[0]

    if origin.len < 1:
      ctx.abortExit(Http400, "Invalid origin while using webhook.")

    result.hook = implement.some createWebhookConnection(
      garageId = result.impl.get.garage.id,
      garageKey = result.impl.get.garage.key,
      origin = origin,
      endpoint = endpoint
    )

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
