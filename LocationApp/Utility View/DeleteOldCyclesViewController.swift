//
//  DeleteOldCyclesViewController.swift
//  LocationApp
//
//  Created by Daniel Spady on 6/11/26.
//

import Foundation
import UIKit
import MessageUI
import AVFoundation

//MARK:  Class

//Super-user admin screen, reached from Tools behind the passcode gate.
//Shows what a delete would affect (protected cycles, older cycles with
//record counts) and the required first step: emailing a full all-cycles
//export. Deleting stays locked until that export has actually been sent.
class DeleteOldCyclesViewController: UIViewController {

    let locations = container.locations

    //The latest 4 cycles (2 years) are protected absolutely.
    //deleteOldCycleRecords recomputes this itself — this only drives the preview.
    static let cyclesToKeep = 4

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var protectedCycles: [String] = []
    //Older cycles that still have records, newest first, with per-cycle counts.
    private var eligibleCycleCounts: [(cycle: String, count: Int)] = []
    private var eligibleTotal = 0

    //Flips only when the mail sheet reports the export was sent — the
    //delete step (next update) keys off this, so cancel/draft don't count.
    private(set) var hasEmailedExport = false
    private var exportedRecordCount = 0

    //MARK:  View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Delete Old Cycles"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self,
                                                            action: #selector(done))

        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        reloadPreview()
    }

    @objc func done() {
        self.dismiss(animated: true, completion: nil)
    }

    //MARK:  Preview

    func reloadPreview() {
        protectedCycles = RecordsUpdate.getLastCycles(cycles: DeleteOldCyclesViewController.cyclesToKeep)

        let eligible = locations.eligibleOldCycleRecords(keepingCycles: DeleteOldCyclesViewController.cyclesToKeep)
        eligibleTotal = eligible.count

        var counts: [String: Int] = [:]
        for item in eligible {
            //eligibleOldCycleRecords never returns a nil cycleDate, but stay
            //defensive — an unexpected record lands in its own bucket rather
            //than crashing the admin screen.
            let cycle = item.cycleDate ?? "No cycle date"
            counts[cycle, default: 0] += 1
        }
        eligibleCycleCounts = counts
            .map { (cycle: $0.key, count: $0.value) }
            .sorted { sortKey(for: $0.cycle) > sortKey(for: $1.cycle) }

        print("Super-user screen: \(eligibleTotal) records in \(eligibleCycleCounts.count) old cycles eligible; protected cycles: \(protectedCycles)")
        tableView.reloadData()
    }

    //Orders "M-1-YYYY" cycle keys chronologically (year first, then month).
    //A plain string sort would put "7-1-2024" after "1-1-2025".
    private func sortKey(for cycle: String) -> Int {
        let parts = cycle.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[0]),
              let year = Int(parts[2]) else { return Int.min }
        return year * 100 + month
    }

    //MARK:  All-cycles export email

    func emailAllCyclesExport() {
        guard MFMailComposeViewController.canSendMail() else {
            let alert = UIAlertController(title: "Mail Not Set Up",
                                          message: "This device cannot send email. Set up a Mail account, then return here — the export must be emailed before anything can be deleted.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true)
            return
        }

        //Every cached record, all cycles — a superset of anything deletable.
        let items = locations.filter(by: { _ in true })
        let csv = CycleCSVExport.csvText(for: items)
        exportedRecordCount = items.count

        let protectedList = protectedCycles.joined(separator: ", ")
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = self
        mail.setSubject("Area Dosimeter Data - Full Export (All Cycles)")
        mail.setMessageBody("Attached is a full export of all \(items.count) location records across all cycles, generated before deleting old cycles. Protected cycles: \(protectedList). Eligible for deletion: \(eligibleTotal) records in \(eligibleCycleCounts.count) older cycles.", isHTML: false)
        mail.addAttachmentData(Data(csv.utf8), mimeType: "text/csv", fileName: "Dosi_Data_All_Cycles.csv")
        present(mail, animated: true)

        print("Delete Old Cycles: composing all-cycles export, \(items.count) records")
    }
}

//MARK:  Mail compose delegate

extension DeleteOldCyclesViewController: MFMailComposeViewControllerDelegate {

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)

        switch result {
        case .sent:
            hasEmailedExport = true
            //Same sent sound as the Tools email export.
            let systemSoundID: SystemSoundID = 1001
            AudioServicesPlaySystemSound(systemSoundID)
            print("Delete Old Cycles: all-cycles export emailed (\(exportedRecordCount) records)")
            tableView.reloadData()
        case .failed:
            print("Delete Old Cycles: export email failed: \(String(describing: error))")
            let alert = UIAlertController(title: "Export Not Sent",
                                          message: "The export email could not be sent. Deleting stays locked until an export is emailed successfully.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true)
        default:
            //Cancelled or saved as draft — the export gate stays locked.
            print("Delete Old Cycles: export email not sent (result \(result.rawValue))")
        }
    }
}

//MARK:  Table data source

extension DeleteOldCyclesViewController: UITableViewDataSource {

    //Sections: 0 protected cycles, 1 eligible cycles, 2 the export step.
    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Protected — latest \(DeleteOldCyclesViewController.cyclesToKeep) cycles"
        }
        if section == 1 {
            return "Older cycles eligible for deletion"
        }
        return "Step 1 — Export all cycles"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return "Records in these cycles can never be deleted."
        }
        if section == 1 {
            if eligibleTotal == 0 {
                return "No records older than the protected cycles were found."
            }
            return "\(eligibleTotal) records total. Deleting requires a fresh export of all cycles first — Step 1 below."
        }
        if hasEmailedExport {
            return "Export emailed — \(exportedRecordCount) records attached. The delete step arrives in the next update."
        }
        return "Emails a CSV of every record in every cycle. Required before anything can be deleted."
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return protectedCycles.count
        }
        if section == 1 {
            return max(eligibleCycleCounts.count, 1)
        }
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cycleCell")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "cycleCell")
        cell.textLabel?.textColor = .label
        cell.selectionStyle = .none

        if indexPath.section == 0 {
            cell.textLabel?.text = protectedCycles[indexPath.row]
            cell.detailTextLabel?.text = "Protected"
            cell.detailTextLabel?.textColor = .secondaryLabel
            return cell
        }

        if indexPath.section == 2 {
            cell.textLabel?.text = "Email All-Cycles Export"
            cell.textLabel?.textColor = view.tintColor
            cell.detailTextLabel?.text = hasEmailedExport ? "Sent ✓" : "Required"
            cell.detailTextLabel?.textColor = hasEmailedExport ? .systemGreen : .secondaryLabel
            cell.selectionStyle = .default
            return cell
        }

        guard !eligibleCycleCounts.isEmpty else {
            cell.textLabel?.text = "Nothing to delete"
            cell.detailTextLabel?.text = nil
            return cell
        }

        let entry = eligibleCycleCounts[indexPath.row]
        cell.textLabel?.text = entry.cycle
        cell.detailTextLabel?.text = "\(entry.count) record\(entry.count == 1 ? "" : "s")"
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }
}

//MARK:  Table delegate

extension DeleteOldCyclesViewController: UITableViewDelegate {

    //Only the export row is actionable; the cycle lists stay read-only.
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return indexPath.section == 2 ? indexPath : nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        emailAllCyclesExport()
    }
}
