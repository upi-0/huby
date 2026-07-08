import
  prologue, strutils, json, context

import
  service/[tokenHandler, types]

proc createToken*(ctx: Context) {.async.} =
  let req = ctx.request.nativeRequest
  var cap : string

  ctx.json()

  if req.headers.table["content-type"][0] == "application/json":
    cap = getStr parseJson(req.body)["capacity"]

  else:
    cap = ctx.getFormParams("capacity")
  
  ctx.send createToken cap

proc lookToken*(ctx: Context) {.async.} =
  ctx.json()
  ctx.send lookToken ctx.tokenSignature

proc lookTokenUsage*(ctx: Context) {.async.} =
  ctx.json()
  ctx.send lookTokenUsage ctx.tokenSignature
