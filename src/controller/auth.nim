import context, prologue, tables, json, strutils
import service/[tokenHandler, types]

proc login*(ctx: Context) {.async.} = 
  ctx.json()

  let
    tokenSignature = ctx.getFormParams("token")
    valid = isValidToken tokenSignature

  if valid.isNone:
    return ctx.send valid

  block:
    ctx.session["token_signature"] = tokenSignature
    ctx.send("Hello World", Http200)

proc lookTokenSignature*(ctx: Context) {.async.} =
  ctx.json()
  ctx.send(ctx.tokenSignature, Http200)
