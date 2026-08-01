import
  uri, strutils, json

proc loadQuery*(queries: string): JsonNode =
  result = newJObject()

  for da, sa in decodeQuery queries:
    result[da] = newJString sa

proc splitFromHash*(queryField: string): tuple[hash, noHash: string] =
  let hashPos = queryField.find("&hash=")
  (queryField[hashPos + 6 .. ^1], queryField[0 .. hashPos - 1])

export
  json, strutils
