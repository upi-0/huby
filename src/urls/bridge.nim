import prologue, controller/[bridge, s3]

let bridgeUrls* = @[
  pattern("/generate-record", generateRecord, [HttpPost]),
  pattern("/confirm-migrate", completeMigrate, [HttpPost]),
  pattern("/s3", s3handler, [HttpGet, HttpPut, HttpPost])
]
