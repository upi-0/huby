import
  strutils, asyncdispatch, httpclient

import
  models/all, db

import  
  s3presign/main as smain,
  service/file/main as fmain,
  service/owner/main as owmain,
  service/storage_repo/main as srmain

import
  service/hf/[uploadHf, resolveHf],
  service/file/adapter,
  service/implement,
  service/presigned/[utils, general, types],
  service/cfcors

export
  strutils, asyncdispatch, httpclient

export
  smain, fmain, owmain, srmain

export  
  adapter, resolveHf, adapter, types, implement, general, utils, types, cfcors, uploadHf, db, all

proc getFileStorageConfig*(impl: FileService, key: string, file: var FileModel): ServiceValue[tuple[s3conf: S3Config, bucket: string, address: string]] =
  >> impl.select(key, file)

  if file.storage_repo.isNil:
    return result.none(500, "Storage repository is not assigned to file")

  if file.storage_repo.access_key.len == 0 and file.storage_repo.id > 0:
    let r = impl.conn.selectRepo(file.storage_repo.id, file.storage_repo)
    if r.isNone:
      return result.none(500, "Storage repository not found in database")

  let
    s3conf = file.storage_repo.toS3Config()
    bucket = file.storage_repo.bucket
    address = file.address
  
  implement.some((s3conf: s3conf, bucket: bucket, address: address))  
