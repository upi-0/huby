import nimcrypto, std/sysrand, sequtils, std/os, strutils, env

type EncrypterAES256 = object of RootObj
  key: array[32, byte]

proc loadEncrypterAES256*(envField: string): EncrypterAES256 =
  let
    keyStr = getEnv(envField)
    maxLen = min(keyStr.len, 32)

  var keyArr: array[32, byte]  

  if maxLen > 0:
    copyMem(addr keyArr[0], unsafeAddr keyStr[0], maxLen)
    
  result = EncrypterAES256(key: keyArr)

proc encrypt*(cry: EncrypterAES256; plainText: string): string =
  var
    ctx: CTR[aes256]
    ivb: array[16, byte]
  
  var  
    ptBytes = newSeq[byte](plainText.len)
    ctBytes = newSeq[byte](plainText.len)

  if plainText.len > 0:
    copyMem(addr ptBytes[0], unsafeAddr plainText[0], plainText.len)

  block:
    discard urandom(ivb)

  block:
    ctx.init(cry.key, ivb)
    if plainText.len > 0:
      ctx.encrypt(ptBytes, ctBytes)  
    ctx.clear() 

  return [ivb[0 .. 15], ctBytes].concat.toHex.toLower

proc decrypt*(cry: EncrypterAES256; cipherHex: string): string =
  var  
    ctx: CTR[aes256]
    textStr = cipherHex.toUpper.parseHexStr()
    text = newSeq[byte](textStr.len)

  if textStr.len > 0:
    copyMem(addr text[0], unsafeAddr textStr[0], textStr.len)
    
  if text.len < 16:
    raise newException(ValueError, "Ciphertext terlalu pendek, kehilangan IV")

  let
    iv = text[0 .. 15]
    cipherText = text[16 .. ^1]
  var dtBytes = newSeq[byte](cipherText.len)

  block:
    ctx.init(cry.key, iv)
    if cipherText.len > 0:
      ctx.decrypt(cipherText, dtBytes)
    ctx.clear()

  var plainText = newString(dtBytes.len)
  if dtBytes.len > 0:
    copyMem(addr plainText[0], addr dtBytes[0], dtBytes.len)

  return plainText
