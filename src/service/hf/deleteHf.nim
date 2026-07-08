import
  ../types

import
  strutils, asyncdispatch, os, osproc

proc deleteProcess(ayang: ref bool; fleh: string) {.async.} =
  let
    app = findExe("hf")
    commands = ["buckets", "rm", fleh, "-y"]
    process = startProcess(app, ".", commands)

  echo "DELETING: " & fleh

  for _ in 0 .. 10:
    await sleepAsync(500)

    if not process.running() and process.peekExitCode < 1:
      ayang[] = true
      return

    elif process.peekExitCode > 0:
      ayang[] = false

proc deleteFile*(hfUrl: string) : Future[ServiceValue[string]] {.async.} =
  let ayang = new bool
  await deleteProcess(ayang, hfUrl)

  if ayang[]:
    return some("File successfully deleted.")

  return result.none(500, "Not ayang.")
