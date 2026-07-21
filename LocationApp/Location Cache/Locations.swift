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

    var pendingChangeCount: Int { get }

    func accountStatus(completionHandler: @escaping (CKAccountStatus) -> Void)

    func eligibleOldCycleRecords(keepingCycles: Int) -> [LocationRecordCacheItem]

    func deleteOldCycleRecords(keepingCycles: Int, progress: @escaping (Int, Int) -> Void, completion: @escaping (Int, Error?) -> Void)
}

class LocationsCK : Locations, SettingsService {
    
    let database = CKContainer.default().publicCloudDatabase
    var timer: Timer?
    let timerSec = 300.0
    var cache: Cache?
    let reachability = Reachability()!
    let semaphore = DispatchSemaphore(value: 1)
    // True while the in-flight query is a full re-download; queryCompletionHandler
    // stamps cache.lastFullReconcile only when that query completes.
    private var fullReconcileInFlight = false

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

        // Recovery pass: stranded records (authored here, never confirmed
        // uploaded) re-enter the queue so the normal upload path retries them.
        let requeued = self.requeueRecoveryCandidates()
        if requeued > 0 {
            print("Recovery: re-queued \(requeued) unsynced records for upload")
            self.cache!.save()
        }

        if reachability.connection != .none {
            updateSettings()
            // Fall back to a full re-download when the queue is drained and the
            // last one is stale — recovered uploads keep their original (old)
            // modifiedDate, so incremental sync alone would never show them here.
            var predicate = NSPredicate(value: true)
            var isFullDownload = true
            if !LocationsCK.shouldRunFullReconcile(pendingChangeCount: self.cache!.changes.count,
                                                   lastReconcile: self.cache!.lastFullReconcile,
                                                   now: Date()),
               let watermark = LocationsCK.syncWatermark(locations: self.cache!.locations) {
                predicate = NSPredicate(format: "modifiedDate > %@", argumentArray: [watermark])
                isFullDownload = false
            }
            self.fullReconcileInFlight = isFullDownload

            print(isFullDownload ? "Location query started (full reconcile)" : "Location query started")
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
        // Stranded records exist only in locations until re-queued; queue them
        // before clear() so a reset can never discard an unuploaded scan.
        _ = self.requeueRecoveryCandidates()
        self.cache?.clear()
        semaphore.signal()
        self.synchronize(loaded: loaded)
    }

