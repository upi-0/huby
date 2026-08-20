import
  asyncdispatch, os, osproc, strutils, streams

import
  utils, deleteHf

import
  service/implement,
  env

proc copyProcess(ayang: ref bool; oldFileUrl, newFileUrl: string) {.async.} =
  let
    app = block:
      if not defined(windows): getHomeDir() / ".local" / "bin" / "hf"
      else: findExe("hf")
    commands = [
      "buckets", "cp",
      oldFileUrl,
      newFileUrl,
    ]
    process = startProcess(app, ".", commands)

  echo commands  

  for _ in 0 .. 20:
    await sleepAsync(500)

    if not process.running() and process.peekExitCode < 1:
      echo "[HF_COPY] " & newFileUrl
      ayang[] = true
      return

    elif process.peekExitCode > 0:
      echo "[HF_ERROR]\n" & process.outputStream.readAll()
      echo "[END_HF_ERROR]"
      return
  
  ayang[] = false


proc renameFile*(fileAddress: string, targetFileName: string) : Future[ServiceValue[string]] {.async.} =
  let
    ayang = new bool
    bucketUrl = "hf://buckets/" & getEnv("HF_REPO")
    originalFileUrl = [bucketUrl, fileAddress].join("/")
    targetFileAddress = [fileAddress.getDirName(), targetFileName].join("/")
    targetFileUrl = [bucketUrl, targetFileAddress].join("/")

  block copy:
    echo originalFileUrl
    echo targetFileName

    await copyProcess(ayang, originalFileUrl, targetFileUrl)
    
    if not ayang[]:
      return result.none(500, "rename - Failed copying file.")

  block delete:
    let deleteProcess = await deleteFile(originalFileUrl)

    if deleteProcess.isSome:
      return some targetFileAddress

  return result.none(500, "rename - Unknown Error")

proc test =
  let resp = waitFor renameFile("huby/2026-8-20/aca496e9-47cf-4f8b-8fdd-287b03924ac7/wahyu.png", "rijal.png")
  assert resp.isSome

when isMainModule:
  test()
