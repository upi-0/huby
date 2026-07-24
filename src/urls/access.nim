import prologue, controller/access

let accessUrls* = @[
  pattern("/{garage_name}/put", put, httpMethod=[HttpOptions, HttpPut]),
  pattern("/{garage_name}/resolve", resolve, httpMethod=[HttpGet]),
]
