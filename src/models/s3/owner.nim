import
  ../base

type
  Owner* {.tableName: "owner", schemaName: "s3".} = ref object of BaseModel
    namespace*: string
    access_key* {.unique.}: string
    secret_access_key* : string
    storage_used*, max_storage*: int64
    last_update_storage_used*: int64
