import
  main, asyncdispatch, strutils

import
  ../types, ../hf/[uploadHf, deleteHf, resolveHf],
  env

import
  db, models/[file, garage]

type
  FirstResponse* = ref object
    size: int64
    signature: string
    url: string  

proc replace(impl: FileService; rec: UploadRequestRecord; key: string; fileLength: int) : Future[ServiceValue[FirstResponse]] {.async.} =
  var
    file = newFile impl.garage
    prevSize: int

  >> impl.select(key, file)

  try:
    prevSize = file.size
    file.size = 0
    file.isUploaded = false
    file.isDeleted = false
    file.signature = rec.signature

    impl.conn.update(file)

  except DbError:
    return result.none(500)  

  block startDeleteThenUpload:
    proc afterUpload(pro: Future[ServiceValue[bool]]) =
      let rex = pro.read
      assert rex.isSome

      if rex.get:
        file.isUploaded = true
        file.size = fileLength div 1024
        file.ext = rec.ext
        file.address = rec.address
        file.repo = getEnv("HF_REPO")
        
        impl.conn.update(file)

      else:
        >> impl.updateStorageUsed(file.size, "-")
        impl.conn.update(file)

        echo "Invalid Target with: $#" % [file.key]

    proc afterDelete(delResult: Future[ServiceValue[string]]) =
      if delResult.read.isSome:
        let uppProcess = startUpload(rec)
        uppProcess.addCallback(afterUpload)       

    block:
      >> impl.updateStorageUsed(prevSize, "-")
      >> impl.updateStorageUsed(fileLength div 1024, "+")

      let deleteProcess = deleteFile(file.resolve.get.hfUrl)
      deleteProcess.addCallback(afterDelete)

  return some(FirstResponse(
    signature: rec.signature,
    size: fileLength,
    url: "/.huby/file/" & rec.signature & "/resolve"
  ), 202)

proc upload*(
    impl: FileService;
    rec: UploadRequestRecord;
    key: string;
    contentLength: int;
    replace = false
  ) : Future[ServiceValue[FirstResponse]] {.async.} =
  
  var file = newFile(impl.garage)
  let
    isExists = impl.exists(key).get
    fileSize = contentLength div 1024

  if replace and isExists:
    return await impl.replace(rec, key, contentLength)

  elif not replace and isExists:
    return result.none(409)
  
  try:
    file.repo = getEnv("HF_REPO")
    file.signature = rec.signature
    file.ext = rec.ext
    file.size = 0
    file.views = 0
    file.address = rec.address
    file.key = key

    >> impl.updateStorageUsed(fileSize)
    impl.conn.insert(file)

  except DbError:
    return result.none(500, getCurrentExceptionMsg())

  block startUpload:
    let process = startUpload(rec)

    process.addCallback(
      proc(process: Future[ServiceValue[bool]]) =
        let rex = process.read
        assert rex.isSome

        if rex.get:
          file.isUploaded = true
          file.size = fileSize
          impl.conn.update(file)

        else:
          >> impl.updateStorageUsed(fileSize, "-")
          echo "Invalid Target with: $#" % [file.key]
    )

    return some(
      FirstResponse(
        signature: rec.signature,
        size: fileSize,
        url: "/.huby/file/" & file.signature & "/resolve"
      ), 202)

proc delete*(impl: FileService; key: string) : Future[ServiceValue[string]] {.async.} =
  var file = newFile impl.garage
  
  >> impl.select(key, file)

  result = await deleteFile file.resolve().get.hfUrl

  if result.isSome:
    file.isDeleted = true
    file.isUploaded = false
    file.size = 0

    conn.update(file)

proc resolveRedirectFile*(impl: FileService; key: string; download = false) : Future[ServiceValue[string]] {.async.} =
  if key == "":
    return result.none(400)

  var file = newFile impl.garage

  try:    
    echo impl.select(key, file).errorReason
    let fleh = file.resolve download

    if fleh.isNone:
      return result.none(fleh.status, fleh.errorReason)
    
    if (
      not file[].isUploaded and
      not file[].isDeleted and
      ["png", "jpg", "jpeg"].contains file[].ext
    ):
      return result.none(202, "Not Ready")

    assert file[].isUploaded and fleh.isSome
    
    let red = await fleh.get.redirectUrl

    if red.isNone:
      return result.none(red.status, red.errorReason)
    
    return some red.get

  except AssertionDefect, DbError, NotFoundError:
    return result.none(404, "File not found. " & getCurrentExceptionMsg())

export
  loadRequestRecord  

when isMainModule:
  var
    dl = emptyFile()

  let
    grg = Garage(id: 2)
    impl = grg.newFileService(conn)
    po = impl.select("linux:rijal", dl)

  try:
    echo po.get
    echo dl.signature

  except AssertionDefect:
    echo po.errorReason
