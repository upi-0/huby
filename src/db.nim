import
  models/[token, file], std/[options, with], norm/model,
  prologue, env

import norm/postgres; export postgres

let
  host = getEnv("DB_HOST")
  user = getEnv("DB_USER")
  pass = getEnv("DB_PASS")
  name = getEnv("DB_NAME")
  conn = open(host, user, pass, name)

# conn.createTables(newFile())

export
  with, model, conn
