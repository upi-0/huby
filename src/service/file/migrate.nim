import
  json, asyncdispatch, strutils,
  hmac, httpclient, sugar, sequtils

import
  ../[types, implement],
  ../hf/uploadHf,
  ../multipart

import  
  http/client,
  adapter, main

import
  s3presign/main,
  env

import
  models/[garage, file],
  db

type
  MigrateData* = tuple
    key: string
    filename: string
    contentLength: int64

proc completeMigrate*(returning: JsonNode) : Future[int] {.async.} =
  var
    file = emptyFile()
    payload = "<CompleteMultipartUpload>\n"
  
  let
    address = returning["address"].str
    key = returning["key"].str
    garage = returning["garage"].str
    uploadId = returning["uploadId"].str
    impl = newFileService(garage)

  >> impl.get.select(key, file)

  let
    httpClient = hc[].client
    meta = file.repo.split("/")
    s3Client = s3GenerateConf(meta[0])
    mpClient = MultipartClient(
      conf: s3Client,
      bucket: meta[1],
      key: address
    )

  block generatePayload:
    let listParts = await mpClient.listParts(uploadId)

    for part in listParts.get:
      payload &= "<Part>\n"
      payload &= "<PartNumber>" & $(part["PartNumber"].num) & "</PartNumber>\n"
      payload &= "<ETag>" & part["ETag"].str & "</ETag>\n"
      payload &= "</Part>\n"

    payload &= "</CompleteMultipartUpload>\n"

  let
    completeUrl = s3Client.presignCompleteMultipartUpload(
      meta[1], address, uploadId)
    response = await httpClient.request(
      completeUrl, HttpPost, body= payload
    )  

  response.status[0 .. 2].parseInt()

proc requestMigrate*(impl: FileService, key: string, data: MigrateData) : Future[ServiceValue[int]] {.async.} =
  let
    httpClient = hc[].client
    meta = getEnv("HF_REPO").split("/")

  var  
    s3client = meta[0].s3GenerateConf()

  let
    url = [getEnv("WORKER_URL"), impl.garage.name, "migrate"].join("/")
    address = impl.putFile(
      key= data.key,
      fileSize= data.contentLength,
      record= loadRequestRecord(data.filename),
      replace= true,
      uploaded= false,
      s3conf=s3client)  
    multipartClient = MultipartClient(
      conf: s3client,
      bucket: meta[1],
      key: address.get,)
    multipartData = await multipartClient.create()

  block:
    >> multipartData
    >> address

  let    
    urls = s3client.presignUploadParts(
      meta[1], address.get, multipartData.get.uploadId, data.contentLength)
    payload = %*{
      "key": key,
      "urls": urls,
      "returning": {
          "address": address.get,
          "key": data.key,
          "garage": impl.garage.name,
          "uploadId": multipartData.get.uploadId
        }
      }
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
  let
    impl = newFileService("rijal")
    data = (
      key: "migrate:linux:dapdap:7",
      filename: "dapdap.pptx",
      contentLength: 17954272.int64) 

  try:
    let resp = waitFor impl.get.requestMigrate("Tactical_Career_Blueprint.pptx", data)
    echo resp.get

  except ServiceValueException:
    let error = ServiceValueException(getCurrentException())
    echo error.status   
    echo error.errorReason

  except:
    echo getCurrentExceptionMsg()
