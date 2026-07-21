//
//  SuperUserTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class SuperUserTests: XCTestCase {

    // MARK: - isEligibleForCycleDeletion (safety invariant)

    // Records from the most recent 4 cycles can never be deleted, even if
    // explicitly requested. deleteOldCycleRecords recomputes eligibility
    // itself rather than trusting the caller's list.

    func test_eligible_falseWhenCycleDateNil() throws {
        let item = try makeItem(recordName: "r1")

        XCTAssertFalse(LocationsCK.isEligibleForCycleDeletion(item: item, protectedCycles: ["1-1-2026"]),
                       "A record without a cycleDate can't be proven old; the conservative answer is keep")
    }

    func test_eligible_falseForEveryProtectedCycle() throws {
        let protectedCycles = RecordsUpdate.getLastCycles(cycles: 4)

        for cycle in protectedCycles {
            let item = try makeItem(recordName: "r1", cycleDate: cycle)
            XCTAssertFalse(LocationsCK.isEligibleForCycleDeletion(item: item, protectedCycles: protectedCycles),
                           "Cycle \(cycle) is within the most recent 4 and must never be deletable")
        }
    }

    func test_eligible_trueForCycleOlderThanProtectedWindow() throws {
        let protectedCycles = RecordsUpdate.getLastCycles(cycles: 4)
        let fifthCycleBack = RecordsUpdate.generatePriorCycleDate(cycleDate: protectedCycles.last!)
        let item = try makeItem(recordName: "r1", cycleDate: fifthCycleBack)

        XCTAssertTrue(LocationsCK.isEligibleForCycleDeletion(item: item, protectedCycles: protectedCycles),
                      "The 5th cycle back is outside the protected window and must be eligible")
    }

    // MARK: - getLastCycles (the protected-window source)

    func test_getLastCycles_returnsContiguousCyclesNewestFirst() {
        let cycles = RecordsUpdate.getLastCycles(cycles: 4)

        XCTAssertEqual(cycles.count, 4)
        XCTAssertEqual(cycles[0], RecordsUpdate.generateCycleDate(),
                       "The newest entry must be the current cycle")
        for cycle in cycles {
            XCTAssertTrue(cycle.hasPrefix("1-1-") || cycle.hasPrefix("7-1-"),
                          "Cycle keys use the exact \"M-1-YYYY\" format with M of 1 or 7; got \(cycle)")
        }
        for index in 1..<cycles.count {
            XCTAssertEqual(cycles[index], RecordsUpdate.generatePriorCycleDate(cycleDate: cycles[index - 1]),
                           "Each entry must be exactly one 6-month cycle older than the previous")
        }
    }

    // MARK: - Delete Old Cycles super-user gate (slice 4)

    // The destructive step stays locked unless BOTH interlocks hold: the
    // all-cycles export was emailed this session AND there is something old to
    // delete. Either alone must keep the delete button inert.
    func test_canDelete_requiresBothExportAndEligibleRecords() {
        XCTAssertTrue(DeleteOldCyclesViewController.canDelete(hasEmailedExport: true, eligibleRecordCount: 5),
                      "Armed: export sent and old records exist")
        XCTAssertFalse(DeleteOldCyclesViewController.canDelete(hasEmailedExport: false, eligibleRecordCount: 5),
                       "Locked: export not yet emailed")
        XCTAssertFalse(DeleteOldCyclesViewController.canDelete(hasEmailedExport: true, eligibleRecordCount: 0),
                       "Locked: nothing old to delete")
        XCTAssertFalse(DeleteOldCyclesViewController.canDelete(hasEmailedExport: false, eligibleRecordCount: 0),
                       "Locked: neither interlock satisfied")
    }

    // A negative count can never arm the gate (defensive — eligibleTotal can't
    // go negative today, but the gate must not depend on that).
    func test_canDelete_falseForNonPositiveCount() {
        XCTAssertFalse(DeleteOldCyclesViewController.canDelete(hasEmailedExport: true, eligibleRecordCount: -1))
    }

    // The type-DELETE confirmation must match EXACTLY: uppercase, no leading or
    // trailing whitespace, no near-misses. This is the last guard before a
    // permanent CloudKit deletion, so the rule is pinned by a test.
    func test_deleteIsConfirmed_requiresExactUppercaseDELETE() {
        XCTAssertTrue(DeleteOldCyclesViewController.deleteIsConfirmed(byTyping: "DELETE"))

        for rejected in ["delete", "Delete", "DELETE ", " DELETE", " DELETE ", "DELET", "DELETED", "", nil] {
            XCTAssertFalse(DeleteOldCyclesViewController.deleteIsConfirmed(byTyping: rejected),
                           "\(String(describing: rejected)) must not confirm a deletion")
        }
    }

    // The forced export must address the SLAC records-management group; a typo
    // here would silently send the audit trail to the wrong place.
    func test_exportRecipient_isTheRecordsManagementGroup() {
        XCTAssertEqual(DeleteOldCyclesViewController.exportRecipient, "esh-DREP@slac.stanford.edu")
    }

    // MARK: - Super-user passcode gate (shared by Reset Cache + Delete Old Cycles + Edit Record)

    // passcodeAccepted is the pure decision the shared gate consults. It must
    // accept only the exact configured passcode and reject empty, non-numeric,
    // or wrong input — the same check guards Reset Cache and Edit Record saves.
    func test_passcodeAccepted_trueOnlyForExactConfiguredValue() {
        XCTAssertTrue(SuperUserGate.passcodeAccepted(entered: "4299", configured: 4299))
        XCTAssertFalse(SuperUserGate.passcodeAccepted(entered: "4298", configured: 4299),
                       "A wrong passcode must not open the gate")
    }

    func test_passcodeAccepted_rejectsEmptyAndNonNumericInput() {
        for rejected in [nil, "", " ", "abc", "42x", "4299 "] {
            XCTAssertFalse(SuperUserGate.passcodeAccepted(entered: rejected, configured: 4299),
                           "\(String(describing: rejected)) must not open the gate")
        }
    }

    func test_passcodeAccepted_honorsRotatedPasscode() {
        // The configured value comes from settings.superUserPasscodeValue, which
        // CloudKit can rotate; the gate must follow it, not a hardcoded default.
        XCTAssertTrue(SuperUserGate.passcodeAccepted(entered: "8121", configured: 8121))
        XCTAssertFalse(SuperUserGate.passcodeAccepted(entered: "4299", configured: 8121),
                       "The old default must stop working once the passcode is rotated")
    }

    // Once-per-session unlock: the flag must be app-wide (a static), so it
    // survives LocationDetails being re-instantiated per navigation.
    func test_editRecordSavesUnlocked_isAppWideSessionFlag() {
        let original = SuperUserGate.editRecordSavesUnlocked
        defer { SuperUserGate.editRecordSavesUnlocked = original }

        SuperUserGate.editRecordSavesUnlocked = false
        XCTAssertFalse(SuperUserGate.editRecordSavesUnlocked)
        SuperUserGate.editRecordSavesUnlocked = true
        XCTAssertTrue(SuperUserGate.editRecordSavesUnlocked,
                      "Once unlocked, Edit Record saves stay unlocked for the rest of the session")
    }
}
