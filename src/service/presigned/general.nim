import
  json, times, strutils, jwt, tables, uri, httpcore

import
  hmac

import
  ../implement, utils,
  types

import
  ../../s3presign/main

const
  HashInitializer = "&hash="

template validateHash() =
  if not queryField.contains(HashInitializer):
    return result.none(400, "Where is the fucking hash?")

  if queryField[queryField.find(HashInitializer)  + 6 .. ^1].len <= 10:
    return result.none(400, "Hash to short")    

proc resolve*(queryField, privateKey: string, action = "static"): ServiceValue[MetaObj] = 
  validateHash()

  let
    (hash, noHash) = splitFromHash queryField
    query = loadQuery noHash
  
  block calculateHash:
    let
      key = privateKey
      calculatedHash = hmac_sha256(key, noHash & action).toHex()

    if not calculatedHash.startsWith hash:
      echo "KEY : ", privateKey      
      echo "HASH: ", calculatedHash

      return result.none(403, "Invalid Hash")

  block defineResult:
    try:
      let terbungkam = MetaObj(
        key: query["key"].str,
        config: parseJson query["config"].str
      )

      if query.hasKey("exp"):
        let exp = parseInt query["exp"].str

        if exp < getTime().toUnix():
          return result.none(419, "Expired")

      return some terbungkam  

    except Exception:
      return result.none(500, "Error.")

proc resolveJWT*(jwtVal, privateKey: string): ServiceValue[MetaObj] =
  try:
    let 
      token = jwtVal.toJWT()
      match = token.verify(privateKey, HS256)

    if not match:
      return result.none(403, "JWT NOT MATCH")    
    
    let meta = MetaObj(
      key: token.claims["key"].node.str,
      config: token.claims["config"].node
    )

    return some meta

  except InvalidToken:
    result.none(403, "INVALID TOKEN")

  except Exception:
    result.none(400)

