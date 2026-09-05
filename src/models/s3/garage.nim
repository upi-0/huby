import
  ../base, publicKey, owner

type
  Garage* {.tableName: "garage", schemaName: "s3".} = ref object of BaseModel
    name*: string
    isBanned* = false
    owner*: Owner
    config*: string

proc newGarage* : Garage =
  Garage(
    name: generateKey()
  ).setCreatedAt()

proc emptyGarage*: Garage =
  Garage(owner: new Owner).setCreatedAt()
