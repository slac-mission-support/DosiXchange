//
//  AlertGalleryViewController.swift
//  LocationApp
//
//  Created by Daniel Spady on 6/18/26.
//

import UIKit

// A debug-only catalog of every scanner pop-up so the alerts can be QA'd on a
// device without walking the scan flow. Each row presents a placeholder copy whose
// handlers only dismiss, so nothing here touches CloudKit or the scan state.
final class AlertGalleryViewController: UIViewController {

    // Stand-in values for the runtime interpolations (dosiNumber / QRCode).
    private let dosi = "21111111116"
    private let qr = "BLG 044-004"

    private struct Demo {
        let name: String
        let make: () -> UIViewController
    }

    private struct Section {
        let title: String
        let demos: [Demo]
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var sections: [Section] = buildSections()

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) { overrideUserInterfaceStyle = .light }
        title = "Alert Gallery"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self,
                                                            action: #selector(close))
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func bundleImage(_ name: String, _ ext: String) -> UIImage? {
        guard let path = Bundle.main.path(forResource: name, ofType: ext) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    // Builds a PopupAlertController with handlers that only log, so tapping any
    // button is side-effect free.
    private func popup(title: String?,
                       message: String?,
                       image: UIImage? = nil,
                       background: String? = nil,
                       actions: [PopupAction]) -> UIViewController {
        let alert = PopupAlertController(title: title, message: message)
        if let image { alert.setImage(image) }
        if let background { alert.setBackgroundColor(UIColor(named: background)) }
        actions.forEach { alert.addAction($0) }
        return alert
    }

    private func buildSections() -> [Section] {
        let inlight = bundleImage("Inlight", "jpg")
        let qrImage = bundleImage("QRCodeImage", "png")

        let refactored = Section(title: "Refactored — new popup", demos: [
            Demo(name: "alert3 · Replace Dosimeter") { [self] in
                popup(title: "Replace Dosimeter",
                      message: "Please scan the new dosimeter for location \(qr).",
                      image: inlight,
                      actions: [PopupAction(title: "OK")])
            },
            Demo(name: "alert4 · Scan Accepted (scan location)") { [self] in
                popup(title: "Scan Accepted",
                      message: "Dosimeter barcode accepted \(dosi). Please scan the corresponding location code.",
                      image: qrImage,
                      actions: [PopupAction(title: "OK")])
            },
            Demo(name: "alert5 · Scan Accepted (scan dosimeter)") { [self] in
                popup(title: "Scan Accepted",
                      message: "Location code accepted \(qr). Please scan the corresponding dosimeter.",
                      image: inlight,
                      actions: [PopupAction(title: "OK")])
            },
            Demo(name: "alert6a · Error (scan location)") { [self] in
                popup(title: "Error",
                      message: "Try again...Please scan the corresponding location code.",
                      image: qrImage,
                      actions: [PopupAction(title: "OK", style: .cancel)])
            },
            Demo(name: "alert6b · Error (scan dosimeter)") { [self] in
                popup(title: "Error",
                      message: "Try again...Please scan the corresponding dosimeter.",
                      image: inlight,
                      actions: [PopupAction(title: "OK", style: .cancel)])
            },
            Demo(name: "alert7a · Duplicate Dosimeter") { [self] in
                popup(title: "Duplicate Dosimeter:\n\(dosi)",
                      message: "Try again...Please scan a new dosimeter.",
                      image: inlight,
                      actions: [PopupAction(title: "OK", style: .cancel)])
            },
            Demo(name: "alert7b · Location In Use") { [self] in
                popup(title: "Location In Use:\n\(qr)",
                      message: "Try again...Please scan a different location.",
                      image: qrImage,
                      actions: [PopupAction(title: "OK", style: .cancel)])
            },
            Demo(name: "alert13 · Warning (already exchanged)") { [self] in
                popup(title: "Warning",
                      message: "This dosimeter already exchanged in the current cycle. Are you sure you want to continue?",
                      background: "WarningDialogBackground",
                      actions: [PopupAction(title: "Continue", style: .destructive),
                                PopupAction(title: "Cancel", style: .cancel)])
            },
            Demo(name: "alert3a · Exchange Dosimeter (switch)") { [self] in
                let alert = PopupAlertController(title: "Exchange Dosimeter:\n\(dosi)\n\nLocation:\n\(qr)",
                                                 message: "\nCycle Date: 1-1-2026")
                alert.addSwitch(title: "RGD", isOn: false) { _ in }
                alert.addAction(PopupAction(title: "Exchange"))
                alert.addAction(PopupAction(title: "Cancel", style: .cancel))
                return alert
            },
            Demo(name: "alert3i · Collect Dosimeter (switch)") { [self] in
                let alert = PopupAlertController(title: "Collect Dosimeter:\n\(dosi)\n\nLocation:\n\(qr)",
                                                 message: "\nCycle Date: 1-1-2026")
                alert.addSwitch(title: "RGD", isOn: false) { _ in }
                alert.addAction(PopupAction(title: "Collect"))
                alert.addAction(PopupAction(title: "Cancel", style: .cancel))
                return alert
            },
            Demo(name: "alert8 · Deploy Dosimeter (text + 2 switches)") { [self] in
                let alert = PopupAlertController(title: "Deploy Dosimeter:\n\(dosi)", message: "\nLocation: \(qr)")
                alert.addTextField(text: "ryans office", placeholder: "Type or dictate location details") { _ in }
                alert.addSwitch(title: "Moderator", isOn: false) { _ in }
                alert.addSwitch(title: "RGD", isOn: false) { _ in }
                alert.addAction(PopupAction(title: "Add photo"))
                alert.addAction(PopupAction(title: "Save"))
                alert.addAction(PopupAction(title: "Cancel", style: .cancel))
                return alert
            },
            Demo(name: "Map · Filter legend (6 colored switches)") {
                let alert = PopupAlertController(title: nil, message: nil)
                alert.addSection(title: "Active")
                alert.addSwitch(title: "Current Cycle:", isOn: true, color: .red) { _ in }
                alert.addSwitch(title: "Prior Cycle:", isOn: true, color: .green) { _ in }
                alert.addSwitch(title: "No Dosimeter:", isOn: false, color: .orange) { _ in }
                alert.addSection(title: "Inactive")
                alert.addSwitch(title: "Current Cycle:", isOn: true, color: .purple) { _ in }
                alert.addSwitch(title: "Prior Cycle:", isOn: true, color: .blue) { _ in }
                alert.addSwitch(title: "No Dosimeter:", isOn: false, color: .yellow) { _ in }
                alert.addAction(PopupAction(title: "OK"))
                return alert
            }
        ])

        let stress = Section(title: "Popup layout stress tests", demos: [
            Demo(name: "Title only") { [self] in
                popup(title: "Title Only", message: nil, actions: [PopupAction(title: "OK")])
            },
            Demo(name: "Long message (should scroll)") { [self] in
                popup(title: "Long Message",
                      message: String(repeating: "This message is intentionally long so the card hits its height cap and the content scrolls instead of pushing the buttons off-screen. ", count: 6),
                      actions: [PopupAction(title: "OK")])
            },
            Demo(name: "Three actions") { [self] in
                popup(title: "Three Actions",
                      message: "Buttons should stack vertically with hairlines between them.",
                      actions: [PopupAction(title: "Option A"),
                                PopupAction(title: "Option B"),
                                PopupAction(title: "Cancel", style: .cancel)])
            },
            Demo(name: "Destructive + Cancel (no image)") { [self] in
                popup(title: "Delete?",
                      message: "Destructive should be red, Cancel should be bold.",
                      actions: [PopupAction(title: "Delete", style: .destructive),
                                PopupAction(title: "Cancel", style: .cancel)])
            },
            Demo(name: "Tall image + long message") { [self] in
                popup(title: "Image + Text",
                      message: "Image sits between the message and the buttons, capped at 90pt tall.",
                      image: inlight,
                      actions: [PopupAction(title: "OK")])
            }
        ])

        // Plain title/message/button alerts, now PopupAlertController too so the whole
        // scan flow shares one look. These have no images or switches to lay out.
        let simple = Section(title: "Refactored — simple alerts", demos: [
            Demo(name: "alert1 · Dosimeter Not Found") { [self] in
                popup(title: "Dosimeter Not Found:\n\(dosi)", message: nil,
                      actions: [PopupAction(title: "Deploy"),
                                PopupAction(title: "Cancel", style: .cancel)])
            },
            Demo(name: "alert2 · New Location (deploy/cancel)") { [self] in
                popup(title: "New Location:\n\(qr)", message: nil,
                      actions: [PopupAction(title: "Deploy"),
                                PopupAction(title: "Cancel", style: .cancel)])
            },
            Demo(name: "alert2a · Inactive Location") { [self] in
                popup(title: "Inactive Location:\n\(qr)",
                      message: "Please activate this location to deploy a dosimeter.",
                      actions: [PopupAction(title: "OK")])
            },
            Demo(name: "alert9 · Invalid Barcode Type") { [self] in
                popup(title: "Invalid Barcode Type",
                      message: "Please scan either a location barcode or a dosimeter.",
                      actions: [PopupAction(title: "OK", style: .cancel)])
            },
            Demo(name: "alert9a · Invalid Dosimeter") { [self] in
                popup(title: "Invalid Dosimeter:\n\(dosi)",
                      message: "This dosimeter has already been collected.",
                      actions: [PopupAction(title: "OK", style: .cancel)])
            },
            Demo(name: "alert10 · Save Successful") { [self] in
                popup(title: "Save Successful!", message: "QR Code: \(qr)\nDosimeter: \(dosi)",
                      actions: [PopupAction(title: "OK")])
            },
            Demo(name: "alert11 · Collection Successful") { [self] in
                popup(title: "Collection Successful!", message: "QR Code: \(qr)\nDosimeter: \(dosi)",
                      actions: [PopupAction(title: "OK")])
            },
            Demo(name: "alert12 · Invalid code (rescan)") { [self] in
                popup(title: "Invalid code", message: "Invalid barcode, please rescan!",
                      actions: [PopupAction(title: "Rescan")])
            },
            Demo(name: "alert14 · Invalid length (rescan)") { [self] in
                popup(title: "Invalid length",
                      message: "The length of the dosimeter barcodes must be 8 characters. Please rescan!",
                      actions: [PopupAction(title: "Rescan")])
            },
            Demo(name: "alert15 · GPS Coordinate Error") { [self] in
                popup(title: "GPS Coordinate Error",
                      message: "Your fix is not on SLAC property.  Please tap Try Again.",
                      actions: [PopupAction(title: "Try Again", style: .cancel)])
            },
            Demo(name: "Scanning not supported") { [self] in
                popup(title: "Scanning not supported",
                      message: "Your device does not support scanning a code from an item. Please use a device with a camera.",
                      actions: [PopupAction(title: "OK")])
            }
        ])

        return [refactored, simple, stress]
    }
}

extension AlertGalleryViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].demos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = sections[indexPath.section].demos[indexPath.row].name
        cell.textLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        present(sections[indexPath.section].demos[indexPath.row].make(), animated: true)
    }
}
