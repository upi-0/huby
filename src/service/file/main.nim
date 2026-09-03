import
  query,
  ../garage/[main, query],
  ../implement,
  ../owner/main

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

proc newFileService*(ownerId: int; grg: string) : ServiceValue[FileService] =
  let gara = ownerId.getGarageByField("name", grg)
  
  if gara.isNone:
    return result.none gara

  some newFileService(gara.get, conn)  

proc updateStorageUsed*(impl: FileService; length: int; operator = "+") : ServiceValue[int] =
  >> impl.conn.updateStorageUsed(impl.garage.owner, length, operator)

  let
    query = GarageQuery()
    garageId = impl.garage.id    
    updateq = query.updateStorageUsed(garageId, length, operator)
    cintamu = impl.conn.getRow(sql updateq)

  if cintamu.isNone:
    return result.none(500, "Menuju Tanpa Dapdap")

  some cintamu.get[0].to(int)

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
    let safeKey = key.replace("'", "''")
    impl.conn.select(file, impl.query.select % [safeKey, $impl.garage.id])
    some(true)

  except NotFoundError, DbError:
    return result.none(404, "File Not Found")  

proc setPersistAccess*(impl: FileService; key: string; to: bool) : ServiceValue[bool] =
  var file = emptyFile()
  >> impl.select(key, file)

  file.persistAccess = to
  impl.conn.update(file)

  some true

export Garage

when isMainModule:
  var gar = newGarage()

  block:
    conn.createTables newFile gar

  let fs = FileService(
    garage: newGarage(),
    query: FileQuery(),
    conn: conn
  )

  echo fs.listFiles("linux:rijal").errorReason
