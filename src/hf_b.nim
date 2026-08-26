import
  prologue, strutils

import
  urls/[access, bridge],
  middleware/[cors, form],
  env

import
  prologue/middlewares/sessions/memorysession

let
  settings = newSettings(
    address = "127.0.0.1",
    appName = getEnv("APP_NAME", "Prologue"),
    debug = getEnv("APP_DEBUG", "true").parseBool(),
    port = Port( parseInt getEnv("APP_PORT", "6969") ),
    secretKey = getEnv("APP_KEY", ""),
  )

settings["prologue"]["maxBody"] = %(8_388_608 * 100)

var app = newApp(settings = settings)

app.use @[
  sessionMiddleware(settings, "huby_token", 3600 * 24, "/.huby"),
  normalize(),
  noCors()
]

block setRoute:
  app.addRoute(
    accessUrls, "/.huby/storage")
  app.addRoute(
    bridgeUrls, "/.huby/bridge")  

app.run()
