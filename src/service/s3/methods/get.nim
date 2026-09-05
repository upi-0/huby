import ../base

proc handleListParts*(
    impl: FileService,
    url: string,
    key: string,
    uploadId: string
): ServiceValue[string] =
  if uploadId.len == 0:
    return result.none(400, "Missing uploadId parameter")

  >> resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpGet)

  var file = emptyFile()
  let
    cfgRes = impl.getFileStorageConfig(key, file)
    targetUrl = cfgRes.get.s3conf.presignListParts(
      cfgRes.get.bucket,
      cfgRes.get.address,
      uploadId)
  implement.some(targetUrl)

proc handleGetObject*(
    impl: FileService,
    url: string,
    key: string
): ServiceValue[string] =
  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpGet)
  var file = emptyFile()

  >> impl.select(key, file)
  
  if not file.isUploaded:
    return result.none(404)

  let targetUrl = file.resolve.get.httpUrl
  implement.some(targetUrl)
