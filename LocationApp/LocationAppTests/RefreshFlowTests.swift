//
//  RefreshFlowTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
import UIKit
@testable import LocationApp

class RefreshFlowTests: XCTestCase {

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

    // MARK: - Map refresh button (cloud sync)

    // The Map only read the local cache (queryForMap), so its pins could be stale
    // until something else synced. The new Refresh button must run synchronize()
    // (a real CloudKit pull) BEFORE re-querying the cache to redraw the pins.

    private func loadMapViewController() throws -> MapViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: MapViewController.self))
        let controller = storyboard.instantiateViewController(withIdentifier: "Map")
        let map = try XCTUnwrap(controller as? MapViewController,
                                "Main storyboard identifier \"Map\" should resolve to MapViewController")
        map.loadViewIfNeeded()
        map.locationmanager.stopUpdatingLocation()
        return map
    }

    func test_mapRefresh_syncsFromCloudBeforeReQuerying() throws {
        let map = try loadMapViewController()
        let mock = RefreshSpyLocations()
        map.locations = mock

        let requeried = expectation(description: "re-query ran after sync")
        mock.onFilter = { requeried.fulfill() }

        map.refreshMapFromCloud(self)

        wait(for: [requeried], timeout: 2.0)
        XCTAssertEqual(mock.synchronizeCallCount, 1, "refresh must trigger a cloud sync")
        XCTAssertEqual(mock.filterCallCount, 1, "refresh must re-query the cache after syncing")
        XCTAssertTrue(mock.syncedBeforeFilter, "sync must run before the re-query")
    }
}

// Minimal Locations test double. Records the order of synchronize()/filter() so the
// Nearest pull-to-refresh and Map refresh tests can assert the cloud sync happens
// before the local re-filter. Every other protocol member is an inert stub.
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
    func accountStatus(completionHandler: @escaping (CKAccountStatus) -> Void) { completionHandler(.available) }
    func eligibleOldCycleRecords(keepingCycles: Int) -> [LocationRecordCacheItem] { [] }
    func deleteOldCycleRecords(keepingCycles: Int, progress: @escaping (Int, Int) -> Void, completion: @escaping (Int, Error?) -> Void) { completion(0, nil) }
}
