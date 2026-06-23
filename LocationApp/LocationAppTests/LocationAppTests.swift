//
//  LocationAppTests.swift
//  LocationAppTests
//
//  Created by Ford, Ryan M. on 10/3/18.
//  Copyright © 2018 Ford, Ryan M. All rights reserved.
//

import XCTest
import CloudKit
@testable import LocationApp

class LocationAppTests: XCTestCase {

    // MARK: - Cache.add upsert behavior

    func test_add_appendsNewItem() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: "r1"))

        XCTAssertEqual(cache.locations.count, 1)
        XCTAssertEqual(cache.locations[0].recordName, "r1")
    }

    func test_add_upsertsByRecordName() throws {
        let cache = Cache()
        let first = try makeItem(recordName: "r1", locdescription: "old")
        let second = try makeItem(recordName: "r1", locdescription: "new")

        cache.add(first)
        cache.add(second)

        XCTAssertEqual(cache.locations.count, 1, "Adding the same recordName twice must upsert, not duplicate")
        XCTAssertEqual(cache.locations[0].locdescription, "new")
    }

    func test_add_preservesDistinctRecordNames() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: "r1"))
        cache.add(try makeItem(recordName: "r2"))
        cache.add(try makeItem(recordName: "r3"))

        XCTAssertEqual(cache.locations.count, 3)
        XCTAssertEqual(cache.locations.map { $0.recordName }, ["r1", "r2", "r3"])
    }

    func test_add_appendsItemsWithNilRecordName() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: nil))
        cache.add(try makeItem(recordName: nil))

        XCTAssertEqual(cache.locations.count, 2, "Items lacking a recordName cannot be deduped; they must each append")
    }

    // MARK: - Cache.clear resets index

    func test_clear_allowsRecycledRecordNameWithoutStaleSlot() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: "r1", locdescription: "before-clear"))
        cache.clear()
        cache.add(try makeItem(recordName: "r1", locdescription: "after-clear"))

        XCTAssertEqual(cache.locations.count, 1)
        XCTAssertEqual(cache.locations[0].locdescription, "after-clear",
                       "After clear(), re-adding the same recordName must land in a fresh slot, not collide with the cleared index")
    }

    // MARK: - save/load rebuilds the index

    func test_saveLoad_rebuildsIndexSoSubsequentAddUpserts() throws {
        removeCacheFileOnDisk()
        addTeardownBlock { self.removeCacheFileOnDisk() }

        let cache = Cache()
        cache.add(try makeItem(recordName: "r1", locdescription: "v1"))
        cache.add(try makeItem(recordName: "r2", locdescription: "v1"))
        cache.save()

        let loaded = try XCTUnwrap(Cache.load(), "Cache.load() should return the just-saved cache")
        XCTAssertEqual(loaded.locations.count, 2)

        // If the index wasn't rebuilt after decode, this add() would append a 3rd entry
        // instead of upserting onto the existing "r1".
        loaded.add(try makeItem(recordName: "r1", locdescription: "v2"))

        XCTAssertEqual(loaded.locations.count, 2, "Index must be rebuilt after load() so add() still upserts")
        let r1 = try XCTUnwrap(loaded.locations.first { $0.recordName == "r1" })
        XCTAssertEqual(r1.locdescription, "v2")
    }

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

    // MARK: - uploadChanges item→record conversion (Day 4)

    // Day 4 moved the item.to() conversion out of saveChanges() and into
    // uploadChanges()'s paging loop (slice.map { $0.to() }). These lock down
    // the conversion the loop now depends on; Days 5-7 build the fetch-merge
    // on top of it.

    func test_to_buildsLocationRecordWithMatchingRecordID() throws {
        let record = try makeItem(recordName: "r1").to()

        XCTAssertEqual(record.recordType, "Location")
        XCTAssertEqual(record.recordID.recordName, "r1",
                       "uploadChanges builds the CKRecord from the cache item; the recordID must round-trip the item's recordName so the save targets the correct server record")
    }

    func test_to_copiesScalarFieldsOntoRecord() throws {
        let record = try makeItem(recordName: "r1", locdescription: "north gate").to()

        XCTAssertEqual(record["locdescription"] as? String, "north gate")
        XCTAssertEqual(record["QRCode"] as? String, "Q")
        XCTAssertEqual(record["latitude"] as? String, "0")
        XCTAssertEqual(record["longitude"] as? String, "0")
        XCTAssertEqual(record["active"] as? Int64, 0)
    }

    func test_to_mapsHasPhotoBoolToRecordInt() throws {
        let withPhoto = try makeItem(recordName: "r1", hasPhoto: true).to()
        let withoutPhoto = try makeItem(recordName: "r2", hasPhoto: false).to()

        XCTAssertEqual(withPhoto["hasPhoto"] as? Int, 1, "hasPhoto == true must serialize to 1")
        XCTAssertEqual(withoutPhoto["hasPhoto"] as? Int, 0, "hasPhoto == false must serialize to 0")
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

    // MARK: - apply-onto-fetched merge (Day 7)

    // Day 7 flips uploadChanges' savePolicy from .allKeys to .ifServerRecordUnchanged
    // and, for records that exist on the server, applies local fields onto the
    // *fetched* CKRecord rather than building a fresh one via item.to(). This
    // preserves the server's recordChangeTag so CloudKit can reject the save when
    // another device modified the record between our fetch and save. These tests
    // lock the merge semantics that the new save path depends on.

    func test_update_overwritesServerFieldsWithItemFields() throws {
        // A server record with the "before" state of every field update() writes.
        let server = makeLocationRecord()
        let item = try makeItem(recordName: "r1", locdescription: "north gate")
        item.dosinumber = "D-NEW"
        item.collectedFlag = 1
        item.cycleDate = "1-1-2026"
        item.moderator = 1
        item.active = 0
        item.mismatch = 1
        item.modifiedBy = "spady"
        item.reportGroup = "group-7"

        item.update(newRecord: server)

        XCTAssertEqual(server["locdescription"] as? String, "north gate")
        XCTAssertEqual(server["QRCode"] as? String, "Q")
        XCTAssertEqual(server["latitude"] as? String, "0")
        XCTAssertEqual(server["longitude"] as? String, "0")
        XCTAssertEqual(server["active"] as? Int64, 0)
        XCTAssertEqual(server["dosinumber"] as? String, "D-NEW")
        XCTAssertEqual(server["collectedFlag"] as? Int64, 1)
        XCTAssertEqual(server["cycleDate"] as? String, "1-1-2026")
        XCTAssertEqual(server["moderator"] as? Int64, 1)
        XCTAssertEqual(server["mismatch"] as? Int64, 1)
        XCTAssertEqual(server["modifiedBy"] as? String, "spady")
        XCTAssertEqual(server["reportGroup"] as? String, "group-7")
        XCTAssertEqual(server["hasPhoto"] as? Int, 0)
    }

    func test_update_preservesFetchedRecordID() throws {
        // uploadChanges relies on update(newRecord:) mutating the *same* CKRecord
        // object it was handed — that's what carries the fetched recordChangeTag
        // through to the .ifServerRecordUnchanged save. If update() ever started
        // returning a new record (or replacing recordID), the conflict check
        // would silently fall back to a tag-less save.
        let server = CKRecord(recordType: "Location",
                              recordID: CKRecord.ID(recordName: "server-id-1"))
        server.setValue("Q-OLD", forKey: "QRCode")
        server.setValue("0", forKey: "latitude")
        server.setValue("0", forKey: "longitude")
        server.setValue("old", forKey: "locdescription")
        server.setValue(Int64(0), forKey: "active")

        let item = try makeItem(recordName: "client-cache-id", locdescription: "new")

        item.update(newRecord: server)

        XCTAssertEqual(server.recordID.recordName, "server-id-1",
                       "update(newRecord:) must mutate the fetched record in place; it must not replace recordID with the item's recordName, or .ifServerRecordUnchanged loses the fetched tag")
        XCTAssertEqual(server["locdescription"] as? String, "new",
                       "Field values still flow from item onto the fetched record")
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

    // MARK: - Cache.location(forRecordName:) lookup (Day 8)

    // The guardrail needs the current cache entry for a recordName without an O(n)
    // scan; location(forRecordName:) reuses the same transient index add() maintains.

    func test_cacheLocation_returnsAddedItem() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: "r1", locdescription: "north gate"))

        XCTAssertEqual(cache.location(forRecordName: "r1")?.locdescription, "north gate")
        XCTAssertNil(cache.location(forRecordName: "missing"),
                     "Unknown recordName must return nil, not a neighbouring record")
    }

    func test_cacheLocation_reflectsUpsert() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: "r1", locdescription: "old"))
        cache.add(try makeItem(recordName: "r1", locdescription: "new"))

        XCTAssertEqual(cache.location(forRecordName: "r1")?.locdescription, "new",
                       "add() upserts in place; the lookup must see the latest value at the indexed slot")
    }

    // MARK: - createdDateForSort (nil-safe ordering key)

    func test_createdDateForSort_returnsCreatedDateWhenPresent() throws {
        // 0 seconds since the reference date == 2001-01-01 00:00:00 UTC.
        let item = try makeItem(recordName: "r1", createdDate: 0)
        XCTAssertEqual(item.createdDate, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(item.createdDateForSort, Date(timeIntervalSinceReferenceDate: 0),
                       "When createdDate is set, the sort key must equal it exactly")
    }

    func test_createdDateForSort_fallsBackToDistantPastWhenNil() throws {
        let item = try makeItem(recordName: "r1")
        XCTAssertNil(item.createdDate, "Fixture without createdDate must decode to nil")
        XCTAssertEqual(item.createdDateForSort, .distantPast,
                       "A nil createdDate must sort as the oldest possible date, not crash")
    }

    func test_createdDateForSort_sortsNilLastInNewestFirstOrder() throws {
        let newer = try makeItem(recordName: "r1", createdDate: 1000)
        let older = try makeItem(recordName: "r2", createdDate: 0)
        let undated = try makeItem(recordName: "r3")

        // Mirrors the UI sort comparators: descending by createdDateForSort.
        let sorted = [undated, older, newer].sorted { $0.createdDateForSort > $1.createdDateForSort }

        XCTAssertEqual(sorted.map { $0.recordName }, ["r1", "r2", "r3"],
                       "Newest first, with the nil-createdDate record sorted last")
    }

    // MARK: - buildDateString (auto-derived Tools build date)

    func test_buildDateString_formatsAsMonthCommaYear() {
        // 2023-05-15 12:00 UTC — mid-month, so no timezone boundary ambiguity.
        var components = DateComponents()
        components.year = 2023
        components.month = 5
        components.day = 15
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: components)!

        // Matches the "May, 2023" label this replaces (en_US test environment).
        XCTAssertEqual(ToolsViewController.buildDateString(from: date), "May, 2023")
    }

    // MARK: - Settings fallback coordinates (offline scan, no GPS fix)

    // Field devices have a cached Settings JSON written before the coordinate
    // fields existed; it must stay decodable (the fields are optional) and the
    // accessor must fall back to the built-in coordinate.
    func test_settingsDecode_withoutCoordinateFields_succeedsAndUsesFallback() throws {
        let oldFormat = #"{"dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(oldFormat.utf8))

        XCTAssertNil(settings.defaultLatitude)
        XCTAssertNil(settings.defaultLongitude)
        XCTAssertEqual(settings.defaultCoordinates.coordinate.latitude, 37.41927542738301, accuracy: 0.000001)
        XCTAssertEqual(settings.defaultCoordinates.coordinate.longitude, -122.20517033784913, accuracy: 0.000001)
    }

    func test_settingsDecode_withCoordinateFields_usesConfiguredValues() throws {
        let configured = #"{"dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11, "defaultLatitude": 37.5, "defaultLongitude": -122.5}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(configured.utf8))

        XCTAssertEqual(settings.defaultCoordinates.coordinate.latitude, 37.5, accuracy: 0.000001)
        XCTAssertEqual(settings.defaultCoordinates.coordinate.longitude, -122.5, accuracy: 0.000001)
    }

    func test_defaultCoordinates_fallsBackPerAxisWhenPartiallyConfigured() {
        // Only one field set in CloudKit (a half-finished edit of the Settings
        // record) must not zero the other axis.
        let settings = Settings()
        settings.defaultLatitude = 37.5

        XCTAssertEqual(settings.defaultCoordinates.coordinate.latitude, 37.5, accuracy: 0.000001)
        XCTAssertEqual(settings.defaultCoordinates.coordinate.longitude, -122.20517033784913, accuracy: 0.000001)
    }

    func test_settings_roundTripPreservesCoordinateFields() throws {
        let settings = Settings()
        settings.defaultLatitude = 37.5
        settings.defaultLongitude = -122.5

        let data = try JSONEncoder().encode(settings)
        let reloaded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(reloaded.defaultLatitude, 37.5)
        XCTAssertEqual(reloaded.defaultLongitude, -122.5)
    }

    // MARK: - Settings super-user passcode (delete-old-cycles gate)

    // Same decode-compatibility invariant as the coordinate fields: cached
    // Settings JSON written before the passcode field existed must still
    // decode, with the accessor falling back to the initial passcode.
    func test_settingsDecode_withoutPasscodeField_succeedsAndUsesFallback() throws {
        let oldFormat = #"{"dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(oldFormat.utf8))

        XCTAssertNil(settings.superUserPasscode)
        XCTAssertEqual(settings.superUserPasscodeValue, 4299)
    }

    func test_settingsDecode_withPasscodeField_usesConfiguredValue() throws {
        // A rotated passcode set on the CloudKit Settings record must win over
        // the built-in initial value.
        let configured = #"{"dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11, "superUserPasscode": 8121}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(configured.utf8))

        XCTAssertEqual(settings.superUserPasscodeValue, 8121)
    }

    func test_settings_roundTripPreservesPasscode() throws {
        let settings = Settings()
        settings.superUserPasscode = 8121

        let data = try JSONEncoder().encode(settings)
        let reloaded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(reloaded.superUserPasscode, 8121)
    }

    // MARK: - Cache.remove (super-user delete)

    // remove(recordNames:) must prune BOTH the locations array and the
    // pending-changes queue (else a queued upload resurrects a deleted
    // record on the next sync) and rebuild the transient index.

    func test_remove_removesNamedLocationsAndReportsCount() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: "r1"))
        cache.add(try makeItem(recordName: "r2"))
        cache.add(try makeItem(recordName: "r3"))

        let removed = cache.remove(recordNames: ["r1", "r3"])

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(cache.locations.map { $0.recordName }, ["r2"])
    }

    func test_remove_prunesPendingChangesForDeletedRecords() throws {
        let cache = Cache()
        let item = try makeItem(recordName: "r1")
        cache.add(item)
        cache.addChange(item)
        cache.addChange(try makeItem(recordName: "r2"))

        cache.remove(recordNames: ["r1"])

        XCTAssertEqual(cache.changes.map { $0.recordName }, ["r2"],
                       "A deleted record's queued edit must be pruned, or the next sync re-uploads (resurrects) it")
    }

    func test_remove_rebuildsIndexSoLookupMissesAndReAddAppendsFresh() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: "r1", locdescription: "before"))
        cache.add(try makeItem(recordName: "r2"))

        cache.remove(recordNames: ["r1"])

        XCTAssertNil(cache.location(forRecordName: "r1"),
                     "Lookup must miss after removal, not return a neighbouring record via a stale index slot")
        XCTAssertEqual(cache.location(forRecordName: "r2")?.recordName, "r2",
                       "Surviving records must stay reachable through the rebuilt index")

        cache.add(try makeItem(recordName: "r1", locdescription: "after"))
        XCTAssertEqual(cache.locations.count, 2)
        XCTAssertEqual(cache.location(forRecordName: "r1")?.locdescription, "after")
    }

    func test_remove_leavesNilRecordNameItemsAndUnknownNamesAlone() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: nil))
        cache.add(try makeItem(recordName: "r1"))

        let removed = cache.remove(recordNames: ["r1", "never-existed"])

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(cache.locations.count, 1, "The nil-recordName item must survive; it can't match any name")
    }

    // MARK: - isEligibleForCycleDeletion (safety invariant)

    // Records from the most recent 4 cycles can never be deleted, even if
    // explicitly requested. deleteOldCycleRecords recomputes eligibility
    // itself rather than trusting the caller's list.

    func test_eligible_falseWhenCycleDateNil() throws {
        let item = try makeItem(recordName: "r1")

        XCTAssertFalse(LocationsCK.isEligibleForCycleDeletion(item: item, protectedCycles: ["1-1-2026"]),
                       "A record without a cycleDate can't be proven old; the conservative answer is keep")
    }

    func test_eligible_falseForEveryProtectedCycle() throws {
        let protectedCycles = RecordsUpdate.getLastCycles(cycles: 4)

        for cycle in protectedCycles {
            let item = try makeItem(recordName: "r1", cycleDate: cycle)
            XCTAssertFalse(LocationsCK.isEligibleForCycleDeletion(item: item, protectedCycles: protectedCycles),
                           "Cycle \(cycle) is within the most recent 4 and must never be deletable")
        }
    }

    func test_eligible_trueForCycleOlderThanProtectedWindow() throws {
        let protectedCycles = RecordsUpdate.getLastCycles(cycles: 4)
        let fifthCycleBack = RecordsUpdate.generatePriorCycleDate(cycleDate: protectedCycles.last!)
        let item = try makeItem(recordName: "r1", cycleDate: fifthCycleBack)

        XCTAssertTrue(LocationsCK.isEligibleForCycleDeletion(item: item, protectedCycles: protectedCycles),
                      "The 5th cycle back is outside the protected window and must be eligible")
    }

    // MARK: - getLastCycles (the protected-window source)

    func test_getLastCycles_returnsContiguousCyclesNewestFirst() {
        let cycles = RecordsUpdate.getLastCycles(cycles: 4)

        XCTAssertEqual(cycles.count, 4)
        XCTAssertEqual(cycles[0], RecordsUpdate.generateCycleDate(),
                       "The newest entry must be the current cycle")
        for cycle in cycles {
            XCTAssertTrue(cycle.hasPrefix("1-1-") || cycle.hasPrefix("7-1-"),
                          "Cycle keys use the exact \"M-1-YYYY\" format with M of 1 or 7; got \(cycle)")
        }
        for index in 1..<cycles.count {
            XCTAssertEqual(cycles[index], RecordsUpdate.generatePriorCycleDate(cycleDate: cycles[index - 1]),
                           "Each entry must be exactly one 6-month cycle older than the previous")
        }
    }

    // MARK: - CycleCSVExport (the forced all-cycles export before deletion)

    func test_csvHeader_matchesTheToolsExportColumns() {
        XCTAssertEqual(CycleCSVExport.header,
                       "LocationID (QRCode),Latitude,Longitude,Description,Moderator (0/1),Active (0/1),Dosimeter,Collected Flag (0/1),Wear Period,System_Date Deployed,System_Date Collected,RGD (0/1), my_Date Deployed, my_Date Collected, recordID, ModifiedBy, Report Group\n",
                       "Header must stay column-compatible with the Tools email export")
    }

    // Pins the Mismatch -> RGD relabel. Display-only: the exported column header
    // reads "RGD", but the backend CKRecord key stays "mismatch" (see the to()
    // round-trip test, which asserts server["mismatch"]).
    func test_csvHeader_usesRGDLabel() {
        XCTAssertTrue(CycleCSVExport.header.contains("RGD (0/1)"),
                      "Exported header should expose the column as \"RGD (0/1)\"")
    }

    func test_csvHeader_dropsOldMismatchLabel() {
        XCTAssertFalse(CycleCSVExport.header.contains("Mismatch"),
                       "The old \"Mismatch\" label must not appear in the exported header")
    }

    func test_row_rendersEveryFieldInColumnOrder() throws {
        let deployed = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 5))
        let modified = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 10))
        let json = """
        { "QRCode": "BLG 006-015", "latitude": "37.4", "longitude": "-122.2", \
        "locdescription": "Test Bldg", "active": 1, "dosinumber": "D123", \
        "collectedFlag": 1, "cycleDate": "1-1-2026", "mismatch": 0, "moderator": 1, \
        "creationDate": \(deployed.timeIntervalSinceReferenceDate), \
        "createdDate": \(deployed.timeIntervalSinceReferenceDate), \
        "modifiedDate": \(modified.timeIntervalSinceReferenceDate), \
        "modificationDate": \(modified.timeIntervalSinceReferenceDate), \
        "recordName": "rec-1", "modifiedBy": "tester", "reportGroup": "G1", \
        "hasPhoto": false }
        """
        let item = try JSONDecoder().decode(LocationRecordCacheItem.self, from: Data(json.utf8))

        XCTAssertEqual(CycleCSVExport.row(for: item),
                       "BLG 006-015,37.4,-122.2,\"Test Bldg\",1,1,D123,1,1-1-2026,06/05/2026,06/10/2026,0,06/05/2026,06/10/2026,rec-1,tester,\"G1\"\n",
                       "Description and Report Group cells are quoted so free text can't shift columns")
    }

    func test_row_rendersNilOptionalFieldsAsBlankCells() throws {
        // makeItem populates only the required fields; every optional is nil.
        // The Tools row builder force-unwrapped dates — this one must not.
        let item = try makeItem(recordName: nil)

        // Description is quoted ("test"); the nil Report Group is quoted-empty
        // ("\"\""); every other optional renders as a bare empty cell.
        let fields = ["Q", "0", "0", "\"test\"", "", "0",
                      "", "", "", "", "", "", "", "", "", "", "\"\""]
        XCTAssertEqual(CycleCSVExport.row(for: item),
                       fields.joined(separator: ",") + "\n",
                       "Nil optionals must render as empty cells, never crash or shift columns")
    }

    func test_csvText_sortsByQRCodeThenNewestDeployFirst() throws {
        let later = try makeItem(recordName: "rB", QRCode: "BLG 044")
        let olderDeploy = try makeItem(recordName: "rA-old", QRCode: "BLG 003", createdDate: 700_000_000)
        let newerDeploy = try makeItem(recordName: "rA-new", QRCode: "BLG 003", createdDate: 800_000_000)

        let text = CycleCSVExport.csvText(for: [later, olderDeploy, newerDeploy])
        let lines = text.components(separatedBy: "\n")

        XCTAssertTrue(lines[1].contains("rA-new"), "QRCode ascending, newest deploy first within a QRCode")
        XCTAssertTrue(lines[2].contains("rA-old"))
        XCTAssertTrue(lines[3].contains("rB"))
    }

    func test_csvText_includesDeletableRecordsTheToolsExportWouldDrop() throws {
        // A record with an old cycle but a nil createdDate is delete-eligible,
        // yet the Tools export filters on createdDate != nil and would omit it.
        // The pre-delete audit export must be a superset of anything deletable.
        let protectedCycles = RecordsUpdate.getLastCycles(cycles: 4)
        let fifthCycleBack = RecordsUpdate.generatePriorCycleDate(cycleDate: protectedCycles.last!)
        let item = try makeItem(recordName: "ghost-record", cycleDate: fifthCycleBack)

        XCTAssertTrue(LocationsCK.isEligibleForCycleDeletion(item: item, protectedCycles: protectedCycles),
                      "Precondition: this record must be deletable for the test to mean anything")
        XCTAssertTrue(CycleCSVExport.csvText(for: [item]).contains("ghost-record"),
                      "Every deletable record must appear in the audit export")
    }

    func test_csvText_beginsWithHeaderAndEndsWithEndOfFileMarker() throws {
        let text = CycleCSVExport.csvText(for: [try makeItem(recordName: "r1")])

        XCTAssertTrue(text.hasPrefix(CycleCSVExport.header))
        XCTAssertTrue(text.hasSuffix("End of File\n"))
        XCTAssertEqual(text.components(separatedBy: "\n").count, 4,
                       "Header + one row + End of File + the trailing newline's empty component")
    }

    // MARK: - Tools "email data" export nil-date crash

    // recordFetchedBlock builds each CSV line for the Tools "email data" export. It
    // used to force-unwrap the CKRecord system dates, which are nil for unsynced or
    // orphan records — one such record crashed the whole export. These pin nil-safety.

    func test_recordFetchedBlock_withNilSystemDates_doesNotCrashAndBlanksDateCells() throws {
        let tools = ToolsViewController()
        let record = try makeItem(recordName: "ghost-record")
        XCTAssertNil(record.creationDate, "Precondition: the record must lack a system creation date")
        XCTAssertNil(record.modificationDate, "Precondition: the record must lack a system modification date")

        tools.recordFetchedBlock(record: record) // must not crash on the missing dates

        // The row is produced (no crash), and the two system-date columns it used
        // to force-unwrap (9 = deployed, 10 = collected) render as blank cells.
        let cells = tools.csvText.components(separatedBy: ",")
        XCTAssertEqual(cells.count, 17, "The export row must keep all 17 columns even with missing dates")
        XCTAssertEqual(cells[0], "Q")
        XCTAssertEqual(cells[9], "", "A nil system deploy date must be a blank cell, not a crash")
        XCTAssertEqual(cells[10], "", "A nil system collected date must be a blank cell, not a crash")
        XCTAssertEqual(cells[14], "ghost-record", "The record ID column must still render")
    }

    func test_recordFetchedBlock_withSystemDates_rendersFormattedDates() throws {
        let deployed = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 5))
        let collected = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 10))
        let json = """
        { "QRCode": "BLG 006-015", "latitude": "37.4", "longitude": "-122.2", \
        "locdescription": "north gate", "active": 1, \
        "creationDate": \(deployed.timeIntervalSinceReferenceDate), \
        "modificationDate": \(collected.timeIntervalSinceReferenceDate), \
        "recordName": "rec-1", "hasPhoto": false }
        """
        let record = try JSONDecoder().decode(LocationRecordCacheItem.self, from: Data(json.utf8))

        let tools = ToolsViewController()
        tools.recordFetchedBlock(record: record)

        // Columns 9 and 10 are the system deploy/collected dates (MM/dd/yyyy).
        let cells = tools.csvText.components(separatedBy: ",")
        XCTAssertEqual(cells[9], "06/05/2026", "System deploy date must still render when present")
        XCTAssertEqual(cells[10], "06/10/2026", "System collected date must still render when present")
    }

    /// Noon local time avoids DST-edge surprises when the exporter formats
    /// the date back in the current calendar.
    private func noonLocal(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    // MARK: - Fixtures

    /// A Location CKRecord with every field `init?(withRecord:)` needs, minus the
    /// photo CKAsset — i.e. what a record looks like after bulk-sync desiredKeys
    /// filtering. Pass `restrictedTo` to populate only a subset of fields.
    private func makeLocationRecord(restrictedTo allowed: [String]? = nil) -> CKRecord {
        let record = CKRecord(recordType: "Location")
        func set(_ key: String, _ value: Any) {
            guard allowed == nil || allowed!.contains(key) else { return }
            record.setValue(value, forKey: key)
        }
        set("QRCode", "Q-1")
        set("latitude", "37.0")
        set("longitude", "-122.0")
        set("locdescription", "a location")
        set("active", Int64(1))
        set("dosinumber", "D-1")
        set("collectedFlag", Int64(0))
        set("cycleDate", "2026-01")
        set("mismatch", Int64(0))
        set("moderator", Int64(0))
        set("createdDate", Date())
        set("modifiedDate", Date())
        set("modifiedBy", "tester")
        set("reportGroup", "group-1")
        set("hasPhoto", Int64(0))
        return record
    }

    // copy() must produce a DISTINCT instance with the same field values, and
    // mutating the copy must not touch the original. This is the invariant the
    // edit popup relies on so LocationsCK.save's already-collected guard sees the
    // record's true prior state instead of an in-place-mutated alias (QA-1 DEFECT-1):
    // before the fix the popup edited the cached record in place, flipping
    // collectedFlag to 1 before the guard ran, so a genuine collect was skipped.
    func test_copy_isDistinctInstanceAndDoesNotAliasOriginal() throws {
        let original = try makeItem(recordName: "R1", cycleDate: "1-1-2026")
        original.collectedFlag = 0
        original.dosinumber = "QA000000001"

        let copy = original.copy()

        XCTAssertFalse(copy === original, "copy must be a distinct instance")
        XCTAssertEqual(copy.recordName, "R1")
        XCTAssertEqual(copy.cycleDate, "1-1-2026")
        XCTAssertEqual(copy.collectedFlag, 0)
        XCTAssertEqual(copy.dosinumber, "QA000000001")

        // Mutating the copy (as the popup does on a collect) must not leak back.
        copy.collectedFlag = 1
        XCTAssertEqual(original.collectedFlag, 0, "copy must not alias the original")
    }

    private func makeItem(recordName: String?, QRCode: String = "Q", locdescription: String = "test", hasPhoto: Bool = false, cycleDate: String? = nil, createdDate: Double? = nil) throws -> LocationRecordCacheItem {
        var fields: [String] = [
            "\"QRCode\": \"\(QRCode)\"",
            "\"latitude\": \"0\"",
            "\"longitude\": \"0\"",
            "\"locdescription\": \"\(locdescription)\"",
            "\"active\": 0",
            "\"hasPhoto\": \(hasPhoto)"
        ]
        if let recordName = recordName {
            fields.append("\"recordName\": \"\(recordName)\"")
        }
        if let cycleDate = cycleDate {
            fields.append("\"cycleDate\": \"\(cycleDate)\"")
        }
        // JSONDecoder's default .deferredToDate strategy decodes Date from a
        // Double (seconds since the reference date), so callers pass an interval.
        if let createdDate = createdDate {
            fields.append("\"createdDate\": \(createdDate)")
        }
        let json = "{ \(fields.joined(separator: ", ")) }"
        return try JSONDecoder().decode(LocationRecordCacheItem.self, from: Data(json.utf8))
    }

    /// A minimal "server-side" CKRecord populated only with the fields
    /// shouldSkipSave reads. Pass nil to omit a field entirely (CKRecord
    /// returns nil for unset keys, which is the case we want to assert on).
    private func makeServerRecord(collectedFlag: Int64?, cycleDate: String?) -> CKRecord {
        let record = CKRecord(recordType: "Location")
        if let collectedFlag = collectedFlag {
            record.setValue(collectedFlag, forKey: "collectedFlag")
        }
        if let cycleDate = cycleDate {
            record.setValue(cycleDate, forKey: "cycleDate")
        }
        return record
    }

    private func removeCacheFileOnDisk() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("cache.txt"))
    }

    // MARK: - Delete Old Cycles super-user gate (slice 4)

    // The destructive step stays locked unless BOTH interlocks hold: the
    // all-cycles export was emailed this session AND there is something old to
    // delete. Either alone must keep the delete button inert.
    func test_canDelete_requiresBothExportAndEligibleRecords() {
        XCTAssertTrue(DeleteOldCyclesViewController.canDelete(hasEmailedExport: true, eligibleRecordCount: 5),
                      "Armed: export sent and old records exist")
        XCTAssertFalse(DeleteOldCyclesViewController.canDelete(hasEmailedExport: false, eligibleRecordCount: 5),
                       "Locked: export not yet emailed")
        XCTAssertFalse(DeleteOldCyclesViewController.canDelete(hasEmailedExport: true, eligibleRecordCount: 0),
                       "Locked: nothing old to delete")
        XCTAssertFalse(DeleteOldCyclesViewController.canDelete(hasEmailedExport: false, eligibleRecordCount: 0),
                       "Locked: neither interlock satisfied")
    }

    // A negative count can never arm the gate (defensive — eligibleTotal can't
    // go negative today, but the gate must not depend on that).
    func test_canDelete_falseForNonPositiveCount() {
        XCTAssertFalse(DeleteOldCyclesViewController.canDelete(hasEmailedExport: true, eligibleRecordCount: -1))
    }

    // The type-DELETE confirmation must match EXACTLY: uppercase, no leading or
    // trailing whitespace, no near-misses. This is the last guard before a
    // permanent CloudKit deletion, so the rule is pinned by a test.
    func test_deleteIsConfirmed_requiresExactUppercaseDELETE() {
        XCTAssertTrue(DeleteOldCyclesViewController.deleteIsConfirmed(byTyping: "DELETE"))

        for rejected in ["delete", "Delete", "DELETE ", " DELETE", " DELETE ", "DELET", "DELETED", "", nil] {
            XCTAssertFalse(DeleteOldCyclesViewController.deleteIsConfirmed(byTyping: rejected),
                           "\(String(describing: rejected)) must not confirm a deletion")
        }
    }

    // The forced export must address the SLAC records-management group; a typo
    // here would silently send the audit trail to the wrong place.
    func test_exportRecipient_isTheRecordsManagementGroup() {
        XCTAssertEqual(DeleteOldCyclesViewController.exportRecipient, "esh-DREP@slac.stanford.edu")
    }

    // MARK: - Super-user passcode gate (shared by Reset Cache + Delete Old Cycles + Edit Record)

    // passcodeAccepted is the pure decision the shared gate consults. It must
    // accept only the exact configured passcode and reject empty, non-numeric,
    // or wrong input — the same check guards Reset Cache and Edit Record saves.
    func test_passcodeAccepted_trueOnlyForExactConfiguredValue() {
        XCTAssertTrue(SuperUserGate.passcodeAccepted(entered: "4299", configured: 4299))
        XCTAssertFalse(SuperUserGate.passcodeAccepted(entered: "4298", configured: 4299),
                       "A wrong passcode must not open the gate")
    }

    func test_passcodeAccepted_rejectsEmptyAndNonNumericInput() {
        for rejected in [nil, "", " ", "abc", "42x", "4299 "] {
            XCTAssertFalse(SuperUserGate.passcodeAccepted(entered: rejected, configured: 4299),
                           "\(String(describing: rejected)) must not open the gate")
        }
    }

    func test_passcodeAccepted_honorsRotatedPasscode() {
        // The configured value comes from settings.superUserPasscodeValue, which
        // CloudKit can rotate; the gate must follow it, not a hardcoded default.
        XCTAssertTrue(SuperUserGate.passcodeAccepted(entered: "8121", configured: 8121))
        XCTAssertFalse(SuperUserGate.passcodeAccepted(entered: "4299", configured: 8121),
                       "The old default must stop working once the passcode is rotated")
    }

    // Once-per-session unlock: the flag must be app-wide (a static), so it
    // survives LocationDetails being re-instantiated per navigation.
    func test_editRecordSavesUnlocked_isAppWideSessionFlag() {
        let original = SuperUserGate.editRecordSavesUnlocked
        defer { SuperUserGate.editRecordSavesUnlocked = original }

        SuperUserGate.editRecordSavesUnlocked = false
        XCTAssertFalse(SuperUserGate.editRecordSavesUnlocked)
        SuperUserGate.editRecordSavesUnlocked = true
        XCTAssertTrue(SuperUserGate.editRecordSavesUnlocked,
                      "Once unlocked, Edit Record saves stay unlocked for the rest of the session")
    }

    // MARK: - Refresh Count button wiring

    // Wired in the storyboard + viewDidLoad with no pure logic, so these load the
    // startup scene to check the button's outlet, title, and action and that the old
    // hidden tap is gone. Loading runs viewDidLoad; we stop the notifier right after.

    private func loadStartupViewController() throws -> StartupViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: StartupViewController.self))
        let controller = storyboard.instantiateViewController(withIdentifier: "Main")
        let startup = try XCTUnwrap(controller as? StartupViewController,
                                    "Main storyboard identifier \"Main\" should resolve to StartupViewController")
        startup.loadViewIfNeeded()
        startup.reachability.stopNotifier()
        return startup
    }

    func test_refreshCountButton_isConnectedAndCallsSetProgress() throws {
        let startup = try loadStartupViewController()

        let button = try XCTUnwrap(startup.refreshButton,
                                   "refreshButton outlet must be connected in Main.storyboard")
        XCTAssertEqual(button.title(for: .normal), "Refresh Count")

        let actions = button.actions(forTarget: startup, forControlEvent: .touchUpInside) ?? []
        XCTAssertTrue(actions.contains("setProgress"),
                      "Refresh Count button must trigger setProgress on touchUpInside")
    }

    func test_statusLabel_noLongerHasHiddenTapToRefresh() throws {
        let startup = try loadStartupViewController()

        XCTAssertTrue((startup.statusLabel.gestureRecognizers ?? []).isEmpty,
                      "the hidden tap-to-refresh gesture should be removed from the status label")
    }

    // MARK: - PopupAlertController (custom cross-iOS alert)

    // Collects every UIButton in a view tree so a built popup can be inspected
    // without reaching into its private subviews.
    private func buttons(in view: UIView) -> [UIButton] {
        view.subviews.reduce(into: []) { result, subview in
            if let button = subview as? UIButton { result.append(button) }
            result.append(contentsOf: buttons(in: subview))
        }
    }

    func test_popupAction_storesItsFieldsAndDefaultsToNormalStyle() {
        var fired = false
        let action = PopupAction(title: "OK") { fired = true }

        XCTAssertEqual(action.title, "OK")
        XCTAssertEqual(action.style, .normal, "Style should default to .normal when omitted")

        action.handler?()
        XCTAssertTrue(fired, "Invoking the stored handler should run the closure")
    }

    func test_popup_buildsOneButtonPerActionInOrder() {
        let popup = PopupAlertController(title: "Title", message: "Message")
        popup.addAction(PopupAction(title: "Cancel", style: .cancel))
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        let titles = buttons(in: popup.view).map { $0.title(for: .normal) }
        XCTAssertEqual(titles, ["Cancel", "OK"],
                       "Each PopupAction should render one button, in the order added")
    }

    // The simple scanner alerts (alert1/alert2 etc.) are now PopupAlertControllers
    // with a title, no message, and two buttons. A nil message must not drop the
    // title or the buttons — guards the native-alert conversion.
    func test_popup_titleOnlyWithTwoActionsBuildsBothButtonsAndTitle() {
        let popup = PopupAlertController(title: "Dosimeter Not Found:\n21111111116", message: nil)
        popup.addAction(PopupAction(title: "Deploy"))
        popup.addAction(PopupAction(title: "Cancel", style: .cancel))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let titles = buttons(in: popup.view).map { $0.title(for: .normal) }
        XCTAssertEqual(titles, ["Deploy", "Cancel"],
                       "A title-only popup should still build both buttons in order")
        let hasTitle = labels(in: popup.view).contains { ($0.text ?? "").hasPrefix("Dosimeter Not Found") }
        XCTAssertTrue(hasTitle, "The title must render even when the message is nil")
    }

    func test_popup_buildsWithASingleActionAndImage() {
        let popup = PopupAlertController(title: "Scan Accepted", message: "Please scan.")
        popup.setImage(UIImage())
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(buttons(in: popup.view).count, 1,
                       "A single-action popup with an image should still build exactly one button")
    }

    // Finds the popup's rounded card — the view setBackgroundColor tints — by its
    // distinctive corner radius, so the test never touches a private property.
    private func cardView(in view: UIView) -> UIView? {
        if view.layer.cornerRadius == 13.5 { return view }
        for subview in view.subviews {
            if let found = cardView(in: subview) { return found }
        }
        return nil
    }

    func test_popup_defaultsToSystemBackgroundWhenNoColorSet() {
        let popup = PopupAlertController(title: "Title", message: "Message")
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(cardView(in: popup.view)?.backgroundColor, .systemBackground,
                       "The card should use the system background when no color is set")
    }

    func test_popup_setBackgroundColorTintsTheCard() {
        let popup = PopupAlertController(title: "Warning", message: "Message")
        popup.setBackgroundColor(.yellow)
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(cardView(in: popup.view)?.backgroundColor, .yellow,
                       "setBackgroundColor should tint the card, replacing the old private-subview hack")
    }

    func test_popup_setBackgroundColorIgnoresNil() {
        let popup = PopupAlertController(title: "Warning", message: "Message")
        popup.setBackgroundColor(nil)
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(cardView(in: popup.view)?.backgroundColor, .systemBackground,
                       "Passing nil should leave the default system background intact")
    }

    // Collects every UILabel in a view tree so a laid-out popup can be inspected.
    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.reduce(into: []) { result, subview in
            if let label = subview as? UILabel { result.append(label) }
            result.append(contentsOf: labels(in: subview))
        }
    }

    // Regression for the zero-height scroll view: the title/message sit in a
    // UIScrollView that collapsed to 0pt and clipped them. After a real layout
    // pass the title and message must have non-zero height.
    func test_popup_titleAndMessageLayOutWithNonZeroHeight() {
        let popup = PopupAlertController(title: "Scan Accepted",
                                         message: "Please scan the corresponding location code.")
        popup.addAction(PopupAction(title: "OK"))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let content = labels(in: popup.view).filter {
            $0.text == "Scan Accepted" || ($0.text?.hasPrefix("Please scan") ?? false)
        }
        XCTAssertEqual(content.count, 2, "Both the title and message labels should be present")
        for label in content {
            XCTAssertGreaterThan(label.bounds.height, 0,
                                 "\"\(label.text ?? "")\" must lay out with non-zero height; a collapsed scroll view clips it")
        }
    }

    // The popup pins to light so the card stays a known light background in any
    // device mode — both for cross-mode consistency and so transparent-background
    // images (e.g. the black-on-alpha QRCodeImage) don't vanish on a dark card.
    func test_popup_pinsToLightAppearance() {
        let popup = PopupAlertController(title: "Title", message: "Message")
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(popup.overrideUserInterfaceStyle, .light,
                       "PopupAlertController should force light appearance")
    }

    private func switches(in view: UIView) -> [UISwitch] {
        view.subviews.reduce(into: []) { result, subview in
            if let toggle = subview as? UISwitch { result.append(toggle) }
            result.append(contentsOf: switches(in: subview))
        }
    }

    // The switch row (RGD on Exchange/Collect) must reflect the initial state
    // and report flips, since that drives variables.mismatch in the scanner flow.
    func test_popup_switchRowReflectsInitialStateAndReportsChanges() {
        var reported: Bool?
        let popup = PopupAlertController(title: "Exchange", message: "Cycle")
        popup.addSwitch(title: "Mismatch", isOn: true) { reported = $0 }
        popup.addAction(PopupAction(title: "Exchange"))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let found = switches(in: popup.view)
        XCTAssertEqual(found.count, 1, "addSwitch should render exactly one UISwitch")
        XCTAssertEqual(found.first?.isOn, true, "The switch should reflect the initial isOn state")

        found.first?.isOn = false
        found.first?.sendActions(for: .valueChanged)
        XCTAssertEqual(reported, false, "Flipping the switch should fire onChange with the new value")
    }

    private func textFields(in view: UIView) -> [UITextField] {
        view.subviews.reduce(into: []) { result, subview in
            if let field = subview as? UITextField { result.append(field) }
            result.append(contentsOf: textFields(in: subview))
        }
    }

    // The text-field row (deploy location) must prefill from the initial value and
    // report edits, since the scanner relies on that to track variables.dosiLocation.
    func test_popup_textFieldReflectsInitialTextAndReportsEdits() {
        var reported: String?
        let popup = PopupAlertController(title: "Deploy", message: nil)
        popup.addTextField(text: "ryans office", placeholder: "Location") { reported = $0 }
        popup.addAction(PopupAction(title: "Save"))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let fields = textFields(in: popup.view)
        XCTAssertEqual(fields.count, 1, "addTextField should render exactly one UITextField")
        XCTAssertEqual(fields.first?.text, "ryans office", "The field should prefill with the initial text")

        fields.first?.text = "lab 12"
        fields.first?.sendActions(for: .editingChanged)
        XCTAssertEqual(reported, "lab 12", "Editing should report the new text via onChange")
    }

    // The Deploy popup (alert8) carries two independent switch rows — Moderator
    // (variables.moderator) and RGD (variables.mismatch) — each reporting only its
    // own flips; a cross-wire would corrupt the other field. Order matches alert8.
    func test_popup_twoSwitchesAreIndependent() {
        var moderatorReported: Bool?
        var rgdReported: Bool?
        let popup = PopupAlertController(title: "Deploy Dosimeter:", message: "\nLocation: BLG 044-004")
        popup.addTextField(text: "ryans office", placeholder: "Location") { _ in }
        popup.addSwitch(title: "Moderator", isOn: false) { moderatorReported = $0 }
        popup.addSwitch(title: "RGD", isOn: true) { rgdReported = $0 }
        popup.addAction(PopupAction(title: "Save"))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let found = switches(in: popup.view)
        XCTAssertEqual(found.count, 2, "Deploy should render exactly two UISwitches")
        XCTAssertEqual(found.first?.isOn, false, "Moderator should reflect its initial off state")
        XCTAssertEqual(found.last?.isOn, true, "RGD should reflect its initial on state")

        found.first?.isOn = true
        found.first?.sendActions(for: .valueChanged)
        XCTAssertEqual(moderatorReported, true, "Flipping Moderator should fire only its onChange")
        XCTAssertNil(rgdReported, "Flipping Moderator must not fire RGD's onChange")

        found.last?.isOn = false
        found.last?.sendActions(for: .valueChanged)
        XCTAssertEqual(rgdReported, false, "Flipping RGD should fire its onChange with the new value")
        XCTAssertEqual(moderatorReported, true, "RGD's flip must not disturb the Moderator value")
    }

    // MARK: - ManagedAppConfig (JAMF managed username)

    func test_username_readsConfiguredKey() {
        let config: [String: Any] = [ManagedAppConfig.usernameKey: "Jane Tech"]
        XCTAssertEqual(ManagedAppConfig.username(from: config), "Jane Tech")
    }

    func test_username_trimsWhitespace() {
        let config: [String: Any] = [ManagedAppConfig.usernameKey: "  Jane Tech \n"]
        XCTAssertEqual(ManagedAppConfig.username(from: config), "Jane Tech")
    }

    func test_username_blankWhenPayloadMissing() {
        XCTAssertEqual(ManagedAppConfig.username(from: nil), "")
    }

    func test_username_blankWhenKeyAbsent() {
        let config: [String: Any] = ["someOtherKey": "value"]
        XCTAssertEqual(ManagedAppConfig.username(from: config), "")
    }

    func test_username_blankWhenValueNotString() {
        let config: [String: Any] = [ManagedAppConfig.usernameKey: 42]
        XCTAssertEqual(ManagedAppConfig.username(from: config), "")
    }

    // MARK: - Nearest Locations pull-to-refresh (cloud sync)

    // The pull-to-refresh used to only re-filter the local cache, so a technician's
    // pull never picked up another worker's changes. This verifies the pull now runs
    // synchronize() (a real CloudKit pull) BEFORE re-filtering the cache.

    func test_pullToRefresh_syncsFromCloudBeforeReFiltering() {
        let mock = RefreshSpyLocations()
        let nearest = NearestLocations()
        nearest.locations = mock

        let refreshed = expectation(description: "re-filter ran after sync")
        mock.onFilter = { refreshed.fulfill() }

        nearest.refreshFromCloud()

        wait(for: [refreshed], timeout: 2.0)
        XCTAssertEqual(mock.synchronizeCallCount, 1, "pull must trigger a cloud sync")
        XCTAssertEqual(mock.filterCallCount, 1, "pull must re-filter after syncing")
        XCTAssertTrue(mock.syncedBeforeFilter, "sync must run before the re-filter")
    }
}

