//
//  RecordItemTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class RecordItemTests: XCTestCase {

    // MARK: - uploadChanges item→record conversion (Day 4)

    // Day 4 moved the item.to() conversion out of saveChanges() and into
    // uploadChanges()'s paging loop (slice.map { $0.to() }). These lock down
    // the conversion the loop now depends on; Days 5-7 build the fetch-merge
    // on top of it.

    func test_to_buildsLocationRecordWithMatchingRecordID() throws {
        let record = try makeItem(recordName: "r1").to()

        XCTAssertEqual(record.recordType, "Location")
        XCTAssertEqual(record.recordID.recordName, "r1",
                       "uploadChanges builds the CKRecord from the cache item; the recordID must round-trip the item's recordName so the save targets the correct server record")
    }

    func test_to_copiesScalarFieldsOntoRecord() throws {
        let record = try makeItem(recordName: "r1", locdescription: "north gate").to()

        XCTAssertEqual(record["locdescription"] as? String, "north gate")
        XCTAssertEqual(record["QRCode"] as? String, "Q")
        XCTAssertEqual(record["latitude"] as? String, "0")
        XCTAssertEqual(record["longitude"] as? String, "0")
        XCTAssertEqual(record["active"] as? Int64, 0)
    }

    func test_to_mapsHasPhotoBoolToRecordInt() throws {
        let withPhoto = try makeItem(recordName: "r1", hasPhoto: true).to()
        let withoutPhoto = try makeItem(recordName: "r2", hasPhoto: false).to()

        XCTAssertEqual(withPhoto["hasPhoto"] as? Int, 1, "hasPhoto == true must serialize to 1")
        XCTAssertEqual(withoutPhoto["hasPhoto"] as? Int, 0, "hasPhoto == false must serialize to 0")
    }

    // MARK: - apply-onto-fetched merge (Day 7)

    // Day 7 flips uploadChanges' savePolicy from .allKeys to .ifServerRecordUnchanged
    // and, for records that exist on the server, applies local fields onto the
    // *fetched* CKRecord rather than building a fresh one via item.to(). This
    // preserves the server's recordChangeTag so CloudKit can reject the save when
    // another device modified the record between our fetch and save. These tests
    // lock the merge semantics that the new save path depends on.

    func test_update_overwritesServerFieldsWithItemFields() throws {
        // A server record with the "before" state of every field update() writes.
        let server = makeLocationRecord()
        let item = try makeItem(recordName: "r1", locdescription: "north gate")
        item.dosinumber = "D-NEW"
        item.collectedFlag = 1
        item.cycleDate = "1-1-2026"
        item.moderator = 1
        item.active = 0
        item.mismatch = 1
        item.modifiedBy = "spady"
        item.reportGroup = "group-7"

        item.update(newRecord: server)

        XCTAssertEqual(server["locdescription"] as? String, "north gate")
        XCTAssertEqual(server["QRCode"] as? String, "Q")
        XCTAssertEqual(server["latitude"] as? String, "0")
        XCTAssertEqual(server["longitude"] as? String, "0")
        XCTAssertEqual(server["active"] as? Int64, 0)
        XCTAssertEqual(server["dosinumber"] as? String, "D-NEW")
        XCTAssertEqual(server["collectedFlag"] as? Int64, 1)
        XCTAssertEqual(server["cycleDate"] as? String, "1-1-2026")
        XCTAssertEqual(server["moderator"] as? Int64, 1)
        XCTAssertEqual(server["mismatch"] as? Int64, 1)
        XCTAssertEqual(server["modifiedBy"] as? String, "spady")
        XCTAssertEqual(server["reportGroup"] as? String, "group-7")
        XCTAssertEqual(server["hasPhoto"] as? Int, 0)
    }

    func test_update_preservesFetchedRecordID() throws {
        // uploadChanges relies on update(newRecord:) mutating the *same* CKRecord
        // object it was handed — that's what carries the fetched recordChangeTag
        // through to the .ifServerRecordUnchanged save. If update() ever started
        // returning a new record (or replacing recordID), the conflict check
        // would silently fall back to a tag-less save.
        let server = CKRecord(recordType: "Location",
                              recordID: CKRecord.ID(recordName: "server-id-1"))
        server.setValue("Q-OLD", forKey: "QRCode")
        server.setValue("0", forKey: "latitude")
        server.setValue("0", forKey: "longitude")
        server.setValue("old", forKey: "locdescription")
        server.setValue(Int64(0), forKey: "active")

        let item = try makeItem(recordName: "client-cache-id", locdescription: "new")

        item.update(newRecord: server)

        XCTAssertEqual(server.recordID.recordName, "server-id-1",
                       "update(newRecord:) must mutate the fetched record in place; it must not replace recordID with the item's recordName, or .ifServerRecordUnchanged loses the fetched tag")
        XCTAssertEqual(server["locdescription"] as? String, "new",
                       "Field values still flow from item onto the fetched record")
    }

    // MARK: - createdDateForSort (nil-safe ordering key)

    func test_createdDateForSort_returnsCreatedDateWhenPresent() throws {
        // 0 seconds since the reference date == 2001-01-01 00:00:00 UTC.
        let item = try makeItem(recordName: "r1", createdDate: 0)
        XCTAssertEqual(item.createdDate, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(item.createdDateForSort, Date(timeIntervalSinceReferenceDate: 0),
                       "When createdDate is set, the sort key must equal it exactly")
    }

    func test_createdDateForSort_fallsBackToDistantPastWhenNil() throws {
        let item = try makeItem(recordName: "r1")
        XCTAssertNil(item.createdDate, "Fixture without createdDate must decode to nil")
        XCTAssertEqual(item.createdDateForSort, .distantPast,
                       "A nil createdDate must sort as the oldest possible date, not crash")
    }

    func test_createdDateForSort_sortsNilLastInNewestFirstOrder() throws {
        let newer = try makeItem(recordName: "r1", createdDate: 1000)
        let older = try makeItem(recordName: "r2", createdDate: 0)
        let undated = try makeItem(recordName: "r3")

        // Mirrors the UI sort comparators: descending by createdDateForSort.
        let sorted = [undated, older, newer].sorted { $0.createdDateForSort > $1.createdDateForSort }

        XCTAssertEqual(sorted.map { $0.recordName }, ["r1", "r2", "r3"],
                       "Newest first, with the nil-createdDate record sorted last")
    }

    // copy() must produce a DISTINCT instance with the same field values, and
    // mutating the copy must not touch the original. This is the invariant the
    // edit popup relies on so LocationsCK.save's already-collected guard sees the
    // record's true prior state instead of an in-place-mutated alias (QA-1 DEFECT-1):
    // before the fix the popup edited the cached record in place, flipping
    // collectedFlag to 1 before the guard ran, so a genuine collect was skipped.
    func test_copy_isDistinctInstanceAndDoesNotAliasOriginal() throws {
        let original = try makeItem(recordName: "R1", cycleDate: "1-1-2026")
        original.collectedFlag = 0
        original.dosinumber = "QA000000001"

        let copy = original.copy()

        XCTAssertFalse(copy === original, "copy must be a distinct instance")
        XCTAssertEqual(copy.recordName, "R1")
        XCTAssertEqual(copy.cycleDate, "1-1-2026")
        XCTAssertEqual(copy.collectedFlag, 0)
        XCTAssertEqual(copy.dosinumber, "QA000000001")

        // Mutating the copy (as the popup does on a collect) must not leak back.
        copy.collectedFlag = 1
        XCTAssertEqual(original.collectedFlag, 0, "copy must not alias the original")
    }
}