    // Number of edits queued for upload but not yet synced. Read under the same
    // semaphore every other cache mutation uses, so the count is consistent with
    // a concurrent save/sync rather than a half-applied batch. Day 10's Reset Cache
    // confirmation surfaces this to the user before clearing the cache.
    var pendingChangeCount: Int {
        semaphore.wait()
        defer { semaphore.signal() }
        return cache?.changes.count ?? 0
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

    // Copies the server-assigned system dates onto a cached item after a successful
    // upload, so a device-created record shows its System dates without a Reset Cache.
    // Pure/internal so tests can drive it (CKRecord.creationDate can't be set offline).
    internal static func applyServerDates(creationDate: Date?, modificationDate: Date?, to item: LocationRecordCacheItem) {
        item.creationDate = creationDate
        item.modificationDate = modificationDate
    }

    // Newest modifiedDate among server-stamped records (creationDate set) only.
    // Device-authored edits carry a scan-time modifiedDate before ever reaching the
    // server; letting them advance the watermark hides other devices' cloud edits.
    internal static func syncWatermark(locations: [LocationRecordCacheItem]) -> Date? {
        return locations
            .filter({ $0.modifiedDate != nil && $0.creationDate != nil })
            .max(by: { a, b -> Bool in a.modifiedDate! < b.modifiedDate! })?
            .modifiedDate
    }

    // The three-way branch for one queued record after the server lookup: fetched
    // → merge onto the server copy (carries its change tag); confirmed absent →
    // first-time insert; unresolved → keep queued, never attempt a tag-less save.
    internal enum UploadAction {
        case saveWithTag(CKRecord)
        case saveAsNew
        case keepQueued
    }

    internal static func uploadAction(serverRecord: CKRecord?, confirmedMissing: Bool) -> UploadAction {
        if let serverRecord = serverRecord {
            return .saveWithTag(serverRecord)
        }
        return confirmedMissing ? .saveAsNew : .keepQueued
    }

    // Which queued changes leave the retry queue after an upload pass: only those
    // the server confirmed saved or shouldSkipSave deliberately skipped. Items with
    // no recordName can never upload; dropping them preserves the old behavior.
    internal static func shouldRemoveFromQueue(item: LocationRecordCacheItem, resolved: Set<String>) -> Bool {
        guard let name = item.recordName else { return true }
        return resolved.contains(name)
    }

    //MARK:  Stranded-record recovery

    // The stranded marker: no server System dates means the record was authored
    // on this device and no upload was ever confirmed. recordName-less legacy
    // items can never upload, so they are not candidates.
    internal static func isRecoveryCandidate(item: LocationRecordCacheItem) -> Bool {
        return item.recordName != nil && item.creationDate == nil && item.modificationDate == nil
    }

    // Stranded records not already queued, in cache order. Returns the cached
    // instances themselves so a recovered upload keeps its original modifiedBy
    // and modifiedDate — who collected it, and when — instead of restamping.
    internal static func recoveryCandidates(locations: [LocationRecordCacheItem], queuedNames: Set<String>) -> [LocationRecordCacheItem] {
        return locations.filter { item in
            guard let name = item.recordName else { return false }
            return isRecoveryCandidate(item: item) && !queuedNames.contains(name)
        }
    }

    // Whether synchronize should run a full re-download instead of the
    // incremental fetch: only once the upload queue has drained, at most every
    // 24 hours, and always when no reconcile timestamp exists yet.
    internal static func shouldRunFullReconcile(pendingChangeCount: Int, lastReconcile: Date?, now: Date) -> Bool {
        guard pendingChangeCount == 0 else { return false }
        guard let lastReconcile = lastReconcile else { return true }
        return now.timeIntervalSince(lastReconcile) > 24 * 60 * 60
    }

    // Caller must hold the semaphore. Appends directly rather than through
    // addChange, which would overwrite modifiedBy with the current user.
    private func requeueRecoveryCandidates() -> Int {
        guard let cache = self.cache else { return 0 }
        let queuedNames = Set(cache.changes.compactMap { $0.recordName })
        let candidates = LocationsCK.recoveryCandidates(locations: cache.locations, queuedNames: queuedNames)
        cache.changes.append(contentsOf: candidates)
        return candidates.count
    }

    //MARK:  Super-user delete

    // A record may be deleted only when its cycleDate is NOT among the
    // protected (most recent) cycles; a nil cycleDate is never deletable.
    // Internal so LocationAppTests can drive the decision matrix offline.
    internal static func isEligibleForCycleDeletion(item: LocationRecordCacheItem, protectedCycles: [String]) -> Bool {
        guard let cycleDate = item.cycleDate else { return false }
        return !protectedCycles.contains(cycleDate)
    }

    // Everything whose cycleDate falls outside the most recent keepingCycles
    // cycles. The admin screen uses this to preview the affected records.
    func eligibleOldCycleRecords(keepingCycles: Int) -> [LocationRecordCacheItem] {
        let protectedCycles = RecordsUpdate.getLastCycles(cycles: keepingCycles)
        return filter(by: { LocationsCK.isEligibleForCycleDeletion(item: $0, protectedCycles: protectedCycles) })
    }

    static let deleteOfflineError = NSError(domain: "LocationApp", code: 503,
        userInfo: [NSLocalizedDescriptionKey: "No network connection. Deletion stopped — records already deleted are gone; the rest are untouched."])

    // Deletes every eligible old-cycle record from CloudKit in pages of 200.
    // Eligibility is recomputed here rather than trusted from the caller; only
    // confirmed deletions leave the cache, and every step prints for audit.
    func deleteOldCycleRecords(keepingCycles: Int, progress: @escaping (Int, Int) -> Void, completion: @escaping (Int, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let names = self.eligibleOldCycleRecords(keepingCycles: keepingCycles).compactMap { $0.recordName }
            let total = names.count
            print("Super-user delete: \(total) records eligible (keeping last \(keepingCycles) cycles)")
            guard total > 0 else {
                DispatchQueue.main.async { completion(0, nil) }
                return
            }

            var deleted = 0
            let size = 200
            var start = 0
            while start < names.count {
                // Graceful interruption: stop between batches the moment
                // connectivity drops; everything deleted so far stays deleted.
                if self.reachability.connection == .none {
                    print("Super-user delete: connectivity lost after \(deleted)/\(total); stopping")
                    DispatchQueue.main.async { completion(deleted, LocationsCK.deleteOfflineError) }
                    return
                }
                let batch = Array(names[start..<min(start + size, names.count)])
                start += size

                var succeeded: [String] = []
                var batchError: Error? = nil
                let operation = CKModifyRecordsOperation(recordsToSave: nil,
                                                         recordIDsToDelete: batch.map { CKRecord.ID(recordName: $0) })
                operation.qualityOfService = .userInitiated
                operation.perRecordDeleteBlock = { id, result in
                    switch result {
                    case .success:
                        succeeded.append(id.recordName)
                    case .failure(let error):
                        print("Super-user delete failed for \(id.recordName): \(error.localizedDescription)")
                        batchError = error
                    }
                }
                operation.modifyRecordsResultBlock = { result in
                    if case .failure(let error) = result {
                        batchError = error
                    }
                }
                self.database.add(operation)
                operation.waitUntilFinished()

                if !succeeded.isEmpty {
                    self.semaphore.wait()
                    let removed = self.cache?.remove(recordNames: Set(succeeded)) ?? 0
                    self.cache?.save()
                    self.semaphore.signal()
                    deleted += succeeded.count
                    print("Super-user delete: batch deleted \(succeeded.count) from cloud, removed \(removed) from cache (\(deleted)/\(total))")
                    DispatchQueue.main.async { progress(deleted, total) }
                }
                if let error = batchError {
                    print("Super-user delete: stopping after error with \(deleted)/\(total) deleted")
                    DispatchQueue.main.async { completion(deleted, error) }
                    return
                }
            }
            print("Super-user delete: completed, \(deleted)/\(total) records deleted")
            DispatchQueue.main.async { completion(deleted, nil) }
        }
    }

    // Outcome of the pre-save server fetch: `records` holds the fetched server
    // copies; `confirmedMissing` holds IDs the server definitively reported as
    // nonexistent (safe to insert). IDs in neither set are unresolved this pass.
    struct ServerLookup {
        var records: [CKRecord.ID: CKRecord] = [:]
        var confirmedMissing: Set<CKRecord.ID> = []
    }

    // Fetches the current server copies for the given IDs so uploadChanges can
    // skip already-collected records, merge local fields onto the fetched base
    // (keeping its recordChangeTag), and leave unresolved IDs queued.
    fileprivate func fetchServerRecords(_ ids: [CKRecord.ID]) -> ServerLookup {
        guard !ids.isEmpty else { return ServerLookup() }
        var lookup = ServerLookup()
        let waitSemaphore = DispatchSemaphore(value: 0)
        let fetchOp = CKFetchRecordsOperation(recordIDs: ids)
        fetchOp.qualityOfService = .userInitiated
        fetchOp.perRecordResultBlock = { id, result in
            switch result {
            case .success(let record): lookup.records[id] = record
            case .failure(let error):
                // Only .unknownItem proves the record isn't on the server. Any
                // other error leaves the ID unresolved so the save is deferred.
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    lookup.confirmedMissing.insert(id)
                }
                else {
                    print("Fetch unresolved for \(id.recordName): \(error.localizedDescription)")
                }
            }
        }
        fetchOp.fetchRecordsResultBlock = { _ in waitSemaphore.signal() }
        self.database.add(fetchOp)
        waitSemaphore.wait()
        return lookup
    }

