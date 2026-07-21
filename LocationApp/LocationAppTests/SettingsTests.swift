//
//  SettingsTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class SettingsTests: XCTestCase {

    // MARK: - Settings fallback coordinates (offline scan, no GPS fix)

    // Field devices have a cached Settings JSON written before the coordinate
    // fields existed; it must stay decodable (the fields are optional) and the
    // accessor must fall back to the built-in coordinate.
    func test_settingsDecode_withoutCoordinateFields_succeedsAndUsesFallback() throws {
        let oldFormat = #"{"dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(oldFormat.utf8))

        XCTAssertNil(settings.defaultLatitude)
        XCTAssertNil(settings.defaultLongitude)
        XCTAssertEqual(settings.defaultCoordinates.coordinate.latitude, 37.41927542738301, accuracy: 0.000001)
        XCTAssertEqual(settings.defaultCoordinates.coordinate.longitude, -122.20517033784913, accuracy: 0.000001)
    }

    func test_settingsDecode_withCoordinateFields_usesConfiguredValues() throws {
        let configured = #"{"dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11, "defaultLatitude": 37.5, "defaultLongitude": -122.5}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(configured.utf8))

        XCTAssertEqual(settings.defaultCoordinates.coordinate.latitude, 37.5, accuracy: 0.000001)
        XCTAssertEqual(settings.defaultCoordinates.coordinate.longitude, -122.5, accuracy: 0.000001)
    }

    func test_defaultCoordinates_fallsBackPerAxisWhenPartiallyConfigured() {
        // Only one field set in CloudKit (a half-finished edit of the Settings
        // record) must not zero the other axis.
        let settings = Settings()
        settings.defaultLatitude = 37.5

        XCTAssertEqual(settings.defaultCoordinates.coordinate.latitude, 37.5, accuracy: 0.000001)
        XCTAssertEqual(settings.defaultCoordinates.coordinate.longitude, -122.20517033784913, accuracy: 0.000001)
    }

    func test_settings_roundTripPreservesCoordinateFields() throws {
        let settings = Settings()
        settings.defaultLatitude = 37.5
        settings.defaultLongitude = -122.5

        let data = try JSONEncoder().encode(settings)
        let reloaded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(reloaded.defaultLatitude, 37.5)
        XCTAssertEqual(reloaded.defaultLongitude, -122.5)
    }

    // MARK: - Settings super-user passcode (delete-old-cycles gate)

    // Same decode-compatibility invariant as the coordinate fields: cached
    // Settings JSON written before the passcode field existed must still
    // decode, with the accessor falling back to the initial passcode.
    func test_settingsDecode_withoutPasscodeField_succeedsAndUsesFallback() throws {
        let oldFormat = #"{"dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(oldFormat.utf8))

        XCTAssertNil(settings.superUserPasscode)
        XCTAssertEqual(settings.superUserPasscodeValue, 4299)
    }

    func test_settingsDecode_withPasscodeField_usesConfiguredValue() throws {
        // A rotated passcode set on the CloudKit Settings record must win over
        // the built-in initial value.
        let configured = #"{"dosimeterMinimumLength": 11, "dosimeterMaximumLength": 11, "superUserPasscode": 8121}"#

        let settings = try JSONDecoder().decode(Settings.self, from: Data(configured.utf8))

        XCTAssertEqual(settings.superUserPasscodeValue, 8121)
    }

    func test_settings_roundTripPreservesPasscode() throws {
        let settings = Settings()
        settings.superUserPasscode = 8121

        let data = try JSONEncoder().encode(settings)
        let reloaded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(reloaded.superUserPasscode, 8121)
    }
}
