type
  ServiceValueError* = enum
    success, userFailure, serverFailure

  ServiceValue*[T] = ref object of RootObj
    value: T
    errorReason*: string
    status* = 200
    isEmpty = true

proc groupError*(status: int) : ServiceValueError =
  if status in 200 .. 304:
    return success

  elif status in 400 .. 499:
    return userFailure

  elif status in 500 .. 550:
    return serverFailure

func none*[T](value: typedesc[T]; status: int; reason = "") : ServiceValue[T] =
  result = ServiceValue[T](
    isEmpty: true,
    errorReason: reason,
    status: status
  )

func none*[T](sv: ServiceValue[T]; status: int; reason = "") : ServiceValue[T] =
  none(typeof T, status, reason)

func none*[T, Y](sv: ServiceValue[T]; svv: ServiceValue[Y]) : ServiceValue[T] =
  none(typeof T, svv.status, svv.errorReason)

func some*[T](value: T; status = 200) : ServiceValue[T] =
  result = ServiceValue[T](
    value: value,
    isEmpty: false,
    status: status
  )

proc error*[T](sv: ServiceValue[T]) : ServiceValueError =
  sv.status.groupError()

proc isSome*[T](sv: ServiceValue[T]) : bool =
  not sv.isEmpty

proc isNone*[T](sv: ServiceValue[T]) : bool =
  sv.isEmpty

proc get*[T](sv: ServiceValue[T]) : T =
  assert not sv.isEmpty
  sv.value
  