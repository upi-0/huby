import
  prologue, context, json, env,
  strutils, tables, hmac

import  
  s3presign/main,
  service/hf/uploadHf,
  service/file/[main, adapter, migrate],
  service/storage_repo/main,
  service/[types, implement],
  service/presigned/general

proc generateRecord*(ctx: Context) {.async.} =
  ctx.json()
  let
    hash = ctx.request.headers.table["x-hash-256"][0].replace("sha256=")
    body = ctx.request.body()

  if not (
      hmac_sha256(
        getEnv("WORKER_KEY"),
        body
      ).toHex() == hash
    ):
    return ctx.send("", Http403)

  let
    payload = parseJson body    
    impl = newFileService(
      payload["garage"].str)
    meta = resolve(
      payload["query"].str,
      impl.get.garage.key,
      "put").get  
    fileSize = max(payload["size"].getInt() div 1024, 1)       
    replace = meta.config.getOrDefault("replace").getBool(false)

  let
    record = loadRequestRecord(
      meta.config["name"].str)
    datang = impl.get.conn.getIdleStorageRepo().get.getRepoAddress().split("/")
    s3 = datang[0].s3GenerateConf()  

  block:
    let address = impl.get.putFile(meta.key, fileSize, record, replace)

    ctx.send %*{
      "upload_url": s3.presignPut(datang[1], address.get),
      "storage_used": impl.get.garage.storage_used + fileSize
    }

proc completeMigrate*(ctx: Context) {.async.} =
  let body = parseJson ctx.request.body()
  resp $(await completeMigrate(body))
