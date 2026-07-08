{.deprecated.}

import
  db, models/token, strutils, types

type
  TokenUsage* = ref object
    totalViews*: int64
    totalSize*: int64

proc lookToken*(id: string) : ServiceValue[Token] =
  var tkn = new(Token)
  result = none(Token, 404, "Not Found")

  if id == "":
    return
  
  try:
    conn.select(tkn, "hfb_token.signature = '$#'" % id)
    result = some tkn

  except NotFoundError:
    discard

proc lookTokenUsage*(id: string) : ServiceValue[TokenUsage] =
  var
    usage = new(TokenUsage)
    tkn = newToken()

  try:
    const query =
      """
      SELECT
        COALESCE(SUM(f.views)::bigint, 0) AS totalViews,
        COALESCE(SUM(f.size)::bigint, 0) AS totalSize
      FROM hfb_file f
      JOIN hfb_token t ON f.token = t.id
      WHERE t.signature = '$#'
      """
    
    conn.select(tkn, "hfb_token.signature = '$#'" % id)
    conn.rawSelect(query % id, usage)

  except NotFoundError:
    return none(TokenUsage, 404)

  return some usage

proc resolveCapacity(cpt: string) : TokenStorageType {.gcsafe.} =
  for token in TokenStorageType:
    if $token == cpt:
      return token

  assert false

proc createToken*(storageType: string) : ServiceValue[Token] =
  result = none(Token, 404, "Lo goblok coey")

  try:
    var
      cap = resolveCapacity(storageType)
      tkn = newToken(cap)

    conn.insert(tkn)
    result = some(tkn, 201)

  except AssertionDefect:
    discard

proc isValidToken*(tokenSignature: string) : ServiceValue[bool] =
  if tokenSignature == "":
    return none(bool, 400, "`token` is required.")
  
  try:
    result = block:
      if conn.exists(Token, "hfb_token.signature = '$#'" % tokenSignature):
        some(true, 200)
      else:
        none(bool, 404, "Token not found")

  except Exception:
    return none(bool, 500, getCurrentExceptionMsg())
