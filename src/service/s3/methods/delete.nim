import ../base

proc handleAbortMultipartUpload*(
    impl: FileService,
    url: string,
    key: string,
    uploadId: string
): ServiceValue[string] =
  if uploadId.len == 0:
    return result.none(400, "Missing uploadId parameter")

  let resolve = resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpDelete)
  if resolve.isNone:
    return result.none(resolve.status, resolve.errorReason)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)
  if cfgRes.isNone:
    return result.none(cfgRes.status, cfgRes.errorReason)

  file.isDeleted = true
  file.isUploaded = false
  file.is_size_sync = false
  try:
    impl.conn.update(file)
  except DbError:
    discard

  let targetUrl = cfgRes.get.s3conf.presignAbortMultipartUpload(
    cfgRes.get.bucket,
    cfgRes.get.address,
    uploadId
  )
  implement.some(targetUrl)

proc handleDeleteObject*(
    impl: FileService,
    url: string,
    key: string
): Future[ServiceValue[string]] {.async.} =
  >> resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpDelete)

  var file = emptyFile()
  let cfgRes = impl.getFileStorageConfig(key, file)

  block:
    file.isDeleted = true
    file.isUploaded = false
    file.is_size_sync = false

  try:
    impl.conn.update(file)
  except DbError:
    discard

  let targetUrl = cfgRes.get.s3conf.presignDelete(cfgRes.get.bucket, cfgRes.get.address)
  return implement.some(targetUrl)
