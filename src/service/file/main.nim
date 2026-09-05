import
  query,
  ../garage/[main, query],
  ../implement,
  ../owner/main,
  asyncdispatch

from options import isNone, get

import
  strutils

import  
  models/all, db

type
  FileObj* = ref object
    size*: int
    isUploaded*: bool
    isDeleted*: bool
    signature*: string
    ext*: string
    views*: int
    key*: string

  FileStatus* = ref object
    isUploaded*: bool   
    isDeleted*: bool
    persistAccess*: bool

  FileList* = ref object of RootObj
    key: string
    lastModified: string
    etag: string
    size: int64

  FileService* = ref object of RootObj
    garage*: Garage
    query: FileQuery
    conn*: DbConn

proc newFileService*(garage: Garage; conn: DbConn) : FileService =
  FileService(
    garage: garage,
    conn: conn,
    query: FileQuery()
  )    

proc newFileService*(ownerId: int; grg: string) : Future[ServiceValue[FileService]] {.gcsafe, async.} =
  let
    gara = ownerId.getGarageByField("name", grg)
    db = await tryPopDb()
  
  if gara.isNone:
    return result.none gara
  
  some newFileService(gara.get, db)

proc updateStorageUsed*(impl: FileService; length: int; operator = "+") : ServiceValue[int] {.deprecated: "2026-09-05".} =
  impl.conn.updateStorageUsed(impl.garage.owner, length, operator)

proc status*(impl: FileService; key: string) : ServiceValue[FileStatus] =
  var status = new FileStatus

  try:
    impl.conn.rawSelect(
      impl.query.checkStatus(impl.garage.owner.secret_access_key, key),
      status
    )

  except DbError:
    return result.none(500, getCurrentExceptionMsg())

  except NotFoundError:
    return result.none(404, "Not Found")

  return some status  

proc exists*(impl: FileService; key: string) : ServiceValue[bool] =
  let safeKey = key.replace("'", "''")
  let querySql = impl.query.select % [safeKey, $impl.garage.id]
  some impl.conn.exists(file.File, querySql)

proc listFiles*(impl: FileService; keyPrefix: string) : ServiceValue[seq[FileObj]] =
  var files = @[FileObj()]
  
  try:
    impl.conn.rawSelect(
      impl.query.list(impl.garage.owner.secret_access_key, keyPrefix & ":", false),
      files
    )

    if files.len > 0:
      return result.none(404, "Zahir was here")  

    some files

  except Exception:
    return result.none(500, "ERroR")   

proc select*(impl: FileService; key: string; file: var FileModel) : ServiceValue[bool] =
  try:
    file = emptyFile()
    impl.conn.select(file, impl.query.select % [key, $impl.garage.id])
    implement.some(true)

  except NotFoundError, DbError:
    return result.none(404, getCurrentExceptionMsg())  

proc setPersistAccess*(impl: FileService; key: string; to: bool) : ServiceValue[bool] =
  var file = emptyFile()
  >> impl.select(key, file)

  file.persistAccess = to
  impl.conn.update(file)

  some true
