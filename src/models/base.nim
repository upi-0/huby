import norm/model; export model;
import norm/pragmas; export pragmas;
import times; export times

type BaseModel* = ref object of Model
  createdAt*: int64

proc setCreatedAt*[T: BaseModel](model: T): T =
  model.createdAt = getTime().toUnix()
  return model
