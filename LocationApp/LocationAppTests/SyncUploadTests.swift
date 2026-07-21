//
//  SyncUploadTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class SyncUploadTests: XCTestCase {

    // MARK: - bulkSyncDesiredKeys (Day 3: drop the photo asset from bulk sync)

    func test_bulkSyncDesiredKeys_dropsPhotoButKeepsHasPhoto() {
        let keys = LocationsCK.bulkSyncDesiredKeys
        XCTAssertFalse(keys.contains("photo"),
                       "Bulk sync must not pull the photo CKAsset; it is fetched lazily via fetch(id:)")
        XCTAssertTrue(keys.contains("hasPhoto"),
                      "hasPhoto must stay in bulk sync so the UI knows a photo exists without the asset")
    }

    func test_recordWithoutPhotoField_stillDecodesWithHasPhotoPreserved() throws {
        // A record as it arrives after desiredKeys filtering: no photo asset.
        let record = makeLocationRecord()
        record.setValue(Int64(1), forKey: "hasPhoto")

        let item = try XCTUnwrap(LocationRecordCacheItem(withRecord: record),
                                 "A photo-less Location record must still decode into a cache item")
        XCTAssertNil(item.photo, "Bulk sync omits the asset, so photo stays nil until fetch(id:)")
        XCTAssertTrue(item.hasPhoto, "hasPhoto must survive bulk sync independent of the photo asset")
    }

    func test_bulkSyncDesiredKeys_coverEveryFieldRequiredToDecodeARecord() {
        // Build a record holding ONLY the fields bulk sync requests. If
        // init?(withRecord:) ever needs a field missing from the list, every
        // synced record would silently fail to decode — this catches that drift.
        let record = makeLocationRecord(restrictedTo: LocationsCK.bulkSyncDesiredKeys)

        XCTAssertNotNil(LocationRecordCacheItem(withRecord: record),
                        "bulkSyncDesiredKeys must include every field init?(withRecord:) requires")
    }

    // MARK: - shouldSkipSave decision (Day 6)

    // shouldSkipSave is the pure decision uploadChanges consults inside its
    // paging loop to skip records the server already shows as collected on the
    // same cycle. The fetched-but-unused dictionary from Day 5 now drives this.

    func test_shouldSkipSave_returnsFalseWhenServerRecordMissing() throws {
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")

        XCTAssertFalse(LocationsCK.shouldSkipSave(item: item, serverRecord: nil),
                       "Without a server record we can't make a skip decision; let the save proceed and rely on CloudKit's own conflict handling")
    }

    func test_shouldSkipSave_returnsTrueWhenServerCollectedOnSameCycle() throws {
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")
        let server = makeServerRecord(collectedFlag: 1, cycleDate: "1-1-2026")

        XCTAssertTrue(LocationsCK.shouldSkipSave(item: item, serverRecord: server),
                      "Server is source of truth: a collected record on the same cycle must not be overwritten by a stale local edit")
    }

    func test_shouldSkipSave_returnsFalseWhenServerNotCollected() throws {
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")
        let server = makeServerRecord(collectedFlag: 0, cycleDate: "1-1-2026")

        XCTAssertFalse(LocationsCK.shouldSkipSave(item: item, serverRecord: server),
                       "An uncollected server record is exactly what the local edit means to update; do not skip")
    }

    func test_shouldSkipSave_returnsFalseWhenServerCollectedOnPriorCycle() throws {
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")
        let server = makeServerRecord(collectedFlag: 1, cycleDate: "7-1-2025")

        XCTAssertFalse(LocationsCK.shouldSkipSave(item: item, serverRecord: server),
                       "Collected-flag is per-cycle; a prior-cycle collection must not block this cycle's save")
    }

    func test_shouldSkipSave_returnsFalseWhenServerMissingCollectedFlag() throws {
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")
        let server = makeServerRecord(collectedFlag: nil, cycleDate: "1-1-2026")

        XCTAssertFalse(LocationsCK.shouldSkipSave(item: item, serverRecord: server),
                       "Without server-side collected status we cannot conclude collected; do not skip")
    }

    // MARK: - shouldSkipLocalSave decision (Day 8)

    // shouldSkipLocalSave is the local-write guardrail save(items:) consults before
    // queuing an edit. It is the local mirror of shouldSkipSave: where shouldSkipSave
    // trusts the fetched *server* record, this one trusts our own *cache* entry, so a
    // record already known-collected for the current cycle never gets queued for
    // upload in the first place.

    func test_shouldSkipLocalSave_returnsFalseWhenNotCached() throws {
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")

        XCTAssertFalse(LocationsCK.shouldSkipLocalSave(item: item, cached: nil),
                       "A record we've never cached can't be a stale re-collect; let the save proceed")
    }

    func test_shouldSkipLocalSave_returnsTrueWhenCachedCollectedOnSameCycle() throws {
        let cached = try makeItem(recordName: "r1", cycleDate: "1-1-2026")
        cached.collectedFlag = 1
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")

        XCTAssertTrue(LocationsCK.shouldSkipLocalSave(item: item, cached: cached),
                      "A record our cache already shows collected this cycle is immutable until next cycle; drop the edit before it's queued")
    }

    func test_shouldSkipLocalSave_returnsFalseWhenCachedNotCollected() throws {
        let cached = try makeItem(recordName: "r1", cycleDate: "1-1-2026")
        cached.collectedFlag = 0
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")

        XCTAssertFalse(LocationsCK.shouldSkipLocalSave(item: item, cached: cached),
                       "An uncollected cached record is exactly what this edit means to update; do not skip")
    }

    func test_shouldSkipLocalSave_returnsFalseWhenCachedCollectedOnPriorCycle() throws {
        let cached = try makeItem(recordName: "r1", cycleDate: "7-1-2025")
        cached.collectedFlag = 1
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")

        XCTAssertFalse(LocationsCK.shouldSkipLocalSave(item: item, cached: cached),
                       "Collected-flag is per-cycle; a prior-cycle collection must not block this cycle's save")
    }

    func test_shouldSkipLocalSave_returnsFalseWhenCachedMissingCycle() throws {
        let cached = try makeItem(recordName: "r1")
        cached.collectedFlag = 1
        let item = try makeItem(recordName: "r1", cycleDate: "1-1-2026")

        XCTAssertFalse(LocationsCK.shouldSkipLocalSave(item: item, cached: cached),
                       "Without a cached cycle we can't conclude same-cycle collection; do not skip")
    }

    // MARK: - New records carry their System dates after upload

    // uploadChanges copies a saved record's server dates onto the cached item so a
    // device-created record's System_Date columns populate without a Reset Cache.
    // CKRecord.creationDate can't be set offline, so the test passes them directly.
    func test_applyServerDates_populatesSystemDatesOnNewlyCreatedRecord() throws {
        let item = try makeItem(recordName: "fresh-record")
        XCTAssertNil(item.creationDate, "Precondition: a device-authored record has no server creation date yet")
        XCTAssertNil(item.modificationDate, "Precondition: a device-authored record has no server modification date yet")

        let deployed = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 24))
        let collected = try XCTUnwrap(noonLocal(year: 2026, month: 7, day: 1))
        LocationsCK.applyServerDates(creationDate: deployed, modificationDate: collected, to: item)

        XCTAssertEqual(item.creationDate, deployed)
        XCTAssertEqual(item.modificationDate, collected)

        // Full circle: the two System_Date columns (9, 10) now render instead of blank.
        let cells = CycleCSVExport.row(for: item).components(separatedBy: ",")
        XCTAssertEqual(cells[9], "06/24/2026", "System deploy date must populate after upload, no Reset Cache needed")
        XCTAssertEqual(cells[10], "07/01/2026", "System collected date must populate after upload, no Reset Cache needed")
    }

    // MARK: - Upload resilience: refused uploads stay queued

    // The three-way decision for one queued record after the pre-save server
    // lookup. A record whose lookup didn't resolve must NOT be saved tag-less —
    // .ifServerRecordUnchanged would reject it and the old code then dropped it.

    func test_uploadAction_fetchedRecord_savesWithTag() {
        let server = makeServerRecord(collectedFlag: 0, cycleDate: "1-1-2026")
        let action = LocationsCK.uploadAction(serverRecord: server, confirmedMissing: false)
        guard case .saveWithTag(let record) = action else {
            return XCTFail("expected saveWithTag when the server copy was fetched")
        }
        XCTAssertTrue(record === server, "must carry the fetched record so the save keeps its change tag")
    }

    func test_uploadAction_confirmedMissing_savesAsNew() {
        let action = LocationsCK.uploadAction(serverRecord: nil, confirmedMissing: true)
        guard case .saveAsNew = action else {
            return XCTFail("expected saveAsNew when the server confirmed the record doesn't exist")
        }
    }

    func test_uploadAction_unresolvedFetch_keepsQueued() {
        let action = LocationsCK.uploadAction(serverRecord: nil, confirmedMissing: false)
        guard case .keepQueued = action else {
            return XCTFail("an unresolved lookup must defer the save, never attempt it tag-less")
        }
    }

    func test_uploadAction_fetchedRecordWinsOverMissingFlag() {
        let server = makeServerRecord(collectedFlag: 0, cycleDate: "1-1-2026")
        let action = LocationsCK.uploadAction(serverRecord: server, confirmedMissing: true)
        guard case .saveWithTag = action else {
            return XCTFail("a fetched record is definitive even if the id was also flagged missing")
        }
    }

    // Queue retention: after an upload pass only resolved recordNames leave the
    // retry queue — the fix for the unconditional removeAll() that discarded
    // refused uploads (signed-out iCloud, unaccepted terms, transient errors).

    func test_queueRetention_removesOnlyResolvedNames() throws {
        let cache = Cache()
        cache.addChange(try makeItem(recordName: "R1"))
        cache.addChange(try makeItem(recordName: "R2"))
        cache.addChange(try makeItem(recordName: "R3"))

        let resolved: Set<String> = ["R1", "R3"]
        cache.changes.removeAll(where: { LocationsCK.shouldRemoveFromQueue(item: $0, resolved: resolved) })

        XCTAssertEqual(cache.changes.map { $0.recordName }, ["R2"], "the unresolved record must stay queued")
    }

    func test_queueRetention_keepsRefusedRecords() throws {
        let cache = Cache()
        cache.addChange(try makeItem(recordName: "R1"))
        cache.addChange(try makeItem(recordName: "R2"))

        // An empty resolved set models a fully refused pass (e.g. device signed out).
        cache.changes.removeAll(where: { LocationsCK.shouldRemoveFromQueue(item: $0, resolved: []) })

        XCTAssertEqual(cache.changes.count, 2, "refused uploads must survive to retry on the next sync")
    }

    func test_queueRetention_dropsNilRecordName() throws {
        let cache = Cache()
        cache.addChange(try makeItem(recordName: nil))

        cache.changes.removeAll(where: { LocationsCK.shouldRemoveFromQueue(item: $0, resolved: []) })

        XCTAssertTrue(cache.changes.isEmpty, "an item that can never upload must not clog the queue forever")
    }

    // MARK: - Incremental-sync watermark ignores device-authored edits

    // Local scans stamp modifiedDate with scan time before the record ever reaches
    // the server. If those edits advance the incremental-fetch watermark, cloud
    // edits by other devices with earlier timestamps are skipped forever.

    func test_syncWatermark_ignoresDeviceAuthoredEdits() throws {
        let synced = try makeItem(recordName: "R1", creationDate: 1_000, modifiedDate: 5_000)
        let deviceAuthored = try makeItem(recordName: "R2", modifiedDate: 9_000)

        let watermark = LocationsCK.syncWatermark(locations: [synced, deviceAuthored])

        XCTAssertEqual(watermark, Date(timeIntervalSinceReferenceDate: 5_000),
                       "an unsynced local edit must not advance the incremental watermark")
    }

    func test_syncWatermark_picksNewestServerStampedModifiedDate() throws {
        let older = try makeItem(recordName: "R1", creationDate: 1_000, modifiedDate: 4_000)
        let newer = try makeItem(recordName: "R2", creationDate: 1_000, modifiedDate: 6_000)

        XCTAssertEqual(LocationsCK.syncWatermark(locations: [older, newer]),
                       Date(timeIntervalSinceReferenceDate: 6_000))
    }

    func test_syncWatermark_nilWhenNoServerStampedRecords() throws {
        let deviceAuthored = try makeItem(recordName: "R1", modifiedDate: 9_000)

        XCTAssertNil(LocationsCK.syncWatermark(locations: [deviceAuthored]),
                     "an all-local cache must fall back to a full fetch, not a bogus watermark")
    }
}
