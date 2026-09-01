import
  base, times

type
  StorageRepo* {.tableName: "hfb_storage_repo".} = ref object of Model
    namespace*, bucket*: string
    token*, access_key*, secret_access_key*: string
    createdAt*, storage_used*: int64

proc newStorageRepo*() : StorageRepo {.inline.} =
  result = StorageRepo(createdAt: getTime().toUnix())
