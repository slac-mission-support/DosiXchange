//
//  Locations.swift
//  LocationApp
//
//  Created by Szöllősi László on 2023. 05. 11..
//  Copyright © 2023. Ford, Ryan M. All rights reserved.
//

import Foundation
import CloudKit

protocol Locations {
        
    func synchronize(loaded: @escaping ((Int) -> Void))
    
    func filter(by: (LocationRecordCacheItem) -> Bool) -> [LocationRecordCacheItem]
    
    func filter(by: @escaping (LocationRecordCacheItem) -> Bool, completionHandler: @escaping ([LocationRecordCacheItem]) -> Void)
    
    func groups(completionHandler: @escaping ([String]) -> Void)
    
    func count(by: (LocationRecordCacheItem) -> Bool) -> Int
    
    func save(item: LocationRecordCacheItem, completionHandler: (() -> Void)?)
    
    func save(items: [LocationRecordCacheItem], completionHandler: (() -> Void)?)
    
    func reset(_ loaded: @escaping  ((Int) -> Void))
    
    func fetch(id: String, completionHandler: @escaping (LocationRecordCacheItem?, Error?) -> Void)
}

class LocationsCK : Locations, SettingsService {
    
    let database = CKContainer.default().publicCloudDatabase
    var timer: Timer?
    let timerSec = 300.0
    var cache: Cache?
    let reachability = Reachability()!
    let semaphore = DispatchSemaphore(value: 1)

    init() {
        reachability.whenReachable = reachable
        timer = Timer.scheduledTimer(withTimeInterval: timerSec, repeats: true) { _ in
            DispatchQueue.global(qos: .background).async {
                if self.reachability.connection != .none {
                    print("Synchronization from timer")
                    self.synchronize(loaded: { _ in })
                }
            }
        }
        do {
            try reachability.startNotifier()
        }
        catch {
            print("Unable to start notifier")
        }
    }
        
    func synchronize(loaded: @escaping  ((Int) -> Void)) {
        semaphore.wait()
        if self.cache == nil {
            self.cache = Cache.load() ?? Cache()
        }
        
        if reachability.connection != .none {
            updateSettings()
            let lastDate = self.cache!.locations
                .filter({ $0.modifiedDate != nil })
                .max(by: { a,b -> Bool in a.modifiedDate! < b.modifiedDate!})

            var predicate = NSPredicate(value: true)
            if lastDate != nil {
                predicate = NSPredicate(format: "modifiedDate > %@", argumentArray: [lastDate!.modifiedDate!])
            }

            print("Location query started")
            self.query(predicate: predicate, sortDescriptors: [], pageSize: 50, loaded:{
                self.semaphore.signal()
                loaded($0)
            }, completionHandler: self.queryCompletionHandler)
            self.saveChanges()
        }
        else {
            semaphore.signal()
            loaded(self.cache!.locations.count)
        }
    }
    
    func filter(by: (LocationRecordCacheItem) -> Bool) -> [LocationRecordCacheItem] {
        semaphore.wait()
        defer { semaphore.signal() }
        return self.cache!.locations.filter(by)
    }
    
    func filter(by: @escaping (LocationRecordCacheItem) -> Bool, completionHandler: @escaping ([LocationRecordCacheItem]) -> Void) {
        semaphore.wait()
        DispatchQueue.global(qos: .background).async {
            let items = self.cache!.locations.filter(by)
            self.semaphore.signal()
            completionHandler(items)
        }
    }
    
    func groups(completionHandler: @escaping ([String]) -> Void) {
        semaphore.wait()
        DispatchQueue.global(qos: .background).async {
            let items = self.cache!.locations.filter({ $0.reportGroup != nil }).map({ $0.reportGroup! })
            self.semaphore.signal()
            completionHandler(Array(Set(items)))
        }
    }
    
    func count(by: (LocationRecordCacheItem) -> Bool) -> Int {
        semaphore.wait()
        defer { semaphore.signal() }
        return self.cache!.locations.reduce(0, { (count, e) in count + (by(e) ? 1 : 0) })
    }
    
    func save(item: LocationRecordCacheItem, completionHandler: (() -> Void)?) {
        self.save(items: [item], completionHandler: completionHandler)
    }
    
