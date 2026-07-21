//
//  SyncAcceptanceTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class SyncAcceptanceTests: XCTestCase {

    // MARK: - Acceptance: the confirmed field cases

    // One test per confirmed failure from the July incident, each asserting the
    // end state the fix must produce for that device's records.

    // Signed-out iCloud (43 scans): every save is refused, so the pass resolves
    // nothing. The scans survive the sync cycle, persist, and are announced.
    func test_acceptance_signedOutDevice_refusedUploadsStayQueued() throws {
        removeCacheFileOnDisk()
        addTeardownBlock { self.removeCacheFileOnDisk() }

        let cache = Cache()
        for i in 1...43 {
            let scan = try makeItem(recordName: "SIGNEDOUT-\(i)", cycleDate: "1-1-2026")
            scan.collectedFlag = 1
            cache.add(scan)
            cache.changes.append(scan)
        }

        // a fully refused upload pass: the server confirmed nothing
        cache.changes.removeAll(where: { LocationsCK.shouldRemoveFromQueue(item: $0, resolved: []) })
        XCTAssertEqual(cache.changes.count, 43, "every refused scan stays queued")

        cache.save()
        let relaunched = try XCTUnwrap(Cache.load())
        XCTAssertEqual(relaunched.changes.count, 43, "the queue survives a relaunch")

        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .noAccount,
                                                                pendingChangeCount: 43),
                       "Sign in to iCloud in Settings — 43 scans waiting to upload.",
                       "the failure is announced on the startup screen instead of staying silent")
    }

    // Un-accepted iCloud Terms & Conditions (19 scans): CloudKit reports
    // temporarilyUnavailable and refuses saves — same retention as signed-out.
    func test_acceptance_tcBlockedDevice_behavesSameAsSignedOut() throws {
        let cache = Cache()
        for i in 1...19 {
            let scan = try makeItem(recordName: "WEDGED-\(i)", cycleDate: "1-1-2026")
            scan.collectedFlag = 1
            cache.add(scan)
            cache.changes.append(scan)
        }

        cache.changes.removeAll(where: { LocationsCK.shouldRemoveFromQueue(item: $0, resolved: []) })
        XCTAssertEqual(cache.changes.count, 19, "a wedged device retains exactly like a signed-out one")

        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .temporarilyUnavailable,
                                                                pendingChangeCount: 19),
                       "iCloud needs attention — open Settings and accept any iCloud prompts (19 scans waiting to upload).")
    }

    // The half-uploaded exchange (GALRY-065): the new deploy record saved but the
    // collect update's server lookup failed transiently. The old code then made a
    // tag-less save CloudKit rejected — and dropped the collect.
    func test_acceptance_transientFetchFailure_noTaglessSave_recordRetried() throws {
        let cache = Cache()
        let deploy = try makeItem(recordName: "GALRY-065-DEPLOY", cycleDate: "1-1-2026")
        let collect = try makeItem(recordName: "GALRY-065-COLLECT", cycleDate: "7-1-2025")
        collect.collectedFlag = 1
        cache.changes.append(deploy)
        cache.changes.append(collect)

        // the deploy is confirmed absent (first-time insert); the collect's lookup failed
        guard case .saveAsNew = LocationsCK.uploadAction(serverRecord: nil, confirmedMissing: true) else {
            return XCTFail("a confirmed-absent record must save as a first-time insert")
        }
        guard case .keepQueued = LocationsCK.uploadAction(serverRecord: nil, confirmedMissing: false) else {
            return XCTFail("an unresolved lookup must never produce a tag-less save")
        }

        // only the deploy resolves; the collect survives to retry
        cache.changes.removeAll(where: { LocationsCK.shouldRemoveFromQueue(item: $0, resolved: ["GALRY-065-DEPLOY"]) })
        XCTAssertEqual(cache.changes.map { $0.recordName }, ["GALRY-065-COLLECT"],
                       "the half-uploaded exchange retries its collect instead of losing it")
    }

    // The recovery sweep over a cache modeled on the real exports: 95 stranded
    // collects (43 + 32 + 19 + 1 across four devices) among healthy records.
    func test_acceptance_strandedRecords_selectedForRecovery_expectedCounts() throws {
        var locations: [LocationRecordCacheItem] = []
        for (device, count) in [("A", 43), ("B", 32), ("C", 19), ("D", 1)] {
            for i in 1...count {
                let scan = try makeItem(recordName: "\(device)-\(i)", cycleDate: "1-1-2026", modifiedDate: 4_000)
                scan.collectedFlag = 1
                locations.append(scan)
            }
        }
        // healthy server-stamped records must not be swept up
        for i in 1...20 {
            locations.append(try makeItem(recordName: "SYNCED-\(i)", creationDate: 1_000, modificationDate: 1_000))
        }

        let candidates = LocationsCK.recoveryCandidates(locations: locations, queuedNames: [])
        XCTAssertEqual(candidates.count, 95, "exactly the 95 stranded collects are selected")

        // a recovered record the server ALREADY shows collected (a pre-fix upload
        // that landed) resolves via the skip, never a duplicate save
        let landed = try XCTUnwrap(candidates.first)
        XCTAssertTrue(LocationsCK.shouldSkipSave(item: landed,
                                                 serverRecord: makeServerRecord(collectedFlag: 1, cycleDate: "1-1-2026")),
                      "already-landed uploads resolve harmlessly instead of double-saving")
    }

    // The stale-record shape (BA00064894S): another tech's cloud edit was
    // invisible because this device's own unsynced edit had pushed the
    // incremental watermark past it.
    func test_acceptance_staleRecord_downloadedAfterWatermarkFix() throws {
        let synced = try makeItem(recordName: "R1", creationDate: 1_000, modifiedDate: 5_000)
        let localUnsynced = try makeItem(recordName: "BA00064894S", modifiedDate: 9_000)

        let watermark = try XCTUnwrap(LocationsCK.syncWatermark(locations: [synced, localUnsynced]))

        XCTAssertEqual(watermark, Date(timeIntervalSinceReferenceDate: 5_000),
                       "the local unsynced edit (9 000) no longer advances the watermark")
        XCTAssertTrue(Date(timeIntervalSinceReferenceDate: 6_000) > watermark,
                      "the other tech's cloud edit (6 000) now clears 'modifiedDate > watermark' and downloads")
    }

    // A recovered upload keeps its original (old) modifiedDate, which sits below
    // every other device's incremental watermark — the recurring full reconcile
    // is what makes it visible fleet-wide.
    func test_acceptance_recoveredRecords_visibleToOtherDevices() throws {
        let otherDeviceCache = [try makeItem(recordName: "R1", creationDate: 1_000, modifiedDate: 5_000)]
        let watermark = try XCTUnwrap(LocationsCK.syncWatermark(locations: otherDeviceCache))

        // the recovered record uploaded with its original scan time, below the watermark
        XCTAssertFalse(Date(timeIntervalSinceReferenceDate: 4_000) > watermark,
                       "the incremental predicate can never pick the recovered record up")

        XCTAssertTrue(LocationsCK.shouldRunFullReconcile(pendingChangeCount: 0,
                                                         lastReconcile: Date(timeIntervalSinceReferenceDate: 0),
                                                         now: Date(timeIntervalSinceReferenceDate: 25 * 60 * 60)),
                      "the daily reconcile is the path that downloads it on the other device")
    }
}
