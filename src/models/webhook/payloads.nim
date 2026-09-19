import
  ../base

type
  WebhookPayloads* {.tableName: "payloads", schemaName: "webhook".} = ref object of BaseModel
    payload*, signature*: string

proc newWebhookPayloads*: WebhookPayloads =
  WebhookPayloads()