proc resolveS3*(
    urlOrQuery: string,
    secretAccessKey = "",
    cfg: S3Config = nil,
    httpMethod: HttpMethod = HttpGet
): ServiceValue[MetaObj] =
  ## Validates an AWS S3 SigV4 presigned URL or query string.
  ##
  ## Verifies algorithm, credential scope, expiry, and HMAC-SHA256 signature.
  ## Returns `ServiceValue[MetaObj]` with the extracted object key and
  ## query parameters in `config`.
  let effectiveSecret = block:
    if secretAccessKey.len > 0:
      secretAccessKey
    elif cfg != nil and cfg.secretAccessKey.len > 0:
      cfg.secretAccessKey
    else:
      return result.none(400, "Secret access key is required")

  var
    canonicalUri: string
    queryString: string
    hostPart: string

  if urlOrQuery.contains("://"):
    let u = parseUri(urlOrQuery)
    hostPart = u.hostname
    if u.port.len > 0:
      hostPart.add ":" & u.port
    canonicalUri = if u.path.len > 0: u.path else: "/"
    queryString = u.query
  else:
    if '?' in urlOrQuery:
      let parts = urlOrQuery.split('?', 1)
      canonicalUri = if parts[0].len > 0: parts[0] else: "/"
      queryString = parts[1]
    else:
      canonicalUri = "/"
      queryString = urlOrQuery

    if cfg != nil:
      if cfg.endpoint.len > 0:
        let eu = parseUri(cfg.endpoint)
        hostPart = eu.hostname
        if eu.port.len > 0:
          hostPart.add ":" & eu.port
      elif cfg.region.len > 0:
        hostPart = "s3." & cfg.region & ".amazonaws.com"
      else:
        hostPart = ""
    else:
      hostPart = ""

  if canonicalUri.len == 0 or canonicalUri[0] != '/':
    canonicalUri = "/" & canonicalUri

  var
    params = initTable[string, string]()
    queryPairs: seq[QueryPair] = @[]
    configNode = newJObject()

  try:
    for da, sa in decodeQuery(queryString):
      params[da] = sa
      configNode[da] = newJString(sa)
      if da != "X-Amz-Signature":
        queryPairs.add((da, sa))
  except Exception:
    return result.none(400, "Malformed query string")

  # Validate required AWS SigV4 query parameters
  if not params.hasKey("X-Amz-Algorithm") or params["X-Amz-Algorithm"] != AlgorithmName:
    return result.none(400, "Invalid or missing X-Amz-Algorithm")

  if not params.hasKey("X-Amz-Credential"):
    return result.none(400, "Missing X-Amz-Credential")

  let credParts = params["X-Amz-Credential"].split('/')
  if credParts.len < 5:
    return result.none(400, "Malformed X-Amz-Credential")

  let
    dateStamp = credParts[1]
    region = credParts[2]
    service = credParts[3]
    reqSuffix = credParts[4]

  if reqSuffix != RequestSuffix:
    return result.none(400, "Invalid Credential scope suffix")

  if not params.hasKey("X-Amz-Date"):
    return result.none(400, "Missing X-Amz-Date")

  let amzDate = params["X-Amz-Date"]
  var requestTime: DateTime
  try:
    requestTime = parse(amzDate, "yyyyMMdd'T'HHmmss'Z'", utc())
  except Exception:
    return result.none(400, "Invalid X-Amz-Date format")

  if not params.hasKey("X-Amz-Expires"):
    return result.none(400, "Missing X-Amz-Expires")

  var expiresSeconds: int
  try:
    expiresSeconds = parseInt(params["X-Amz-Expires"])
  except Exception:
    return result.none(400, "Invalid X-Amz-Expires")

  if expiresSeconds < 1 or expiresSeconds > MaxExpirySeconds:
    return result.none(400, "X-Amz-Expires out of range")

  if not params.hasKey("X-Amz-Signature"):
    return result.none(400, "Missing X-Amz-Signature")

  let expiryTime = requestTime + initDuration(seconds = expiresSeconds)
  if getTime().utc > expiryTime:
    return result.none(419, "Expired")

  let expectedSignature = params["X-Amz-Signature"].toLowerAscii()

  # Ensure host header matches what was signed
  if params.hasKey("X-Amz-SignedHeaders") and "host" in params["X-Amz-SignedHeaders"].toLowerAscii():
    if hostPart.len == 0 and cfg != nil:
      if cfg.endpoint.len > 0:
        let eu = parseUri(cfg.endpoint)
        hostPart = eu.hostname & (if eu.port.len > 0: ":" & eu.port else: "")
      elif cfg.region.len > 0:
        hostPart = "s3." & cfg.region & ".amazonaws.com"

  try:
    let
      canonQs = canonicalQuery(queryPairs)
      creq = canonicalRequest(httpMethod, canonicalUri, canonQs, hostPart)
      scope = dateStamp & "/" & region & "/" & service & "/" & reqSuffix
      sts = AlgorithmName & "\n" & amzDate & "\n" & scope & "\n" & sha256Hex(creq)
      calculatedSignature = calculateSignature(effectiveSecret, dateStamp, region, service, sts)

    if calculatedSignature != expectedSignature:
      return result.none(403, "Invalid Signature")

    # Extract key from query params or canonical URI
    var objKey = ""
    if params.hasKey("key"):
      objKey = params["key"]
    elif params.hasKey("k"):
      objKey = params["k"]
    else:
      let p = canonicalUri.strip(leading = true, chars = {'/'})
      if cfg != nil and cfg.forcePathStyle and '/' in p:
        let slashIdx = p.find('/')
        objKey = p[slashIdx + 1 .. ^1]
      else:
        objKey = p

    let meta = MetaObj(
      key: objKey,
      config: configNode
    )

    return some meta

  except Exception:
    return result.none(500, "Error.")

export
  HttpMethod, json
