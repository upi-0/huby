import unittest, json, times, strutils, asyncdispatch, hmac
import db, models/[garage, webhook], webhook, publickey, service/implement

suite "Webhook Service Tests (Extreme Edge Cases & Event Filtering)":

  var
    testGarage: Garage

  setup:
    testGarage = newGarage()
    conn.insert(testGarage)

  teardown:
    try:
      if testGarage.id != 0:
        conn.exec(sql("DELETE FROM webhook.deliveries WHERE garage = " & $testGarage.id))
        conn.exec(sql("DELETE FROM hfb_garage WHERE id = " & $testGarage.id))
    except Exception as e:
      echo "Teardown error: ", e.msg

  test "createWebhookConnection and structure initialization":
    let captureArr = %*["file.put", "file.delete"]
    let connObj = createWebhookConnection(
      garageKey = testGarage.key,
      origin = "https://example.com",
      endpoint = "/webhook/huby",
      garageId = testGarage.id,
      capture = captureArr
    )

    check connObj.garageKey == testGarage.key
    check connObj.garageId == testGarage.id
    check connObj.origin == "https://example.com"
    check connObj.endpoint == "/webhook/huby"

  test "Event filtering with capture: ignored events vs allowed events":
    let captureArr = %*["file.put", "file.delete"]
    let connObj = createWebhookConnection(
      garageKey = testGarage.key,
      origin = "http://127.0.0.1:9999",
      endpoint = "/hook",
      garageId = testGarage.id,
      capture = captureArr
    )

    # 1. Send ignored event ("file.renamed" not in capture)
    connObj.sendHook("file.renamed", %*{"key": "test_ignored"})
    waitFor sleepAsync(500)

    # Check that no delivery was inserted for "file.renamed"
    let ignoredRows = conn.getAllRows(
      sql("SELECT id FROM webhook.deliveries WHERE garage = " & $testGarage.id & " AND event = 'file.renamed'")
    )
    check ignoredRows.len == 0

    # 2. Send allowed event ("file.put" in capture)
    connObj.sendHook("file.put", %*{"key": "test_allowed", "success": true})
    waitFor sleepAsync(1000)

    # Check that delivery was inserted for "file.put"
    let allowedRows = conn.getAllRows(
      sql("SELECT id, event, origin, endpoint FROM webhook.deliveries WHERE garage = " & $testGarage.id & " AND event = 'file.put'")
    )
    check allowedRows.len >= 1
    check allowedRows[0][1].to(string) == "file.put"

  test "Extreme Case: Emoji and Unicode in Webhook Event & Data":
    let connObj = createWebhookConnection(
      garageKey = testGarage.key,
      origin = "http://127.0.0.1:9999",
      endpoint = "/hook/🐱",
      garageId = testGarage.id,
      capture = newJArray() # capture all
    )

    let emojiEvent = "file.upload_🐱_🔥"
    let emojiData = %*{
      "filename": "foto_kucing_😺.jpg",
      "tags": ["🐱", "🔥", "🚀"],
      "unicode": "こんにちは世界"
    }

    connObj.sendHook(emojiEvent, emojiData)
    waitFor sleepAsync(1000)

    let emojiRows = conn.getAllRows(
      sql("SELECT id, event, origin, endpoint FROM webhook.deliveries WHERE garage = " & $testGarage.id & " AND event = '" & emojiEvent & "'")
    )
    check emojiRows.len >= 1
    check emojiRows[0][1].to(string) == emojiEvent
    check emojiRows[0][3].to(string) == "/hook/🐱"

  test "Extreme Case: SQL Injection & XSS Payloads in Webhook origin & endpoint":
    let sqliOrigin = "https://site.com/test' OR '1'='1"
    let sqliEndpoint = "/webhook'; DROP TABLE deliveries; --"

    let connObj = createWebhookConnection(
      garageKey = testGarage.key,
      origin = sqliOrigin,
      endpoint = sqliEndpoint,
      garageId = testGarage.id,
      capture = newJArray()
    )

    let sqliEvent = "file.sqli_test"
    connObj.sendHook(sqliEvent, %*{"payload": "<script>alert('XSS')</script>"})
    waitFor sleepAsync(1000)

    let sqliRows = conn.getAllRows(
      sql("SELECT id, event FROM webhook.deliveries WHERE garage = " & $testGarage.id & " AND event = '" & sqliEvent & "'")
    )
    check sqliRows.len >= 1
    check sqliRows[0][1].to(string) == sqliEvent

  test "Webhook Signature Generation validation":
    let body = $(%*{"event": "file.put", "data": {"size": 5120}})
    let expectedSig = "sha256=" & hmac_sha256(testGarage.key, body).toHex()
    
    check expectedSig.startsWith("sha256=")
    check expectedSig.len == 7 + 64 # "sha256=" + 64 hex chars
