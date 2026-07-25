//
//  ReportGroupsTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/24/26.
//

import XCTest
@testable import LocationApp

final class ReportGroupsTests: XCTestCase {

    //MARK: - Prefix parsing

    func test_prefix_stripsSuffixAfterLastDash() {
        XCTAssertEqual(ReportGroups.prefix(of: "BLG 025-010"), "BLG 025")
        XCTAssertEqual(ReportGroups.prefix(of: "ACC TNL-001"), "ACC TNL")
    }

    func test_prefix_dashlessCodeIsItsOwnPrefix() {
        XCTAssertEqual(ReportGroups.prefix(of: "ALPINE"), "ALPINE")
    }

    func test_suffixNumber_parsesDigitsIncludingLetterSuffix() {
        XCTAssertEqual(ReportGroups.suffixNumber(of: "GALRY-005A"), 5)
        XCTAssertEqual(ReportGroups.suffixNumber(of: "LCLS-136"), 136)
        XCTAssertEqual(ReportGroups.suffixNumber(of: "ALPINE"), -1)
        XCTAssertEqual(ReportGroups.suffixNumber(of: "BLG-X01"), -1)
    }

    //MARK: - Group lookup

    func test_group_exactMatchWinsOverFallback() {
        // BSY-001 is GALLERY even though the BSY prefix trends BSY
        XCTAssertEqual(ReportGroups.group(for: "BSY-001"), "GALLERY")
    }

    func test_group_unknownCodeWithKnownPrefix_inheritsPrefixGroup() {
        // The live case: Matt's new location 07/20 exported with a null group
        XCTAssertEqual(ReportGroups.group(for: "BLG 025-010"), "GEN")
    }

    func test_group_splitPrefixes_followHighestNumberedEntry() {
        XCTAssertEqual(ReportGroups.group(for: "GALRY-095"), "GEN")
        XCTAssertEqual(ReportGroups.group(for: "LCLS-137"), "LCLS")
        XCTAssertEqual(ReportGroups.group(for: "BSY-006"), "BSY")
    }

    func test_group_unknownPrefixReturnsNil() {
        XCTAssertNil(ReportGroups.group(for: "ZZTOP-001"))
        XCTAssertNil(ReportGroups.group(for: ""))
    }

    func test_groupsTable_valuesAreCaseConsistent() {
        // Locks the SUSB "Gen" -> "GEN" normalization
        let values = Set(Groups.values)
        let folded = Set(values.map { $0.lowercased() })
        XCTAssertEqual(values.count, folded.count)
    }

    //MARK: - Backfill helpers

    func test_resolvedGroup_sameQRCodeDonorWins() {
        XCTAssertEqual(ReportGroups.resolvedGroup(donor: "MANUAL", qrCode: "GALRY-095"), "MANUAL")
    }

    func test_resolvedGroup_fallsBackToLookup_thenNil() {
        XCTAssertEqual(ReportGroups.resolvedGroup(donor: nil, qrCode: "GALRY-095"), "GEN")
        XCTAssertEqual(ReportGroups.resolvedGroup(donor: "", qrCode: "GALRY-095"), "GEN")
        XCTAssertNil(ReportGroups.resolvedGroup(donor: nil, qrCode: "ZZTOP-001"))
    }

    func test_canonicalCaseFix_fixesCaseOnlyDifference() {
        XCTAssertEqual(ReportGroups.canonicalCaseFix(current: "Gen", qrCode: "SUSB-002"), "GEN")
    }

    func test_canonicalCaseFix_leavesExactValueAndManualOverridesAlone() {
        XCTAssertNil(ReportGroups.canonicalCaseFix(current: "GEN", qrCode: "SUSB-002"))
        XCTAssertNil(ReportGroups.canonicalCaseFix(current: "BSY", qrCode: "SUSB-002"))
        XCTAssertNil(ReportGroups.canonicalCaseFix(current: "GEN", qrCode: "ZZTOP-001"))
        XCTAssertNil(ReportGroups.canonicalCaseFix(current: nil, qrCode: "SUSB-002"))
    }
}
