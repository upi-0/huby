{.define: ssl.}

import
  httpclient, asyncdispatch, net, env

type
  HttpConnection* = ref object of RootObj  
    client*: AsyncHttpClient

var hcs = newSeq[HttpConnection](0)
let hca = hcs.addr

proc generateClient() : AsyncHttpClient =
  newAsyncHttpClient(
    userAgent= getEnv("HTTP_USER_AGENT", "Huby"),
    maxRedirects=0
  )

proc newHttpConnection() : HttpConnection =
  HttpConnection(
    client: generateClient()
  )

proc createHttpConnectionPool*(count = 10) =
  for _ in 1 .. count:  
    hca[].add newHttpConnection()

proc inheritHttpConnection* : HttpConnection =
  hca[].pop()

proc stop*(conn: HttpConnection) =
  conn.client.reset()
  hca[].add newHttpConnection()

proc reNewClient(conn: HttpConnection) : void =
  conn.client.reset()
  conn.client = generateClient()

proc request*(conn: ptr HttpConnection; url: string; headers: HttpHeaders = nil) : Future[AsyncResponse] {.async.} =
  let client = conn[].client

  proc sendRequest() : Future[AsyncResponse] {.async.} =
    await client.request(url, headers=headers)

  try:
    result = await sendRequest()

  except ProtocolError:
    conn[].reNewClient()
    result = await sendRequest()

let
  conn {.deprecated.} = newHttpConnection()
  hc* {.deprecated.} = addr conn

createHttpConnectionPool(10)
