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
  service/presigned/[utils, general, types]

proc s3handler*(ctx: Context) {.async.} =
  ## Payload:
  ## {
  ##    method: string,
  ##    url: string,
  ##    contentLength: string
  ## }
  ## 
  ## http://localhost:6868/<OWNER>/<BUCKET_NAME>/<FILE_KEY>
  ## http://localhost:6868/sunarso/kadapi-bengkel-123/kadapi.png

  let
    body = ctx.request.body()
    payload = parseJson body

  let
    url = payload["url"].str
    reqMethod = payload.getOrDefault("method").str

  let  
    query = url.split("?")[^1].loadQuery()
    path = url.replace("http://").replace("https://").split("/")
    owner = path[1]
    bucket = path[2]
    impl = newFileService(bucket)

  var
    targetUrl, key: string
    s3 = new S3Config
    resolve: ServiceValue[MetaObj]

  let
    uploadId = query.getOrDefault("uploadId")
    partNumber = query.getOrDefault("partNumber")

  let
    contentLength = payload["contentLength"].getStr().parseInt()
    record = loadRequestRecord(url.split("/")[^1].split("?")[0])

  if reqMethod == "PUT":
    resolve = resolveS3(
      url, impl.get.garage.key,
      httpMethod=HttpPut
    )

    key = resolve.get.key.split("/")[2 .. ^1].join("/")

    targetUrl = get impl.get.putFile(
      key=key,
      contentLength=contentLength,
      record=record,
      replace=true,
      uploaded=true,
      s3conf=s3
    )

    targetUrl = s3.presignPut("exx", targetUrl)

  else:
    targetUrl = "Pastinya~"  

  resp targetUrl
