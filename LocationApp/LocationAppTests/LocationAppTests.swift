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

    // MARK: - buildDateString (SOW 2.4: auto-derived Tools build date)

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

    // MARK: - Settings fallback coordinates (SOW R3-a: offline scan, no GPS fix)

    // Devices in the field have a cached Settings JSON written before the
    // coordinate fields existed. They must stay decodable — the fields are
    // optional for exactly this reason — and the accessor must fall back to the
    // SOW R3 coordinate. If decode ever starts failing here, shipping it would
    // break every already-deployed cache.
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

    private func makeItem(recordName: String?, locdescription: String = "test", hasPhoto: Bool = false, cycleDate: String? = nil, createdDate: Double? = nil) throws -> LocationRecordCacheItem {
        var fields: [String] = [
            "\"QRCode\": \"Q\"",
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
}
