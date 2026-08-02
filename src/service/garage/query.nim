import strutils

type GarageQuery* = object
  updateStorageUsed = """
    UPDATE "hfb_garage"
    SET storage_used = storage_used $operator $length
    WHERE
      id = $garageId AND
      storage_used $operator $length <= max_storage
    RETURNING storage_used::bigint
  """

func updateStorageUsed*(query: GarageQuery; garageId, length: int, operator = "+"): string =
  assert operator in ["+", "-"]
  query.updateStorageUsed % [
    "operator", operator,
    "length", $length,
    "garageId", $garageId
  ]
