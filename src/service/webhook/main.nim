import
  strutils, json

import
  db,
  models/webhook/[payloads, endpoints]

import
  ../implement,
  ../file

type
  WebhookEndpointFields* = ref object
    garage_id*, id*: int64
    url*, hmac_key*, subscribed_events*: string
    status*: int   

  WebhookDeliveryStatus* = ref object
    endpoint*: WebhookEndpoints
    payload*: JsonNode

  WebhookWriteDeliveryPayload* = ref object
    endpoint_id*: int
    status*: int
    delivered*: bool

  WebhoookInsertReturning* = ref object
    id*, endpoint*: int64

proc garageEndpoints*(impl: FileService; action = "PutObject"): ServiceValue[seq[WebhookEndpointFields]] =
  let
    query = query(
      select(
        "garage::bigint AS garage_id",
        "id::bigint",
        "url", "hmac_key", "subscribed_events", "status"),
      frm("webhook.endpoints endpoint"),
      where(
        @["endpoint.garage", $impl.garage.id],
        @["endpoint.subscribed_events", "LIKE", q"%$#%" % action])
    )
  var endpoints = @[WebhookEndpointFields()]

  try:
    assert ["CompleteMultipartUpload", "PutObject"].contains action
    impl.conn.rawSelect(query, endpoints)

  except DbError, NotFoundError, AssertionDefect:
    return result.none(404)
  
  some(endpoints)

proc toModel*(impl: FileService; endpoint: WebhookEndpointFields) : WebhookEndpoints =
  WebhookEndpoints(
    id: endpoint.id,
    garage: impl.garage,
    url: endpoint.url,
    hmac_key: endpoint.hmac_key,
    subscribed_events: endpoint.subscribed_events,
    status: WebhookEndpointStatus(endpoint.status)
  )

proc writeDeliver*(impl: FileService; endpoints: seq[WebhookWriteDeliveryPayload]; payload: JsonNode) : ServiceValue[int] =
  var
    setValues: seq[string]
    returning = @[WebhoookInsertReturning()]
    payloadObj = new WebhookPayloads

  block upsertPayload:
    let
      insertedQuery = scopeQuery(
        "INSERT INTO webhook.payloads(signature, payload, createdat)",
        "VALUES ('$#', '$#', $#)" % [payload["signature"].str, $payload["data"], "13"],
        "ON CONFLICT (signature) DO NOTHING",
        "RETURNING *")

      selectQuery = query(
        "WITH inserted AS ($#)" % insertedQuery.replace(";"),
        "SELECT * FROM inserted",
        "UNION ALL",
        "SELECT * FROM webhook.payloads WHERE signature = '$#'" % [payload["signature"].str],
        "LIMIT 1")  

    try:
      impl.conn.rawSelect(selectQuery, payloadObj)

    except DbError, NotFoundError:
      return result.none(404)  

  for enp in endpoints:
    setValues.add "($#, $#, $#, $#, $#, $#, $#)" % [
      $enp.endpoint_id,
      $enp.delivered,
      "false",
      $enp.status,
      payload["event"].str.q,
      $payloadObj.id,
      ($payload["timestamp"].num).q
    ]

  let query = query(
    "INSERT INTO webhook.deliveries(endpoint, delivered, redeliver, status_code, event, payload, createdat)",
    "VALUES", setValues.join(",\n"),
    "RETURNING id, endpoint"
  )

  try:
    impl.conn.rawSelect(query, returning)
    return some(1, 201)

  except DbError, NotFoundError:
    return result.none(500, getCurrentExceptionMsg())
  