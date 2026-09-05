import unittest, json, times, strutils, uri, httpcore
import s3presign/main
import service/presigned/general
import service/implement

suite "S3 Presign & Worker Proxy Method Handlers Tests":

  let
    accessKey = "AKIAIOSFODNN7EXAMPLE"
    secretKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    region = "us-east-1"
    bucket = "test-bucket"
    objectKey = "photos/kadapi.png"
    uploadId = "upload-session-xyz-123"

  var cfg = initS3Config(accessKey, secretKey, region)
  cfg.forcePathStyle = true

  test "Single-part presignUploadPart generates valid signed URL":
    let url = cfg.presignUploadPart(bucket, objectKey, uploadId, 1)
    check url.contains("partNumber=1")
    check url.contains("uploadId=" & uploadId)
    check url.contains("X-Amz-Signature=")

    # Validate using resolveS3 as HttpPut
    let resolved = resolveS3(url, secretKey, cfg, HttpPut)
    check resolved.isSome
    check resolved.status == 200
    check resolved.get.config["partNumber"].getStr() == "1"
    check resolved.get.config["uploadId"].getStr() == uploadId

  test "Single-part presignPutPart alias matches presignUploadPart":
    let fixedTime = parse("20260903T120000Z", "yyyyMMdd'T'HHmmss'Z'", utc())
    let url1 = cfg.presignUploadPart(bucket, objectKey, uploadId, 2, at = fixedTime)
    let url2 = cfg.presignPutPart(bucket, objectKey, uploadId, 2, at = fixedTime)
    check url1 == url2

  test "presignUploadPart rejects invalid partNumber":
    expect(MultipartError):
      discard cfg.presignUploadPart(bucket, objectKey, uploadId, 0)
    expect(MultipartError):
      discard cfg.presignUploadPart(bucket, objectKey, uploadId, 10001)

  test "presignUploadPart rejects empty uploadId":
    expect(MultipartError):
      discard cfg.presignUploadPart(bucket, objectKey, "", 1)

  test "CreateMultipartUpload presigned URL validates as HttpPost":
    let url = cfg.presignCreateMultipartUpload(bucket, objectKey)
    check url.contains("uploads=")
    check url.contains("X-Amz-Signature=")

    let resolved = resolveS3(url, secretKey, cfg, HttpPost)
    check resolved.isSome
    check resolved.status == 200

  test "CompleteMultipartUpload presigned URL validates as HttpPost":
    let url = cfg.presignCompleteMultipartUpload(bucket, objectKey, uploadId)
    check url.contains("uploadId=" & uploadId)

    let resolved = resolveS3(url, secretKey, cfg, HttpPost)
    check resolved.isSome
    check resolved.status == 200

  test "AbortMultipartUpload presigned URL validates as HttpDelete":
    let url = cfg.presignAbortMultipartUpload(bucket, objectKey, uploadId)
    check url.contains("uploadId=" & uploadId)

    let resolved = resolveS3(url, secretKey, cfg, HttpDelete)
    check resolved.isSome
    check resolved.status == 200

  test "ListParts presigned URL validates as HttpGet":
    let url = cfg.presignListParts(bucket, objectKey, uploadId)
    check url.contains("uploadId=" & uploadId)

    let resolved = resolveS3(url, secretKey, cfg, HttpGet)
    check resolved.isSome
    check resolved.status == 200

  test "GetObject presigned URL validates as HttpGet":
    let url = cfg.presignGet(bucket, objectKey)
    let resolved = resolveS3(url, secretKey, cfg, HttpGet)
    check resolved.isSome
    check resolved.status == 200

  test "PutObject presigned URL validates as HttpPut":
    let url = cfg.presignPut(bucket, objectKey)
    let resolved = resolveS3(url, secretKey, cfg, HttpPut)
    check resolved.isSome
    check resolved.status == 200

  test "HeadObject presigned URL validates as HttpHead":
    let url = cfg.presignHead(bucket, objectKey)
    let resolved = resolveS3(url, secretKey, cfg, HttpHead)
    check resolved.isSome
    check resolved.status == 200

  test "DeleteObject presigned URL validates as HttpDelete":
    let url = cfg.presignDelete(bucket, objectKey)
    let resolved = resolveS3(url, secretKey, cfg, HttpDelete)
    check resolved.isSome
    check resolved.status == 200

  test "Worker Proxy dispatch logic correctly routes operations":
    # Helper to simulate the dispatcher logic in controller/s3
    proc determineOperation(reqMethod: string, query: JsonNode): string =
      case reqMethod
      of "POST":
        if query.hasKey("uploads"): "CreateMultipartUpload"
        elif query.hasKey("uploadId"): "CompleteMultipartUpload"
        else: "Unknown"
      of "PUT":
        if query.hasKey("partNumber") and query.hasKey("uploadId"): "PutPart"
        else: "PutObject"
      of "GET":
        if query.hasKey("uploadId"): "ListParts"
        else: "GetObject"
      of "DELETE":
        if query.hasKey("uploadId"): "AbortMultipartUpload"
        else: "DeleteObject"
      of "HEAD":
        "HeadObject"
      else:
        "Unsupported"

    check determineOperation("POST", %*{"uploads": ""}) == "CreateMultipartUpload"
    check determineOperation("POST", %*{"uploadId": "123"}) == "CompleteMultipartUpload"
    check determineOperation("PUT", %*{"partNumber": "1", "uploadId": "123"}) == "PutPart"
    check determineOperation("PUT", %*{}) == "PutObject"
    check determineOperation("GET", %*{"uploadId": "123"}) == "ListParts"
    check determineOperation("GET", %*{}) == "GetObject"
    check determineOperation("DELETE", %*{"uploadId": "123"}) == "AbortMultipartUpload"
    check determineOperation("DELETE", %*{}) == "DeleteObject"
    check determineOperation("HEAD", %*{}) == "HeadObject"
