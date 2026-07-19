import
  prologue, context

proc normalize*() : HandlerAsync =
  proc handler(ctx: Context) {.async.} =
    let allowedPayload = not [HttpGet, HttpHead, HttpDelete].contains ctx.request.reqMethod

    if ctx.request.formParams.data.isNil and allowedPayload:
      return ctx.send("", Http403)

    else:
      try:
        await ctx.switch()
      except ExpectedExit:
        discard  

  result = handler
