{.deprecated.}

import base
import controller/wpolicy
import prologue

let wpolicyUrls* = @[
  private("/c", generateUrl, mthod=[HttpPost]),
  public("/", resolvePolicy, mthod=[HttpPost, HttpOptions])
]
