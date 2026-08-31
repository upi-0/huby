import
  json, asyncdispatch, strutils,
  hmac, httpclient

import
  ../[types, implement],
  ../hf/uploadHf,
  http/client,
  adapter, main

import
  s3presign/main,
  env

type
  MigrateData* = tuple
    key: string
    filename: string
    contentLength: int

proc requestMigrate*(impl: FileService, key: string, data: MigrateData) : Future[ServiceValue[int]] {.async.} =
  let
    httpClient = hc[].client
    meta = getEnv("HF_REPO").split("/")
    s3client = meta[0].s3GenerateConf()

  let
    url = [getEnv("WORKER_URL"), impl.garage.name, "migrate"].join("/")
    address = impl.putFile(
      key= data.key,
      fileSize= data.contentLength,
      record= loadRequestRecord(data.filename),
      replace= false,
      uploaded= false)  
    payload = %*{
      "key": key,
      "url": s3client.presignPut(meta[1], address.get),
      "part": 12}
    hash = hmac_sha256(getEnv("WORKER_KEY"), $payload).toHex()  
    header = newHttpHeaders(
      {"x-hash-256": "sha256=" & hash})  
    response = await httpClient.request(
      url,
      httpMethod= HttpPost,
      body= $payload,
      headers= header
    )  

  response.status[0 .. 2].parseInt.some()    

when isMainModule:
  # let
  #   impl = newFileService("rijal")
  #   data = (
  #     key: "migrate:linux:dapdap",
  #     filename: "banner-perusahaan.png",
  #     contentLength: 250) 
  #   resp = waitFor impl.get.requestMigrate("Screenshot_20260501_194252.png", data)

  let s3 = s3GenerateConf("upi-0")
  let las =  s3.presignUploadParts("exx", "rijal.png", "asd1234", 7'i64 * 1000 * 900 * 1024)

  for la in las:
    echo [la.offset, la.size].join(" ")
