import
  asyncdispatch,
  xmltree, xmlparser,
  json, strutils

import
  http/client, s3presign/main,
  ./[types, implement],
  httpclient  

type
  MultipartUploadData* = ref object of RootObj
    key, uploadId: string

  MultipartClient* = ref object of RootObj
    conf*: S3Config
    bucket*, key*: string
    contentLength*: int    

  MultipartListParts* = seq[JsonNode]

proc createUrl*(client: MultipartClient) : string =
  client.conf.presignCreateMultipartUpload(client.bucket, client.key)

proc create*(client: MultipartClient): Future[ServiceValue[MultipartUploadData]] {.async.} =
  let
    url = client.createUrl()
    resp = await hc[].client.request(url, httpMethod=HttpPost)

  var
    body: string
    xml: XmlNode
  
  if not resp.code.is2xx:
    return result.none(403)

  block:
    body = await resp.body
    xml = body.parseXml()

  some MultipartUploadData(
    key: client.key,
    uploadId: xml.findAll("UploadId")[0].innerText
  )

proc putPartUrl*(client: MultipartClient; uploadId: string; partNumber: int) : string =
  let urls = client.conf.presignUploadParts(client.bucket, client.key, uploadId, client.contentLength)
  urls[partNumber - 1].url

proc listPartsUrl*(client: MultipartClient, uploadId: string) : string =
  client.conf.presignListParts(client.bucket, client.key, uploadId)

proc listParts*(client: MultipartClient, uploadId: string) : Future[ServiceValue[MultipartListParts]] {.async.} = 
  let
    url = client.listPartsUrl(uploadId)
    resp = await hc[].client.request(url)

  if not resp.code.is2xx:
    return result.none(403)

  var res = newSeq[JsonNode](0)

  for part in parseXml(await resp.body).findAll("Part"):
    res.add %*{
      "PartNumber": part.child("PartNumber").innerText.parseInt(),
      "ETag": part.child("ETag").innerText,
      "Size": part.child("Size").innerText.parseInt()
    }

  res.some()

proc completeUrl*(client: MultipartClient; uploadId: string) : string =
  client.conf.presignCompleteMultipartUpload(client.bucket, client.key, uploadId)

const yahh = isMainModule

when yahh:
  import oids

  let
    conf = r2GenerateConf()
    multipart = MultipartClient(
      conf: conf,
      bucket: "kara",
      key: $genOID() & "/kadapi21.png",
      contentLength: 200)

  echo multipart.listPartsUrl("dapi21")
