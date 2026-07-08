## Requires:
##    - Expired
##    - User Agent
##    - IP

import
  nimcrypto, std/sysrand, base64, uri

import
  json, times, strutils

import
  db, models/file

import
  env, types

type
  UploadPolicy* = tuple  
    ip, ua, key, request: string

  TargetPolicy* = ref object
    request*, key*: string

var
  iv*: ptr array[16, byte]
  ke*: ptr array[32, byte]

block:
  block:
    var myIv: array[16, byte]
    if urandom(myIv): iv = myIv.addr

  block:
    var key = cast[array[32, byte]]("MANG UJANG")
    ke = key.addr

proc encryptAES256(key: array[32, byte], iv: array[16, byte], plainText: string): seq[byte] =
  var
    ctx: CTR[aes256]
    ptBytes = cast[seq[byte]](plainText)
    ctBytes = newSeq[byte](ptBytes.len)

  block:
    ctx.init(key, iv)
    ctx.encrypt(ptBytes, ctBytes)  
    ctx.clear() 

  return ctBytes

proc decryptAES256(key: array[32, byte], iv: array[16, byte], cipherText: seq[byte]): string =
  var
    ctx: CTR[aes256]
    dtBytes = newSeq[byte](cipherText.len)

  block:
    ctx.init(key, iv)
    ctx.decrypt(cipherText, dtBytes)
    ctx.clear()

  return cast[string](dtBytes)

proc generatePolicy(policy: UploadPolicy) : string =
  # Generate Policy for upload.
  result = $(%*{
    "user-agent": policy.ua,
    "ip": policy.ip,
    "request": policy.request,
    "key": policy.key,
    "exp": (getTime() + 3.hours).toUnix()
  })

proc generateUrl*(ip, ua, key: string; replace = false) : ServiceValue[string] =
  if key == "":
    return result.none(400, "`key` as `k` is required.")

  let fileExist = conn.exists(FileModel, "hfb_file.key = '$#'" % key)
  var repl = "upload"

  if replace and fileExist:
    repl = "replace"

  elif not replace and fileExist:
    return result.none(409, "File with the same key already exists. Bypass by adding `replace=true`")

  let
    policy: UploadPolicy = (ip, ua, key, repl)
    enc = encryptAES256(ke[], iv[], generatePolicy(policy))

  result = some "/.huby/wpolicy?p=" & enc.encode

proc resolvePolicy*(ip, ua, requestedPolicyPayload: string) : ServiceValue[TargetPolicy] =
  var
    expired = (getTime())
    policyJson: string
    res = new TargetPolicy
  
  try:
    policyJson = decryptAES256(ke[], iv[], cast[seq[byte]](requestedPolicyPayload.decode))
    assert policyJson.startsWith("{")

  except AssertionDefect:
    return result.none(403)

  let payload = parseJson policyJson

  try:
    assert payload["user-agent"].str == ua
    assert payload["ip"].str == ip
    assert ["upload", "replace"].contains payload["request"].str
    assert payload["exp"].num > expired.toUnix()

    block:
      res.request = payload["request"].str
      res.key = payload["key"].str
      return some res

  except KeyError, AssertionDefect:
    return result.none(403, "Invalid hash.")

proc main() =
  let
    pesanRahasia = generateUrl("11.22.33.44", "Mozilla Firefox.", "moze:xxx:rijal")
    po = resolvePolicy("11.22.33.44", "Mozilla Firefox.", pesanRahasia.get.replace("/.huby?p="))
  
  try:
    echo pesanRahasia.get
    echo po.get.request

  except AssertionDefect:
    echo po.status
    echo po.errorReason  
