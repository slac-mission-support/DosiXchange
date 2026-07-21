//
//  StartupScreenTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import CloudKit
import UIKit
@testable import LocationApp

class StartupScreenTests: XCTestCase {

    // MARK: - Refresh Count button wiring

    // Wired in the storyboard + viewDidLoad with no pure logic, so these load the
    // startup scene to check the button's outlet, title, and action and that the old
    // hidden tap is gone. Loading runs viewDidLoad; we stop the notifier right after.

    private func loadStartupViewController() throws -> StartupViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: StartupViewController.self))
        let controller = storyboard.instantiateViewController(withIdentifier: "Main")
        let startup = try XCTUnwrap(controller as? StartupViewController,
                                    "Main storyboard identifier \"Main\" should resolve to StartupViewController")
        startup.loadViewIfNeeded()
        startup.reachability.stopNotifier()
        return startup
    }

    func test_refreshCountButton_isConnectedAndCallsSetProgress() throws {
        let startup = try loadStartupViewController()

        let button = try XCTUnwrap(startup.refreshButton,
                                   "refreshButton outlet must be connected in Main.storyboard")
        XCTAssertEqual(button.title(for: .normal), "Refresh Count")

        let actions = button.actions(forTarget: startup, forControlEvent: .touchUpInside) ?? []
        XCTAssertTrue(actions.contains("setProgress"),
                      "Refresh Count button must trigger setProgress on touchUpInside")
    }

    func test_statusLabel_noLongerHasHiddenTapToRefresh() throws {
        let startup = try loadStartupViewController()

        XCTAssertTrue((startup.statusLabel.gestureRecognizers ?? []).isEmpty,
                      "the hidden tap-to-refresh gesture should be removed from the status label")
    }

    // MARK: - Sync warning (account visibility)

    // CloudKit reads work anonymously but writes need an iCloud account, so a
    // signed-out or wedged device failed every upload silently. The startup
    // screen now maps account status + queued-upload count to a visible warning.

    func test_accountWarningMessage_perStatus() {
        XCTAssertNil(StartupViewController.syncWarningMessage(accountStatus: .available, pendingChangeCount: 0),
                     "a healthy account with nothing queued needs no warning")
        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .noAccount, pendingChangeCount: 0),
                       "Sign in to iCloud in Settings — scans cannot upload.")
        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .restricted, pendingChangeCount: 0),
                       "iCloud is restricted on this device — scans cannot upload.")
        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .temporarilyUnavailable, pendingChangeCount: 0),
                       "iCloud needs attention — open Settings and accept any iCloud prompts.")
        XCTAssertNil(StartupViewController.syncWarningMessage(accountStatus: .couldNotDetermine, pendingChangeCount: 0),
                     "an indeterminate status with nothing queued is not worth alarming the user")
    }

    func test_pendingWarning_reflectsPendingChangeCount() {
        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .available, pendingChangeCount: 1),
                       "1 scan waiting to upload — will retry automatically.")
        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .available, pendingChangeCount: 43),
                       "43 scans waiting to upload — will retry automatically.")
        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .noAccount, pendingChangeCount: 43),
                       "Sign in to iCloud in Settings — 43 scans waiting to upload.")
        XCTAssertEqual(StartupViewController.syncWarningMessage(accountStatus: .couldNotDetermine, pendingChangeCount: 2),
                       "iCloud status unknown — 2 scans waiting to upload.")
    }

    func test_syncWarningLabel_installedAndHiddenUntilFirstSync() throws {
        let controller = try loadStartupViewController()
        XCTAssertNotNil(controller.syncWarningLabel.superview,
                        "the warning label must be installed in the startup view hierarchy")
        XCTAssertTrue(controller.syncWarningLabel.isHidden,
                      "no warning shows until a sync reports something wrong")
    }
}
