import ../base
import httpclient

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
    cfgRes = impl.getFileStorageConfig(key, file)

  result = cfgRes.get.s3conf.presignCompleteMultipartUpload(
    cfgRes.get.bucket,
    cfgRes.get.address,
    uploadId).some()
