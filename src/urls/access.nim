import prologue, controller/access

let accessUrls* = @[
  pattern("/{garage_name}/put", put, httpMethod=[HttpOptions, HttpPut]),
  pattern("/{garage_name}/resolve", resolve, httpMethod=[HttpGet]),
  pattern("/{garage_name}/check-status", checkStatus, httpMethod=[HttpGet]),
  pattern("/{garage_name}/set-persist-access", setPersistAccess, httpMethod=[HttpPut]),
  pattern("/{garage_name}/rename", rename, httpMethod=[HttpPut])
]
