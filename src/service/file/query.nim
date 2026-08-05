import strutils

type FileQuery* = object
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

    byStatus = """
      SELECT
        file.isuploaded,
        file.isdeleted,
        file.persistaccess
      FROM
        "hfb_file" file
      INNER JOIN
        "hfb_garage" garage ON file.id = garage.id
      WHERE
        file.key = '$#' AND
        garage.key = '$#'
    """

    select* = "hfb_file.key = '$#' AND hfb_file.garage = $#"


func list*(query: FileQuery; garageKey, fileKey: string; isDeleted = false; limit = 50): string =
  query.listFiles % [fileKey, $isDeleted, garageKey, $limit]

func checkStatus*(query: FileQuery; garageKey, key: string): string =
  query.byStatus % [key, garageKey]
