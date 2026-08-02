import
  json, times, strutils

import
  hmac

import
  ../types, utils

const
  Key = "dapdap"
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

proc getPrivateKey(publicKey: string): ServiceValue[string] =
  some Key

proc resolve*(queryField, publicKey: string, action = "static"): ServiceValue[MetaObj] = 
  validateHash()

  let
    (hash, noHash) = splitFromHash queryField
    query = loadQuery noHash
  
  block calculateHash:
    let
      key = getPrivateKey publicKey
      calculatedHash = hmac_sha256(key.get, noHash & action).toHex()

    if not calculatedHash.startsWith hash:
      echo noHash & action
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

when isMainModule:
  proc persist =
    const
      queryField = "key=linux%3Arijal&config=%7B%7D&hash=f248ff256267598e2177cedd482bc3869f6e94af0cc92d0059f4e09b064372f9"
      publicKey = "MAMAM"

    let melihat = resolve(queryField, publicKey, "static")

    try:
      assert melihat.isSome
      echo melihat.get.key

    except AssertionDefect:
      echo melihat.errorReason

  persist()
