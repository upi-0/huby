import
  strutils

import
  query,
  models/storage_repo, db

import
  service/[implement, types],
  s3presign/main,
  crypto  

proc getIdleStorageRepo*(fcon: DbConn): ServiceValue[StorageRepo] =
  let query = StorageRepoQuery()
  var storageRepo = new StorageRepo
  
  try:
    fcon.rawSelect(
      query.getIdleStorageRepo("*"),
      storageRepo)
    storageRepo.some()

  except:
    result.none(500, "No Idle Repo found.")  

proc selectRepo*(fcon: DbConn; id: int; repo: var StorageRepo): ServiceValue[bool] =
  try:
    fcon.select(repo, "hfb_storage_repo.id = $#" % $id)
    some(true)

  except:
    return result.none(404)

proc getRepoAddress*(storageRepo: StorageRepo) : string =
  let c = loadEncrypterAES256("DB_REPO_SECRET")
  [c.decrypt storageRepo.namespace, storageRepo.bucket].join("/")

proc getUploadToken*(storageRepo: StorageRepo) : string =
  let c = loadEncrypterAES256("DB_REPO_SECRET")
  c.decrypt storageRepo.token

proc toS3Config*(storageRepo: StorageRepo) : S3Config =
  let c = loadEncrypterAES256("DB_REPO_SECRET")

  S3Config(
    accessKeyId: c.decrypt(storageRepo.access_key),
    secretAccessKey: c.decrypt(storageRepo.secret_access_key),
    forcePathStyle: true,
    region: "us-east-1",
    endpoint: "https://s3.hf.co/" & c.decrypt(storageRepo.namespace),
    expiresSeconds: 3600 * 3,
    multipartThreshold: 95'i64 * 1024 * 1024,
    multipartChunkSize: 95'i64 * 1024 * 1024    
  )

