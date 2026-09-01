import
  models/[garage, file, storage_repo, webhook], norm/model,
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
  conn.createTables(WebhookDeliveries(garage: newGarage()))

export
  model, conn
