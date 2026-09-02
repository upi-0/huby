import
  main, asyncdispatch, strutils, webhook

import
  ../implement, ../hf/[uploadHf, deleteHf, resolveHf, renameHf, utils],
  ../storage_repo/main,
  s3presign/main,
  env  

import
  db, models/[file, garage, storage_repo]

type
  FirstResponse* = ref object
    size*: int64
    signature*: string
    url*: string  

# Webhook notification helpers
proc notifyUploaded(hook: ServiceValue[WebhookConnection]; garageName: string; file: FileModel; size: int) =
  hook.sendHook("file.put", %*{
    "garage": garageName,
    "success": true,
    "key": file.key,
    "size": size,
    "ext": file.ext,
    "uploaded": file.isUploaded
  })

proc notifyReplaced(hook: ServiceValue[WebhookConnection]; garageName: string; file: FileModel; size, prevSize: int) =
  hook.sendHook("file.put.replace", %*{
    "garage": garageName,
    "success": true,
    "key": file.key,
    "size": size,
    "prevSize": prevSize,
    "ext": file.ext,
    "uploaded": file.isUploaded
  })

proc notifyConflict(hook: ServiceValue[WebhookConnection]; garageName: string; key: string) =
  hook.sendHook("file.put", %*{
    "garage": garageName,
    "success": false,
    "key": key,
    "msg": "conflict"
  })

proc notifyAborted(hook: ServiceValue[WebhookConnection]; garageName: string; key: string; reason = "upload_failed") =
  hook.sendHook("file.put", %*{
    "garage": garageName,
    "success": false,
    "key": key,
    "uploaded": false,
    "msg": reason
  })

proc notifyDeleted(hook: ServiceValue[WebhookConnection]; garageName: string; key: string) =
  hook.sendHook("file.delete", %*{
    "garage": garageName,
    "success": true,
    "key": key,
  })

proc replace(
    impl: FileService;
    rec: UploadRequestRecord;
    key: string;
    fileLength: int;
    hook: ServiceValue[WebhookConnection] = none(WebhookConnection, 0)
  ) : Future[ServiceValue[FirstResponse]] {.async, deprecated.} =
  var
    file = newFile impl.garage
    prevSize: int

  >> impl.select(key, file)

  try:
    prevSize = file.size.int
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
        file.storage_repo = get impl.conn.getIdleStorageRepo
        
        impl.conn.update(file)
        hook.notifyReplaced(impl.garage.name, file, file.size.int, prevSize)

      else:
        >> impl.updateStorageUsed(file.size.int, "-")
        impl.conn.update(file)
        hook.notifyAborted(impl.garage.name, file.key, "replace_failed")

        echo "Invalid Target with: $#" % [file.key]

    proc afterDelete(delResult: Future[ServiceValue[string]]) =
      if delResult.read.isSome:
        let uppProcess = startUpload(
          rec,
          file.storage_repo.getUploadToken(),
          file.storage_repo.getRepoAddress()
        )
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
    replace = false;
    hook: ServiceValue[WebhookConnection] = none(WebhookConnection, 0)
  ) : Future[ServiceValue[FirstResponse]] {.async.} =
  
  var file = newFile(impl.garage)
  let
    isExists = impl.exists(key).get
    fileSize = contentLength div 1024
    idleRepo = impl.conn.getIdleStorageRepo()

  if replace and isExists:
    return await impl.replace(rec, key, contentLength, hook)

  elif not replace and isExists:
    hook.notifyConflict(impl.garage.name, key)
    return result.none(409)
  
  try:
    file.storage_repo = idleRepo.get
    file.signature = rec.signature
    file.ext = rec.ext
    file.size = 0
    file.address = rec.address
    file.key = key

    >> impl.updateStorageUsed(fileSize)
    impl.conn.insert(file)

  except DbError:
    return result.none(500, getCurrentExceptionMsg())

  block startUpload:
    let process = startUpload(
      rec,
      uploadToken=idleRepo.get.getUploadToken(),
      repo=idleRepo.get.getRepoAddress()
    )

    process.addCallback(
      proc(process: Future[ServiceValue[bool]]) =
        let rex = process.read
        assert rex.isSome
        echo "DAJJDAKSJDJKLASHDJKALSBDLASBDKHJ>"

        if rex.get:
          file.isUploaded = true
          file.size = fileSize
          impl.conn.update(file)
          hook.notifyUploaded(impl.garage.name, file, fileSize)

        else:
          >> impl.updateStorageUsed(fileSize, "-")
          hook.notifyAborted(impl.garage.name, file.key)
    )

    return some(
      FirstResponse(
        signature: rec.signature,
        size: fileSize,
        url: "/.huby/file/" & file.signature & "/resolve"
      ), 202)

proc delete*(
    impl: FileService;
    key: string;
    hook: ServiceValue[WebhookConnection] = none(WebhookConnection, 0)
  ) : Future[ServiceValue[string]] {.async.} =
  var file = newFile impl.garage
  
  >> impl.select(key, file)

  result = await deleteFile file.resolve().get.hfUrl

  if result.isSome:
    file.isDeleted = true
    file.isUploaded = false
    file.size = 0

    conn.update(file)
    hook.notifyDeleted(impl.garage.name, key)

proc rename*(
  impl: FileService;
  key: string;
  targetName: string;
  hook: ServiceValue[WebhookConnection] = none(WebhookConnection, 0)
) : Future[ServiceValue[bool]] {.async.} =
  var file = newFile impl.garage
  
  >> impl.select(key, file)

  block:
    let
      prevName = file.address.getFileName()
      renameProcess = renameFile(file.address, targetName, file.storage_repo.getUploadToken(), file.storage_repo.getRepoAddress())
    
    renameProcess.addCallback(
      proc(fb: Future[ServiceValue[string]]) =
        let fbb = fb.read
        if fb.read.isSome:
          file.address = fbb.get
          conn.update file  

          hook.sendHook("file.renamed", %*{
            "garage": impl.garage.name,
            "key": key,
            "success": true,
            "new_name": targetName,
            "prev_name": prevName
          })

        else:
          hook.sendHook("file.renamed", %*{
            "garage": impl.garage.name,
            "key": key,
            "success": false
          })
    )

  result = some(true, 202)

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

proc putFile*(
  impl: FileService;
  key: string;
  fileSize: int;
  record: UploadRequestRecord;
  replace = false;
  uploaded = true;
  s3conf: var S3Config;
) : ServiceValue[string] =
  var
    file = newFile(impl.garage)
    address = record.address

  let exists = impl.exists(key).get

  if exists and replace:
    >> impl.select(key, file)

    var prevSize = file.size

    block:
      file.size = fileSize
      address = file.address

    >> impl.updateStorageUsed(prevSize, "-")
    >> impl.updateStorageUsed(fileSize)

    conn.update file
    s3conf = file.storage_repo.toS3Config()

    return address.some()

  elif exists and not replace:
    return result.none(409)  

  try:
    file.isUploaded = uploaded
    file.isDeleted = false
    file.signature = record.signature
    file.size = fileSize
    file.key = key
    file.ext = record.ext
    file.persistAccess = true
    file.address = record.address
    file.storage_repo = impl.conn.getIdleStorageRepo().get()

    >> impl.updateStorageUsed(fileSize)

    s3conf = file.storage_repo.toS3Config()
    conn.insert file

  except DbError, NotFoundError:
    return result.none(500)

  address.some()

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
