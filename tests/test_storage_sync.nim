import unittest, times, strutils
import db, models/all, cron/storage_sync, service/owner/main, service/storage_repo/main, service/implement, publickey

suite "Storage Sync Cron & Owner Quota Tests":

  var
    testOwner: Owner
    testGarage: Garage
    testRepo: StorageRepo
    createdFileIds: seq[int64] = @[]

  setup:
    # Setup test repo
    let idleRepo = conn.getIdleStorageRepo()
    if idleRepo.isSome:
      testRepo = idleRepo.get
    else:
      testRepo = newStorageRepo()
      testRepo.namespace = "test_ns"
      testRepo.access_key = "test_ak"
      testRepo.secret_access_key = "test_sk"
      testRepo.token = "test_token"
      testRepo.bucket = "test_bucket"
      testRepo.storage_used = 0
      conn.insert(testRepo)

    # Setup test owner
    testOwner = (new Owner).setCreatedAt()
    testOwner.namespace = "test_sync_" & generateKey("", 2)
    testOwner.access_key = "sync_ak_" & generateKey("", 2)
    testOwner.secret_access_key = "sync_sk_" & generateKey("", 2)
    testOwner.storage_used = 0
    testOwner.max_storage = 1048576 # 1 MB limit
    testOwner.last_update_storage_used = 0
    conn.insert(testOwner)

    # Setup test garage
    testGarage = newGarage()
    testGarage.owner = testOwner
    conn.insert(testGarage)

  teardown:
    try:
      if createdFileIds.len > 0:
        conn.exec(sql("DELETE FROM s3.file WHERE id IN (" & createdFileIds.join(",") & ")"))
      if testGarage.id != 0:
        conn.exec(sql("DELETE FROM s3.garage WHERE id = " & $testGarage.id))
      if testOwner.id != 0:
        conn.exec(sql("DELETE FROM s3.owner WHERE id = " & $testOwner.id))
    except Exception as e:
      echo "Teardown error: ", e.msg

  test "Batch CTE syncs active files, updates owner storage, and marks is_size_sync":
    # 1. Insert file 1 (active: 150 KB)
    var f1 = FileModel(
      garage: testGarage,
      key: "sync/f1.png",
      signature: "sig_f1_" & generateKey("", 2),
      ext: "png",
      size: 150,
      isUploaded: true,
      isDeleted: false,
      persistAccess: true,
      is_size_sync: false,
      address: "huby/f1.png",
      storage_repo: testRepo
    )
    conn.insert(f1)
    createdFileIds.add(f1.id)

    # 2. Insert file 2 (active: 250 KB)
    var f2 = FileModel(
      garage: testGarage,
      key: "sync/f2.png",
      signature: "sig_f2_" & generateKey("", 2),
      ext: "png",
      size: 250,
      isUploaded: true,
      isDeleted: false,
      persistAccess: true,
      is_size_sync: false,
      address: "huby/f2.png",
      storage_repo: testRepo
    )
    conn.insert(f2)
    createdFileIds.add(f2.id)

    # 3. Insert file 3 (in-progress upload: 500 KB, isUploaded = false)
    var f3 = FileModel(
      garage: testGarage,
      key: "sync/f3.png",
      signature: "sig_f3_" & generateKey("", 2),
      ext: "png",
      size: 500,
      isUploaded: false,
      isDeleted: false,
      persistAccess: true,
      is_size_sync: false,
      address: "huby/f3.png",
      storage_repo: testRepo
    )
    conn.insert(f3)
    createdFileIds.add(f3.id)

    # Execute syncStorage
    let summary1 = syncStorage(conn)
    check summary1.ownersUpdated >= 1

    # Verify Owner in DB
    var refreshedOwner = new Owner
    conn.select(refreshedOwner, "s3.owner.id = $#" % [$testOwner.id])
    check refreshedOwner.storage_used == 400 # 150 + 250 (f3 ignored because not uploaded)
    check refreshedOwner.last_update_storage_used > 0

    # Verify Files in DB marked is_size_sync = true
    var chkF1 = emptyFile()
    conn.select(chkF1, "s3.file.id = $#" % [$f1.id])
    check chkF1.is_size_sync == true

    var chkF2 = emptyFile()
    conn.select(chkF2, "s3.file.id = $#" % [$f2.id])
    check chkF2.is_size_sync == true

    # Second run without changes should update 0 dirty owners
    let summary2 = syncStorage(conn)
    check summary2.ownersUpdated == 0

    # 4. Soft Delete f1 -> mark is_size_sync = false
    chkF1.isDeleted = true
    chkF1.isUploaded = false
    chkF1.is_size_sync = false
    conn.update(chkF1, ["isDeleted", "isUploaded", "is_size_sync"])

    # Re-run syncStorage
    let summary3 = syncStorage(conn)
    check summary3.ownersUpdated >= 1

    conn.select(refreshedOwner, "s3.owner.id = $#" % [$testOwner.id])
    check refreshedOwner.storage_used == 250 # Only f2 remains active!

    # Check f1 is marked sync again
    conn.select(chkF1, "s3.file.id = $#" % [$f1.id])
    check chkF1.is_size_sync == true

  test "checkStorageQuota accurately validates against max_storage":
    testOwner.storage_used = 500
    testOwner.max_storage = 1000

    # Within quota
    let allowed = testOwner.checkStorageQuota(400)
    check allowed.isSome
    check allowed.get == true

    # Exceeds quota
    let blocked = testOwner.checkStorageQuota(600)
    check blocked.isNone
    check blocked.status == 403
    check blocked.errorReason == "Limit Reached"