// Minimal Locations test double. Records the order of synchronize()/filter() so the
// pull-to-refresh test can assert the cloud sync happens before the local re-filter.
// Every other protocol member is an inert stub; the refresh path never calls them.
private final class RefreshSpyLocations: Locations {
    var synchronizeCallCount = 0
    var filterCallCount = 0
    var syncedBeforeFilter = false
    var onFilter: (() -> Void)?

    private var didSync = false

    func synchronize(loaded: @escaping ((Int) -> Void)) {
        synchronizeCallCount += 1
        didSync = true
        loaded(0)   // offline or online, synchronize always reports a count back
    }

    func filter(by: (LocationRecordCacheItem) -> Bool) -> [LocationRecordCacheItem] {
        filterCallCount += 1
        if didSync { syncedBeforeFilter = true }
        onFilter?()
        return []
    }

    func filter(by: @escaping (LocationRecordCacheItem) -> Bool, completionHandler: @escaping ([LocationRecordCacheItem]) -> Void) {
        completionHandler([])
    }
    func groups(completionHandler: @escaping ([String]) -> Void) { completionHandler([]) }
    func count(by: (LocationRecordCacheItem) -> Bool) -> Int { 0 }
    func save(item: LocationRecordCacheItem, completionHandler: (() -> Void)?) { completionHandler?() }
    func save(items: [LocationRecordCacheItem], completionHandler: (() -> Void)?) { completionHandler?() }
    func reset(_ loaded: @escaping ((Int) -> Void)) { loaded(0) }
    func fetch(id: String, completionHandler: @escaping (LocationRecordCacheItem?, Error?) -> Void) { completionHandler(nil, nil) }
    var pendingChangeCount: Int { 0 }
    func eligibleOldCycleRecords(keepingCycles: Int) -> [LocationRecordCacheItem] { [] }
    func deleteOldCycleRecords(keepingCycles: Int, progress: @escaping (Int, Int) -> Void, completion: @escaping (Int, Error?) -> Void) { completion(0, nil) }
}
