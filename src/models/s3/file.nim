import
  strutils

import
  ../base

import
  ../storage/repo,
  garage  

type
  FileIdentifier = ref object of BaseModel
    key*: string

  File* {.tableName: "file", schemaName: "s3".} = ref object of FileIdentifier
    garage*: Garage
    size*: int64
    isUploaded*: bool
    isDeleted*: bool
    persistAccess* = true
    signature* {.unique.}: string
    ext*: string
    address*: string
    storage_repo*: StorageRepo
    version*: int

  FileModel* = File    

proc newFile*(garage: Garage) : File =
  File(garage: Garage(id: garage.id), storage_repo: newStorageRepo()).setCreatedAt()

proc emptyFile*: File =
  File(garage: emptyGarage(), storage_repo: newStorageRepo()).setCreatedAt()

proc newFile*(key = "") : File {.deprecated.} =
  File(key: key).setCreatedAt()

type
  FileQuery* = object
    listFiles = """
      SELECT
        "s3.file".size,
        "s3.file".isUploaded,
        "s3.file".isDeleted,
        "s3.file".signature,
        "s3.file".ext,
        "s3.file".views,
        "s3.file".key
      FROM
        "s3.file" file
      INNER JOIN
        "s3.garage" garage ON file.id = garage.id
      WHERE
        file.key LIKE   '$#%' AND
        file.isDeleted = $#   AND
        garage.key =    '$#'  AND
        LIMIT            $#
    """

    byStatus = """
      SELECT
        file.isuploaded,
        file.isdeleted,
        file.persistaccess
      FROM
        "s3.file" file
      INNER JOIN
        "s3.garage" garage ON file.garage = garage.id
      WHERE
        file.key = '$#' AND
        garage.key = '$#'
    """

    select* = "s3.file.key = '$#' AND s3.file.garage = $#"

func escapeSql(val: string): string =
  val.replace("'", "''")

func list*(query: FileQuery; garageKey, fileKey: string; isDeleted = false; limit = 50): string =
  query.listFiles % [fileKey.escapeSql, $isDeleted, garageKey.escapeSql, $limit]

func checkStatus*(query: FileQuery; garageKey, key: string): string =
  query.byStatus % [key.escapeSql, garageKey.escapeSql]
