import
  db, models/garage

import
  ../implement

import strutils

proc getGarageByField*(field, fieldVal: string) : ServiceValue[Garage] =
  try:
    var yakut = new Garage
    conn.select(yakut, "hfb_garage.$# = '$#'" % [field, fieldVal])

    return some yakut

  except Exception:
    return result.none(404, "Garage Not Found")  
