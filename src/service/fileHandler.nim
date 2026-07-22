{.deprecated.}

import
  strutils, asyncdispatch
  
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

proc select*(file: var FileModel; key: string) : ServiceValue[bool] =
  if key == "":
    return result.none(400)

  try:
    file = newFile("")
    conn.select(file, "hfb_file.key = '$#'" % key)
    return some(true)

  except Exception:
    return result.none(404)

proc exists*[T: FileModel](fk: typedesc[T]; key: string) : ServiceValue[bool] =
  if key == "":
    return result.none(400)

  try:
    assert conn.exists(T, "hfb_file.key = '$#'" % key)

  except Exception, DbError:
    return some false

  some true

proc listFiles*(key: string; delete = false) : Future[ServiceValue[seq[FileObj]]] {.async.} =
  var files = @[FileObj()]

  if key == "" or key.endsWith(":"):
    return result.none(400)  

  try:
    conn.rawSelect(Q_LIST_FILES_K % [key & ":", $delete], files)    

    if files.len > 0:
      return some files

    result.none(404, "No File.")

  except Exception:
    result.none(500, getCurrentExceptionMsg())

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

proc replace(rec: UploadRequestRecord; key: string; fileLength: int) : Future[ServiceValue[FirstResponse]] {.async.} =
  var file: FileModel

  if file.select(key).isNone:
    return result.none(404)

  try:
    file.size = 0
    file.isUploaded = false
    file.isDeleted = false
    file.signature = rec.signature

    conn.update(file)

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
        
        conn.update(file)

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
    rec: UploadRequestRecord;
    key: string;
    fileLength: int;
    replace = false
  ) : Future[ServiceValue[FirstResponse]] {.async.} =
  
  var file = newFile(key)
  let isExists = FileModel.exists(key).get

  if replace and isExists:
    return await replace(rec, key, fileLength)

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

proc delete*(key: string) : Future[ServiceValue[string]] {.async.} =
  var file = new FileModel
  
  if file.select(key).isNone:
    return result.none(404)

  result = await deleteFile(file.resolve().get.hfUrl)

  if result.isSome:
    file.isDeleted = true
    file.isUploaded = false
    file.size = 0

    conn.update(file)

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

when isMainModule:
  import os

  proc upp() {.async.} =
    let po = loadRequestRecord("load.txt")
    writeFile(po.dname / po.fname, "Ini File TXT")

    let ax = await replace(po, "linux:rijal", 3_000)
    await sleepAsync(15_000)

    try:
      assert ax.isSome
      echo ax.get.size

    except AssertionDefect:
      echo ax.status
      echo ax.errorReason    

  waitFor upp()

  # let po = waitFor delete("linux:rijal")  

  # try:
  #   assert po.isSome
  #   echo po.get

  # except Exception:    
  #   echo po.status
  #   echo po.errorReason
