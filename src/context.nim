import
  prologue, json, tables, strutils

import
  service/implement,
  service/presigned/[general, types],
  service/file/main,
  webhook  

type
  IpUa* = tuple
    ip, ua: string

  ExpectedExit* = object of HttpError

proc json*(ctx: Context) =
  ctx.response.headers["Content-Type"] = @["application/json"]


proc send*[T: string | JsonNode](ctx: Context; body: T, code = Http200) {.async.} =
  var text: string

  when body is JsonNode:
    ctx.json()  

  when body is string:
    text = body    

  let
    typeContent = ctx.response.headers.getTables()["content-type"][0]
    success = code.is2xx

  if typeContent == "application/json":
    let illall = %*{
      "success": success,
      "data": {},
      "error": nil,
    }
    if success:
      illall["data"] = %body

    else:
      illall["error"] = %body

    text = $body

  ctx.response.body = ""

  if not (ctx.request.reqMethod == HttpOptions):
    ctx.response.body = text

  ctx.response.code = code

  return

proc send*[T](ctx: Context; sv: ServiceValue[T]) {.async.} =
  let statusCode = HttpCode(sv.status)

  if sv.isNone:
    return ctx.send(sv.errorReason, statusCode)

  when not T is object:
    return ctx.send(sv.get, statusCode)  

  return ctx.send(%sv.get, statusCode)

proc send*[T](ctx: Context; sv: Future[ServiceValue[T]]) {.async.} =
  send(ctx, await sv)

proc tokenSignature*(ctx: Context): string {.deprecated.} = 
  let
    headers = ctx.request.nativeRequest.headers.table

  if headers.hasKey("authorization"):
    let val = headers["authorization"][0]

    if val.startsWith("Bearer"):
      return val.replace("Bearer ")

  block fromSession:
    return ctx.session.getOrDefault("token_signature")

proc ipua*(ctx: Context) : Future[IpUa] {.async.} =
  let headers = ctx.request.nativeRequest.headers.table
  var ua, ip: string

  if not (headers.hasKey("user-agent") and headers.hasKey("x-forwarded-for")):
    await ctx.send("", Http400)
  
  block:
    ua = headers["user-agent"][0]
    ip = headers["x-forwarded-for"][0]

  return (ip, ua)

template `||`*[T](sv: ServiceValue[T]) =
  if ctx.request.reqMethod == HttpOptions:
    raise ServiceValueException(
      status: sv.status,
      errorReason: "",
      msg: ""
    )

  else:
    >> sv  

template `??`*[T](sv: ServiceValue[T]) {.deprecated.} =
  >> sv

proc getMeta*(ctx: Context; privateKey, action: string): MetaObj =
  resolve(
    ctx.request.query,
    privateKey,
    action
  ).get()

proc retrieve*(ctx: Context; actionName: string, json = false) : tuple[
  impl: ServiceValue[FileService],
  meta: MetaObj,
  hook: ServiceValue[WebhookConnection]
] =
  block:
    result.impl = newFileService ctx.getPathParams("garage_name")
    result.meta = block:
      if not json: ctx.getMeta(result.impl.get.garage.key, actionName)
      else: resolveJWT(ctx.getPathParams("jwt_val"), result.impl.get.garage.key).get()
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
