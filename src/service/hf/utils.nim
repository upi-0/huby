import strutils

proc getDirName*(fileAddress: string) : string =
  fileAddress.split("/")[0 .. ^2].join("/")
  
proc getFileName*(fileAddress: string) : string =
  fileAddress.split("/")[^1]
