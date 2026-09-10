import prologue, controller/[s3, bridge]

let bridgeUrls* = @[
  pattern("/s3", s3handler, [HttpGet, HttpPut, HttpPost])
]
