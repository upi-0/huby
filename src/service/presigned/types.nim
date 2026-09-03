import json

type
  MetaObj* = ref object of RootObj
    key*: string
    config*: JsonNode

export json
