import unittest, json, times, strutils, uri, httpcore
import service/presigned/general
import s3presign/main
import service/implement

suite "S3 Presigned Validation (resolves3) Tests":

  let
    accessKey = "AKIAIOSFODNN7EXAMPLE"
    secretKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    region = "us-east-1"
    bucket = "mybucket"
    objectKey = "folder/photo.jpg"

  test "Valid S3 presigned GET URL succeeds":
    var cfg = initS3Config(accessKey, secretKey, region)
    cfg.forcePathStyle = true
    let signedUrl = presignGet(cfg, bucket, objectKey)
    
    let res = resolves3(signedUrl, secretKey, cfg, HttpGet)
    check res.isSome
    check res.status == 200
    check res.get.key == objectKey
    check res.get.config.hasKey("X-Amz-Algorithm")
    check res.get.config["X-Amz-Algorithm"].getStr() == "AWS4-HMAC-SHA256"
    check res.get.config.hasKey("X-Amz-Credential")
    check res.get.config.hasKey("X-Amz-Signature")

  test "Valid S3 presigned PUT URL with custom endpoint":
    var cfg = initS3Config(accessKey, secretKey, "auto")
    cfg.endpoint = "http://localhost:9000"
    cfg.forcePathStyle = true
    let signedUrl = presignPut(cfg, bucket, "uploads/doc.pdf")

    let res = resolves3(signedUrl, secretKey, cfg, HttpPut)
    check res.isSome
    check res.status == 200
    check res.get.key == "uploads/doc.pdf"

  test "Valid S3 presigned URL using secret in S3Config without explicit secret parameter":
    var cfg = initS3Config(accessKey, secretKey, region)
    cfg.forcePathStyle = true
    let signedUrl = presignGet(cfg, bucket, objectKey)

    let res = resolves3(signedUrl, cfg = cfg, httpMethod = HttpGet)
    check res.isSome
    check res.status == 200
    check res.get.key == objectKey

  test "Validation fails with 403 on wrong HTTP method":
    var cfg = initS3Config(accessKey, secretKey, region)  
    cfg.forcePathStyle = true
    let signedUrl = presignGet(cfg, bucket, objectKey) # generated for GET

    let res = resolves3(signedUrl, secretKey, cfg, HttpPut) # validated as PUT
    check res.isNone
    check res.status == 403
    check res.errorReason.contains("Signature")

  test "Validation fails with 403 on tampered query parameter":
    var cfg = initS3Config(accessKey, secretKey, region)
    cfg.forcePathStyle = true
    let signedUrl = presignGet(cfg, bucket, objectKey)
    let tamperedUrl = signedUrl.replace("photo.jpg", "hacked.jpg")

    let res = resolves3(tamperedUrl, secretKey, cfg, HttpGet)
    check res.isNone
    check res.status == 403
    check res.errorReason.contains("Signature")

  test "Validation fails with 403 on invalid secret key":
    var cfg = initS3Config(accessKey, secretKey, region)
    cfg.forcePathStyle = true
    let signedUrl = presignGet(cfg, bucket, objectKey)

    let res = resolves3(signedUrl, "WRONG_SECRET_KEY", cfg, HttpGet)
    check res.isNone
    check res.status == 403
    check res.errorReason.contains("Signature")

  test "Validation fails with 419 on expired timestamp":
    var cfg = initS3Config(accessKey, secretKey, region)
    cfg.forcePathStyle = true
    let pastInstant = getTime().utc - initDuration(hours = 2)
    let signedUrl = presignGet(cfg, bucket, objectKey, at = pastInstant)

    let res = resolves3(signedUrl, secretKey, cfg, HttpGet)
    check res.isNone
    check res.status == 419
    check res.errorReason.contains("Expired")

  test "Validation fails with 400 on missing X-Amz-Signature":
    let badUrl = "https://s3.us-east-1.amazonaws.com/mybucket/key.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKID/20260902/us-east-1/s3/aws4_request&X-Amz-Date=20260902T000000Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host"
    let res = resolves3(badUrl, secretKey)
    check res.isNone
    check res.status == 400
    check res.errorReason.contains("X-Amz-Signature")

  test "Validation fails with 400 on missing secret access key":
    var cfg = initS3Config(accessKey, "", region)
    let badUrl = "https://s3.us-east-1.amazonaws.com/mybucket/key.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256"
    let res = resolves3(badUrl, secretAccessKey = "", cfg = cfg)
    check res.isNone
    check res.status == 400
