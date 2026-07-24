//
//  ReconcilePruneTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/23/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class ReconcilePruneTests: XCTestCase {

    // MARK: - Prune decision after a completed full reconcile

    // A completed full re-download returned every record the server has. A cached
    // record missing from that set was deleted server-side (dashboard cleanup)
    // and must be pruned — unless it still holds unconfirmed local work.

    func test_prune_serverDeletedRecord_selected() throws {
        let ghost = try makeItem(recordName: "GHOST", creationDate: 1_000, modificationDate: 1_000)

        let pruned = LocationsCK.namesToPruneAfterReconcile(locations: [ghost],
                                                            serverNames: ["OTHER"],
                                                            queuedNames: [])

        XCTAssertEqual(pruned, ["GHOST"],
                       "a server-stamped record the full download no longer returns is a ghost")
    }

    func test_prune_serverReturnedRecord_kept() throws {
        let alive = try makeItem(recordName: "R1", creationDate: 1_000, modificationDate: 1_000)

        let pruned = LocationsCK.namesToPruneAfterReconcile(locations: [alive],
                                                            serverNames: ["R1"],
                                                            queuedNames: [])

        XCTAssertTrue(pruned.isEmpty, "a record the server still returns is never pruned")
    }

    func test_prune_queuedEdit_kept() throws {
        // A record with a queued (not yet confirmed) upload must survive even if
        // the server doesn't return it — pruning it would discard a tech's work.
        let edited = try makeItem(recordName: "QUEUED", creationDate: 1_000, modificationDate: 1_000)

        let pruned = LocationsCK.namesToPruneAfterReconcile(locations: [edited],
                                                            serverNames: ["OTHER"],
                                                            queuedNames: ["QUEUED"])

        XCTAssertTrue(pruned.isEmpty, "a queued upload must never be pruned out from under the queue")
    }

    func test_prune_strandedRecord_kept() throws {
        // No server System dates = authored here, never confirmed uploaded. The
        // server not returning it is expected, not evidence of deletion.
        let stranded = try makeItem(recordName: "STRANDED", cycleDate: "7-1-2026")

        let pruned = LocationsCK.namesToPruneAfterReconcile(locations: [stranded],
                                                            serverNames: ["OTHER"],
                                                            queuedNames: [])

        XCTAssertTrue(pruned.isEmpty, "a stranded scan belongs to recovery, not the pruner")
    }

    func test_prune_legacyNilRecordName_kept() throws {
        let orphan = try makeItem(recordName: nil)

        let pruned = LocationsCK.namesToPruneAfterReconcile(locations: [orphan],
                                                            serverNames: ["OTHER"],
                                                            queuedNames: [])

        XCTAssertTrue(pruned.isEmpty, "an item without a recordName can't be matched against the server")
    }

    func test_prune_emptyServerResult_prunesNothing() throws {
        // Safety valve: a full download that "completes" with zero records is far
        // more likely a malfunction than a real database wipe — never prune on it.
        let synced = try makeItem(recordName: "R1", creationDate: 1_000, modificationDate: 1_000)

        let pruned = LocationsCK.namesToPruneAfterReconcile(locations: [synced],
                                                            serverNames: [],
                                                            queuedNames: [])

        XCTAssertTrue(pruned.isEmpty, "an empty server result must never empty the cache")
    }

    func test_prune_mixedCache_selectsExactlyTheGhosts() throws {
        let alive = try makeItem(recordName: "ALIVE", creationDate: 1_000, modificationDate: 1_000)
        let ghost1 = try makeItem(recordName: "GHOST-1", creationDate: 1_000, modificationDate: 1_000)
        let ghost2 = try makeItem(recordName: "GHOST-2", creationDate: 2_000, modificationDate: 2_000)
        let queued = try makeItem(recordName: "QUEUED", creationDate: 1_000, modificationDate: 1_000)
        let stranded = try makeItem(recordName: "STRANDED")
        let orphan = try makeItem(recordName: nil)

        let pruned = LocationsCK.namesToPruneAfterReconcile(locations: [alive, ghost1, ghost2, queued, stranded, orphan],
                                                            serverNames: ["ALIVE"],
                                                            queuedNames: ["QUEUED"])

        XCTAssertEqual(pruned, ["GHOST-1", "GHOST-2"],
                       "exactly the server-deleted records are selected, nothing protected")
    }

    // MARK: - Applying the prune to the cache

    func test_cacheRemove_clearsRecordAndLookup() throws {
        let cache = Cache()
        cache.add(try makeItem(recordName: "GHOST", creationDate: 1_000, modificationDate: 1_000))
        cache.add(try makeItem(recordName: "ALIVE", creationDate: 1_000, modificationDate: 1_000))

        let removed = cache.remove(recordNames: ["GHOST"])

        XCTAssertEqual(removed, 1)
        XCTAssertNil(cache.location(forRecordName: "GHOST"), "the ghost is gone from the lookup index")
        XCTAssertNotNil(cache.location(forRecordName: "ALIVE"),
                        "the index still resolves surviving records after the rebuild")
        XCTAssertEqual(cache.locations.map { $0.recordName }, ["ALIVE"])
    }

    // MARK: - Acceptance: the dashboard-delete case

    // A record deleted on the CloudKit dashboard lingers on every device that
    // already downloaded it, because incremental sync only adds and updates.
    // The daily full reconcile must drop it without touching pending scans.
    func test_acceptance_dashboardDelete_propagatesOnDailyReconcile() throws {
        let cache = Cache()
        for i in 1...4 {
            cache.add(try makeItem(recordName: "R\(i)", creationDate: 1_000, modificationDate: 1_000))
        }
        cache.add(try makeItem(recordName: "DELETED-ON-DASHBOARD", creationDate: 1_000, modificationDate: 1_000))
        let pendingCollect = try makeItem(recordName: "PENDING-COLLECT", cycleDate: "7-1-2026")
        pendingCollect.collectedFlag = 1
        cache.add(pendingCollect)

        // the completed full download returns everything the server still has
        let serverNames: Set<String> = ["R1", "R2", "R3", "R4"]
        let queuedNames = Set(cache.changes.compactMap { $0.recordName })
        let pruned = LocationsCK.namesToPruneAfterReconcile(locations: cache.locations,
                                                            serverNames: serverNames,
                                                            queuedNames: queuedNames)
        cache.remove(recordNames: pruned)

        XCTAssertEqual(pruned, ["DELETED-ON-DASHBOARD"], "the dashboard delete reaches the device")
        XCTAssertNotNil(cache.location(forRecordName: "PENDING-COLLECT"),
                        "the unuploaded scan survives the same reconcile")
        XCTAssertEqual(cache.locations.count, 5)
    }
}
