import
  ../base,
  ../s3/garage

type
  WebhookDeliveries* {.
    tableName: "deliveries",
    schemaName: "webhook"
  .} = ref object of Model
    garage*: Garage
    event*: string
    origin*: string
    endpoint*: string
    status_code*: string
    trigger_ip*: string
    date*: DateTime
    delivered*: bool

proc newWebhookDelivery*(
  garage: Garage;
  event, origin, endpoint: string;
  trigger_ip = ""
) : WebhookDeliveries =
  WebhookDeliveries(
    garage: garage,
    event: event,
    origin: origin,
    endpoint: endpoint,
    trigger_ip: trigger_ip,
    date: now(),
    delivered: false
  )
