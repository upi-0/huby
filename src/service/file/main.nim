import
  query, ../types,
  ../garage/main

import
  strutils,
  models/[garage, file], db

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

proc newFileService*(grg: string) : ServiceValue[FileService] =
  let gara = getGarageByField("name", grg)
  
  if gara.isNone:
    return result.none gara

  some newFileService(gara.get, conn)  

proc status*(impl: FileService; key: string) : ServiceValue[FileStatus] =
  var status = new FileStatus

  try:
    impl.conn.rawSelect(
      impl.query.checkStatus(impl.garage.key, key),
      status
    )

  except DbError:
    return result.none(500, getCurrentExceptionMsg())

  except NotFoundError:
    return result.none(404, "Not Found")

  return some status  

proc exists*(impl: FileService; key: string) : ServiceValue[bool] =
  let querySql = impl.query.select % [key, $impl.garage.id]
  some impl.conn.exists(file.File, querySql)

proc listFiles*(impl: FileService; keyPrefix: string) : ServiceValue[seq[FileObj]] =
  var files = @[FileObj()]
  
  try:
    impl.conn.rawSelect(
      impl.query.list(impl.garage.key, keyPrefix & ":", false),
      files
    )

    if files.len > 0:
      return result.none(404, "No File")  

    some files

  except Exception:
    return result.none(500, "ERroR")   

proc select*(impl: FileService; key: string; file: var FileModel) : ServiceValue[bool] =
  try:
    impl.conn.select(file, impl.query.select % [key, $impl.garage.id])
    some true

  except NotFoundError:
    return result.none(404, "File Not Found")  

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
