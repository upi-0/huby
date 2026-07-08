import controller/file, prologue, base

let fileUrls* = @[
  private("/upload", uploadFile, mthod=[HttpPost]),
  public("/{signature}/resolve", resolveFile),
  private("/{key}/delete", deleteFile, mthod=[HttpDelete]),
  private("/{key}/ls/deleted", listFilesDeleted),
  private("/{key}/redirect", redirectFile),
  private("/{key}/ls", listFiles),  
  private("/{key}", lookFile)
]
