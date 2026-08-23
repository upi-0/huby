import strutils
import os

proc loadEnv =
  try:
    let rawEnv = open(".env", fmRead).readAll

    for line in rawEnv.splitLines:
      let r = line.split("=", 1)
      if r.len > 1: putEnv(r[0], r[1].replace("\""))

  except IOError:
    discard   

loadEnv()
putEnv("PYTHONIOENCODING", "utf-8")
putEnv("PYTHONUTF8", "1")

export envvars
