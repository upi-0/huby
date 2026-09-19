import prologue, controller/[s3, bridge]

let bridgeUrls* = @[
  pattern("/s3", s3handler, [HttpGet, HttpPut, HttpPost]),
  pattern("/confirm/{owner}/{garage}", acceptHead, [HttpPost]),
  pattern("/hook/{owner}/{garage}", acceptHook, [HttpPost]),
  pattern("/report/{owner}/{garage}", acceptHookReport, [HttpPost])
]
