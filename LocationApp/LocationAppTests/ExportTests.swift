//
//  ExportTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class ExportTests: XCTestCase {

    // MARK: - buildDateString (auto-derived Tools build date)

    func test_buildDateString_formatsAsMonthCommaYear() {
        // 2023-05-15 12:00 UTC — mid-month, so no timezone boundary ambiguity.
        var components = DateComponents()
        components.year = 2023
        components.month = 5
        components.day = 15
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: components)!

        // Matches the "May, 2023" label this replaces (en_US test environment).
        XCTAssertEqual(ToolsViewController.buildDateString(from: date), "May, 2023")
    }

    // MARK: - CycleCSVExport (the forced all-cycles export before deletion)

    func test_csvHeader_matchesTheToolsExportColumns() {
        XCTAssertEqual(CycleCSVExport.header,
                       "LocationID (QRCode),Latitude,Longitude,Description,Moderator (0/1),Active (0/1),Dosimeter,Collected Flag (0/1),Wear Period,System_Date Deployed,System_Date Collected,RGD (0/1), my_Date Deployed, my_Date Collected, recordID, ModifiedBy, Report Group\n",
                       "Header must stay column-compatible with the Tools email export")
    }

    // Pins the Mismatch -> RGD relabel. Display-only: the exported column header
    // reads "RGD", but the backend CKRecord key stays "mismatch" (see the to()
    // round-trip test, which asserts server["mismatch"]).
    func test_csvHeader_usesRGDLabel() {
        XCTAssertTrue(CycleCSVExport.header.contains("RGD (0/1)"),
                      "Exported header should expose the column as \"RGD (0/1)\"")
    }

    func test_csvHeader_dropsOldMismatchLabel() {
        XCTAssertFalse(CycleCSVExport.header.contains("Mismatch"),
                       "The old \"Mismatch\" label must not appear in the exported header")
    }

    func test_row_rendersEveryFieldInColumnOrder() throws {
        let deployed = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 5))
        let modified = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 10))
        let json = """
        { "QRCode": "BLG 006-015", "latitude": "37.4", "longitude": "-122.2", \
        "locdescription": "Test Bldg", "active": 1, "dosinumber": "D123", \
        "collectedFlag": 1, "cycleDate": "1-1-2026", "mismatch": 0, "moderator": 1, \
        "creationDate": \(deployed.timeIntervalSinceReferenceDate), \
        "createdDate": \(deployed.timeIntervalSinceReferenceDate), \
        "modifiedDate": \(modified.timeIntervalSinceReferenceDate), \
        "modificationDate": \(modified.timeIntervalSinceReferenceDate), \
        "recordName": "rec-1", "modifiedBy": "tester", "reportGroup": "G1", \
        "hasPhoto": false }
        """
        let item = try JSONDecoder().decode(LocationRecordCacheItem.self, from: Data(json.utf8))

        XCTAssertEqual(CycleCSVExport.row(for: item),
                       "BLG 006-015,37.4,-122.2,\"Test Bldg\",1,1,D123,1,1-1-2026,06/05/2026,06/10/2026,0,06/05/2026,06/10/2026,rec-1,tester,\"G1\"\n",
                       "Description and Report Group cells are quoted so free text can't shift columns")
    }

    func test_row_rendersNilOptionalFieldsAsBlankCells() throws {
        // makeItem populates only the required fields; every optional is nil.
        // The Tools row builder force-unwrapped dates — this one must not.
        let item = try makeItem(recordName: nil)

        // Description is quoted ("test"); the nil Report Group is quoted-empty
        // ("\"\""); every other optional renders as a bare empty cell.
        let fields = ["Q", "0", "0", "\"test\"", "", "0",
                      "", "", "", "", "", "", "", "", "", "", "\"\""]
        XCTAssertEqual(CycleCSVExport.row(for: item),
                       fields.joined(separator: ",") + "\n",
                       "Nil optionals must render as empty cells, never crash or shift columns")
    }

    func test_csvText_sortsByQRCodeThenNewestDeployFirst() throws {
        let later = try makeItem(recordName: "rB", QRCode: "BLG 044")
        let olderDeploy = try makeItem(recordName: "rA-old", QRCode: "BLG 003", createdDate: 700_000_000)
        let newerDeploy = try makeItem(recordName: "rA-new", QRCode: "BLG 003", createdDate: 800_000_000)

        let text = CycleCSVExport.csvText(for: [later, olderDeploy, newerDeploy])
        let lines = text.components(separatedBy: "\n")

        XCTAssertTrue(lines[1].contains("rA-new"), "QRCode ascending, newest deploy first within a QRCode")
        XCTAssertTrue(lines[2].contains("rA-old"))
        XCTAssertTrue(lines[3].contains("rB"))
    }

    func test_csvText_includesDeletableRecordsTheToolsExportWouldDrop() throws {
        // A record with an old cycle but a nil createdDate is delete-eligible,
        // yet the Tools export filters on createdDate != nil and would omit it.
        // The pre-delete audit export must be a superset of anything deletable.
        let protectedCycles = RecordsUpdate.getLastCycles(cycles: 4)
        let fifthCycleBack = RecordsUpdate.generatePriorCycleDate(cycleDate: protectedCycles.last!)
        let item = try makeItem(recordName: "ghost-record", cycleDate: fifthCycleBack)

        XCTAssertTrue(LocationsCK.isEligibleForCycleDeletion(item: item, protectedCycles: protectedCycles),
                      "Precondition: this record must be deletable for the test to mean anything")
        XCTAssertTrue(CycleCSVExport.csvText(for: [item]).contains("ghost-record"),
                      "Every deletable record must appear in the audit export")
    }

    func test_csvText_beginsWithHeaderAndEndsWithEndOfFileMarker() throws {
        let text = CycleCSVExport.csvText(for: [try makeItem(recordName: "r1")])

        XCTAssertTrue(text.hasPrefix(CycleCSVExport.header))
        XCTAssertTrue(text.hasSuffix("End of File\n"))
        XCTAssertEqual(text.components(separatedBy: "\n").count, 4,
                       "Header + one row + End of File + the trailing newline's empty component")
    }

    // MARK: - Tools "email data" export nil-date crash

    // recordFetchedBlock builds each CSV line for the Tools "email data" export. It
    // used to force-unwrap the CKRecord system dates, which are nil for unsynced or
    // orphan records — one such record crashed the whole export. These pin nil-safety.

    func test_recordFetchedBlock_withNilSystemDates_doesNotCrashAndBlanksDateCells() throws {
        let tools = ToolsViewController()
        let record = try makeItem(recordName: "ghost-record")
        XCTAssertNil(record.creationDate, "Precondition: the record must lack a system creation date")
        XCTAssertNil(record.modificationDate, "Precondition: the record must lack a system modification date")

        tools.recordFetchedBlock(record: record) // must not crash on the missing dates

        // The row is produced (no crash), and the two system-date columns it used
        // to force-unwrap (9 = deployed, 10 = collected) render as blank cells.
        let cells = tools.csvText.components(separatedBy: ",")
        XCTAssertEqual(cells.count, 17, "The export row must keep all 17 columns even with missing dates")
        XCTAssertEqual(cells[0], "Q")
        XCTAssertEqual(cells[9], "", "A nil system deploy date must be a blank cell, not a crash")
        XCTAssertEqual(cells[10], "", "A nil system collected date must be a blank cell, not a crash")
        XCTAssertEqual(cells[14], "ghost-record", "The record ID column must still render")
    }

    func test_recordFetchedBlock_withSystemDates_rendersFormattedDates() throws {
        let deployed = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 5))
        let collected = try XCTUnwrap(noonLocal(year: 2026, month: 6, day: 10))
        let json = """
        { "QRCode": "BLG 006-015", "latitude": "37.4", "longitude": "-122.2", \
        "locdescription": "north gate", "active": 1, \
        "creationDate": \(deployed.timeIntervalSinceReferenceDate), \
        "modificationDate": \(collected.timeIntervalSinceReferenceDate), \
        "recordName": "rec-1", "hasPhoto": false }
        """
        let record = try JSONDecoder().decode(LocationRecordCacheItem.self, from: Data(json.utf8))

        let tools = ToolsViewController()
        tools.recordFetchedBlock(record: record)

        // Columns 9 and 10 are the system deploy/collected dates (MM/dd/yyyy).
        let cells = tools.csvText.components(separatedBy: ",")
        XCTAssertEqual(cells[9], "06/05/2026", "System deploy date must still render when present")
        XCTAssertEqual(cells[10], "06/10/2026", "System collected date must still render when present")
    }
}
