//
//  TestFixtures.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

// Shared fixture builders used across every test file in this target.
extension XCTestCase {

    /// Noon local time avoids DST-edge surprises when the exporter formats
    /// the date back in the current calendar.
    func noonLocal(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    /// A Location CKRecord with every field `init?(withRecord:)` needs, minus the
    /// photo CKAsset — i.e. what a record looks like after bulk-sync desiredKeys
    /// filtering. Pass `restrictedTo` to populate only a subset of fields.
    func makeLocationRecord(restrictedTo allowed: [String]? = nil) -> CKRecord {
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

    func makeItem(recordName: String?, QRCode: String = "Q", locdescription: String = "test", hasPhoto: Bool = false, cycleDate: String? = nil, createdDate: Double? = nil, creationDate: Double? = nil, modifiedDate: Double? = nil, modificationDate: Double? = nil) throws -> LocationRecordCacheItem {
        var fields: [String] = [
            "\"QRCode\": \"\(QRCode)\"",
            "\"latitude\": \"0\"",
            "\"longitude\": \"0\"",
            "\"locdescription\": \"\(locdescription)\"",
            "\"active\": 0",
            "\"hasPhoto\": \(hasPhoto)"
        ]
        if let recordName = recordName {
            fields.append("\"recordName\": \"\(recordName)\"")
        }
        if let cycleDate = cycleDate {
            fields.append("\"cycleDate\": \"\(cycleDate)\"")
        }
        // JSONDecoder's default .deferredToDate strategy decodes Date from a
        // Double (seconds since the reference date), so callers pass an interval.
        if let createdDate = createdDate {
            fields.append("\"createdDate\": \(createdDate)")
        }
        if let creationDate = creationDate {
            fields.append("\"creationDate\": \(creationDate)")
        }
        if let modifiedDate = modifiedDate {
            fields.append("\"modifiedDate\": \(modifiedDate)")
        }
        if let modificationDate = modificationDate {
            fields.append("\"modificationDate\": \(modificationDate)")
        }
        let json = "{ \(fields.joined(separator: ", ")) }"
        return try JSONDecoder().decode(LocationRecordCacheItem.self, from: Data(json.utf8))
    }

    /// A minimal "server-side" CKRecord populated only with the fields
    /// shouldSkipSave reads. Pass nil to omit a field entirely (CKRecord
    /// returns nil for unset keys, which is the case we want to assert on).
    func makeServerRecord(collectedFlag: Int64?, cycleDate: String?) -> CKRecord {
        let record = CKRecord(recordType: "Location")
        if let collectedFlag = collectedFlag {
            record.setValue(collectedFlag, forKey: "collectedFlag")
        }
        if let cycleDate = cycleDate {
            record.setValue(cycleDate, forKey: "cycleDate")
        }
        return record
    }

    func removeCacheFileOnDisk() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("cache.txt"))
    }
}
