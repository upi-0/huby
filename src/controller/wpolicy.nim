import
  prologue, context, tables, strutils, net, uri

import
  service/[presignedurl, fileHandler]

proc generateUrl*(ctx: Context) {.async.} =
  let
    key = ctx.getFormParams("k")
    replace = ctx.getFormParams("replace")
    (ip, ua) = await ctx.ipua()

  echo "==== $# ====" % ua

  block:
    ctx.json()
    ctx.send generateUrl(ip, ua, key, replace == "true")

proc resolvePolicy*(ctx: Context) {.async.} =
  ctx.json()
  ctx.response.headers.add("Access-Control-Request-Method", "OPTIONS, POST")

  let
    payload = ctx.request.nativeRequest.url.query[2 .. ^1]
    (ip, ua) = await ctx.ipua()
    po = resolvePolicy(ip, ua, payload)

  if ctx.request.reqMethod == HttpOptions:
    return ctx.send("", HttpCode(po.status))

  if po.isNone:
    return ctx.send po

  let
    file = ctx.getUploadFile("file")
    fileLength = ctx.request.headers.table["content-length"][0].parseInt()
    record = loadRequestRecord(file.filename)
    key = po.get.key

  block:
    file.save(record.dname, record.fname)
    ctx.send upload(record, key, fileLength, po.get.request == "replace")  