    func save(items: [LocationRecordCacheItem], completionHandler: (() -> Void)?) {
        DispatchQueue.global(qos: .background).async {
            self.semaphore.wait()
            var queued = 0
            for item in items {
                // Local guardrail: drop the edit if our own cache already shows this
                // record collected for the same cycle. Catching it at the local-write
                // boundary keeps a stale edit from ever being queued for upload — the
                // local complement to uploadChanges' server-side skip (shouldSkipSave),
                // which guards the same invariant against changes made on another
                // device. See shouldSkipLocalSave for the decision.
                let cached = item.recordName.flatMap { self.cache?.location(forRecordName: $0) }
                if LocationsCK.shouldSkipLocalSave(item: item, cached: cached) {
                    print("Skipping save for \(item.recordName ?? "?"): local cache shows collected for cycle \(cached?.cycleDate ?? "nil")")
                    continue
                }
                self.reportGroupUpdate(item)
                self.cache?.add(item)
                self.cache?.addChange(item)
                queued += 1
            }
            if queued > 0 {
                self.cache?.save()
            }
            self.semaphore.signal()
            if queued > 0 {
                self.saveChanges()
            }
            DispatchQueue.main.async {
                completionHandler?()
            }
        }
    }
    
    func reset(_ loaded: @escaping  ((Int) -> Void)) {
        semaphore.wait()
        self.cache?.clear()
        semaphore.signal()
        self.synchronize(loaded: loaded)
    }
    
    private func reachable(_ : Reachability) {
        DispatchQueue.global(qos: .background).async {
            self.semaphore.wait()
            if self.cache == nil {
                self.cache = Cache.load() ?? Cache()
            }
            self.semaphore.signal()
            self.setUser(completionHandler: {
                self.cache?.setUser(name: $0)
                self.saveChanges()
            })
            self.synchronize(loaded: { _ in print("Synchronization from reachability") })
        }
    }
    
    // Pure decision used by uploadChanges: skip saving when the server already
    // shows the record collected on the same cycle. The server is the source of
    // truth — overwriting a server-side collected record with a stale local one
    // would silently revert a completed field action.
    // Internal (not private) so LocationAppTests can drive the decision matrix
    // offline; same exception precedent as Day 3's bulkSyncDesiredKeys.
    internal static func shouldSkipSave(item: LocationRecordCacheItem, serverRecord: CKRecord?) -> Bool {
        guard let serverRecord = serverRecord else { return false }
        guard let serverCollected = serverRecord["collectedFlag"] as? Int64,
              let serverCycle = serverRecord["cycleDate"] as? String else { return false }
        return serverCollected == 1 && serverCycle == item.cycleDate
    }

    // Pure decision used by save(items:): the local complement to shouldSkipSave.
    // Skip queuing an edit when our own cache already shows the record collected on
    // the same cycle — once collected for a cycle a record is meant to be immutable
    // until the next cycle, so re-saving it would only queue a stale upload. `cached`
    // is the existing cache entry for this recordName (nil if we've never seen it).
    // Internal (not private) so LocationAppTests can drive the decision matrix
    // offline; same exception precedent as Day 3's bulkSyncDesiredKeys.
    internal static func shouldSkipLocalSave(item: LocationRecordCacheItem, cached: LocationRecordCacheItem?) -> Bool {
        guard let cached = cached else { return false }
        guard cached.collectedFlag == 1, let cachedCycle = cached.cycleDate else { return false }
        return cachedCycle == item.cycleDate
    }

    // Fetches the current server-side records for the given IDs. uploadChanges
    // uses the returned dictionary to (1) skip records the server already shows
    // collected on the same cycle and (2) apply local fields onto the fetched
    // base so .ifServerRecordUnchanged can detect mid-flight conflicts via the
    // record's recordChangeTag.
    fileprivate func fetchServerRecords(_ ids: [CKRecord.ID]) -> [CKRecord.ID: CKRecord] {
        guard !ids.isEmpty else { return [:] }
        var fetched: [CKRecord.ID: CKRecord] = [:]
        let waitSemaphore = DispatchSemaphore(value: 0)
        let fetchOp = CKFetchRecordsOperation(recordIDs: ids)
        fetchOp.qualityOfService = .userInitiated
        fetchOp.perRecordResultBlock = { id, result in
            switch result {
            case .success(let record): fetched[id] = record
            case .failure(let error): print("Fetch failed for \(id.recordName): \(error.localizedDescription)")
            }
        }
        fetchOp.fetchRecordsResultBlock = { _ in waitSemaphore.signal() }
        self.database.add(fetchOp)
        waitSemaphore.wait()
        return fetched
    }

