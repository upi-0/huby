import norm/postgres
export postgres except update, insert

import
  norm/model,
  norm/private/postgres/[llexec, rowutils]

import  
  sugar, strutils

proc insert*[T: Model](dbConn: DbConn; obj: var T, force = false) =
  checkRo(T)

  if obj.id != 0 and not force:
    return

  var
    cols = obj.cols()
    row = obj.toRow()

  if obj.id != 0 and force:
      cols.add("id")
      row.add dbValue(obj.id)

  let
    phds = collect(newSeq, for i, _ in row: "$" & $(i + 1))
    action = "ON CONFLICT (id) DO NOTHING"
    qry = "INSERT INTO $# ($#) VALUES($#) $#" % [T.table, cols.join(", "), phds.join(", "), action]

  obj.id = dbConn.insertID(sql qry, row)

  if obj.id != 0 and force:
    let qry = sql "SELECT SETVAL((SELECT PG_GET_SERIAL_SEQUENCE('$#', 'id')), (SELECT MAX(id) FROM $#)+1, FALSE)" % [T.table, T.table]
    execExpectTuplesOk(dbConn, qry, @[])


proc update*[T: Model](dbConn: DbConn; obj: var T) =
  checkRo(T)

  let
    row = obj.toRow()
    phds = collect(newSeq):
      for i, col in obj.cols:
        "$# = $$$#" %  [col, $(i + 1)]
    qry = "UPDATE $# SET $# WHERE id = $#" % [T.table, phds.join(", "), $obj.id]

  dbConn.exec(sql qry, row)
