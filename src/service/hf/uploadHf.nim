import os, osproc, streams, asyncdispatch, strutils, uuids, times
import std/envvars
import ../types
import db, models/token
import models/file as fmodel

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

proc prepareFile(tokenSignature: string) : ServiceValue[fmodel.File] {.deprecated.} =
  var
    token = newToken()
    file = token.newFile()

  try:
    conn.select(token, "hfb_token.signature = '$#'" % tokenSignature)
    file.some

  except NotFoundError:
    return none(fmodel.File, 404)

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

proc startUpload*(reqRec: UploadRequestRecord; tokenSignature: string; fileLength: int): ServiceValue[UploadHfResponse] {.gcsafe, deprecated.} =
  try:
    var
      ayang = new bool
      file = prepareFile(tokenSignature)

    if file.isNone:
      return none(UploadHfResponse, 404, "Invalid Token.")

    var rijal = file.get

    let
      repo = getEnv("HF_REPO")
      signature = reqRec.signature
      asdir = asd.findEmpty()

    block setDataAndStore:
      rijal.repo = repo
      rijal.signature = reqRec.signature
      rijal.ext = reqRec.ext
      rijal.size = fileLength div 1000 # 1 KilloByte
      rijal.views = 0
      rijal.address = reqRec.address

      conn.insert(rijal)

    let response = UploadHfResponse(
      id: signature,
      size: rijal.size
    )

    proc afterUploadProcess =
      if not ayang[]:
        echo "Invalid Target: " & reqRec.signature

      else:  
        rijal.isUploaded = true
        conn.update(rijal)

      rijal.reset()

    proc afterFindDir(dir: Future[UploadDir]) =
      dir.read.uploadProcess(reqRec, ayang).addCallback(afterUploadProcess)

    asdir.addCallback(afterFindDir)

    return some(response, 201)

  except:
    return none(UploadHfResponse, 404, getCurrentExceptionMsg())
