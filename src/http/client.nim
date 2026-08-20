{.define: ssl.}

import
  httpclient, asyncdispatch, net

type
  HttpConnection* = ref object of RootObj  
    client*: AsyncHttpClient

proc generateClient() : AsyncHttpClient =
  newAsyncHttpClient(
    userAgent="Huby by Devtrine",
    maxRedirects=0
  )

proc newHttpConnection() : HttpConnection =
  HttpConnection(
    client: generateClient()
  )

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
  conn = newHttpConnection()
  hc* = addr conn
