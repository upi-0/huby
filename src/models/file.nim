import
  base, garage

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
    repo*: string
    ext*: string
    views* {.deprecated.}: int 
    address*: string

  FileModel* = File    

func newFile*(garage: Garage) : File =
  File(garage: Garage(id: garage.id))

func emptyFile*: File =
  File(garage: Garage())

func newFile*(key = "") : File {.deprecated.} =
  File(key: key)
