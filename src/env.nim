import strutils
import std/envvars

const rawEnv = staticRead("../.env")

proc loadEnv =
  for line in rawEnv.splitLines:
    let r = line.split("=", 1)
    if r.len > 1: putEnv(r[0], r[1].replace("\""))

loadEnv()

export envvars
