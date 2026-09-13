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
  webhook,
  db

proc resolve*(ctx: Context) {.async.} =
  ctx.json()

  let
    (impl, meta, _) = await ctx.retrieve("resolve")
  
  defer:
    impl.get.conn.stop()

  var
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

  defer:
    impl.get.conn.stop()

  ctx.send impl.get.status(meta.key)    
