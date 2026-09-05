import
  asyncdispatch, json, times, hmac, env, strutils, options

import
  http/client,
  httpclient

import
  models/all,
  service/[implement, types],
  db

type
  WebhookPayload*[T] = ref object of RootObj
    event*: string
    timestamp*: string
    data*: T

  WebhookConnection* = ref object of RootObj
    garageKey*: string
    garageId*: int
    origin*: string
    endpoint*: string
    capture: seq[JsonNode]

  WebhookAbort* = ref object of CatchableError
    event*: string
    message*: string

proc createWebhookConnection*(garageKey, origin, endpoint: string; garageId: int ; capture = newJArray()) : WebhookConnection =
  WebhookConnection(
    garageKey: garageKey,
    garageId: garageId,
    origin: origin,
    endpoint: endpoint,
    capture: capture.getElems newSeq[JsonNode](0)
  )

proc sendPayload(conn: WebhookConnection; payload: WebhookPayload) : Future[Option[AsyncResponse]] {.async.} =
  let
    http: HttpConnection = inheritHttpConnection()
    client = http.client
    body = $(%*payload)
    headers = newHttpHeaders {
      "content-type": "application/json",
      "x-huby-creator" : "github.com/upi-0",
      "x-huby-signature-256" : "sha256=" & hmac_sha256(conn.garageKey, body).toHex()
    }

  defer:
    http.stop()

  var
    response: AsyncResponse
    url = conn.origin & conn.endpoint

  if getEnv("WEBHOOK_ACTIVATE").parseBool:
    headers["x-target"] = @[conn.origin]
    headers["x-secret"] = @[getEnv("WEBHOOK_SECRET")]
    url = getEnv("WEBHOOK_URL") & conn.endpoint

  try:
    response = await client.request(
      url = url,
      httpMethod = HttpPost,
      body = body,
      headers = headers
    )

    return options.some response

  except Exception:
    none AsyncResponse

proc sendHook*[T](conn: WebhookConnection; event: string; data: T) =
  if (not conn.capture.contains(%event)) and conn.capture.len > 0:
    return

  let
    payload = WebhookPayload[T](
      event: event,
      timestamp: $getTime(),
      data: data)

  var
    garage = Garage(id: conn.garageId)
    hookDelivery = garage.newWebhookDelivery(
      event, conn.origin, conn.endpoint, "18.18.18")
    hookProcess = conn.sendPayload(payload)

  db.conn.insert hookDelivery

  proc afterHookProcess(hp: Future[Option[AsyncResponse]]) =
    let res = hp.read

    if res.isSome:
      hookDelivery.status_code = res.get.status
      hookDelivery.delivered = true

      db.conn.update hookDelivery

  hookProcess.addCallback afterHookProcess

proc sendHook*[T](hookConn: ServiceValue[WebhookConnection]; event: string; data: T) =
  if hookConn.isSome:
    hookConn.get.sendHook(event, data)

export json

proc test() =
  let
    conn = createWebhookConnection(
      garageKey="dapdap",
      garageId=1,
      origin="https://webhook.site",
      endpoint="/5e30173d-edab-4e5d-a6d4-c2de9cf8d815X"
    )

  conn.sendHook("dafis", "event.dapdap")
  waitFor sleepAsync 3000

when isMainModule:
  test()
