import strutils

type StorageRepoQuery* = object
  getIdle = """
    SELECT $#
    FROM public.hfb_storage_repo
    ORDER BY storage_used ASC
    LIMIT 1;
  """

func getIdleStorageRepo*(query: StorageRepoQuery; returning = "id"): string =
  query.getIdle % returning
