import
  strutils

import
  query,
  models/storage_repo, db

import
  service/[implement, types],
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
  let dapdap = loadEncrypterAES256("DB_REPO_SECRET")
  [dapdap.decrypt storageRepo.namespace, storageRepo.bucket].join("/")

proc getUploadToken*(storageRepo: StorageRepo) : string =
  let dapdap = loadEncrypterAES256("DB_REPO_SECRET")
  dapdap.decrypt storageRepo.token
