import prologue, controller/bridge

let bridgeUrls* = @[
  pattern("/generate-record", generateRecord, [HttpPost])
]
