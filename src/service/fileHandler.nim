{.deprecated.}

import
  strutils, asyncdispatch, file/main
  
import hf/[
  deleteHf,
  resolveHf,
  uploadHf
]  

import
  db, types, env

import
  models/file

type
  FileObj* = ref object
    size*: int
    isUploaded*: bool
    isDeleted*: bool
    signature*: string
    ext*: string
    views*: int
    key*: string

  VerifyFormat* = tuple
    accept: bool
    limit: int64
    key: string  

  FirstResponse* = ref object
    size: int64
    signature: string
    url: string

  FileStatus* = ref object
    isUploaded*: bool    

  FileQuery = object
    listFiles = """
      SELECT
        "hfb_file".size,
        "hfb_file".isUploaded,
        "hfb_file".isDeleted,
        "hfb_file".signature,
        "hfb_file".ext,
        "hfb_file".views,
        "hfb_file".key
      FROM
        "hfb_file" file
      INNER JOIN
        "hfb_garage" garage ON file.id = garage.id
      WHERE
        file.key LIKE   '$#%' AND
        file.isDeleted = $#   AND
        garage.key =    '$#'  AND
        LIMIT            $#
    """


  FileHander* = ref object of RootObj
    Q_LIST_FILES = ""    

const
  Q_LIST_FILES {.deprecated.} = """
    SELECT
      "hfb_file".size,
      "hfb_file".isUploaded,
      "hfb_file".isDeleted,
      "hfb_file".signature,
      "hfb_file".ext,
      "hfb_file".views,
      "hfb_file".key
    FROM
      "hfb_file"
  """
  Q_LIST_FILES_K {.deprecated.} = Q_LIST_FILES & """
    WHERE
      key LIKE '$#%' AND
      hfb_file.isDeleted = $#
  """

proc key*(paths: varargs[string]): string {.deprecated.} =
  if paths.len == 1 and not (paths[0].endsWith(":")):
    return paths[0] & ":"
  paths.join(":")  

proc resolveRedirectFile*(signature: string) : Future[ServiceValue[string]] {.async.} =
  if signature == "":
    return result.none(400)

  var file = new FileModel

  try:    
    conn.select(file, "hfb_file.signature = '$#'" % signature)

    let fleh = file.resolve()

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

proc look*(signature: string) : Future[ServiceValue[FileObj]] {.async.} =
  var file = new FileModel
  
  try:
    conn.select(file, "hfb_file.signature = '$#'" % signature)

  except DbError, NotFoundError:  
    return result.none(404)

  return some FileObj(
    size: file[].size,
    isUploaded: file[].isUploaded,
    isDeleted: file[].isDeleted,
    signature: file[].signature,
    ext: file[].ext,
    views: file[].views
  )

proc redirectFile*(fileKey: string) : ServiceValue[string] =
  var file = new FileModel

  if file.select(fileKey).isNone:
    return result.none(404, "File Not Found")

  let po = file.resolve

  if po.isNone:
    return result.none(po)

  some "/.huby/file/" & file.signature & "/resolve"

proc status*(signature: string) : ServiceValue[FileStatus] =
  var status = new FileStatus
  let query = """
    SELECT
      "hfb_file".isUploaded
    FROM
      "hfb_file"      
    WHERE
      "hfb_file".signature = '$#'  
  """

  try:
    conn.rawSelect(query % signature, status)

  except DbError:
    return result.none(500, getCurrentExceptionMsg())

  except NotFoundError:
    return result.none(404, "Not Found")

  return some status  

export
  deleteHf, resolveHf,
  uploadHf, types
  
  # let po = waitFor delete("linux:rijal")  

  # try:
  #   assert po.isSome
  #   echo po.get

  # except Exception:    
  #   echo po.status
  #   echo po.errorReason
