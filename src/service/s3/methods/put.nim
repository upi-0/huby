import ../base

proc handlePutPart*(
    impl: FileService,
    url: string,
    key: string,
    uploadId: string,
    partNumber: int,
    contentLength: int
): ServiceValue[string] =
  if uploadId.len == 0:
    return result.none(400, "Missing uploadId parameter")
  if partNumber < 1 or partNumber > MaxParts:
    return result.none(400, "Invalid partNumber: must be between 1 and " & $MaxParts)

  >> resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpPut)
  
  var file = emptyFile()
  let
    cfgRes = impl.getFileStorageConfig(key, file)
    targetUrl = cfgRes.get.s3conf.presignUploadPart(
      cfgRes.get.bucket,
      cfgRes.get.address,
      uploadId,
      partNumber)
      
  implement.some(targetUrl)

proc handlePutObject*(
    impl: FileService,
    url: string,
    key: string,
    contentLength: int
): ServiceValue[string] =
  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpPut)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  let record = loadRequestRecord(key.split("/")[^1])
  var s3conf: S3Config
  let addrRes = impl.putFile(
    key = key,
    contentLength = contentLength,
    record = record,
    replace = true,
    uploaded = true,
    s3conf = s3conf
  )
  if addrRes.isNone:
    return result.none(addrRes.status, addrRes.errorReason)

  var file = emptyFile()
  let
    cfgRes = impl.getFileStorageConfig(key, file)
    bucket = if cfgRes.isSome: cfgRes.get.bucket else: "exx"
    targetUrl = s3conf.presignPut(bucket, addrRes.get)
  
  implement.some(targetUrl)
