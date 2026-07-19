import
  prologue, json, strutils, httpclient

import
  context,
  service/fileHandler,
  os

proc uploadFile*(ctx: Context) {.async.} =
  if ctx.request.reqMethod == HttpOptions:
    return ctx.send("", HttpCode(204))

  let
    file = ctx.getUploadFile("file")
    fileLength = ctx.request.headers.table["content-length"][0].parseInt()
    record = loadRequestRecord(file.filename)
    key = ctx.getFormParams("key")

  block:
    ctx.json()
    file.save(record.dname, record.fname)    

  ctx.send upload(record, key, fileLength)

proc lookFile*(ctx: Context) {.async.} = 
  ctx.json()
  ctx.send look ctx.getPathParams("signature")

proc resolveFile*(ctx: Context) {.async.} =
  let
    key = ctx.getPathParams("signature")
    red = await resolveRedirectFile key

  echo key

  if red.isNone and red.status == 202:
    await ctx.staticFileResponse("not-ready-img.png", "src/public")

  elif red.isNone:
    return ctx.send red

  resp redirect(red.get, Http302)

proc redirectFile*(ctx: Context) {.async.} =
  let
    signature = ctx.getPathParams("key")
    po = redirectFile(signature)

  block:
    ctx.json()
    ctx.send po    

proc deleteFile*(ctx: Context) {.async.} =
  ctx.json()
  ctx.send delete ctx.getPathParams("key")

proc listFiles*(ctx: Context) {.async.} =
  ctx.json()
  ctx.send listFiles ctx.getPathParams("key")

proc listFilesDeleted*(ctx: Context) {.async.} =
  ctx.json()
  ctx.send listFiles(ctx.getPathParams("key"), true)

proc statusFile*(ctx: Context) {.async.} =
  ctx.json()
  ctx.send status ctx.getPathParams("signature")
  