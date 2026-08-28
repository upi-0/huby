import
  asyncdispatch,
  xmltree, xmlparser

import
  http/client, s3presign/main,
  ./[types, implement],
  httpclient  

type MultipartUploadData* = ref object of RootObj
  key, uploadId: string

proc multipartCreateUpload(conf: S3Config, bucket, key: string): Future[ServiceValue[MultipartUploadData]] {.async.} =
  let
    url = conf.presignCreateMultipartUpload(bucket, key)
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
    key: key,
    uploadId: xml.findAll("UploadId")[0].innerText
  )

const yahh = isMainModule

when yahh:
  import json

  let
    conf = s3GenerateConf("upi-0")
    upload = waitFor conf.multipartCreateUpload("exx", "asd.png")

  block:
    echo conf.presignListParts("exx", "asd.png", upload.get.uploadId)
    echo %(upload.get)
