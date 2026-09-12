import
  ../base,
  ../s3/garage,
  endpoints

type
  WebhookDeliveries* {.
    tableName: "deliveries",
    schemaName: "webhook"
  .} = ref object of BaseModel
    endpoint*: WebhookEndpoints
    event*: string
    status_code*: string
    payload*: string
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
    delivered: false
  )

proc newWebhookDelivery*: WebhookDeliveries =
  result = WebhookDeliveries(endpoint: newWebhookEndpoints())
  result = result.setCreatedAt()
