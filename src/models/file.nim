import
  base, token, garage

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
    signature* {.unique.}: string
    repo*: string
    ext*: string
    views*: int
    address*: string

  FileModel* = File    

func newFile*(garage: Garage) : File =
  File(garage: garage)

func emptyFile*: File =
  File(garage: Garage())

func newFile*(token = newToken()) : File {.deprecated.} =
  File(key: token.signature)

func newFile*(key = "") : File {.deprecated.} =
  File(key: key)
