import
  prologue, context,
  db, models/all,
  asyncdispatch

import json

import
  service/implement,
  service/file/main,
  service/owner/main

proc acceptHead*(ctx: Context) {.async.} =
  ## Payload:
  ## data: {
  ##    size: int
  ##    etag: string
  ##    key: string
  ##    content_type: string // as ext
  ## }

  echo "DAPDAP"

  let
    body = parseJson ctx.request.body
    owner = ctx.getPathParams("owner").ownerId()
    garag = ctx.getPathParams("garage")
    impl = await newFileService(owner.get, garag)

  block:
    var file: FileModel
    >> impl.get.select(body["key"].str, file)

    try:
      file.createdAt = getTime().toUnix()
      file.size = body["size"].num
      file.ext = body["content_type"].str
      file.etag = body["etag"].str
      file.isUploaded = true

      impl.get.conn.update(file)

    except Exception:
      return ctx.send("Error", Http500)

  await ctx.send("Success", Http200)
