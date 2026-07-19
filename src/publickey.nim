import
  strutils, std/random, uuids

randomize()

const
  IdWords = staticRead("data/publickey/kata.txt").splitLines
  IdNames = staticRead("data/publickey/nama.txt").splitLines

proc generate() : string =
  IdWords[rand(0 .. 29_921)]

proc generateKey*(seperator = "-"; len = 2; prefix = ""): string =
  var harutoka = @[IdNames[rand(0 .. 1_007)]]

  for _ in 1 .. len - 1:
    harutoka.add generate()

  block:
    harutoka.add ($genUUID())[^4 .. ^1]
    prefix & harutoka.join seperator
