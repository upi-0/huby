import
  prologue, context, json, env,
  strutils, tables, hmac

import
  models/file

import  
  s3presign/main,
  service/hf/uploadHf,
  service/file/[main, adapter, migrate],
  service/storage_repo/main,
  service/[types, implement],
  service/presigned/general

proc translate*(ctx: Context) {.async.} =
  ## Payload:
  ## {
  ##    method: string,
  ##    url: string,
  ##    payload: string,
  ##    garage: string,
  ##    contentLength: int
  ## }

  ctx.json()
  
  let
    body = ctx.request.body()
    payload = parseJson body
    impl = newFileService(payload["garage"].str)
    mthod = payload["method"].str
  
  var
    url: string
    file = newFile impl.get.garage

  let
    uploadId = payload.getOrDefault("uploadId")
    partNumber = payload.getOrDefault("partNumber")

  let
    contentLength = payload["contentLength"].getInt()
    record = loadRequestRecord(payload["url"].str.split("/")[^1].split("?")[0])
    resolve = resolveS3(
      payload["url"].str,
      impl.get.garage.key,
      httpMethod=ctx.request.reqMethod
    )

  if mthod == "PUT" and uploadId.isNil:
    url = get impl.get.putFile(resolve.get.key, contentLength, record, true)

  resp url
