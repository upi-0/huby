import
  strutils, asyncdispatch, httpclient, tables

import
  ../implement,
  models/file as fm,
  http/client

type HuggingfaceUrl* = tuple
  hfUrl: string
  httpUrl: string

proc resolve*(file: fm.File) : ServiceValue[HuggingfaceUrl] =
  try:
    let
      repo = file.repo
      filename = [file.signature, file.ext].join(".")
      hfUrl = "hf://buckets/" & [repo, file.address, filename].join("/")
      httpUrl = "https://huggingface.co/buckets/$#/resolve/$#/$#" % [repo, file.address, filename]

    return some (hfUrl, httpUrl)
  
  except:
    return none(HuggingfaceUrl, 500)

proc redirectUrl*(resolved: HuggingfaceUrl) : Future[ServiceValue[string]] {.async.} =
  try:
    let
      resp = await hc.request(resolved.httpUrl)
      url = resp.headers.table["location"][0]

    some(url)

  except KeyError:
    none(string, 404, "From HF")

  except Exception:
    none(string, 500)
