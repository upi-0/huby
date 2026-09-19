import
  models/all, norm/[model, pool],
  std/with,
  asyncdispatch

import postgres; export postgres

when defined(useLocalDb):
  import env
  putEnv("DB_HOST", "localhost:5432")
  putEnv("DB_USER", getEnv("DB_USER", "postgres"))
  putEnv("DB_PASS", getEnv("DB_PASS", "password"))
  putEnv("DB_NAME", getEnv("DB_NAME", "postgres"))

var
  connPool = newSeq[DbConn](0)
  connPoolAddr = connPool.addr
  conn* {.deprecated.} = getDb()

proc createDb* = 
  for _ in 1 .. 5:
    connPoolAddr[].add getDb()

proc tryPopDb*: Future[DbConn] {.gcsafe, async.} =
  try:
    result = connPoolAddr[].pop()

  except IndexDefect:
    await sleepAsync(100)
    result = await tryPopDb()

proc stop*(db: var DbConn) {.gcsafe.} =
  connPoolAddr[].add db
  db.reset()
  echo "Current Connection: " & $(connPoolAddr[].len)

createDb()   

with(conn):
  createTables(newStorageRepo())
  createTables(emptyFile())
  createTables(newWebhookEndpoints())
  createTables(newWebhookDelivery()) 
  exec(sql"ALTER TABLE s3.owner ADD COLUMN IF NOT EXISTS last_update_storage_used BIGINT NOT NULL DEFAULT 0;")
  exec(sql"ALTER TABLE s3.file ADD COLUMN IF NOT EXISTS is_size_sync BOOLEAN NOT NULL DEFAULT FALSE;")
  exec(sql"ALTER TABLE s3.garage DROP COLUMN IF EXISTS storage_used;") 
  exec(sql"ALTER TABLE webhook.deliveries DROP COLUMN IF EXISTS garage;")
  exec(sql"ALTER TABLE webhook.deliveries DROP COLUMN IF EXISTS origin;")
  exec(sql"ALTER TABLE webhook.deliveries DROP COLUMN IF EXISTS trigger_ip;")

# Higher Level Query Generator
import strutils
import sequtils, sugar
import times

const sp = "  "  

proc flat*(s: string): string =
  s.replace("\n", " ").replace("  ", "")

proc scopeQuery*(statements: varargs[string]): string =
  result = statements.join("\n") & ";"

proc query*(statements: varargs[string]): string =
  result = scopeQuery(statements)
  let
    dap = now()
    waktu = "[$#:$#] " % [$dap.hour, $dap.minute]

  echo waktu & result.flat

proc select*(statements: varargs[string]): string =
  result = "SELECT\n"
  result &= statements.map((st) => sp & st).join(",\n")

proc frm*(statements: varargs[string]): string =
  result = "FROM\n"
  result &= sp & statements.join(" ")

proc where*(statemetns: varargs[seq[string]]) : string =
  result = "WHERE\n"

  proc dapdap(s: seq[string]): string =
    var dap: seq[string]

    if s.len == 2:
      dap = @[s[0], "=", s[1]]
    elif s.len == 3:
      dap = @[s[0], s[1], s[2]]    

    dap.join(" ")    

  result &= statemetns.map(
    (e) => sp & e.dapdap
  ).join(" AND\n")

proc join*(strategy: string; statements: varargs[string]): string =
  result = [strategy, "JOIN"].join(" ") & '\n'
  result &= sp & statements.join(" ON ")

proc q*(s: string): string = "'" & s & "'"

when defined(seedS3Credentials) or defined(seedAll):
  import crypto
  
  var
    repo = new StorageRepo
    dapi = loadEncrypterAES256("DB_REPO_SECRET")

  block:
    repo.access_key = dapi.encrypt getEnv("S3_ACCESS_KEY")
    repo.secret_access_key = dapi.encrypt getEnv("S3_SECRET_ACCESS_KEY")
    repo.namespace = dapi.encrypt getEnv("S3_NAMESPACE")
    repo.token = dapi.encrypt getEnv("HF_TOKEN")
    repo.bucket = getEnv("S3_DEFAULT_BUCKET")
    repo.storage_used = 1
    repo.createdAt = getTime().toUnix()

  conn.insert repo  

when defined(seedOwner) or defined(seedAll):
  var owner = (new Owner).setCreatedAt()

  block:
    owner.namespace = "bengkel-sepeda-dv8d"
    owner.access_key = "devtrine-private"
    owner.secret_access_key = "heni_sunarso_kadapi_masnur_ari"
    owner.storage_used = 0
    owner.max_storage = 30 * 1024 * 1024 * 1024

  conn.insert owner

when defined(seedGarage) or defined(seedAll):
  var
    garageOwner = Owner(id: 1)
    garage = newGarage()

  block:
    garage.owner = garageOwner
    garage.isBanned = false
    garage.config = "{}"
    garage.name = "kegiatan"

  conn.insert garage

export
  model, conn, pool

