import strutils

proc getDirName*(fileAddress: string) : string =
  fileAddress.split("/")[0 .. ^2].join("/")
  