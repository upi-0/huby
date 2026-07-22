import
  base, token, garage

type
  FileIdentifierUse* = enum
    uToken, uKey

  FileIdentifier = ref object of Model
    key*: string

  File* {.tableName: "hfb_file".} = ref object of FileIdentifier
    storage*: Garage
    size*: int64
    isUploaded*: bool
    isDeleted*: bool
    signature* {.unique.}: string
    repo*: string
    ext*: string
    views*: int
    address*: string

  FileModel* = File    

func newFile*(storage: Garage) : File =
  File(storage: storage)

func newFile*(token = newToken()) : File {.deprecated.} =
  File(key: token.signature)

func newFile*(key = "") : File {.deprecated.} =
  File(key: key)
