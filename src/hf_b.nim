import
  prologue, strutils

import
  urls/[
    wpolicy,
    auth,
    token,
    file,
    access
  ],
  middleware/[cors, form],
  env

import
  prologue/middlewares/sessions/memorysession,
  prologue/middlewares/staticfile

let
  settings = newSettings(
    address = "127.0.0.1",
    appName = getEnv("APP_NAME", "Prologue"),
    debug = getEnv("APP_DEBUG", "true").parseBool(),
    port = Port(6767),
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
    wpolicyUrls, "/.huby/wpolicy"    
  )
  app.addRoute(
    authUrls, "/.huby/auth",
  )  
  app.addRoute(
    tokenUrls, "/.huby/token"
  )
  app.addRoute(
    fileUrls, "/.huby/file"
  )
  app.addRoute(
    accessUrls, "/.huby/storage"
  )

app.run()
