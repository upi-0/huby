import
  ../base, strutils

type
  StorageRepo* {.tableName: "repo", schemaName: "storage".} = ref object of BaseModel
    namespace*, bucket*: string
    token*, access_key*, secret_access_key*: string
    storage_used*: int64

proc newStorageRepo*() : StorageRepo {.inline.} =
  result = StorageRepo(createdAt: getTime().toUnix())

type StorageRepoQuery* = object
  getIdle = """
    SELECT $#
    FROM storage.repo
    ORDER BY storage_used ASC
    LIMIT 1;
  """

func getIdleStorageRepo*(query: StorageRepoQuery; returning = "id"): string =
  query.getIdle % returning
