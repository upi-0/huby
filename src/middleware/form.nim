import
  prologue, context, db, times

import
  service/implement  

proc normalize*() : HandlerAsync =
  proc handler(ctx: Context) {.async.} =
    let allowedPayload = not [HttpGet, HttpHead, HttpDelete].contains ctx.request.reqMethod

    if ctx.request.formParams.data.isNil and allowedPayload:
      return ctx.send("INVALID FORM.", Http403)

    else:
      try:
        await ctx.switch()
      except ServiceValueException:
        let
          error = ServiceValueException getCurrentException()
          msg = block:
            if ctx.request.reqMethod == HttpOptions: ""
            else: error.errorReason
            
        await ctx.send(msg, HttpCode error.status)

  result = handler
