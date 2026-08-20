type
  ServiceValueError* = enum
    success, userFailure, serverFailure

  ServiceValueException* = ref object of CatchableError
    errorReason*: string
    status*: int

  ServiceValue*[T] = ref object of RootObj
    value*: T
    errorReason*: string
    status* = 200
    isEmpty* = true
