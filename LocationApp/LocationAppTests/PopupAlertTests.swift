//
//  PopupAlertTests.swift
//  LocationAppTests
//
//  Created by Daniel Spady on 7/21/26.
//

import XCTest
import UIKit
@testable import LocationApp

class PopupAlertTests: XCTestCase {

    // MARK: - PopupAlertController (custom cross-iOS alert)

    // Collects every UIButton in a view tree so a built popup can be inspected
    // without reaching into its private subviews.
    private func buttons(in view: UIView) -> [UIButton] {
        view.subviews.reduce(into: []) { result, subview in
            if let button = subview as? UIButton { result.append(button) }
            result.append(contentsOf: buttons(in: subview))
        }
    }

    func test_popupAction_storesItsFieldsAndDefaultsToNormalStyle() {
        var fired = false
        let action = PopupAction(title: "OK") { fired = true }

        XCTAssertEqual(action.title, "OK")
        XCTAssertEqual(action.style, .normal, "Style should default to .normal when omitted")

        action.handler?()
        XCTAssertTrue(fired, "Invoking the stored handler should run the closure")
    }

    func test_popup_buildsOneButtonPerActionInOrder() {
        let popup = PopupAlertController(title: "Title", message: "Message")
        popup.addAction(PopupAction(title: "Cancel", style: .cancel))
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        let titles = buttons(in: popup.view).map { $0.title(for: .normal) }
        XCTAssertEqual(titles, ["Cancel", "OK"],
                       "Each PopupAction should render one button, in the order added")
    }

    // The simple scanner alerts (alert1/alert2 etc.) are now PopupAlertControllers
    // with a title, no message, and two buttons. A nil message must not drop the
    // title or the buttons — guards the native-alert conversion.
    func test_popup_titleOnlyWithTwoActionsBuildsBothButtonsAndTitle() {
        let popup = PopupAlertController(title: "Dosimeter Not Found:\n21111111116", message: nil)
        popup.addAction(PopupAction(title: "Deploy"))
        popup.addAction(PopupAction(title: "Cancel", style: .cancel))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let titles = buttons(in: popup.view).map { $0.title(for: .normal) }
        XCTAssertEqual(titles, ["Deploy", "Cancel"],
                       "A title-only popup should still build both buttons in order")
        let hasTitle = labels(in: popup.view).contains { ($0.text ?? "").hasPrefix("Dosimeter Not Found") }
        XCTAssertTrue(hasTitle, "The title must render even when the message is nil")
    }

    func test_popup_buildsWithASingleActionAndImage() {
        let popup = PopupAlertController(title: "Scan Accepted", message: "Please scan.")
        popup.setImage(UIImage())
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(buttons(in: popup.view).count, 1,
                       "A single-action popup with an image should still build exactly one button")
    }

    // Finds the popup's rounded card — the view setBackgroundColor tints — by its
    // distinctive corner radius, so the test never touches a private property.
    private func cardView(in view: UIView) -> UIView? {
        if view.layer.cornerRadius == 13.5 { return view }
        for subview in view.subviews {
            if let found = cardView(in: subview) { return found }
        }
        return nil
    }

    func test_popup_defaultsToSystemBackgroundWhenNoColorSet() {
        let popup = PopupAlertController(title: "Title", message: "Message")
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(cardView(in: popup.view)?.backgroundColor, .systemBackground,
                       "The card should use the system background when no color is set")
    }

    func test_popup_setBackgroundColorTintsTheCard() {
        let popup = PopupAlertController(title: "Warning", message: "Message")
        popup.setBackgroundColor(.yellow)
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(cardView(in: popup.view)?.backgroundColor, .yellow,
                       "setBackgroundColor should tint the card, replacing the old private-subview hack")
    }

    func test_popup_setBackgroundColorIgnoresNil() {
        let popup = PopupAlertController(title: "Warning", message: "Message")
        popup.setBackgroundColor(nil)
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(cardView(in: popup.view)?.backgroundColor, .systemBackground,
                       "Passing nil should leave the default system background intact")
    }

