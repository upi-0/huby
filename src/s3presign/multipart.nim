## Multipart presigning driven by ``multipartThreshold`` and ``multipartChunkSize``.
##
## The library never talks to S3; callers perform the requests themselves:
## 1. ``presignCreateMultipartUpload`` -> POST it -> read ``UploadId`` from XML
## 2. ``presignUploadParts``           -> PUT every part with its own signed URL
## 3. ``presignCompleteMultipartUpload`` -> POST the part manifest XML to it
##    (or use ``presignAbortMultipartUpload`` to roll back)
import std/[httpcore, times]
import ./[config, signing, url]

type
  MultipartError* = object of ValueError
    ## Raised when sizes violate S3 limits.

  PresignedPart* = object
    partNumber*: int   ## 1-based part number expected by S3
    offset*: int64     ## byte offset of this part within the source object
    last*: int64
    url*: string       ## presigned PUT for UploadPart

  PartSlice* = tuple[offset, size: int64]
    ## Pure geometry of one planned part.

proc multipartPlan*(contentLength, chunkSize: int64): seq[PartSlice] =
  ## Splits ``contentLength`` bytes into consecutive slices of ``chunkSize``,
  ## the last slice carrying the remainder. Enforces S3 limits:
  ## 5 MiB <= chunkSize <= 5 GiB and at most MaxParts slices.
  if contentLength < 0:
    raise newException(MultipartError, "contentLength must be >= 0")
  if contentLength == 0:
    return @[]
  if chunkSize < MinChunkSize or chunkSize > MaxChunkSize:
    raise newException(MultipartError,
      "chunkSize must be between 5 MiB and 5 GiB, got " & $chunkSize)
  var offset: int64 = 0
  while offset < contentLength:
    let size = min(chunkSize, contentLength - offset)
    result.add (offset, size)
    offset += size
  if result.len > MaxParts:
    raise newException(MultipartError,
      "chunkSize yields " & $result.len & " parts but S3 allows at most " &
      $MaxParts)

proc shouldUseMultipart*(cfg: S3Config, contentLength: int64): bool =
  ## True when an object of ``contentLength`` bytes exceeds the configured
  ## ``multipartThreshold`` and should take the multipart flow.
  cfg.validate()
  if contentLength < 0:
    raise newException(MultipartError, "contentLength must be >= 0")
  contentLength > cfg.multipartThreshold

proc presignCreateMultipartUpload*(cfg: S3Config, bucket, key: string,
                                   at: DateTime = getTime().utc): string =
  ## Presigned ``POST ?uploads``; the response XML contains the UploadId.
  let t = resolveObjectTarget(cfg, bucket, key)
  presignRequest(cfg, HttpPost, t.baseUrl, t.canonicalUri,
                 @[("uploads", "")], at = at)

proc presignPutPart*(cfg: S3Config; bucket, key, uploadId: string; totalPartNumber: int) : seq[string] =
  for num in 1 .. totalPartNumber:
    let
      t = resolveObjectTarget(cfg, bucket, key)
      q = @[
        ("partNumber", $num),
        ("uploadId", uploadId)
      ]
    result.add presignRequest(cfg, HttpPut, t.baseUrl, t.canonicalUri, q, at=getTime().utc)

proc presignUploadParts*(cfg: S3Config, bucket, key, uploadId: string,
                         contentLength: int64,
                         at: DateTime = getTime().utc): seq[PresignedPart] =
  ## One presigned PUT per part, sized by ``multipartChunkSize``.
  cfg.validate()
  if uploadId.len == 0:
    raise newException(MultipartError, "uploadId must not be empty")
  if contentLength <= 0:
    raise newException(MultipartError,
      "contentLength must be positive for multipart uploads")
  let plan = multipartPlan(contentLength, cfg.multipartChunkSize)
  let t = resolveObjectTarget(cfg, bucket, key)
  for i, slice in plan:
    let url = presignRequest(cfg, HttpPut, t.baseUrl, t.canonicalUri,
                             @[("partNumber", $(i + 1)), ("uploadId", uploadId)],
                             at = at)
    let
      last = slice.offset + slice.size - 1
    result.add PresignedPart(partNumber: i + 1, offset: slice.offset,
                             url: url, last: last)

proc presignCompleteMultipartUpload*(cfg: S3Config, bucket, key, uploadId: string,
                                     at: DateTime = getTime().utc): string =
  ## Presigned ``POST ?uploadId=...``; POST the part manifest XML to it.
  let t = resolveObjectTarget(cfg, bucket, key)
  presignRequest(cfg, HttpPost, t.baseUrl, t.canonicalUri,
                 @[("uploadId", uploadId)], at = at)

proc presignAbortMultipartUpload*(cfg: S3Config, bucket, key, uploadId: string,
                                   at: DateTime = getTime().utc): string =
  ## Presigned ``DELETE ?uploadId=...``.
  let t = resolveObjectTarget(cfg, bucket, key)
  presignRequest(cfg, HttpDelete, t.baseUrl, t.canonicalUri,
                 @[("uploadId", uploadId)], at = at)

proc presignListParts*(cfg: S3Config, bucket, key, uploadId: string,
                       at: DateTime = getTime().utc): string =
  ## Presigned ``GET ?uploadId=...`` (``ListParts``); lists uploaded parts.
  let t = resolveObjectTarget(cfg, bucket, key)
  presignRequest(cfg, HttpGet, t.baseUrl, t.canonicalUri,
                 @[("uploadId", uploadId)], at = at)
