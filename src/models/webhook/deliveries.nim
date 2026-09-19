import
  ../base,
  ../s3/garage,
  ./[endpoints, payloads]

type
  WebhookDeliveries* {.
    tableName: "deliveries",
    schemaName: "webhook"
  .} = ref object of BaseModel
    endpoint*: WebhookEndpoints
    event*: string
    status_code*: string
    payload*: WebhookPayloads
    delivered*: bool
    redeliver*: bool

proc newWebhookDelivery*(
  garage: Garage;
  event, origin, endpoint: string;
  trigger_ip = ""
) : WebhookDeliveries {.deprecated.} =
  WebhookDeliveries(
    event: event,
    endpoint: new WebhookEndpoints,
    payload: new WebhookPayloads,
    delivered: false
  )

proc newWebhookDelivery*: WebhookDeliveries =
  result = WebhookDeliveries(
    endpoint: newWebhookEndpoints(),
    payload: newWebhookPayloads()
  )
  result = result.setCreatedAt()
