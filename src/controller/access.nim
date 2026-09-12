{.deprecated.}

import
  prologue, tables, context, json, strutils

import
  service/[multipart, implement],
  service/presigned/general,
  service/file/[main, adapter]

import
  s3presign/main,  
  models/s3/file,
  webhook

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  var
    (impl, meta, _) = await ctx.retrieve("resolve")
    file = newFile impl.get.garage
    
  || impl.get.select(meta.key, file)

  block:
    let
      download = meta.config.getOrDefault("download").getBool(false)
      redirectTarget = await impl.get.resolveRedirectFile(file[].key, download)
    resp redirect(redirectTarget.get, Http302)

proc checkStatus*(ctx: Context) {.async.} =
  block:
    ctx.json()

  let
    (impl, meta, _) = await ctx.retrieve("check-status")

  ctx.send impl.get.status(meta.key)    
