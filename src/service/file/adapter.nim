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
  var file = emptyFile()

  if not impl.select(key, file).get:
    return result.none(404, "File Not Found")

  try:
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
        echo "Invalid Target with: $#" % [file.key]

    proc afterDelete(delResult: Future[ServiceValue[string]]) =
      if delResult.read.isSome:
        let uppProcess = startUpload(rec)
        uppProcess.addCallback(afterUpload)     

    block:
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
    fileLength: int;
    replace = false
  ) : Future[ServiceValue[FirstResponse]] {.async.} =
  
  var file = new FileModel
  let isExists = impl.exists(key).get

  if replace and isExists:
    return await impl.replace(rec, key, fileLength)

  elif not replace and isExists:
    return result.none(409)
  
  try:
    file.repo = getEnv("HF_REPO")
    file.signature = rec.signature
    file.ext = rec.ext
    file.size = 0
    file.views = 0
    file.address = rec.address

    conn.insert(file)

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
          file.size = fileLength div 1024
          conn.update(file)

        else:
          echo "Invalid Target with: $#" % [file.key]
    )

    return some(
      FirstResponse(
        signature: rec.signature,
        size: fileLength,
        url: "/.huby/file/" & file.signature & "/resolve"
      ), 202)

proc delete*(impl: FileService; key: string) : Future[ServiceValue[string]] {.async.} =
  var file = emptyFile()
  
  if not impl.select(key, file).get:
    return result.none(404)

  result = await deleteFile file.resolve().get.hfUrl

  if result.isSome:
    file.isDeleted = true
    file.isUploaded = false
    file.size = 0

    conn.update(file)

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
