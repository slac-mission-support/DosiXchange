//
//  Cache.swift
//  LocationApp
//
//  Created by Szöllősi László on 2023. 05. 12..
//  Copyright © 2023. Ford, Ryan M. All rights reserved.
//

import Foundation

class Cache: Codable {
    var version = "1.0"
    var user = ""
    var locations = [LocationRecordCacheItem]()
    var changes = [LocationRecordCacheItem]()
    var settings = Settings()

    // Transient recordName -> index map. Not persisted; rebuilt after load().
    // Without it, add() does an O(n) firstIndex(where:) per record, which makes
    // initial sync of N records O(N^2).
    private var locationIndex: [String: Int] = [:]

    private enum CodingKeys: String, CodingKey {
        case version, user, locations, changes, settings
    }

    private func rebuildLocationIndex() {
        locationIndex.removeAll(keepingCapacity: true)
        for (i, loc) in locations.enumerated() {
            if let name = loc.recordName { locationIndex[name] = i }
        }
    }

    static func load() -> Cache? {
        if Cache.locationRecordCacheFileExists() {
            let cacheFileURL = URL(fileURLWithPath: pathToCache())
            guard let cacheData = try? Data(contentsOf: cacheFileURL) else {
                print("Error loading Cache data")
                return nil
            }
            guard let locationsCache = try? JSONDecoder().decode(Cache.self,
                                                                 from: cacheData) else {
                print("Error decoding cache from data")
                return nil
            }
            locationsCache.rebuildLocationIndex()
            return locationsCache
        }
        return nil
    }

    func add(_ item: LocationRecordCacheItem) {
        guard let name = item.recordName else {
            locations.append(item)
            return
        }
        if let i = locationIndex[name] {
            locations[i] = item
        }
        else {
            locationIndex[name] = locations.count
            locations.append(item)
        }
    }
    
    // O(1) lookup by recordName via the same transient index add() maintains.
    // Lets callers check the cached state of a record without an O(n) scan.
    func location(forRecordName name: String) -> LocationRecordCacheItem? {
        guard let i = locationIndex[name] else { return nil }
        return locations[i]
    }

    // Removes the named records from the locations array AND the
    // pending-changes queue (so a queued upload can't resurrect them),
    // then rebuilds the index. Returns how many records were removed.
    @discardableResult
    func remove(recordNames: Set<String>) -> Int {
        guard !recordNames.isEmpty else { return 0 }
        let before = locations.count
        let isNamed: (LocationRecordCacheItem) -> Bool = { item in
            guard let name = item.recordName else { return false }
            return recordNames.contains(name)
        }
        locations.removeAll(where: isNamed)
        changes.removeAll(where: isNamed)
        rebuildLocationIndex()
        return before - locations.count
    }

    func addChange(_ item: LocationRecordCacheItem) {
        item.setValue(user, forKey: "modifiedBy")
        if let index = changes.firstIndex(where: { l in l.recordName == item.recordName}) {
            changes[index] = item
        }
        else {
            changes.append(item)
        }
    }
    
    func clear() {
        locations.removeAll()
        locationIndex.removeAll()
    }
    
    func save() {
        guard let cacheData = try? JSONEncoder().encode(self) else {
            print("Error encoding DosimeterRecordCache data")
            return
        }
        
        // delete the locations record cache file if it exists.
        let cacheFileURL = URL(fileURLWithPath: Cache.pathToCache())
        try? FileManager.default.removeItem(at: cacheFileURL)
        
        // save the locations record cahe data.
        guard let _ = try? cacheData.write(to: cacheFileURL) else {
            return
        }
    }
    
    func setUser(name: String){
        user = name
        print("Cloudkit user: \(name)")
    }
    
    func setSettings(settings: Settings){
        self.settings = settings
    }
    
    private static func locationRecordCacheFileExists() -> Bool {
        return FileManager.default.fileExists(atPath: pathToCache())
    }
    
    private static func pathToCache() -> String {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = cachesDirectory.appendingPathComponent("cache.txt")
        return url.path
    }
}
