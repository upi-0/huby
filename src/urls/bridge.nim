import prologue, controller/s3

let bridgeUrls* = @[
  pattern("/s3", s3handler, [HttpGet, HttpPut, HttpPost])
]
