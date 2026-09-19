import
  times, json

import
  service/[file, implement, webhook]

type
  S3BridgeUrl = ref object
    download*, real*: string

  S3BridgeConfig = ref object
    self_response*: bool
    secret_access_key*, key*: string
    headers*: JsonNode

  S3BridgeReturning = ref object
    action*, bucket*, owner_namespace*: string

  S3BridgeResponse = ref object
    status*: int
    use_webhook*: bool
    timestamp: int
    returning*: S3BridgeReturning
    config*: S3BridgeConfig
    url*: S3BridgeUrl
    webhook*: seq[WebhookEndpointFields]

proc newResponse(impl: FileService): S3BridgeResponse =
  S3BridgeResponse(
    status: 200,
    use_webhook: false,
    timestamp: getTime().toUnix(),
    returning: S3BridgeReturning(
      bucket: impl.garage.name
    ),
    config: S3BridgeConfig(
      self_response: false,
      secret_access_key: impl.garage.owner.secret_access_key,
      headers: newJObject()
    ),
    url: new S3BridgeUrl,
    webhook: @[WebhookEndpointFields()]
  )  

proc action*(response: S3BridgeResponse; action: string; url: ServiceValue[string]; downloadUrl: ServiceValue[string] = nil) : void =
  response.url.real = url.get
  response.returning.action = action

  if not downloadUrl.isNil:
    response.url.download = downloadUrl.get

export
  newResponse,
  S3BridgeUrl, S3BridgeConfig, S3BridgeResponse, S3BridgeReturning
