//
//  ManagedAppConfigTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
@testable import LocationApp

class ManagedAppConfigTests: XCTestCase {

    // MARK: - ManagedAppConfig (JAMF managed username)

    func test_username_readsConfiguredKey() {
        let config: [String: Any] = [ManagedAppConfig.usernameKey: "Jane Tech"]
        XCTAssertEqual(ManagedAppConfig.username(from: config), "Jane Tech")
    }

    func test_username_trimsWhitespace() {
        let config: [String: Any] = [ManagedAppConfig.usernameKey: "  Jane Tech \n"]
        XCTAssertEqual(ManagedAppConfig.username(from: config), "Jane Tech")
    }

    func test_username_blankWhenPayloadMissing() {
        XCTAssertEqual(ManagedAppConfig.username(from: nil), "")
    }

    func test_username_blankWhenKeyAbsent() {
        let config: [String: Any] = ["someOtherKey": "value"]
        XCTAssertEqual(ManagedAppConfig.username(from: config), "")
    }

    func test_username_blankWhenValueNotString() {
        let config: [String: Any] = [ManagedAppConfig.usernameKey: 42]
        XCTAssertEqual(ManagedAppConfig.username(from: config), "")
    }
}
