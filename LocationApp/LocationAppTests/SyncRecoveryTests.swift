//
//  SyncRecoveryTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class SyncRecoveryTests: XCTestCase {

    // MARK: - Stranded-record recovery

    // A record with no server System dates was authored on this device and never
    // confirmed uploaded — the stranded marker. Each synchronize re-queues those
    // records so the normal upload path retries them.

    func test_recoveryCandidate_nilServerDates_selected() throws {
        let stranded = try makeItem(recordName: "R1", cycleDate: "1-1-2026")
        XCTAssertTrue(LocationsCK.isRecoveryCandidate(item: stranded),
                      "a never-server-stamped record must be selected for recovery")
    }

    func test_recoveryCandidate_serverDatesPresent_notSelected() throws {
        let synced = try makeItem(recordName: "R1", creationDate: 1_000, modificationDate: 1_000)
        XCTAssertFalse(LocationsCK.isRecoveryCandidate(item: synced),
                       "a server-stamped record has nothing to recover")
    }

    func test_recoveryCandidate_partialServerDates_notSelected() throws {
        // Either system date proves the server has seen the record.
        let creationOnly = try makeItem(recordName: "R1", creationDate: 1_000)
        let modificationOnly = try makeItem(recordName: "R2", modificationDate: 1_000)
        XCTAssertFalse(LocationsCK.isRecoveryCandidate(item: creationOnly))
        XCTAssertFalse(LocationsCK.isRecoveryCandidate(item: modificationOnly))
    }

    func test_recoveryCandidate_nilRecordName_notSelected() throws {
        let orphan = try makeItem(recordName: nil)
        XCTAssertFalse(LocationsCK.isRecoveryCandidate(item: orphan),
                       "an item without a recordName can never upload")
    }

    func test_recovery_requeue_dedupesAgainstExistingQueue() throws {
        let alreadyQueued = try makeItem(recordName: "R1")
        let stranded = try makeItem(recordName: "R2")
        let synced = try makeItem(recordName: "R3", creationDate: 1_000, modificationDate: 1_000)

        let candidates = LocationsCK.recoveryCandidates(locations: [alreadyQueued, stranded, synced],
                                                        queuedNames: ["R1"])

        XCTAssertEqual(candidates.map { $0.recordName }, ["R2"],
                       "only stranded records not already queued may be re-queued")
    }

    func test_recovery_requeuesTheCachedInstanceUnchanged() throws {
        // The cached instance itself goes back on the queue, so a recovered
        // upload keeps its original modifiedBy/modifiedDate instead of being
        // restamped with the current user and time.
        let stranded = try makeItem(recordName: "R1", modifiedDate: 4_000)

        let candidates = LocationsCK.recoveryCandidates(locations: [stranded], queuedNames: [])

        XCTAssertTrue(candidates.first === stranded, "recovery must queue the cached instance, not a copy")
        XCTAssertEqual(candidates.first?.modifiedDate, Date(timeIntervalSinceReferenceDate: 4_000),
                       "the recorded collection time must survive recovery untouched")
    }

    // MARK: - Recurring stale reconcile

    // Recovered uploads keep their original modifiedDate, which sits below other
    // devices' incremental watermarks — only a periodic full re-download makes
    // them visible fleet-wide (and heals pre-existing stale records).

    func test_staleReconcile_runsOnFirstSyncAfterUpdate() {
        XCTAssertTrue(LocationsCK.shouldRunFullReconcile(pendingChangeCount: 0,
                                                         lastReconcile: nil,
                                                         now: Date(timeIntervalSinceReferenceDate: 0)),
                      "no recorded reconcile (fresh install or pre-fix cache) must trigger one")
    }

    func test_staleReconcile_neverWhileChangesPending() {
        XCTAssertFalse(LocationsCK.shouldRunFullReconcile(pendingChangeCount: 1,
                                                          lastReconcile: nil,
                                                          now: Date(timeIntervalSinceReferenceDate: 0)),
                       "uploads drain first; a full download must not race queued work")
    }

    func test_staleReconcile_runsWhenOlderThan24Hours() {
        XCTAssertTrue(LocationsCK.shouldRunFullReconcile(pendingChangeCount: 0,
                                                         lastReconcile: Date(timeIntervalSinceReferenceDate: 0),
                                                         now: Date(timeIntervalSinceReferenceDate: 25 * 60 * 60)))
    }

    func test_staleReconcile_skipsWhenRecent() {
        XCTAssertFalse(LocationsCK.shouldRunFullReconcile(pendingChangeCount: 0,
                                                          lastReconcile: Date(timeIntervalSinceReferenceDate: 0),
                                                          now: Date(timeIntervalSinceReferenceDate: 60 * 60)))
    }

    func test_staleReconcile_timestampPersistsAcrossSaveLoad() throws {
        removeCacheFileOnDisk()
        addTeardownBlock { self.removeCacheFileOnDisk() }

        let cache = Cache()
        cache.lastFullReconcile = Date(timeIntervalSinceReferenceDate: 123_456)
        cache.save()

        let loaded = try XCTUnwrap(Cache.load(), "Cache.load() should return the just-saved cache")
        XCTAssertEqual(loaded.lastFullReconcile, Date(timeIntervalSinceReferenceDate: 123_456),
                       "the reconcile clock must survive an app relaunch")
    }

    func test_staleReconcile_missingTimestampDecodesAsNil() throws {
        // A cache.txt written by the previous build has no lastFullReconcile key;
        // it must still decode (as nil) so the first sync after the update reconciles.
        let json = """
        { "version": "1.0", "user": "", "locations": [], "changes": [],
          "settings": { "dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11 } }
        """
        let cache = try JSONDecoder().decode(Cache.self, from: Data(json.utf8))
        XCTAssertNil(cache.lastFullReconcile)
    }

    // MARK: - Changes queue survives a relaunch

    // A refused upload is only as safe as its persistence: the queued scan must
    // come back from disk with every field intact, or the retry uploads garbage.

    func test_changesQueue_persistsAcrossSaveLoad() throws {
        removeCacheFileOnDisk()
        addTeardownBlock { self.removeCacheFileOnDisk() }

        let cache = Cache()
        let refused = try makeItem(recordName: "R1", cycleDate: "7-1-2026", modifiedDate: 4_000)
        refused.collectedFlag = 1
        refused.dosinumber = "D-1"
        refused.modifiedBy = "tech1"
        cache.changes.append(refused)
        cache.addChange(try makeItem(recordName: "R2"))
        cache.save()

        let relaunched = try XCTUnwrap(Cache.load(), "Cache.load() should return the just-saved cache")
        XCTAssertEqual(relaunched.changes.map { $0.recordName }, ["R1", "R2"],
                       "refused uploads must survive an app relaunch, in queue order")
        let reloaded = try XCTUnwrap(relaunched.changes.first)
        XCTAssertEqual(reloaded.collectedFlag, 1)
        XCTAssertEqual(reloaded.cycleDate, "7-1-2026")
        XCTAssertEqual(reloaded.dosinumber, "D-1")
        XCTAssertEqual(reloaded.modifiedBy, "tech1", "who collected it must survive the relaunch")
        XCTAssertEqual(reloaded.modifiedDate, Date(timeIntervalSinceReferenceDate: 4_000),
                       "the recorded collection time must survive the relaunch untouched")
    }

    // Offline, synchronize takes the no-network branch: no upload pass runs, so
    // no resolved set exists and nothing may leave the queue — the scans must
    // still be on disk, untouched, when connectivity returns after a relaunch.
    func test_saveChanges_offline_keepsQueue() throws {
        removeCacheFileOnDisk()
        addTeardownBlock { self.removeCacheFileOnDisk() }

        let cache = Cache()
        cache.addChange(try makeItem(recordName: "R1", cycleDate: "7-1-2026"))
        cache.addChange(try makeItem(recordName: "R2", cycleDate: "7-1-2026"))
        cache.save()

        let relaunched = try XCTUnwrap(Cache.load(), "Cache.load() should return the just-saved cache")
        XCTAssertEqual(relaunched.changes.map { $0.recordName }, ["R1", "R2"],
                       "an offline session must leave the queue exactly as it was")
    }

    // MARK: - Duplicate edits: newest wins

    func test_addChange_newestEditWinsForSameRecordName() throws {
        let cache = Cache()
        cache.addChange(try makeItem(recordName: "R1", locdescription: "first"))
        cache.addChange(try makeItem(recordName: "R1", locdescription: "second"))

        XCTAssertEqual(cache.changes.count, 1, "the same record queued twice must hold one entry, not two")
        XCTAssertEqual(cache.changes.first?.locdescription, "second", "the newest edit wins")
    }

    func test_addChange_replacesARecoveryRequeuedEntry() throws {
        // A stranded record re-queued by recovery, then edited by the user: the
        // newer edit must replace the recovered entry, not upload beside it.
        let cache = Cache()
        cache.changes.append(try makeItem(recordName: "R1", locdescription: "recovered"))

        cache.addChange(try makeItem(recordName: "R1", locdescription: "edited"))

        XCTAssertEqual(cache.changes.count, 1)
        XCTAssertEqual(cache.changes.first?.locdescription, "edited")
    }

    // MARK: - Recovery is idempotent

    func test_recovery_idempotent_afterServerDatesBackfilled() throws {
        let stranded = try makeItem(recordName: "R1")
        XCTAssertEqual(LocationsCK.recoveryCandidates(locations: [stranded], queuedNames: []).count, 1,
                       "precondition: the record starts stranded")

        // A confirmed upload backfills the server dates (uploadChanges via
        // applyServerDates); the record must stop matching the stranded marker.
        LocationsCK.applyServerDates(creationDate: Date(timeIntervalSinceReferenceDate: 1_000),
                                     modificationDate: Date(timeIntervalSinceReferenceDate: 1_000),
                                     to: stranded)

        XCTAssertTrue(LocationsCK.recoveryCandidates(locations: [stranded], queuedNames: []).isEmpty,
                      "a recovered record must never be re-queued again")
    }

    // MARK: - Reset Cache never discards unuploaded scans

    func test_clear_keepsPendingChangesQueued() throws {
        let cache = Cache()
        let item = try makeItem(recordName: "R1")
        cache.add(item)
        cache.addChange(item)

        cache.clear()

        XCTAssertTrue(cache.locations.isEmpty)
        XCTAssertEqual(cache.changes.map { $0.recordName }, ["R1"],
                       "Reset Cache discards downloaded records, never the upload queue")
    }

    func test_reset_requeuesStrandedRecordsBeforeClearing() throws {
        // Mirrors reset(): stranded records are re-queued BEFORE clear(), so a
        // reset can never throw away a scan that was still waiting to upload.
        let cache = Cache()
        let stranded = try makeItem(recordName: "R1")
        stranded.collectedFlag = 1
        cache.add(stranded)

        let candidates = LocationsCK.recoveryCandidates(locations: cache.locations,
                                                        queuedNames: Set(cache.changes.compactMap { $0.recordName }))
        cache.changes.append(contentsOf: candidates)
        cache.clear()

        XCTAssertTrue(cache.locations.isEmpty)
        XCTAssertEqual(cache.changes.map { $0.recordName }, ["R1"],
                       "the stranded scan survives the reset in the upload queue")
    }
}
