## Configuration for the S3 presign-only client.
runnableExamples:
  var cfg = initS3Config("AKIDEXAMPLE", "secret", "us-east-1")
  cfg.forcePathStyle = true
  validate(cfg)

type
  S3Config* = ref object
    accessKeyId*: string       ## AWS access key ID
    secretAccessKey*: string   ## Secret access key
    region*: string            ## Region, e.g. ``us-east-1`` (``auto`` for Cloudflare R2)
    sessionToken*: string      ## Optional STS session token
    endpoint*: string          ## Custom endpoint such as ``http://localhost:9000``;
                               ## empty means native AWS (``s3.<region>.amazonaws.com``)
    forcePathStyle*: bool      ## true => ``host/bucket/key`` instead of ``bucket.host/key``
    expiresSeconds*: int       ## Validity window of generated URLs (clamped 1..604800)
    multipartThreshold*: int64 ## Objects larger than this should use multipart presigning
    multipartChunkSize*: int64 ## Size of every UploadPart (last part may be smaller)

  S3ConfigError* = object of ValueError
    ## Raised when an S3Config cannot produce valid URLs.

const
  DefaultExpirySeconds* = 3600
  DefaultMultipartThreshold* = 64'i64 * 1024 * 1024
  DefaultMultipartChunkSize* = 8'i64 * 1024 * 1024
  MinExpirySeconds* = 1
  MaxExpirySeconds* = 604_800              ## 7 days, AWS maximum for query auth
  MinChunkSize* = 5'i64 * 1024 * 1024      ## S3 minimum part size (except last part)
  MaxChunkSize* = 5'i64 * 1024 * 1024 * 1024 ## S3 maximum part size (5 GiB)
  MaxParts* = 10_000                       ## S3 limit of parts per upload

proc initS3Config*(accessKeyId, secretAccessKey, region: string): S3Config =
  ## Config with sensible defaults: native AWS endpoints, virtual-host style,
  ## 1 hour expiry, 64 MiB multipart threshold, 8 MiB chunks.
  S3Config(
    accessKeyId: accessKeyId,
    secretAccessKey: secretAccessKey,
    region: region,
    sessionToken: "",
    endpoint: "",
    forcePathStyle: true,
    expiresSeconds: DefaultExpirySeconds,
    multipartThreshold: DefaultMultipartThreshold,
    multipartChunkSize: DefaultMultipartChunkSize,
  )

proc validate*(cfg: S3Config) =
  ## Raises S3ConfigError when the configuration is unusable.
  if cfg.accessKeyId.len == 0:
    raise newException(S3ConfigError, "accessKeyId must not be empty")
  if cfg.secretAccessKey.len == 0:
    raise newException(S3ConfigError, "secretAccessKey must not be empty")
  if cfg.region.len == 0:
    raise newException(S3ConfigError, "region must not be empty")
  if cfg.expiresSeconds < MinExpirySeconds or cfg.expiresSeconds > MaxExpirySeconds:
    raise newException(S3ConfigError,
      "expiresSeconds must be between " & $MinExpirySeconds & " and " &
      $MaxExpirySeconds & ", got " & $cfg.expiresSeconds)
  if cfg.multipartThreshold < 0:
    raise newException(S3ConfigError, "multipartThreshold must be >= 0")
  if cfg.multipartChunkSize < MinChunkSize or cfg.multipartChunkSize > MaxChunkSize:
    raise newException(S3ConfigError,
      "multipartChunkSize must be between 5 MiB and 5 GiB, got " &
      $cfg.multipartChunkSize)
