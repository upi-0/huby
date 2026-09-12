import
  main, asyncdispatch, strutils, webhook

import
  ../implement, ../hf/[uploadHf, deleteHf, resolveHf],
  ../storage_repo/main,
  ../owner/main,
  s3presign/main,
  env  

import
  db, models/all

type
  FirstResponse* = ref object
    size*: int64
    signature*: string
    url*: string  

proc notifyDeleted(hook: ServiceValue[WebhookConnection]; garageName: string; key: string) =
  hook.sendHook("file.delete", %*{
    "garage": garageName,
    "success": true,
    "key": key,
  })

proc delete*(
    impl: FileService;
    key: string;
    hook: ServiceValue[WebhookConnection] = none(WebhookConnection, 0)
  ) : Future[ServiceValue[string]] {.async, deprecated: "3-9-2026".} =
  var file = newFile impl.garage
  
  >> impl.select(key, file)

  result = await deleteFile file.resolve().get.hfUrl

  if result.isSome:
    file.isDeleted = true
    file.isUploaded = false
    file.is_size_sync = false

    impl.conn.update(file)
    hook.notifyDeleted(impl.garage.name, key)

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
  contentLength: int;
  record: UploadRequestRecord;
  replace = false;
  uploaded = true;
  s3conf: var S3Config;
) : ServiceValue[string] =
  var
    file = newFile(impl.garage)
    address = record.address
    fileSize = contentLength div 1024

  if fileSize < 1:
    fileSize = 1    

  let exists = impl.exists(key).get

  if exists and replace:
    >> impl.select(key, file)

    var prevSize = file.size

    if fileSize > prevSize:
      let quotaCheck = impl.garage.owner.checkStorageQuota(fileSize - prevSize)
      if quotaCheck.isNone:
        return result.none(quotaCheck.status, quotaCheck.errorReason)

    block:
      file.size = fileSize
      address = file.address
      file.is_size_sync = false
      file.isUploaded = false

    impl.conn.update(file, ["size", "is_size_sync", "isuploaded"])
    s3conf = file.storage_repo.toS3Config()

    return address.some()

  elif exists and not replace:
    return result.none(409)  

  let quotaCheck = impl.garage.owner.checkStorageQuota(fileSize)
  if quotaCheck.isNone:
    return result.none(quotaCheck.status, quotaCheck.errorReason)

  try:
    file.isUploaded = uploaded
    file.isDeleted = false
    file.is_size_sync = false
    file.signature = record.signature
    file.size = fileSize
    file.key = key
    file.ext = record.ext
    file.persistAccess = true
    file.address = record.address
    file.storage_repo = impl.conn.getIdleStorageRepo().get()

    s3conf = file.storage_repo.toS3Config()
    impl.conn.insert file

  except DbError, NotFoundError:
    return result.none(500, "DAPDAP:" & getCurrentExceptionMsg())

  address.some()

export
  loadRequestRecord  
