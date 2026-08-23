import os, osproc, streams, asyncdispatch, strutils, uuids, times
import std/envvars, uri
import ../implement, utils

type
  UploadHfResponse* = object
    id*: string # As signature
    size*: int

  UploadMetadata* {.deprecated.} = tuple[
    response: UploadHfResponse,
    uploadProcess: Future[bool]
  ]

  UploadRequestRecord* = tuple
    ext: string
    dname: string
    fname: string
    signature: string
    address: string

  UploadDir* = ref object of RootObj
    isInUsed: bool
    address: string

  UploadDirs = seq[UploadDir]    

proc prepareDirs*: UploadDirs {.gcsafe.} =
  let base = getCurrentDir() / "storage"

  createDir(base / "temp")

  for i in 0 .. 40: # Expanded concurrency pool
    let address = base / "dir_" & $i
    
    if not dirExists(address):
      createDir(address)

    result.add UploadDir(isInUsed: false, address: address)      

let
  abc = prepareDirs()
  asd = addr abc

proc findEmpty*(ud: ptr UploadDirs) : Future[UploadDir] {.async.} =
  for _ in 0 .. 100:
    for d in ud[]:
      if not d.isInUsed:
        d.isInUsed = true
        return d

    await sleepAsync(500)  

proc sanitizeFsFileName*(name: string): string =
  result = name
  for ch in [':', '*', '?', '"', '<', '>', '|']:
    result = result.replace(ch, '_')

proc uploadProcess(dir: UploadDir; file: UploadRequestRecord; ayang: ref bool): Future[void] {.async.} =
  let dirAddress = dir.address / file.signature

  defer:
    dir.isInUsed = false

  try:
    block moveFile:
      createDir(dirAddress)
      moveFile(file.dname / file.fname, dirAddress / file.fname)

    let
      repo = getEnv("HF_REPO")
      app = block:
        if not defined(windows): getHomeDir() / ".local" / "bin" / "hf"
        else: findExe("hf")
      target = ["hf://buckets", repo, file.address.getDirName()].join("/")
      process = startProcess(app, ".", ["sync", dirAddress, target])

    echo target

    for _ in 0 .. 20:
      await sleepAsync(1000)

      if not process.running() and process.peekExitCode < 1:
        echo "[HF_SUCCESS] " & file.fname

        block:
          try:
            if fileExists(dirAddress / file.fname):
              removeFile(dirAddress / file.fname)
            if dirExists(dirAddress):
              removeDir(dirAddress)
          except Exception:
            discard
          
          ayang[] = true

        return

      elif process.peekExitCode > 0:
        echo "[HF_ERROR]\n" & process.outputStream.readAll()
        echo "[END_HF_ERROR]"
        break

    block:
      try:
        if fileExists(dirAddress / file.fname):
          removeFile(dirAddress / file.fname)
        if dirExists(dirAddress):
          removeDir(dirAddress)
      except Exception:
        discard
      ayang[] = false

  except Exception as e:
    echo "[HF_UPLOAD_EXCEPTION] ", e.msg
    try:
      if dirExists(dirAddress):
        removeDir(dirAddress)
    except Exception:
      discard
    ayang[] = false

proc loadRequestRecord*(rawName: string) : UploadRequestRecord =
  let
    asd = now()
    hfDir = [$asd.year, $asd.month.ord, $asd.monthday.ord].join("-")

  block:
    result.dname = getCurrentDir() / "storage" / "temp"
    result.signature = $genUUID()
    result.ext = if rawName.contains('.'): rawName.split(".")[1 .. ^1].join(".") else: ""
    result.fname = sanitizeFsFileName(rawName)

    result.address = [
      "huby",
      hfDir,
      result.signature,
      result.fname
    ].join("/")

  result.dname.createDir()    

proc startUpload*(rec: UploadRequestRecord): Future[ServiceValue[bool]] {.async.} =
  let
    ayang = new bool
    dir = await asd.findEmpty()
  
  block:
    await uploadProcess(dir, rec, ayang)   
    some ayang[]