    // Returns the recordNames RESOLVED this pass: per-record confirmed saves plus
    // deliberate shouldSkipSave skips. Refused or unresolved records are absent
    // from the result, so saveChanges keeps them queued for the next retry.
    fileprivate func uploadChanges(_ items: [LocationRecordCacheItem]) -> Set<String> {
        var resolved: Set<String> = []
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
            let lookup = fetchServerRecords(ids)
            print("Fetched \(lookup.records.count) server records (\(lookup.confirmedMissing.count) confirmed new) for page of \(slice.count).")

            var recordsToSave: [CKRecord] = []
            for item in slice {
                guard let recordName = item.recordName else { continue }
                let id = CKRecord.ID(recordName: recordName)
                if LocationsCK.shouldSkipSave(item: item, serverRecord: lookup.records[id]) {
                    print("Skipping save for \(recordName): already collected on server for cycle \(item.cycleDate ?? "nil")")
                    resolved.insert(recordName)
                    continue
                }
                switch LocationsCK.uploadAction(serverRecord: lookup.records[id],
                                                confirmedMissing: lookup.confirmedMissing.contains(id)) {
                case .saveWithTag(let serverRecord):
                    // Apply local fields onto the fetched record so the save
                    // carries the server's recordChangeTag; .ifServerRecordUnchanged
                    // then rejects the write if another device changed the record.
                    item.update(newRecord: serverRecord)
                    recordsToSave.append(serverRecord)
                case .saveAsNew:
                    // Server confirmed the record doesn't exist — first-time upload.
                    recordsToSave.append(item.to())
                case .keepQueued:
                    // A save without the server's change tag would be rejected and
                    // the record lost; defer to the next sync trigger instead.
                    print("Server lookup unresolved for \(recordName): keeping queued")
                }
            }

            if recordsToSave.isEmpty { continue }

            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
            operation.savePolicy = .ifServerRecordUnchanged
            operation.qualityOfService = .userInitiated
            // The server stamps creationDate/modificationDate (the export's System_Date
            // columns) on save. Collect the saved records so the cache can pick up those
            // server dates below, instead of staying nil until a Reset Cache.
            var savedServerRecords: [CKRecord] = []
            operation.perRecordSaveBlock = { id, result in
                switch result {
                case .success(let savedRecord):
                    // Per-record blocks fire serially on the operation's queue and the
                    // array is only read after waitUntilFinished, so no lock is needed.
                    savedServerRecords.append(savedRecord)
                case .failure(let error):
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

            // Mark confirmed saves resolved and backfill their server-assigned System
            // dates, on the saveChanges thread (holding the cache semaphore) after the
            // op finished — never from the callback. saveChanges() then persists.
            for savedRecord in savedServerRecords {
                resolved.insert(savedRecord.recordID.recordName)
                if let cached = self.cache?.location(forRecordName: savedRecord.recordID.recordName) {
                    LocationsCK.applyServerDates(creationDate: savedRecord.creationDate,
                                                 modificationDate: savedRecord.modificationDate,
                                                 to: cached)
                }
            }
        }
        return resolved
    }

    private func saveChanges() {
        if reachability.connection != .none {
            DispatchQueue.global(qos: .background).async {
                self.semaphore.wait()
                if (!self.cache!.changes.isEmpty) {
                    let items = Array(self.cache!.changes)
                    let resolved = self.uploadChanges(items)
                    // Remove only what the server confirmed (or deliberately skipped);
                    // refused/unresolved edits stay queued and retry on the 300s timer,
                    // reachability restore, or the next scan.
                    self.cache?.changes.removeAll(where: { LocationsCK.shouldRemoveFromQueue(item: $0, resolved: resolved) })
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
            // A failed full download proves nothing; leave the reconcile
            // timestamp unstamped so the next sync tries again.
            fullReconcileInFlight = false
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
                // A completed full download refreshed every record — restart
                // the 24h reconcile clock. Runs under the sync's semaphore.
                if fullReconcileInFlight {
                    cache!.lastFullReconcile = Date()
                    fullReconcileInFlight = false
                }
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
    
    // CloudKit public-DB reads work anonymously but writes need an iCloud
    // account, so a signed-out (or wedged) device fails every upload silently.
    // The startup screen surfaces this. Never touches the cache semaphore.
    func accountStatus(completionHandler: @escaping (CKAccountStatus) -> Void) {
        CKContainer.default().accountStatus { status, error in
            if let error = error {
                print("Account status check failed: \(error.localizedDescription)")
            }
            completionHandler(status)
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
    
    // Reads the field-worker username from the MDM (JAMF) managed app config.
    // Replaces the deprecated CloudKit user-discovery path (requestApplicationPermission
    // / discoverUserIdentity); blank on unmanaged devices that carry no MDM payload.
    private func setUser(completionHandler: @escaping (String) -> Void) {
        completionHandler(ManagedAppConfig.currentUsername())
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
                    settings.defaultLatitude = record["defaultLatitude"] as? Double
                    settings.defaultLongitude = record["defaultLongitude"] as? Double
                    settings.superUserPasscode = record["superUserPasscode"] as? Int
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
