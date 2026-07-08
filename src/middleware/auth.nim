import
  prologue, context, env

proc validToken*: HandlerAsync =
  proc handler(ctx: Context) {.async.} =

    if not (ctx.tokenSignature == ""):
      await ctx.switch()

    else:
      return ctx.send("", Http401)
    
  return handler

proc validKey*: HandlerAsync =
  proc handler(ctx: Context) {.async.} =
    if ctx.tokenSignature == getEnv("APP_KEY"):
      await ctx.switch()

    else:
      return ctx.send("", Http403)  

  return handler
