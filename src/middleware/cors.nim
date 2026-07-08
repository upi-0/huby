import prologue, tables

proc useCors*(allowedCors: seq[string]; strict = false) : HandlerAsync =
  proc realHandler(ctx: Context) {.async.} = 
    let
      headerTable = ctx.request.headers.table
      cond = headerTable.hasKey("origin")

    var origin: string

    if cond and strict:
      origin = headerTable["origin"][0]

      if not allowedCors.contains(origin):
        await ctx.respond(Http403, "Invalid Cors")
        return

    elif not cond and strict:
      await ctx.respond(Http400, "Invalid Headers")
      return

    elif not strict:
      origin = "*"

    block:
      await ctx.switch()
      ctx.response.headers["access-control-allow-origin"] = @[origin]
    
  result = realHandler

proc noCors*(): HandlerAsync =
  useCors(@["*"])