    // Collects every UILabel in a view tree so a laid-out popup can be inspected.
    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.reduce(into: []) { result, subview in
            if let label = subview as? UILabel { result.append(label) }
            result.append(contentsOf: labels(in: subview))
        }
    }

    // Regression for the zero-height scroll view: the title/message sit in a
    // UIScrollView that collapsed to 0pt and clipped them. After a real layout
    // pass the title and message must have non-zero height.
    func test_popup_titleAndMessageLayOutWithNonZeroHeight() {
        let popup = PopupAlertController(title: "Scan Accepted",
                                         message: "Please scan the corresponding location code.")
        popup.addAction(PopupAction(title: "OK"))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let content = labels(in: popup.view).filter {
            $0.text == "Scan Accepted" || ($0.text?.hasPrefix("Please scan") ?? false)
        }
        XCTAssertEqual(content.count, 2, "Both the title and message labels should be present")
        for label in content {
            XCTAssertGreaterThan(label.bounds.height, 0,
                                 "\"\(label.text ?? "")\" must lay out with non-zero height; a collapsed scroll view clips it")
        }
    }

    // The popup pins to light so the card stays a known light background in any
    // device mode — both for cross-mode consistency and so transparent-background
    // images (e.g. the black-on-alpha QRCodeImage) don't vanish on a dark card.
    func test_popup_pinsToLightAppearance() {
        let popup = PopupAlertController(title: "Title", message: "Message")
        popup.addAction(PopupAction(title: "OK"))
        popup.loadViewIfNeeded()

        XCTAssertEqual(popup.overrideUserInterfaceStyle, .light,
                       "PopupAlertController should force light appearance")
    }

    private func switches(in view: UIView) -> [UISwitch] {
        view.subviews.reduce(into: []) { result, subview in
            if let toggle = subview as? UISwitch { result.append(toggle) }
            result.append(contentsOf: switches(in: subview))
        }
    }

    // The switch row (RGD on Exchange/Collect) must reflect the initial state
    // and report flips, since that drives variables.mismatch in the scanner flow.
    func test_popup_switchRowReflectsInitialStateAndReportsChanges() {
        var reported: Bool?
        let popup = PopupAlertController(title: "Exchange", message: "Cycle")
        popup.addSwitch(title: "Mismatch", isOn: true) { reported = $0 }
        popup.addAction(PopupAction(title: "Exchange"))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let found = switches(in: popup.view)
        XCTAssertEqual(found.count, 1, "addSwitch should render exactly one UISwitch")
        XCTAssertEqual(found.first?.isOn, true, "The switch should reflect the initial isOn state")

        found.first?.isOn = false
        found.first?.sendActions(for: .valueChanged)
        XCTAssertEqual(reported, false, "Flipping the switch should fire onChange with the new value")
    }

    private func textFields(in view: UIView) -> [UITextField] {
        view.subviews.reduce(into: []) { result, subview in
            if let field = subview as? UITextField { result.append(field) }
            result.append(contentsOf: textFields(in: subview))
        }
    }

    // The text-field row (deploy location) must prefill from the initial value and
    // report edits, since the scanner relies on that to track variables.dosiLocation.
    func test_popup_textFieldReflectsInitialTextAndReportsEdits() {
        var reported: String?
        let popup = PopupAlertController(title: "Deploy", message: nil)
        popup.addTextField(text: "ryans office", placeholder: "Location") { reported = $0 }
        popup.addAction(PopupAction(title: "Save"))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let fields = textFields(in: popup.view)
        XCTAssertEqual(fields.count, 1, "addTextField should render exactly one UITextField")
        XCTAssertEqual(fields.first?.text, "ryans office", "The field should prefill with the initial text")

        fields.first?.text = "lab 12"
        fields.first?.sendActions(for: .editingChanged)
        XCTAssertEqual(reported, "lab 12", "Editing should report the new text via onChange")
    }

    // The Deploy popup (alert8) carries two independent switch rows — Moderator
    // (variables.moderator) and RGD (variables.mismatch) — each reporting only its
    // own flips; a cross-wire would corrupt the other field. Order matches alert8.
    func test_popup_twoSwitchesAreIndependent() {
        var moderatorReported: Bool?
        var rgdReported: Bool?
        let popup = PopupAlertController(title: "Deploy Dosimeter:", message: "\nLocation: BLG 044-004")
        popup.addTextField(text: "ryans office", placeholder: "Location") { _ in }
        popup.addSwitch(title: "Moderator", isOn: false) { moderatorReported = $0 }
        popup.addSwitch(title: "RGD", isOn: true) { rgdReported = $0 }
        popup.addAction(PopupAction(title: "Save"))
        popup.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        popup.view.layoutIfNeeded()

        let found = switches(in: popup.view)
        XCTAssertEqual(found.count, 2, "Deploy should render exactly two UISwitches")
        XCTAssertEqual(found.first?.isOn, false, "Moderator should reflect its initial off state")
        XCTAssertEqual(found.last?.isOn, true, "RGD should reflect its initial on state")

        found.first?.isOn = true
        found.first?.sendActions(for: .valueChanged)
        XCTAssertEqual(moderatorReported, true, "Flipping Moderator should fire only its onChange")
        XCTAssertNil(rgdReported, "Flipping Moderator must not fire RGD's onChange")

        found.last?.isOn = false
        found.last?.sendActions(for: .valueChanged)
        XCTAssertEqual(rgdReported, false, "Flipping RGD should fire its onChange with the new value")
        XCTAssertEqual(moderatorReported, true, "RGD's flip must not disturb the Moderator value")
    }
}
