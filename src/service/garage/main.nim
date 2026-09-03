import
  db, models/s3/[garage, owner]

import
  ../implement,
  service/owner/main

import strutils

proc getGarageByField*(ownerId: int; field, fieldVal: string) : ServiceValue[Garage] =
  try:
    var yakut = emptyGarage()
    let safeVal = fieldVal.replace("'", "''")
    conn.select(yakut, "s3.garage.$# = '$#' AND s3.garage.owner = 1" % [field, safeVal])

    return some yakut

  except Exception:
    return result.none(404, getCurrentExceptionMsg())  

when isMainModule:
  let res = getGarageByField(1, "name", "kegiatan")
  echo res.get.owner.secret_access_key

