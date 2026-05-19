//
//  LocationAppTests.swift
//  LocationAppTests
//
//  Created by Ford, Ryan M. on 10/3/18.
//  Copyright © 2018 Ford, Ryan M. All rights reserved.
//

import XCTest
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

    // MARK: - Fixtures

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
