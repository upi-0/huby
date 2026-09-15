import
  prologue, context,
  db, models/all,
  asyncdispatch,
  http/client, httpclient,
  tables

import json

import
  service/implement,
  service/file/main,
  service/owner/main,
  service/s3/base

proc acceptHead*(ctx: Context) {.async.} =
  ## Payload:
  ## data: {
  ##    size: int
  ##    etag: string
  ##    key: string
  ##    content_type: string // as ext
  ##    action: string
  ## }

  let
    body = parseJson ctx.request.body
    owner = ctx.getPathParams("owner").ownerId()
    garag = ctx.getPathParams("garage")
    impl = await newFileService(owner.get, garag)

  var
    file: FileModel

  defer:
    impl.get.conn.stop()

  let
    http = inheritHttpConnection()
    (hfs3, bucket, address) = get impl.get.getFileStorageConfig(body["key"].str, file)

  defer:
    http.stop()    
    
  try:
    let resp: AsyncResponse = await http.client.request(
      hfs3.presignHead(bucket, address),
      httpMethod=HttpHead)

    if resp.code.is2xx:
      let data = resp.headers.table

      block:
        file.createdAt = getTime().toUnix()
        file.size = data["content-length"][0].parseInt()
        file.etag = data["etag"][0]
        file.ext = data["content-type"][0]
        file.isUploaded = true

      impl.get.conn.update(file)

  except:
    await ctx.send("Error", Http500)

  await ctx.send("Success", Http200)
