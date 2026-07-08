import
  base, token

type
  FileIdentifierUse* = enum
    uToken, uKey

  FileIdentifier = ref object of Model
    key*: string

  File* {.tableName: "hfb_file".} = ref object of FileIdentifier
    size*: int64
    isUploaded*: bool
    isDeleted*: bool
    signature* {.unique.}: string
    repo*: string
    ext*: string
    views*: int
    address*: string

  FileModel* = File    

func newFile*(token = newToken()) : File {.deprecated.} =
  File(key: token.signature)

func newFile*(key = "") : File =
  File(key: key)
