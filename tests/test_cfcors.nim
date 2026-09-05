import unittest, json, strutils
import service/cfcors
import models/s3/garage

suite "Cloudflare CORS & Garage Config Tests":

  let cloudflareSampleJson = """
  [
    {
      "AllowedOrigins": [
        "http://localhost:3001",
        "https://*.example.com"
      ],
      "AllowedMethods": [
        "GET",
        "PUT",
        "POST",
        "DELETE"
      ],
      "AllowedHeaders": [
        "content-type",
        "x-amz-date"
      ],
      "ExposeHeaders": [
        "ETag",
        "Location"
      ],
      "MaxAgeSeconds": 3000
    },
    {
      "AllowedOrigins": [
        "*"
      ],
      "AllowedMethods": [
        "GET"
      ],
      "MaxAgeSeconds": 600
    }
  ]
  """

  test "Parse Cloudflare CORS JSON format into CorsConfig":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    check cfg.len == 2

    # Rule 1
    check cfg[0].allowedOrigins == @["http://localhost:3001", "https://*.example.com"]
    check cfg[0].allowedMethods == @["GET", "PUT", "POST", "DELETE"]
    check cfg[0].allowedHeaders == @["content-type", "x-amz-date"]
    check cfg[0].exposeHeaders == @["ETag", "Location"]
    check cfg[0].maxAgeSeconds == 3000

    # Rule 2
    check cfg[1].allowedOrigins == @["*"]
    check cfg[1].allowedMethods == @["GET"]
    check cfg[1].allowedHeaders.len == 0
    check cfg[1].maxAgeSeconds == 600

  test "Serialize CorsConfig back to Cloudflare format JSON":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    let jsonNode = cfg.toJson()
    check jsonNode.kind == JArray
    check jsonNode.len == 2
    check jsonNode[0].hasKey("AllowedOrigins")
    check jsonNode[0].hasKey("AllowedMethods")
    check jsonNode[0].hasKey("AllowedHeaders")
    check jsonNode[0].hasKey("ExposeHeaders")
    check jsonNode[0].hasKey("MaxAgeSeconds")
    check jsonNode[0]["MaxAgeSeconds"].getInt() == 3000

  test "Parse camelCase and wrapped { 'rules': [...] } formats":
    let wrappedJson = """
    {
      "rules": [
        {
          "allowedOrigins": ["https://app.example.com"],
          "allowedMethods": ["PUT"],
          "allowedHeaders": ["*"],
          "maxAgeSeconds": 1800
        }
      ]
    }
    """
    let cfg = parseCorsConfig(wrappedJson)
    check cfg.len == 1
    check cfg[0].allowedOrigins == @["https://app.example.com"]
    check cfg[0].allowedMethods == @["PUT"]
    check cfg[0].allowedHeaders == @["*"]
    check cfg[0].maxAgeSeconds == 1800

  test "Parse empty or invalid config gracefully":
    check parseCorsConfig("").len == 0
    check parseCorsConfig("{}").len == 0
    check parseCorsConfig("[]").len == 0
    check parseCorsConfig("invalid json").len == 0

  test "Garage model CORS integration":
    var g = emptyGarage()
    check not g.hasCorsConfig()
    check g.corsConfig.len == 0

    g.config = cloudflareSampleJson
    check g.hasCorsConfig()
    let cfg = g.corsConfig
    check cfg.len == 2

    # Test setCorsConfig
    var g2 = emptyGarage()
    g2.setCorsConfig(cfg)
    check g2.hasCorsConfig()
    check g2.corsConfig.len == 2

  test "CORS matching: exact origin match":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    let res = cfg.matchCors("http://localhost:3001", "PUT", @["content-type"])
    check res.matched
    check res.allowOrigin == "http://localhost:3001"
    check res.allowMethods.contains("PUT")
    check res.maxAgeSeconds == 3000
    check res.exposeHeaders == @["ETag", "Location"]

  test "CORS matching: wildcard origin (*)":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    let res = cfg.matchCors("https://random-site.org", "GET")
    check res.matched
    check res.allowOrigin == "*"
    check res.allowMethods.contains("GET")
    check res.maxAgeSeconds == 600

  test "CORS matching: subdomain wildcard match":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    let res = cfg.matchCors("https://sub.example.com", "POST", @["x-amz-date"])
    check res.matched
    check res.allowOrigin == "https://sub.example.com"
    check res.allowMethods.contains("POST")

  test "CORS rejection: disallowed method":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    # PATCH is not in AllowedMethods
    let res = cfg.matchCors("http://localhost:3001", "PATCH")
    check not res.matched

  test "CORS rejection: disallowed origin":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    # random site with PUT (only GET matches wildcard rule 2)
    let res = cfg.matchCors("https://evil.com", "PUT")
    check not res.matched

  test "CORS rejection: disallowed header":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    # x-custom-header is not in AllowedHeaders
    let res = cfg.matchCors("http://localhost:3001", "POST", @["content-type", "x-custom-header"])
    check not res.matched

  test "CORS headers JSON serialization":
    let cfg = parseCorsConfig(cloudflareSampleJson)
    let res = cfg.matchCors("http://localhost:3001", "PUT", @["content-type"])
    check res.matched
    let headersJson = res.toHeadersJson()
    check headersJson["Access-Control-Allow-Origin"].getStr() == "http://localhost:3001"
    check headersJson["Access-Control-Allow-Methods"].getStr() == "GET, PUT, POST, DELETE"
    check headersJson["Access-Control-Allow-Headers"].getStr() == "content-type"
    check headersJson["Access-Control-Expose-Headers"].getStr() == "ETag, Location"
    check headersJson["Access-Control-Max-Age"].getStr() == "3000"