    fileprivate func uploadChanges(_ items: [LocationRecordCacheItem]) {
        let size = 200
        var page = 1
        var total = 0
        print("Prepare to save \(items.count) records.")
        while (items.count > total) {
            let count = items.count >= page * size ? size : items.count - total
            let slice = Array(items[total...total + count - 1])
            total = page * size
            page += 1

            let ids = slice.compactMap { $0.recordName }.map { CKRecord.ID(recordName: $0) }
            let serverRecords = fetchServerRecords(ids)
            print("Fetched \(serverRecords.count) server records for page of \(slice.count).")

            var recordsToSave: [CKRecord] = []
            for item in slice {
                guard let recordName = item.recordName else { continue }
                let id = CKRecord.ID(recordName: recordName)
                if LocationsCK.shouldSkipSave(item: item, serverRecord: serverRecords[id]) {
                    print("Skipping save for \(recordName): already collected on server for cycle \(item.cycleDate ?? "nil")")
                    continue
                }
                if let serverRecord = serverRecords[id] {
                    // Apply local fields onto the fetched record so the save carries
                    // the server's recordChangeTag. .ifServerRecordUnchanged then
                    // rejects this write if another device modified the record
                    // between our fetch and save — the core of the concurrent-user fix.
                    item.update(newRecord: serverRecord)
                    recordsToSave.append(serverRecord)
                }
                else {
                    // No record on server yet — first-time upload. No tag to preserve.
                    recordsToSave.append(item.to())
                }
            }

            if recordsToSave.isEmpty { continue }

            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
            operation.savePolicy = .ifServerRecordUnchanged
            operation.qualityOfService = .userInitiated
            operation.perRecordSaveBlock = { id, result in
                if case .failure(let error) = result {
                    print("Per-record save failed for \(id.recordName): \(error.localizedDescription)")
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                    case .success : print("Saved \(recordsToSave.count) location records.")
                    case .failure(let error) :print(error.localizedDescription)
                }
            }
            self.database.add(operation)
            operation.waitUntilFinished()
        }
    }
    
    private func saveChanges() {
        if reachability.connection != .none {
            DispatchQueue.global(qos: .background).async {
                self.semaphore.wait()
                if (!self.cache!.changes.isEmpty) {
                    let items = Array(self.cache!.changes)
                    self.uploadChanges(items)
                    self.cache?.changes.removeAll()
                    self.cache?.save()
                    self.semaphore.signal()
                }
                else {
                    self.semaphore.signal()
                }
            }
        }
    }
    
    func queryCompletionHandler(records :[LocationRecordDelegate], completed: Bool?, error: Error?, loaded: @escaping ((Int) -> Void))  {
        if let error = error {
            print(error.localizedDescription)
            loaded(cache!.locations.count)
            return
        }
        
        if (!records.isEmpty){
            for record in records {
                if let item = LocationRecordCacheItem(withRecord: record as! CKRecord) {
                    cache!.add(item)
                }
                else {
                    print("Record isn't acceptable.")
                }
            }
            print("Cache new records: \(records.count)")
        }
        
        if let completed = completed {
            if completed {
                print("Location query completed.")
                cache!.save()
                loaded(cache!.locations.count)
            }
        }
    }
    
    func query(predicate: NSPredicate, sortDescriptors: [NSSortDescriptor], pageSize:Int,  loaded: @escaping ((Int) -> Void), completionHandler: @escaping ([LocationRecordDelegate], Bool?, Error?,@escaping ((Int) -> Void)) -> Void)  {
        let query = CKQuery(recordType: "Location", predicate: predicate)
        query.sortDescriptors = sortDescriptors
        let operation = CKQueryOperation(query: query)
        add(operation, loaded: loaded, completionHandler: completionHandler)
    }
    
    func getSettings(completionHandler: @escaping (Settings) -> Void) {
        semaphore.wait()
        DispatchQueue.global(qos: .background).async {
            let settings = self.cache!.settings
            self.semaphore.signal()
            completionHandler(settings)
        }
    }
    
