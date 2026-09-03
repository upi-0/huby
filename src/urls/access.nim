import prologue, controller/access

let accessUrls* = @[
  pattern("/{garage_name}/resolve", resolve, httpMethod=[HttpGet]),
  pattern("/{garage_name}/check-status", checkStatus, httpMethod=[HttpGet]),
  pattern("/{garage_name}/uppy", uppyEndpoint, httpMethod=[HttpPost, HttpOptions])
]
