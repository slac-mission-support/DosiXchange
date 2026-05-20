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

    private func makeItem(recordName: String?, locdescription: String = "test") throws -> LocationRecordCacheItem {
        var fields: [String] = [
            "\"QRCode\": \"Q\"",
            "\"latitude\": \"0\"",
            "\"longitude\": \"0\"",
            "\"locdescription\": \"\(locdescription)\"",
            "\"active\": 0",
            "\"hasPhoto\": false"
        ]
        if let recordName = recordName {
            fields.append("\"recordName\": \"\(recordName)\"")
        }
        let json = "{ \(fields.joined(separator: ", ")) }"
        return try JSONDecoder().decode(LocationRecordCacheItem.self, from: Data(json.utf8))
    }

    private func removeCacheFileOnDisk() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("cache.txt"))
    }
}