    func fetch(id: String, completionHandler: @escaping (LocationRecordCacheItem?, Error?) -> Void) {
        database.fetch(withRecordID: CKRecord.ID(recordName: id), completionHandler: { record, error in
            if let error = error {
                print(error)
                completionHandler(nil, error)
            }
            if let record = record {
                completionHandler(LocationRecordCacheItem(withRecord: record), nil)
            }
        })
    }
    
    // Fields LocationRecordCacheItem(withRecord:) reads, minus the heavy CKAsset.
    // Photos are fetched lazily via Locations.fetch(id:) when the user opens the
    // detail or photo view, so excluding "photo" from bulk sync drops the biggest
    // per-record payload from the initial download.
    // Internal (not private) so unit tests can verify the field set.
    static let bulkSyncDesiredKeys: [String] = [
        "QRCode", "latitude", "longitude", "locdescription", "active",
        "dosinumber", "collectedFlag", "cycleDate", "mismatch", "moderator",
        "createdDate", "modifiedDate", "modifiedBy", "reportGroup", "hasPhoto"
    ]

    private func add(_ query : CKQueryOperation, loaded: @escaping ((Int) -> Void), completionHandler: @escaping ([LocationRecordDelegate], Bool?, Error?,@escaping ((Int) -> Void)) -> Void) {
        var result: [LocationRecordDelegate] = []
        let operation = query
        operation.resultsLimit = 500
        operation.desiredKeys = LocationsCK.bulkSyncDesiredKeys
        operation.recordMatchedBlock = { _, res in
            switch res {
                case .success(let record) : result.append(record)
                case .failure(let error) :print(error.localizedDescription)
            }
        }
        operation.queryResultBlock = { res in
            switch res {
            case .success(let cursor) :
                if let cursor {
                    completionHandler(result, false, nil, loaded)
                    result = []
                    let operation = CKQueryOperation(cursor: cursor)
                    self.add(operation, loaded:loaded, completionHandler:  completionHandler)
                }
                else {
                    completionHandler(result, true, nil, loaded)
                }
            case .failure(let error) :
                print(error.localizedDescription)
                completionHandler([], nil, error, loaded)
            }
        }
        database.add(operation)
    }
    
    private func setUser(completionHandler: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            CKContainer.default().requestApplicationPermission(.userDiscoverability) { (status, error) in
                if let error = error {
                    print(error.localizedDescription)
                }
                if status == .granted {
                        CKContainer.default().fetchUserRecordID { (record, error) in
                            CKContainer.default().discoverUserIdentity(withUserRecordID: record!, completionHandler: { (userID, error) in
                                if let givenName = userID?.nameComponents?.givenName, let familyName = userID?.nameComponents?.familyName {
                                    completionHandler("\(givenName) \(familyName)")
                                }
                                else {
                                    completionHandler(userID?.lookupInfo?.emailAddress ?? "")
                                }
                            })
                        }
                    }
                completionHandler("")
            }
        }
    }
    
    private func updateSettings() {
        let dispatchgroup = DispatchGroup()
        dispatchgroup.enter()
        let query = CKQuery(recordType: "Settings", predicate: NSPredicate(value: true))
        database.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 1, completionHandler: { results in
            switch results {
            case .failure(let error) : print(error.localizedDescription)
            case .success((let matches, _)) :
                switch matches.first!.1 {
                case .failure(let error) : print(error.localizedDescription)
                case .success(let record) :
                    let settings = Settings()
                    settings.dosimeterMinimumLength = record["dosimeterMinimumLength"] as? Int ?? 11
                    settings.dosimeterMaximumLength = record["dosimeterMaximumLength"] as? Int ?? 11
                    self.cache!.setSettings(settings: settings)
                }
            }            
            dispatchgroup.leave()
        })
        dispatchgroup.wait()
    }
    
    private func reportGroupUpdate(_ item: LocationRecordCacheItem) {
        if item.reportGroup == nil || item.reportGroup!.isEmpty
           , let location = cache!.locations.first(where: { l in l.reportGroup != nil && !l.reportGroup!.isEmpty && l.QRCode == item.QRCode }) {
            item.reportGroup = location.reportGroup
        }
    }
                                        
}
