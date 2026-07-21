//
//  CacheTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class CacheTests: XCTestCase {

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
}
