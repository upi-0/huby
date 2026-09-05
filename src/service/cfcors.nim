import
  json, strutils

type
  CorsRule* = object
    allowedOrigins*: seq[string]
    allowedMethods*: seq[string]
    allowedHeaders*: seq[string]
    exposeHeaders*: seq[string]
    maxAgeSeconds*: int

  CorsConfig* = seq[CorsRule]

  CorsMatchResult* = object
    matched*: bool
    allowOrigin*: string
    allowMethods*: seq[string]
    allowHeaders*: seq[string]
    exposeHeaders*: seq[string]
    maxAgeSeconds*: int

func getFieldSeq(node: JsonNode, keys: openArray[string]): seq[string] =
  for key in keys:
    if node.hasKey(key) and node[key].kind == JArray:
      for item in node[key]:
        if item.kind == JString:
          result.add item.getStr()
      return result
  return @[]

func getFieldInt(node: JsonNode, keys: openArray[string], defaultVal: int = 0): int =
  for key in keys:
    if node.hasKey(key):
      if node[key].kind == JInt:
        return node[key].getInt()
      elif node[key].kind == JString:
        try:
          return node[key].getStr().parseInt()
        except ValueError:
          discard
  return defaultVal

proc parseCorsRule*(node: JsonNode): CorsRule =
  result.allowedOrigins = node.getFieldSeq(["AllowedOrigins", "allowedOrigins", "allowed_origins"])
  result.allowedMethods = node.getFieldSeq(["AllowedMethods", "allowedMethods", "allowed_methods"])
  result.allowedHeaders = node.getFieldSeq(["AllowedHeaders", "allowedHeaders", "allowed_headers"])
  result.exposeHeaders = node.getFieldSeq(["ExposeHeaders", "exposeHeaders", "expose_headers"])
  result.maxAgeSeconds = node.getFieldInt(["MaxAgeSeconds", "maxAgeSeconds", "max_age_seconds"], 0)

proc isValid*(rule: CorsRule): bool =
  rule.allowedOrigins.len > 0 or rule.allowedMethods.len > 0

proc parseCorsConfig*(node: JsonNode): CorsConfig =
  if node.isNil:
    return @[]

  if node.kind == JArray:
    for item in node:
      if item.kind == JObject:
        let r = parseCorsRule(item)
        if r.isValid:
          result.add r
  elif node.kind == JObject:
    if node.hasKey("rules") and node["rules"].kind == JArray:
      return parseCorsConfig(node["rules"])
    elif node.hasKey("CORSRules") and node["CORSRules"].kind == JArray:
      return parseCorsConfig(node["CORSRules"])
    else:
      let r = parseCorsRule(node)
      if r.isValid:
        result.add r

proc parseCorsConfig*(jsonStr: string): CorsConfig =
  if jsonStr.strip().len == 0:
    return @[]
  try:
    let node = parseJson(jsonStr)
    return parseCorsConfig(node)
  except Exception:
    return @[]

proc toJson*(rule: CorsRule): JsonNode =
  result = newJObject()
  result["AllowedOrigins"] = %rule.allowedOrigins
  result["AllowedMethods"] = %rule.allowedMethods
  if rule.allowedHeaders.len > 0:
    result["AllowedHeaders"] = %rule.allowedHeaders
  if rule.exposeHeaders.len > 0:
    result["ExposeHeaders"] = %rule.exposeHeaders
  if rule.maxAgeSeconds > 0:
    result["MaxAgeSeconds"] = %rule.maxAgeSeconds

proc toJson*(cfg: CorsConfig): JsonNode =
  result = newJArray()
  for rule in cfg:
    result.add rule.toJson()

proc `$`*(cfg: CorsConfig): string =
  $cfg.toJson()

proc matchOrigin(pattern, origin: string): bool =
  let
    pat = pattern.strip()
    orig = origin.strip()

  if pat == "*" or pat == orig:
    return true

  if pat.contains("://*."):
    let parts = pat.split("://*.", 1)
    let scheme = parts[0] & "://"
    let suffix = parts[1]
    if orig.startsWith(scheme) and orig.endsWith(suffix):
      let mid = orig[scheme.len .. ^(suffix.len + 1)]
      if mid.len > 0 and not mid.contains("/"):
        return true
  elif pat.startsWith("*."):
    let suffix = pat[2 .. ^1]
    if orig.endsWith(suffix):
      return true

  return false

proc matchMethod(allowedMethods: seq[string], reqMethod: string): bool =
  let upperReq = reqMethod.strip().toUpperAscii()
  for m in allowedMethods:
    let upperM = m.strip().toUpperAscii()
    if upperM == "*" or upperM == upperReq:
      return true
  return false

proc matchHeaders(allowedHeaders: seq[string], reqHeaders: seq[string]): bool =
  if reqHeaders.len == 0:
    return true

  for ah in allowedHeaders:
    if ah.strip() == "*":
      return true

  var lowerAllowed: seq[string] = @[]
  for ah in allowedHeaders:
    lowerAllowed.add ah.strip().toLowerAscii()

  for rh in reqHeaders:
    let cleanRh = rh.strip().toLowerAscii()
    if cleanRh.len > 0 and cleanRh notin lowerAllowed:
      return false

  return true

proc matchCors*(
    cfg: CorsConfig,
    origin: string,
    reqMethod: string,
    reqHeaders: seq[string] = @[]
): CorsMatchResult =
  if origin.strip().len == 0 or reqMethod.strip().len == 0:
    return CorsMatchResult(matched: false)

  for rule in cfg:
    var originMatched = false
    var matchedPattern = ""

    for pat in rule.allowedOrigins:
      if matchOrigin(pat, origin):
        originMatched = true
        matchedPattern = pat
        break

    if not originMatched:
      continue

    if not matchMethod(rule.allowedMethods, reqMethod):
      continue

    if not matchHeaders(rule.allowedHeaders, reqHeaders):
      continue

    result.matched = true
    result.allowOrigin = if matchedPattern == "*": "*" else: origin
    result.allowMethods = rule.allowedMethods
    result.allowHeaders = if reqHeaders.len > 0 and not rule.allowedHeaders.contains("*"):
                            reqHeaders
                          else:
                            rule.allowedHeaders
    result.exposeHeaders = rule.exposeHeaders
    result.maxAgeSeconds = rule.maxAgeSeconds
    return result

  return CorsMatchResult(matched: false)

proc toHeadersJson*(res: CorsMatchResult): JsonNode =
  result = newJObject()
  if res.matched:
    result["Access-Control-Allow-Origin"] = %res.allowOrigin
    result["Access-Control-Allow-Methods"] = %res.allowMethods.join(", ")
    if res.allowHeaders.len > 0:
      result["Access-Control-Allow-Headers"] = %res.allowHeaders.join(", ")
    if res.exposeHeaders.len > 0:
      result["Access-Control-Expose-Headers"] = %res.exposeHeaders.join(", ")
    if res.maxAgeSeconds > 0:
      result["Access-Control-Max-Age"] = %($res.maxAgeSeconds)
