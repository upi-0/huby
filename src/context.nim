import
  prologue, json, tables, strutils

import
  service/types  

type
  IpUa* = tuple
    ip, ua: string

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
    success = [Http200, Http201].contains(code)    

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

    text = $illall  

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

proc tokenSignature*(ctx: Context): string = 
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
