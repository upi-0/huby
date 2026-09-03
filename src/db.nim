import
  models/all, norm/model,
  env

import postgres; export postgres

let
  host = getEnv("DB_HOST")
  user = getEnv("DB_USER")
  pass = getEnv("DB_PASS")
  name = when defined(useTest): "jokodb_test" else: getEnv("DB_NAME")
  conn = open(host, user, pass, name)

block:
  conn.createTables(newStorageRepo())
  conn.createTables(emptyFile())
  conn.createTables(WebhookDeliveries(garage: emptyGarage()))

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
    owner.namespace = "penus"
    owner.access_key = "kadapdap21"
    owner.secret_access_key = "laterus"
    owner.storage_used = 0
    owner.max_storage = 30 * 1024 * 1024

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
  model, conn
