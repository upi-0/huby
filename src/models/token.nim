{.deprecated.}

import
  base, uuids, strutils

type
  TokenStorageType* = enum
    tb_1, tb_2, tb_3, mb_500

  TokenUsage* = ref object
    totalViews*: int64
    totalSize*: int64

  Token* {.tableName: "hfb_token".} = ref object of Model
    signature* {.unique.}: string
    isSuspended*: bool
    storage*: TokenStorageType

proc generateTokenSignature : string =
  result = "huby--" & ($genUUID()).replace("-")

proc newToken*(st: TokenStorageType = tb_1) : Token =
  let signature = generateTokenSignature()
  Token(signature: signature, storage: st)
