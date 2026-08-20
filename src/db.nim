import
  models/[garage, file, webhook], norm/model,
  env

import postgres; export postgres

let
  host = getEnv("DB_HOST")
  user = getEnv("DB_USER")
  pass = getEnv("DB_PASS")
  name = getEnv("DB_NAME")
  conn = open(host, user, pass, name)

block:
  conn.createTables(newFile newGarage())
  conn.createTables(WebhookDeliveries(garage: newGarage()))

export
  model, conn
