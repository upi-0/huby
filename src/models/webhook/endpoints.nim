import
  ../base,
  ../s3/garage

type
  WebhookEndpointStatus* = enum
    active, paused, disabled

  WebhookEndpoints* {.tableName: "endpoints", schemaName: "webhook".} = ref object of BaseModel
    garage*: Garage
    url*: string
    hmac_key*: string # Used for hashing.
    subscribed_events*: string
    status*: WebhookEndpointStatus

proc newWebhookEndpoints*: WebhookEndpoints =
  result = WebhookEndpoints(garage: emptyGarage())
  result = result.setCreatedAt()
