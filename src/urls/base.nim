import middleware/auth, prologue

proc protected*(endpoint: string; handler: HandlerAsync; mthod: openArray[HttpMethod] = [HttpGet]) : UrlPattern {.deprecated.} =
  pattern(endpoint, handler, httpMethod=mthod, middlewares = @[validToken()])

proc public*(endpoint: string; handler: HandlerAsync; mthod: openArray[HttpMethod] = [HttpGet]) : UrlPattern =
  pattern(endpoint, handler, httpMethod=mthod)

proc private*(endpoint: string; handler: HandlerAsync; mthod: openArray[HttpMethod] = [HttpGet]) : UrlPattern =
  pattern(endpoint, handler, httpMethod=mthod, middlewares = @[validKey()])
