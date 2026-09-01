import
  base, garage, storage_repo

type
  FileIdentifierUse* = enum
    uToken, uKey

  FileIdentifier = ref object of Model
    key*: string

  File* {.tableName: "hfb_file".} = ref object of FileIdentifier
    garage*: Garage
    size*: int64
    isUploaded*: bool
    isDeleted*: bool
    persistAccess* = true
    signature* {.unique.}: string
    repo* {.deprecated.}: string
    ext*: string
    views* {.deprecated.}: int 
    address*: string
    storage_repo*: StorageRepo

  FileModel* = File    

proc newFile*(garage: Garage) : File =
  File(garage: Garage(id: garage.id), storage_repo: newStorageRepo())

proc emptyFile*: File =
  File(garage: Garage(), storage_repo: newStorageRepo())

func newFile*(key = "") : File {.deprecated.} =
  File(key: key)
