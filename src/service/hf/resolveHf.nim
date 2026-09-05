import
  strutils, asyncdispatch, httpclient, tables

import
  ../implement,
  ../storage_repo/main

import  
  models/s3/file as fm,
  http/client

type HuggingfaceUrl* = tuple
  hfUrl: string
  httpUrl: string

proc resolve*(file: fm.File; download = false) : ServiceValue[HuggingfaceUrl] =
  try:
    let
      realAddress = block:
        if file.address.count('/') == 1: [file.address & "/" & file.signature, file.ext].join(".")
        else: file.address
      dl = block:
        if download: "?download=true"
        else: ""
      repo = file.storage_repo.getRepoAddress()  
      httpUrl = "https://huggingface.co/buckets/$#/resolve/$#" % [repo, realAddress] & dl
      hfUrl = "hf://buckets/" & [repo, realAddress].join("/")

    return some (hfUrl, httpUrl)
  
  except:
    return none(HuggingfaceUrl, 500)

proc redirectUrl*(resolved: HuggingfaceUrl) : Future[ServiceValue[string]] {.async.} =
  try:
    let
      http = inheritHttpConnection()
      resp = await http.client.request(resolved.httpUrl)
      url = resp.headers.table["location"][0]

    defer:
      http.stop()

    some(url)

  except KeyError:
    none(string, 404, resolved.httpUrl)

  except Exception:
    none(string, 500)
