import ../base

type
  PayloadXml = ref object
    etag, key: string
    size, id: int64

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

  let targetUrl = file.resolve.get.httpUrl
  implement.some(targetUrl)

proc handleListObjectsV2Xml*(
  impl: FileService;
  key: string
) : ServiceValue[string] =
  var dap = @[new PayloadXml]
  let query = query(
    select(
      "f.version::text AS etag",
      "f.key", "f.size", "f.id"),
    frm("s3.file", "f"),
    where(
      @["f.garage", $impl.garage.id],
      @["f.isdeleted", $false],
      @["f.key", "LIKE", q(key & "%")]))

  try:
    impl.conn.rawSelect(query, dap)

  except DbError:
    return result.none(404)  

  for da in dap:
    echo da.key
    echo da.size
    echo da.id
