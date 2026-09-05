import
  times,
  db, models/all

type
  OwnerSyncDetail* = object
    ownerId*: int
    storageUsed*: int64

  SyncSummary* = object
    ownersUpdated*: int
    details*: seq[OwnerSyncDetail]
    durationMs*: int64
    timestamp*: int64

const SyncStorageQuery = """
WITH target_owners AS (
    SELECT DISTINCT g.owner AS owner_id
    FROM s3.file f
    JOIN s3.garage g ON f.garage = g.id
    WHERE f.is_size_sync = FALSE
    LIMIT 500
),
files_to_sync AS (
    SELECT f.id AS file_id
    FROM s3.file f
    JOIN s3.garage g ON f.garage = g.id
    JOIN target_owners t ON g.owner = t.owner_id
    WHERE f.is_size_sync = FALSE
),
storage_calc AS (
    SELECT 
        t.owner_id,
        COALESCE(SUM(f.size), 0) AS total_storage
    FROM target_owners t
    JOIN s3.garage g ON g.owner = t.owner_id
    LEFT JOIN s3.file f ON f.garage = g.id 
                       AND f.isUploaded = TRUE 
                       AND f.isDeleted = FALSE
    GROUP BY t.owner_id
),
updated_owners AS (
    UPDATE s3.owner o
    SET 
        storage_used = sc.total_storage,
        last_update_storage_used = $1::bigint
    FROM storage_calc sc
    WHERE o.id = sc.owner_id
    RETURNING o.id, o.storage_used
),
marked_files AS (
    UPDATE s3.file f
    SET is_size_sync = TRUE
    FROM files_to_sync fts
    WHERE f.id = fts.file_id
    RETURNING f.id
)
SELECT id, storage_used FROM updated_owners;
"""

proc syncStorage*(conn: DbConn): SyncSummary =
  ## Performs atomic batch storage synchronization for all owners
  ## that have files with `is_size_sync = false`.
  let startTime = epochTime()
  let nowUnix = getTime().toUnix()
  result.timestamp = nowUnix

  let rows = conn.getAllRows(sql(SyncStorageQuery), $nowUnix)
  for row in rows:
    if row.len >= 2:
      let oid = row[0].to(int)
      let sused = row[1].to(int64)
      result.details.add OwnerSyncDetail(ownerId: oid, storageUsed: sused)

  result.ownersUpdated = result.details.len
  result.durationMs = int64((epochTime() - startTime) * 1000)

when isMainModule:
  echo "== Storage Synchronization Cron Job Starting =="
  let dbConn = getDb()
  try:
    let summary = syncStorage(dbConn)
    echo "== Storage Synchronization Completed in ", summary.durationMs, " ms =="
    echo "Owners updated: ", summary.ownersUpdated
    for d in summary.details:
      echo "  - Owner ID #", d.ownerId, ": storage_used = ", d.storageUsed, " KB"
  finally:
    dbConn.close()
