## s3presign - generate S3 presigned URLs (AWS Signature V4) without any HTTP calls.
##
## Features:
## * Custom ``endpoint`` (MinIO, R2, Ceph, gateways) or native AWS hosts
## * ``forcePathStyle`` addressing (``host/bucket/key``) with automatic
##   fallback when virtual-host style is impossible (IP endpoints, invalid names)
## * ``multipartThreshold`` / ``multipartChunkSize`` driving the multipart
##   presign helpers (create, per-part upload URLs, complete, abort)
##
## Nothing here performs network I/O; every proc just returns a signed URL.
##
## Quick start:
##   ```nim
##   import s3presign
##   var cfg = initS3Config("ACCESS_KEY", "SECRET_KEY", "us-east-1")
##   cfg.endpoint = "http://localhost:9000"
##   cfg.forcePathStyle = true
##   echo presignGet(cfg, "demo", "hello.txt")
##   ```

import config
export config

import signing
export signing

import url
export url

import multipart
export multipart

import env

proc s3GenerateConf*(namespace: string) : S3Config = 
  S3Config(
    accessKeyId:getEnv("S3_ACCESS_KEY"),
    secretAccessKey:getEnv("S3_SECRET_ACCESS_KEY"),
    region:"us-east-1",
    forcePathStyle:true,
    endpoint:"https://s3.hf.co/" & namespace,
    expiresSeconds: 3600,
    multipartThreshold: 2'i64 * 1024 * 1024 * 1024,
    multipartChunkSize: 2'i64 * 1024 * 1024 * 1024
  )

proc r2GenerateConf*() : S3Config = 
  S3Config(
    accessKeyId:getEnv("R2_ACCESS_KEY"),
    secretAccessKey:getEnv("R2_SECRET_ACCESS_KEY"),
    region:"auto",
    forcePathStyle:true,
    endpoint: getEnv("R2_ENDPOINT"),
    expiresSeconds: 3600,
    multipartThreshold: 4'i64 * 1024 * 1024 * 1024,
    multipartChunkSize: 4'i64 * 1024 * 1024 * 1024
  )
