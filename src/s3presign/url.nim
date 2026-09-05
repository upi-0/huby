## Bucket/key addressing (virtual-host vs path style) and object level presigns.
import std/[httpcore, strutils, times, uri]
import ./[config, signing]

type UrlError* = object of ValueError
  ## Raised on invalid bucket/key/endpoint input.

func isIPv4Literal(host: string): bool =
  ## True when ``host`` is a plain IPv4 address; virtual-host buckets cannot
  ## work against such endpoints.
  var parts = 0
  for piece in host.split('.'):
    inc parts
    if piece.len == 0 or piece.len > 3:
      return false
    for ch in piece:
      if ch notin {'0'..'9'}:
        return false
  parts == 4

func dnsCompatibleBucket(bucket: string): bool =
  ## Mirror of the S3 virtual-host naming rules; anything failing this is
  ## silently served via path style instead.
  if bucket.len < 3 or bucket.len > 63:
    return false
  if ".." in bucket:
    return false
  for i, ch in bucket:
    if ch notin {'a'..'z', '0'..'9', '-', '.'}:
      return false
    if (i == 0 or i == bucket.high) and ch in {'.', '-'}:
      return false
  true

type ResolvedEndpoint* = object
  scheme*: string     ## e.g. ``https``
  authority*: string  ## ``host[:port]``; carries the bucket as subdomain when virtual-host
  basePath*: string   ## encoded leading path, e.g. ``""``, ``"/bucket"`` or ``"/proxy/bucket"``

proc resolveEndpoint*(cfg: S3Config, bucket: string): ResolvedEndpoint =
  ## Maps config + bucket onto scheme/authority/base-path.
  var pathStyle = cfg.forcePathStyle
  if cfg.endpoint.len == 0:
    result.scheme = "https"
    let regionalHost = "s3." & cfg.region & ".amazonaws.com"
    if not pathStyle and dnsCompatibleBucket(bucket):
      result.authority = bucket & "." & regionalHost
    else:
      result.authority = regionalHost
      pathStyle = true
  else:
    let u = parseUri(cfg.endpoint)
    if u.scheme.len == 0 or u.hostname.len == 0:
      raise newException(UrlError,
        "endpoint must look like scheme://host[:port], got: " & cfg.endpoint)
    result.scheme = u.scheme
    result.authority = u.hostname
    if u.port.len > 0:
      result.authority.add ":" & u.port
    # Optional base path of the endpoint itself (reverse proxies etc.) comes first.
    if u.path.len > 0 and u.path != "/":
      let trimmed = u.path.strip(leading = false, trailing = true, chars = {'/'})
      for seg in trimmed.split('/'):
        if seg.len > 0:
          result.basePath.add "/" & awsUriEncode(seg)
    if not pathStyle and isIPv4Literal(u.hostname):
      pathStyle = true
    if not pathStyle and not dnsCompatibleBucket(bucket):
      pathStyle = true
    if pathStyle:
      let slash = block:
        if bucket.len == 0: bucket
        else: "/"
      result.basePath.add slash & awsUriEncode(bucket)
    else:
      result.authority = bucket & "." & result.authority
  if cfg.endpoint.len == 0 and pathStyle:
    # reached only through the AWS branch above
    result.basePath = "/" & awsUriEncode(bucket)

type Target* = tuple[baseUrl: string, canonicalUri: string]
  ## Base URL plus canonical (encoded) path for one object.

func objectTarget(ep: ResolvedEndpoint, key: string): Target =
  var k = key
  while k.len > 0 and k[0] == '/':
    k = k[1 .. ^1]
  var path = ep.basePath
  for seg in k.split('/'):
    path.add "/"
    path.add awsUriEncode(seg)
  result = (ep.scheme & "://" & ep.authority, path)

proc resolveObjectTarget*(cfg: S3Config, bucket, key: string): Target =
  ## Validates inputs and returns base URL + canonical path for an object.
  cfg.validate()
  if '/' in bucket:
    raise newException(UrlError, "bucket must not contain '/', got: " & bucket)
  if key.len == 0:
    raise newException(UrlError, "key must not be empty")
  objectTarget(resolveEndpoint(cfg, bucket), key)

proc presignObject*(cfg: S3Config, httpMethod: HttpMethod,
                    bucket, key: string,
                    at: DateTime = getTime().utc): string =
  ## Presigns any object verb (GET / PUT / HEAD / DELETE / ...).
  let t = resolveObjectTarget(cfg, bucket, key)
  presignRequest(cfg, httpMethod, t.baseUrl, t.canonicalUri, at = at)

proc presignGet*(cfg: S3Config, bucket, key: string,
                 at: DateTime = getTime().utc): string =
  ## Download URL.
  presignObject(cfg, HttpGet, bucket, key, at)

proc presignPut*(cfg: S3Config, bucket, key: string,
                 at: DateTime = getTime().utc): string =
  ## Upload URL (body sent by the caller).
  presignObject(cfg, HttpPut, bucket, key, at)

proc presignHead*(cfg: S3Config, bucket, key: string,
                  at: DateTime = getTime().utc): string =
  ## Metadata probe URL.
  presignObject(cfg, HttpHead, bucket, key, at)

proc presignDelete*(cfg: S3Config, bucket, key: string,
                    at: DateTime = getTime().utc): string =
  ## Delete URL.
  presignObject(cfg, HttpDelete, bucket, key, at)
