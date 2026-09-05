import
  strutils,
  ../base, publicKey, owner,
  service/cfcors

export cfcors

type
  Garage* {.tableName: "garage", schemaName: "s3".} = ref object of BaseModel
    name*: string
    isBanned* = false
    owner*: Owner
    config*: string

proc newGarage* : Garage =
  Garage(
    name: generateKey()
  ).setCreatedAt()

proc emptyGarage*: Garage =
  Garage(owner: new Owner).setCreatedAt()

proc corsConfig*(g: Garage): CorsConfig =
  parseCorsConfig(g.config)

proc setCorsConfig*(g: Garage, cfg: CorsConfig) =
  g.config = $cfg

proc hasCorsConfig*(g: Garage): bool =
  g.config.strip().len > 0 and g.corsConfig.len > 0

