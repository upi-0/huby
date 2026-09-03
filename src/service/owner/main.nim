import
  strutils, uuids

import
  db, models/s3/owner,
  postgres

import  
  service/implement

from options import isNone, get

type
  OwnerKeyId = ref object of RootObj
    id*: int64

proc ownerId*(namespace: string) : ServiceValue[int64] =
  try:
    var own = new OwnerKeyId
    let query = """
      SELECT id FROM s3.owner
      WHERE namespace = '$#'
    """ % namespace

    conn.rawSelect(query, own)
    result = some(own.id)

  except Exception:
    return result.none(404, getCurrentExceptionMsg())  

proc owner*(namespace: string) : ServiceValue[Owner] =
  try:
    var owner = new Owner
    conn.select(owner, "s3.owner.namespace = '$#'" % namespace)

    result = some(owner)

  except Exception:
    return result.none(404, "Owner not found")

proc updateStorageUsed*(conn: DbConn; own: Owner; length: int; operator = "+") : ServiceValue[int] =
  const query = """
    UPDATE s3.owner
    SET storage_used = GREATEST(storage_used $operator $length, 1)
    WHERE
      id = $id AND
      GREATEST(storage_used $operator $length, 1) <= max_storage
    RETURNING storage_used::bigint  
  """

  let
    q = query % [
      "operator", operator,
      "length", $length,
      "id", $own.id
    ]
    storageUsed = conn.getRow(sql q)

  if storageUsed.isNone:
    return result.none(403, "Limit Reached")

  result = storageUsed.get[0].to(int).some()

proc refreshSecretAccessKey*(conn: DbConn; own: Owner; currentSecretAccessKey: string) : ServiceValue[string] =
  if own.secret_access_key == currentSecretAccessKey:
    var
      newKey = ($genUUID()).replace("-")
      garageOwner = Owner(id: own.id, secret_access_key: newKey)
    
    conn.update(garageOwner, ["secret_access_key"])

  else:
    return result.none(403, "Invalid Secret Access Key")  

  some("", 204)

when isMainModule:

  template test() =
    try:
      echo res.get

    except:
      echo res.status
      echo res.errorReason  
  
  when defined(a):
    let
      own = getOwner("penus")
      res = conn.updateStorageUsed(own.get, 1000, "+")

    test()

  when defined(b):
    let
      own = getOwner("penus")
      acs = "dapdap"
      res = conn.refreshSecretAccessKey(own.get, acs)

    test()    

  when defined(c):
    let res = ownerId("penus")
    test()
