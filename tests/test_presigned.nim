import unittest, json, times, strutils, uri, hmac
import service/presigned/[general, utils], service/implement

suite "Presigned Service Tests (Extreme Edge Cases & Validation)":

  let
    secretKey = "huby_super_secret_key_123456789!@#$%"
    dummyAction = "put"

  proc generateSignedQuery(
      params: seq[(string, string)],
      secret: string,
      action: string,
      hashPrefixLen = 64
  ): string =
    var queryParts: seq[string] = @[]
    for (k, v) in params:
      queryParts.add(encodeUrl(k) & "=" & encodeUrl(v))
    let noHash = queryParts.join("&")
    let fullHash = hmac_sha256(secret, noHash & action).toHex()
    let chosenHash = fullHash[0 .. min(hashPrefixLen - 1, fullHash.len - 1)]
    result = noHash & "&hash=" & chosenHash

  test "Valid presigned query resolves correctly":
    let
      futureTime = $ (getTime().toUnix() + 3600)
      configJson = $(%*{"replace": true, "webhook": {"use": false}})
      params = @[
        ("key", "documents/report.pdf"),
        ("config", configJson),
        ("exp", futureTime)
      ]
      query = generateSignedQuery(params, secretKey, dummyAction)
      res = resolve(query, secretKey, dummyAction)

    check res.isSome
    check res.status == 200
    let meta = res.get
    check meta.key == "documents/report.pdf"
    check meta.config["replace"].getBool() == true

  test "Extreme Case: Emoji and Unicode in key & config":
    let
      futureTime = $ (getTime().toUnix() + 3600)
      emojiKey = "📁/gambar_kucing_🐱/🔥super_test_🚀.png"
      emojiConfig = $(%*{
        "filename": "🐱_meow_🔥.png",
        "description": "テスト 🚀 😺 Unicode Multi-byte test: äöü ñoñó"
      })
      params = @[
        ("key", emojiKey),
        ("config", emojiConfig),
        ("exp", futureTime)
      ]
      query = generateSignedQuery(params, secretKey, dummyAction)
      res = resolve(query, secretKey, dummyAction)

    check res.isSome
    check res.get.key == emojiKey
    check res.get.config["filename"].getStr() == "🐱_meow_🔥.png"
    check res.get.config["description"].getStr().contains("🚀")

  test "Extreme Case: SQL Injection & XSS Payloads inside key & config":
    let
      futureTime = $ (getTime().toUnix() + 3600)
      sqliKey = "'; DROP TABLE s3.file; DROP TABLE s3.garage; --"
      xssConfig = $(%*{
        "payload": "<script>alert('XSS');</script>",
        "sql": "1' OR '1'='1",
        "nested": {"deep": "admin' --"}
      })
      params = @[
        ("key", sqliKey),
        ("config", xssConfig),
        ("exp", futureTime)
      ]
      query = generateSignedQuery(params, secretKey, dummyAction)
      res = resolve(query, secretKey, dummyAction)

    check res.isSome
    check res.get.key == sqliKey
    check res.get.config["payload"].getStr() == "<script>alert('XSS');</script>"
    check res.get.config["sql"].getStr() == "1' OR '1'='1"

  test "Error Case: Missing &hash= parameter":
    let rawQuery = "key=testfile&config=%7B%7D"
    let res = resolve(rawQuery, secretKey, dummyAction)
    check res.isNone
    check res.status == 400
    check res.errorReason.contains("hash")

  test "Error Case: Hash too short (<= 10 characters)":
    let rawQuery = "key=testfile&config=%7B%7D&hash=123456789"
    let res = resolve(rawQuery, secretKey, dummyAction)
    check res.isNone
    check res.status == 400
    check res.errorReason.contains("short")

  test "Error Case: Tampered Hash (Signature Mismatch)":
    let
      futureTime = $ (getTime().toUnix() + 3600)
      params = @[
        ("key", "safe_file.txt"),
        ("config", "{}"),
        ("exp", futureTime)
      ]
      validQuery = generateSignedQuery(params, secretKey, dummyAction)
      # Tamper the query by changing the key without recalculating hash
      tamperedQuery = validQuery.replace("safe_file.txt", "hacked_file.txt")
      res = resolve(tamperedQuery, secretKey, dummyAction)

    check res.isNone
    check res.status == 403
    check res.errorReason.contains("Invalid Hash")

  test "Error Case: Wrong Action used for Verification":
    let
      futureTime = $ (getTime().toUnix() + 3600)
      params = @[
        ("key", "file.txt"),
        ("config", "{}"),
        ("exp", futureTime)
      ]
      # Hash generated for action "put"
      query = generateSignedQuery(params, secretKey, "put")
      # Verified against action "resolve"
      res = resolve(query, secretKey, "resolve")

    check res.isNone
    check res.status == 403

  test "Error Case: Expired Timestamp":
    let
      pastTime = $ (getTime().toUnix() - 500) # 500 seconds ago
      params = @[
        ("key", "expired.txt"),
        ("config", "{}"),
        ("exp", pastTime)
      ]
      query = generateSignedQuery(params, secretKey, dummyAction)
      res = resolve(query, secretKey, dummyAction)

    check res.isNone
    check res.status == 419
    check res.errorReason.contains("Expired")

  test "Error Case: Malformed JSON in config":
    let
      futureTime = $ (getTime().toUnix() + 3600)
      badConfig = "{ bad_json: undefined, unclosed: "
      params = @[
        ("key", "bad_json.txt"),
        ("config", badConfig),
        ("exp", futureTime)
      ]
      query = generateSignedQuery(params, secretKey, dummyAction)
      res = resolve(query, secretKey, dummyAction)

    check res.isNone
    check res.status == 500

  test "Error Case: Missing required key field in query":
    let
      futureTime = $ (getTime().toUnix() + 3600)
      params = @[
        ("config", "{}"),
        ("exp", futureTime)
      ]
      query = generateSignedQuery(params, secretKey, dummyAction)
      res = resolve(query, secretKey, dummyAction)

    check res.isNone
    check res.status == 500
