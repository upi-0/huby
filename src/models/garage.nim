import
  base, publicKey

type
  Garage* {.tableName: "hfb_file".} = ref object of Model
    name*: string
    key*: string

proc newGarage* : Garage =
  Garage(
    name: generateKey(),
    key: generateKey("", 4, "huby_")
  )
