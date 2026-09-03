import unittest, strutils
import db, models/all, service/file/main, service/implement, publickey

suite "File Service Tests (DB Integration, Logic & Extreme Edge Cases)":

  var
    testGarage: Garage
    testFileService: FileService

  setup:
    testGarage = newGarage()
    testGarage.storage_used = 0
    testGarage.max_storage = 1048576 # 1 MB limit
    conn.insert(testGarage)
    testFileService = newFileService(testGarage, conn)

  teardown:
    try:
      if testGarage.id != 0:
        conn.exec(sql("DELETE FROM s3.file WHERE garage = " & $testGarage.id))
        conn.exec(sql("DELETE FROM s3.garage WHERE id = " & $testGarage.id))
    except Exception as e:
      echo "Teardown error: ", e.msg

  test "newFileService by garage name (Success and Failure)":
    let validServiceVal = newFileService(testGarage.name)
    check validServiceVal.isSome
    check validServiceVal.get.garage.name == testGarage.name

    let nonExistent = newFileService("non_existent_garage_name_99999")
    check nonExistent.isNone
    check nonExistent.status == 404

    # Extreme Case: Syntax-breaking SQL Injection in garage name lookup safely caught as 404
    let brokenSqliName = "test'; INVALID SYNTAX ERROR; --"
    let sqliServiceVal = newFileService(brokenSqliName)
    check sqliServiceVal.isNone
    check sqliServiceVal.status == 404

  test "updateStorageUsed: increments, decrements, and respects max_storage limit":
    # Increment storage by 100 KB
    let updated1 = testFileService.updateStorageUsed(100, "+")
    check updated1.isSome
    check updated1.get == 100

    # Increment storage by another 200 KB
    let updated2 = testFileService.updateStorageUsed(200, "+")
    check updated2.isSome
    check updated2.get == 300

    # Decrement storage by 50 KB
    let updated3 = testFileService.updateStorageUsed(50, "-")
    check updated3.isSome
    check updated3.get == 250

    # Extreme Case: Exceed max_storage limit (limit is 1048576)
    let exceeded = testFileService.updateStorageUsed(2000000, "+")
    check exceeded.isNone
    check exceeded.status == 403
    check exceeded.errorReason.contains("Limit Reached")

  test "exists, select, status, and setPersistAccess (Normal Case)":
    let fileKey = "docs/normal_file.txt"
    var f = FileModel(
      garage: testGarage,
      key: fileKey,
      signature: "sig_normal_" & generateKey("", 2),
      repo: "test_repo",
      ext: "txt",
      size: 100,
      isUploaded: true,
      isDeleted: false,
      persistAccess: true,
      address: "huby/2026-8-23/sig_normal/normal_file.txt"
    )
    conn.insert(f)

    # Test exists
    check testFileService.exists(fileKey).get == true
    check testFileService.exists("non_existent_file_key").get == false

    # Test select
    var selectedFile = emptyFile()
    let selRes = testFileService.select(fileKey, selectedFile)
    check selRes.isSome
    check selectedFile.key == fileKey
    check selectedFile.signature == f.signature
    check selectedFile.isUploaded == true

    # Test status
    let statusRes = testFileService.status(fileKey)
    check statusRes.isSome
    check statusRes.get.isUploaded == true
    check statusRes.get.isDeleted == false
    check statusRes.get.persistAccess == true

    # Test setPersistAccess: toggle to false
    let persistRes1 = testFileService.setPersistAccess(fileKey, false)
    check persistRes1.isSome
    let statusAfterDisable = testFileService.status(fileKey)
    check statusAfterDisable.isSome
    check statusAfterDisable.get.persistAccess == false

    # Test setPersistAccess: toggle back to true
    let persistRes2 = testFileService.setPersistAccess(fileKey, true)
    check persistRes2.isSome
    let statusAfterEnable = testFileService.status(fileKey)
    check statusAfterEnable.isSome
    check statusAfterEnable.get.persistAccess == true

  test "Extreme Case: Emoji and Unicode in file keys":
    let emojiFileKey = "📂/projek_rahasia_🐱/gambar_api_🔥_🚀.png"
    var emojiFile = FileModel(
      garage: testGarage,
      key: emojiFileKey,
      signature: "sig_emoji_" & generateKey("", 2),
      repo: "test_repo",
      ext: "png",
      size: 5120,
      isUploaded: true,
      isDeleted: false,
      persistAccess: true,
      address: "huby/2026-8-23/sig_emoji/gambar_api.png"
    )
    conn.insert(emojiFile)

    # Verify exists with emoji key
    check testFileService.exists(emojiFileKey).get == true

    # Verify select with emoji key
    var selectedEmojiFile = emptyFile()
    let selEmojiRes = testFileService.select(emojiFileKey, selectedEmojiFile)
    check selEmojiRes.isSome
    check selectedEmojiFile.key == emojiFileKey
    check selectedEmojiFile.size == 5120

    # Verify status with emoji key
    let emojiStatus = testFileService.status(emojiFileKey)
    check emojiStatus.isSome
    check emojiStatus.get.isUploaded == true

  test "Extreme Case: SQL Injection attack handling in File Key":
    let sqliKey = "test_file.txt'; DROP TABLE s3.file; --"
    
    # select gracefully handles DbError and returns 404
    var emptyF = emptyFile()
    let selectRes = testFileService.select(sqliKey, emptyF)
    check selectRes.isNone
    check selectRes.status == 404

    # status gracefully handles DbError and returns 500
    let statusRes = testFileService.status(sqliKey)
    check statusRes.isNone
    check statusRes.status in [404, 500]

    # exists with malformed SQL raises DbError
    expect DbError:
      discard testFileService.exists(sqliKey)

  test "Select and Status for Non-Existent File returns 404":
    var dummyF = emptyFile()
    let selRes = testFileService.select("completely_absent_key_xyz", dummyF)
    check selRes.isNone
    check selRes.status == 404

    let statRes = testFileService.status("completely_absent_key_xyz")
    check statRes.isNone
    check statRes.status == 404
