import
  query, ../implement
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

  FileImplement* = ref object of RootObj
    garage: Garage
    query: FileQuery

proc status*(implement: FileImplement; signature: string) : ServiceValue[FileStatus] =
  var status = new FileStatus

  try:
    conn.rawSelect(
      implement.query.checkStatus(implement.garage.key, signature),
      status
    )

  except DbError:
    return result.none(500, getCurrentExceptionMsg())

  except NotFoundError:
    return result.none(404, "Not Found")

  return some status  

