import ../base
import
  http/client, httpclient, tables

template fetchInformationAfter(ms: int) =
  sleepAsync(ms).addCallback(
    proc() =
      let request = http.client.request(
        cfgRes.get.s3conf.presignHead(cfgRes.get.bucket, cfgRes.get.address),
        httpMethod=HttpHead)      

      request.addCallback(
        proc(r: Future[AsyncResponse]) = 
          if r.read.status[0 .. 2].parseInt < 300 and (not file.isdeleted):
            file.size = r.read.headers.table["content-length"][0].parseInt() div 1024
            file.isUploaded = true
            file.is_size_sync = false

            conn.update(file)

          http.stop()  
      )
  )  

proc handleCreateMultipartUpload*(
    impl: FileService,
    url: string,
    key: string,
    contentLength: int
): ServiceValue[string] =
  >> resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpPost)

  var cfgRes: S3Config
  let
    record = loadRequestRecord(key.split("/")[^1])
    addrRes = impl.putFile(
      key = key,
      contentLength = contentLength,
      record = record,
      replace = true,
      uploaded = false,
      s3conf = cfgRes)

  implement.some cfgRes.presignCreateMultipartUpload("exx", addrRes.get)

proc handleCompleteMultipartUpload*(
    impl: FileService,
    url, key, uploadId: string
): Future[ServiceValue[string]] {.async.} =
  if uploadId.len == 0:
    return result.none(400, "Missing uploadId parameter")

  >> resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpPost)

  var
    file = emptyFile()

  let
    cfgRes = impl.getFileStorageConfig(key, file)
    http = inheritHttpConnection()

  fetchInformationAfter(10_000)
  
  result = cfgRes.get.s3conf.presignCompleteMultipartUpload(
    cfgRes.get.bucket,
    cfgRes.get.address,
    uploadId).some()
