import ../base

proc handleHeadObject*(
    impl: FileService,
    url: string,
    key: string
): ServiceValue[string] =
  >> resolveS3(url, impl.garage.owner.secret_access_key, httpMethod = HttpHead)
  
  var file = emptyFile()
  let
    cfgRes = impl.getFileStorageConfig(key, file)
    targetUrl = cfgRes.get.s3conf.presignHead(cfgRes.get.bucket, cfgRes.get.address)

  implement.some(targetUrl)

proc handleOptions*(
    impl: FileService,
    origin: string,
    reqMethod: string,
    reqHeaders: seq[string] = @[]
): ServiceValue[CorsMatchResult] =
  let corsCfg = impl.garage.corsConfig()
  if corsCfg.len == 0:
    return result.none(403, "CORS request not allowed: no CORS configuration for this bucket")

  let matchResult = corsCfg.matchCors(origin, reqMethod, reqHeaders)
  if not matchResult.matched:
    return result.none(403, "CORS request not allowed: origin, method, or headers not allowed")

  implement.some(matchResult)
