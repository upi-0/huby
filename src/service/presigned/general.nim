import
  json, times, strutils

import
  hmac

import
  ../implement, utils,
  models/garage

const
  HashInitializer = "&hash="

type
  MetaObj* = ref object of RootObj
    key*: string
    config*: JsonNode    

template validateHash() =
  if not queryField.contains(HashInitializer):
    return result.none(400, "Where is the fucking hash?")

  if queryField[queryField.find(HashInitializer)  + 6 .. ^1].len <= 10:
    return result.none(400, "Hash to short")    

proc resolve*(queryField, privateKey: string, action = "static"): ServiceValue[MetaObj] = 
  validateHash()

  let
    (hash, noHash) = splitFromHash queryField
    query = loadQuery noHash
  
  block calculateHash:
    let
      key = privateKey
      calculatedHash = hmac_sha256(key, noHash & action).toHex()

    if not calculatedHash.startsWith hash:
      echo "KEY : ", privateKey      
      echo "HASH: ", calculatedHash

      return result.none(403, "Invalid Hash")

  block defineResult:
    try:
      let terbungkam = MetaObj(
        key: query["key"].str,
        config: parseJson query["config"].str
      )

      if query.hasKey("exp"):
        let exp = parseInt query["exp"].str

        if exp < getTime().toUnix():
          return result.none(419, "Expired")

      return some terbungkam  

    except Exception:
      return result.none(500, "Error.")
