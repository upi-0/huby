import
  prologue, context, json,
  strutils, asyncdispatch

import
  models/all, db

import  
  service/owner/main,
  service/[s3, webhook],
  service/[types, implement],
  service/presigned/[utils, general, types],
  service/cfcors

proc setWebhook*(impl: FileService; response: S3BridgeResponse): void =
  let hooks = impl.garageEndpoints(response.returning.action)

  if hooks.isSome:
    response.use_webhook = true
    response.webhook = hooks.get

  else:
    response.use_webhook = false  

proc s3handler*(ctx: Context) {.async.} =
  ## Worker Proxy S3 Bridge Handler
  ##
  ## Expected payload forwarded by Worker Proxy:
  ## {
  ##    "method": "GET" | "PUT" | "POST" | "DELETE" | "HEAD",
  ##    "url": "http://localhost:6868/<OWNER>/<BUCKET_NAME>/<FILE_KEY>?...",
  ##    "contentLength": "1048576"
  ## }
  block:
    ctx.json()
    ctx.response.headers.add("Access-Control-Allow-Methods", "GET, PUT, POST, DELETE, HEAD, OPTIONS")
    ctx.response.headers.add("Access-Control-Allow-Headers", "*")

  if ctx.request.reqMethod == HttpOptions and ctx.getQueryParams("url").len == 0:
    await ctx.send("", Http204)
    return

  var payload: JsonNode
  try:
    payload = %*{
      "url": ctx.getQueryParams("url"),
      "contentLength": ctx.getQueryParams("contentLength"),
      "method": ctx.getQueryParams("method"),
      "origin": ctx.getQueryParams("origin"),
      "requestMethod": ctx.getQueryParams("requestMethod"),
      "requestHeaders": ctx.getQueryParams("requestHeaders")
    }
    echo "QUERY_PARAMS: " & $payload

  except Exception:
    await ctx.send(%*{"error": getCurrentExceptionMsg()}, Http400)
    return

  if not payload.hasKey("url") or payload["url"].getStr().len == 0:
    await ctx.send(%*{"error": "Missing 'url' field in payload"}, Http400)
    return

  let
    url = payload["url"].str
    rawMethod = if payload.hasKey("method") and payload["method"].getStr().len > 0:
                  payload["method"].getStr()
                elif ctx.request.reqMethod == HttpOptions:
                  "OPTIONS"
                else:
                  "GET"
    reqMethod = rawMethod.toUpperAscii()
    cleanUrl = url.replace("http://").replace("https://").split("?")[0]
    path = cleanUrl.split("/")

  if path.len < 3:
    await ctx.send(%*{"error": "Invalid URL format: expected http://host/owner/bucket/key"}, Http400)
    return

  let
    owner = path[1]
    bucket = path[2]
    id = owner.ownerId()
    impl = await newFileService(id.get, bucket)

  defer:
    impl.get.conn.stop()

  if impl.isNone:
    await ctx.send(%*{"error": "Bucket/Garage not found"}, Http404)
    return

  let query = if url.contains("?"): url.split("?")[^1].loadQuery() else: newJObject()

  let uploadId = if query.hasKey("uploadId"): query["uploadId"].getStr()
                 elif payload.hasKey("uploadId"): payload["uploadId"].getStr()
                 else: ""

  let partNumberStr = if query.hasKey("partNumber"): query["partNumber"].getStr()
                      elif payload.hasKey("partNumber"): payload["partNumber"].getStr()
                      else: ""

  let hasUploads = query.hasKey("uploads") or payload.hasKey("uploads")

  let contentLength = block:
    if payload.hasKey("contentLength"):
      try: payload["contentLength"].getStr().parseInt()
      except Exception:
        try: payload["contentLength"].getInt()
        except Exception: 0
    else: 0

  let
    key = block:
      if path.len > 3:
        path[3 .. ^1].join("/")
      else:
        url.split("/")[^1].split("?")[0]

    responseObj: S3BridgeResponse = impl.get.newResponse()

  block:
    responseObj.config.key = key
    responseObj.returning.bucket = bucket
    responseObj.returning.owner_namespace = owner

  var opResult: ServiceValue[string]

  case reqMethod
  of "OPTIONS":
    let
      headerTable = ctx.request.headers.table
      origin = block:
        if headerTable.hasKey("origin") and headerTable["origin"].len > 0: headerTable["origin"][0]
        else: ""

      requestMethod = block:
        if headerTable.hasKey("access-control-request-method") and headerTable["access-control-request-method"].len > 0: headerTable["access-control-request-method"][0]
        else: ""

      requestHeadersRaw = block:
        if headerTable.hasKey("access-control-request-headers") and headerTable["access-control-request-headers"].len > 0: headerTable["access-control-request-headers"][0]
        else: ""
                
      requestHeaders = block:
        if requestHeadersRaw.len > 0: requestHeadersRaw.split(",")
        else: @[]

    let
      corsRes = impl.get.handleOptions(origin, requestMethod, requestHeaders)
      match = corsRes.get
    
    ctx.response.headers["access-control-allow-origin"] = @[match.allowOrigin]
    ctx.response.headers["access-control-allow-methods"] = @[match.allowMethods.join(", ")]
    if match.allowHeaders.len > 0:
      ctx.response.headers["access-control-allow-headers"] = @[match.allowHeaders.join(", ")]
    if match.exposeHeaders.len > 0:
      ctx.response.headers["access-control-expose-headers"] = @[match.exposeHeaders.join(", ")]
    if match.maxAgeSeconds > 0:
      ctx.response.headers["access-control-max-age"] = @[$match.maxAgeSeconds]

    responseObj.status = 204
    responseObj.config.headers = match.toHeadersJson()

    return ctx.send(%responseObj, Http200, formatJson = false)

  of "POST":
    if hasUploads:
      opResult = impl.get.handleCreateMultipartUpload(url, key, contentLength)
      responseObj.action("CreateMultipartUpload", opResult)

    elif uploadId.len > 0:
      opResult = await impl.get.handleCompleteMultipartUpload(url, key, uploadId)
      responseObj.action("CompleteMultipartUpload", opResult, impl.get.handleGetObject(url, key))

    else:
      await ctx.send(%*{"error": "POST request must specify 'uploads' or 'uploadId'"}, Http400)
      return

  of "PUT":
    if partNumberStr.len > 0 and uploadId.len > 0:
      var partNumber = 0
      try:
        partNumber = parseInt(partNumberStr)
      except ValueError:
        await ctx.send(%*{"error": "Invalid partNumber format"}, Http400)
        return
      
      block:
        opResult = impl.get.handlePutPart(url, key, uploadId, partNumber, contentLength)
        responseObj.action("PutPart", opResult)

    else:
      opResult = impl.get.handlePutObject(url, key, contentLength)
      responseObj.action("PutObject", opResult, impl.get.handleGetObject(url, key))

  of "GET":
    if uploadId.len > 0:
      opResult = impl.get.handleListParts(url, key, uploadId)
      responseObj.action("ListParts", opResult)

    else:
      opResult = impl.get.handleGetObject(url, key)
      responseObj.action("GetObject", opResult, opResult)
      responseObj.config.secret_access_key = impl.get.garage.owner.secret_access_key

  of "DELETE":
    if uploadId.len > 0:
      opResult = impl.get.handleAbortMultipartUpload(url, key, uploadId)
      responseObj.action("AbortMultipartUpload", opResult)
        
    else:
      opResult = await impl.get.handleDeleteObject(url, key)
      responseObj.action("DeleteObject", opResult)

  of "HEAD":
    opResult = impl.get.handleHeadObject(url, key)
    responseObj.action("HeadObject", opResult)

  else:
    await ctx.send(%*{"error": "Unsupported HTTP method: " & reqMethod}, Http405)
    return

  if opResult.isNone:
    await ctx.send(%*{"error": opResult.errorReason}, HttpCode(opResult.status))
    return

  block:
    impl.get.setWebhook(responseObj)
    await ctx.send(%responseObj, Http200, formatJson = false)
