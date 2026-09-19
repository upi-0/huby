import
  prologue, context,
  db, models/all,
  asyncdispatch,
  http/client, httpclient,
  tables, strutils

import json

import
  service/implement,
  service/file/main,
  service/owner/main,
  service/s3/base,
  service/webhook

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

proc acceptHook*(ctx: Context) {.async.} =
  let
    body = parseJson ctx.request.body
    data = body["data"]
    owner = ctx.getPathParams("owner").ownerId()
    garag = ctx.getPathParams("garage")    
    impl = await newFileService(owner.get, garag)

  defer:
    impl.get.conn.stop()

  var
    file: FileModel    

  >> impl.get.select(body["data"]["key"].str, file)

  try:
    case body["event"].str
    of "PutObject", "CompleteMultipartUpload":
      file.etag = data["etag"].str
      file.size = data["content_length"].num
      file.ext = data["content_type"].str
      file.isUploaded = true

      impl.get.conn.update(file, ["etag", "size", "ext", "isUploaded"])

    else:
      discard  

  except:
    echo "[$#] $# -> $#" % [impl.get.garage.owner.namespace, body["event"].str, data["key"].str]

  await ctx.respond(Http500, "")

proc acceptHookReport*(ctx: Context) {.async.} =
  let
    body = parseJson ctx.request.body
    owner = ctx.getPathParams("owner").ownerId()
    garag = ctx.getPathParams("garage")     
    impl = await newFileService(owner.get, garag)

  defer:
    impl.get.conn.stop()

  var
    endpoints: seq[WebhookWriteDeliveryPayload]

  if body["report"].len < 1:
    await ctx.respond(Http204, "")
    return

  for endpoint in body["report"]:
    endpoints.add endpoint.to(WebhookWriteDeliveryPayload)

  block:
    let po = impl.get.writeDeliver(endpoints, body["payload"])
    await ctx.send(po)
