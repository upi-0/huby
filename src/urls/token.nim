import controller/token, prologue, base

let tokenUrls* = @[
  public("/create", createToken, mthod=[HttpPost]),
  protected("/usage", lookTokenUsage),
  protected("/", lookToken)
]