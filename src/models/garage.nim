import
  base, publicKey

type
  Garage* {.tableName: "hfb_garage".} = ref object of Model
    name*: string
    key*: string
    isBanned* = false
    storage_used*: int64
    max_storage*: int64

proc newGarage* : Garage =
  Garage(
    name: generateKey(),
    key: generateKey("", 4, "huby_"),
  )
