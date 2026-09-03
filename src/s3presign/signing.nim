## Low-level AWS Signature Version 4 presigning, query-string flavour.
##
## Scope is deliberately minimal because only presigned URLs are produced:
## ``host`` is the sole signed header and the payload hash is the literal
## ``UNSIGNED-PAYLOAD``.
import std/[algorithm, httpcore, strutils, times, uri]
import nimcrypto/sha2
import nimcrypto/hmac
import config

const
  UnsignedPayload* = "UNSIGNED-PAYLOAD"
  AlgorithmName* = "AWS4-HMAC-SHA256"
  ServiceName* = "s3"
  RequestSuffix* = "aws4_request"

type
  QueryPair* = tuple[name, value: string]
    ## Single query parameter used for canonicalisation.
  SigningError* = object of ValueError
    ## Raised on structurally invalid signing input.

func verbName*(m: HttpMethod): string =
  case m
  of HttpGet: "GET"
  of HttpHead: "HEAD"
  of HttpPost: "POST"
  of HttpPut: "PUT"
  of HttpDelete: "DELETE"
  of HttpPatch: "PATCH"
  of HttpOptions: "OPTIONS"
  of HttpTrace: "TRACE"
  of HttpConnect: "CONNECT"

proc awsUriEncode*(s: string, encodeSlash = true): string =
  ## SigV4 URI encoding: RFC 3986 unreserved characters pass through untouched,
  ## everything else becomes ``%XX`` (uppercase hex). Slashes are kept literal
  ## when ``encodeSlash`` is false (used for path segments).
  const Unreserved = {'A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'}
  result = newStringOfCap(s.len)
  for c in s:
    if c in Unreserved or (c == '/' and not encodeSlash):
      result.add c
    else:
      result.add '%'
      result.add toHex(ord(c), 2)

proc canonicalQuery*(query: seq[QueryPair]): string =
  ## Sorts by name then value and produces the encoded canonical query string.
  var q = query
  q.sort(proc(a, b: QueryPair): int =
    result = cmp(a.name, b.name)
    if result == 0:
      result = cmp(a.value, b.value))
  for i, p in q:
    if i > 0:
      result.add '&'
    result.add awsUriEncode(p.name)
    result.add '='
    result.add awsUriEncode(p.value)

func hexLower*(b: openArray[byte]): string =
  const Digits = "0123456789abcdef"
  result = newString(b.len * 2)
  for i, x in b:
    result[2 * i] = Digits[(int(x) shr 4) and 0xF]
    result[2 * i + 1] = Digits[int(x) and 0xF]

proc sha256Hex*(s: string): string =
  ## Lowercase hex SHA-256 digest of ``s``.
  hexLower(sha256.digest(s).data)

proc deriveSigningKey*(secretAccessKey, dateStamp, region, service: string): array[32, byte] =
  ## SigV4 HMAC chain: ``AWS4<secret>`` -> date -> region -> service -> aws4_request.
  let kDate = hmac(sha256, "AWS4" & secretAccessKey, dateStamp)
  let kRegion = hmac(sha256, kDate.data, region)
  let kService = hmac(sha256, kRegion.data, service)
  let kSigning = hmac(sha256, kService.data, RequestSuffix)
  result = kSigning.data

proc calculateSignature*(secretAccessKey, dateStamp, region, service, stringToSign: string): string =
  ## Computes SigV4 hex signature for a given string to sign.
  let key = deriveSigningKey(secretAccessKey, dateStamp, region, service)
  result = hexLower(hmac(sha256, key, stringToSign).data)

func canonicalRequest*(httpMethod: HttpMethod, canonicalUri, queryString,
                      host: string): string =
  verbName(httpMethod) & "\n" &
    canonicalUri & "\n" &
    queryString & "\n" &
    "host:" & host & "\n" &
    "\n" &
    "host" & "\n" &
    UnsignedPayload

proc presignRequest*(cfg: S3Config,
                     httpMethod: HttpMethod,
                     baseUrl: string,
                     canonicalUri: string,
                     extraQuery: seq[QueryPair] = @[],
                     at: DateTime = getTime().utc): string =
  ## Returns a fully presigned URL for an arbitrary request.
  ##
  ## * ``baseUrl``      - ``scheme://host[:port]`` only, no path or query.
  ## * ``canonicalUri`` - already-encoded absolute path beginning with ``/``.
  ## * ``extraQuery``   - operation sub-resources (e.g. ``uploadId``);
  ##                      the ``X-Amz-*`` auth parameters are added automatically.
  ## * ``at``           - signing instant; defaults to now, pin it for tests.
  cfg.validate()
  let u = parseUri(baseUrl)
  if u.scheme.len == 0 or u.hostname.len == 0:
    raise newException(SigningError,
      "baseUrl must look like scheme://host[:port], got: " & baseUrl)
  var hostPart = u.hostname
  if u.port.len > 0:
    hostPart.add ":" & u.port
  let base = u.scheme & "://" & hostPart

  var canonUri = canonicalUri
  if canonUri.len == 0 or canonUri[0] != '/':
    canonUri = "/" & canonUri

  let amzDate = at.format("yyyyMMdd'T'HHmmss'Z'")
  let dateStamp = at.format("yyyyMMdd")
  let scope = dateStamp & "/" & cfg.region & "/" & ServiceName & "/" & RequestSuffix
  let credential = cfg.accessKeyId & "/" & scope

  var query = extraQuery
  query.add ("X-Amz-Algorithm", AlgorithmName)
  query.add ("X-Amz-Credential", credential)
  query.add ("X-Amz-Date", amzDate)
  query.add ("X-Amz-Expires", $cfg.expiresSeconds)
  query.add ("X-Amz-SignedHeaders", "host")
  if cfg.sessionToken.len > 0:
    query.add ("X-Amz-Security-Token", cfg.sessionToken)
  let qs = canonicalQuery(query)

  let creq = canonicalRequest(httpMethod, canonUri, qs, hostPart)
  let sts = AlgorithmName & "\n" & amzDate & "\n" & scope & "\n" & sha256Hex(creq)
  let key = deriveSigningKey(cfg.secretAccessKey, dateStamp, cfg.region, ServiceName)
  let signature = hexLower(hmac(sha256, key, sts).data)

  result = base & canonUri & "?" & qs & "&X-Amz-Signature=" & signature
