import prologue, controller/auth, middleware/auth

let authUrls* = @[
  pattern("/login", login, httpMethod=[HttpPost]),
  pattern("/me", lookTokenSignature, httpMethod=[HttpGet], middlewares = @[validToken()])
]
