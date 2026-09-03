import
  ../base, publicKey, owner, strutils

type
  Garage* {.tableName: "garage", schemaName: "s3".} = ref object of BaseModel
    name*: string
    isBanned* = false
    storage_used*: int64
    owner*: Owner
    config*: string

proc newGarage* : Garage =
  Garage(
    name: generateKey()
  ).setCreatedAt()

proc emptyGarage*: Garage =
  Garage(owner: new Owner).setCreatedAt()

type GarageQuery* = object
  updateStorageUsed = """
    UPDATE s3.garage
    SET storage_used = storage_used $operator $length
    WHERE
      id = $garageId
    RETURNING storage_used::bigint
  """

func updateStorageUsed*(query: GarageQuery; garageId, length: int, operator = "+"): string =
  assert operator in ["+", "-"]
  query.updateStorageUsed % [
    "operator", operator,
    "length", $length,
    "garageId", $garageId
  ]
