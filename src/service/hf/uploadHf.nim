import os, osproc, streams, asyncdispatch, strutils, uuids, times
import std/envvars
import ../types

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

  for i in 0 .. 10: # Example Max Conc
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
        return d

    await sleepAsync(1_000)  

proc uploadProcess(dir: UploadDir; file: UploadRequestRecord; ayang: ref bool): Future[void] {.async.} =
  block moveFile:
    # Besok2 seharusnya ga gini jur.
    moveFile(file.dname / file.fname, dir.address / file.fname)

  let
    repo = getEnv("HF_REPO")
    app = getHomeDir() / ".local" / "bin" / "hf"
    target = ["hf://buckets", repo, file.address].join("/")
    process = startProcess(app, ".", ["sync", dir.address, target])

  dir.isInUsed = true

  for _ in 0 .. 20:
    await sleepAsync(1000)

    if not process.running() and process.peekExitCode < 1:
      echo "[HF_SUCCESS] " & file.fname

      block:
        removeFile(dir.address / file.fname)
        dir.isInUsed = false
        ayang[] = true

      return

    elif process.peekExitCode > 0:
      echo "[HF_ERROR]\n" & process.outputStream.readAll()
      echo "[END_HF_ERROR]"

  block:
    removeFile(dir.address / file.fname)
    ayang[] = false
    dir.isInUsed = false

proc loadRequestRecord*(rawName: string) : UploadRequestRecord =
  let
    asd = now()
    hfDir = [$asd.year, $asd.month.ord, $asd.monthday.ord].join("-")

  block:
    result.dname = getCurrentDir() / "storage" / "temp"
    result.signature = $genUUID()
    result.ext = rawName.split(".")[^1]
    result.fname = [result.signature, result.ext].join(".")
    result.address = "huby/" & hfDir

  result.dname.createDir()    

proc startUpload*(rec: UploadRequestRecord): Future[ServiceValue[bool]] {.async.} =
  let
    ayang = new bool
    dir = await asd.findEmpty()
  
  block:
    await uploadProcess(dir, rec, ayang)   
    some ayang[]
