import prologue, controller/access

let accessUrls* = @[
  pattern("/{public_key}/put", put, httpMethod=[HttpOptions, HttpPut]),
  pattern("/{public_key}/resolve", resolve, httpMethod=[HttpGet]),
]
