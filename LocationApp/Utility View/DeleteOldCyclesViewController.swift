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
//Shows what a delete would affect, then forces an all-cycles export first:
//deleting stays locked until that export has actually been sent.
class DeleteOldCyclesViewController: UIViewController {

    let locations = container.locations

    //The latest 4 cycles (2 years) are protected absolutely.
    //deleteOldCycleRecords recomputes this itself — this only drives the preview.
    static let cyclesToKeep = 4

    //The records-management group the all-cycles export must go to.
    static let exportRecipient = "esh-DREP@slac.stanford.edu"

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var protectedCycles: [String] = []
    //Older cycles that still have records, newest first, with per-cycle counts.
    private var eligibleCycleCounts: [(cycle: String, count: Int)] = []
    private var eligibleTotal = 0

    //Flips only when the mail sheet reports the export was sent — the
    //delete step (next update) keys off this, so cancel/draft don't count.
    private(set) var hasEmailedExport = false
    private var exportedRecordCount = 0

    //Held while a delete is running so progress callbacks can update its
    //message; also guards against starting a second delete on top of one.
    private var deleteProgressAlert: UIAlertController?

    //Watches the type-DELETE field; removed when the confirm alert closes.
    private var deleteConfirmObserver: NSObjectProtocol?

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
        mail.setToRecipients([DeleteOldCyclesViewController.exportRecipient])
        mail.setSubject("Area Dosimeter Data - Full Export (All Cycles)")
        mail.setMessageBody("Attached is a full export of all \(items.count) location records across all cycles, generated before deleting old cycles. Protected cycles: \(protectedList). Eligible for deletion: \(eligibleTotal) records in \(eligibleCycleCounts.count) older cycles.", isHTML: false)
        mail.addAttachmentData(Data(csv.utf8), mimeType: "text/csv", fileName: "Dosi_Data_All_Cycles.csv")
        present(mail, animated: true)

        print("Delete Old Cycles: composing all-cycles export, \(items.count) records")
    }

    //MARK:  Delete step

    //Both interlocks for the destructive step: export emailed this session and
    //something old to delete. Data layer recomputes eligibility too, so this is
    //the UI gate. Static + pure so LocationAppTests can drive it offline.
    static func canDelete(hasEmailedExport: Bool, eligibleRecordCount: Int) -> Bool {
        return hasEmailedExport && eligibleRecordCount > 0
    }

    //Text typed into the confirmation field must read exactly "DELETE" — no
    //surrounding whitespace, no case folding — so a stray tap can't wipe old
    //cycles. Pure so the exact-match rule is locked down by a unit test.
    static func deleteIsConfirmed(byTyping text: String?) -> Bool {
        return text == "DELETE"
    }

    //Whether the destructive Step 2 row should act, for the current UI state.
    var canDelete: Bool {
        return DeleteOldCyclesViewController.canDelete(hasEmailedExport: hasEmailedExport,
                                                       eligibleRecordCount: eligibleTotal)
    }

    //Type-DELETE confirmation. The destructive action stays disabled until the
    //field reads exactly "DELETE", so a stray tap can't wipe old cycles.
    func confirmDelete() {
        guard canDelete else { return }

        let recordWord = eligibleTotal == 1 ? "Record" : "Records"
        let cycleCount = eligibleCycleCounts.count
        let cycleWord = cycleCount == 1 ? "cycle" : "cycles"
        let alert = UIAlertController(title: "Delete \(eligibleTotal) Old \(recordWord)?",
                                      message: "This permanently removes every record in the \(cycleCount) older \(cycleWord) from CloudKit. It cannot be undone. Type DELETE to confirm.",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.autocapitalizationType = .allCharacters
            field.autocorrectionType = .no
        }

        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [weak self, weak alert] _ in
            self?.stopWatchingDeleteField()
            guard DeleteOldCyclesViewController.deleteIsConfirmed(byTyping: alert?.textFields?.first?.text) else { return }
            self?.runDelete()
        }
        deleteAction.isEnabled = false
        alert.addAction(deleteAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.stopWatchingDeleteField()
        })

        //Enable Delete only on an exact match — no trimming, no case folding.
        deleteConfirmObserver = NotificationCenter.default.addObserver(
            forName: UITextField.textDidChangeNotification,
            object: alert.textFields?.first,
            queue: .main) { [weak deleteAction] notification in
            let text = (notification.object as? UITextField)?.text
            deleteAction?.isEnabled = DeleteOldCyclesViewController.deleteIsConfirmed(byTyping: text)
        }

        present(alert, animated: true)
    }

    private func stopWatchingDeleteField() {
        if let observer = deleteConfirmObserver {
            NotificationCenter.default.removeObserver(observer)
            deleteConfirmObserver = nil
        }
    }

    private func runDelete() {
        //One delete at a time: a live progress alert means one is already
        //running, so ignore any second trigger.
        guard deleteProgressAlert == nil else { return }

        //Non-dismissible progress alert. The message stays generic until the
        //first per-batch callback supplies the data layer's own total, so it
        //never shows a stale count from the last preview.
        let progressAlert = UIAlertController(title: "Deleting…",
                                              message: "Preparing…",
                                              preferredStyle: .alert)
        deleteProgressAlert = progressAlert
        present(progressAlert, animated: true)

        print("Delete Old Cycles: starting delete of \(eligibleTotal) eligible records")

        locations.deleteOldCycleRecords(keepingCycles: DeleteOldCyclesViewController.cyclesToKeep,
                                        progress: { [weak self] deleted, total in
            self?.deleteProgressAlert?.message = "\(deleted) of \(total) deleted"
        }, completion: { [weak self] deleted, error in
            self?.finishDelete(deleted: deleted, error: error)
        })
    }

    private func finishDelete(deleted: Int, error: Error?) {
        //Refresh counts first so the preview (and the canDelete gate) reflect
        //what's actually left after the deletion.
        reloadPreview()

        let result: UIAlertController
        if let error = error {
            print("Delete Old Cycles: finished with error after \(deleted) deletions: \(error.localizedDescription)")
            result = UIAlertController(title: "Deletion Stopped",
                                       message: "\(deleted) record\(deleted == 1 ? "" : "s") deleted before stopping.\n\n\(error.localizedDescription)",
                                       preferredStyle: .alert)
        } else {
            print("Delete Old Cycles: finished, \(deleted) records deleted")
            result = UIAlertController(title: "Deletion Complete",
                                       message: "\(deleted) old-cycle record\(deleted == 1 ? "" : "s") deleted.",
                                       preferredStyle: .alert)
        }
        result.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        //Tear down the progress alert, then surface the outcome.
        if let progress = deleteProgressAlert {
            deleteProgressAlert = nil
            progress.dismiss(animated: true) { [weak self] in
                self?.present(result, animated: true)
            }
        } else {
            present(result, animated: true)
        }
    }
}

//MARK:  Mail compose delegate

extension DeleteOldCyclesViewController: MFMailComposeViewControllerDelegate {

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)

        switch result {
        case .sent:
            hasEmailedExport = true
            //Play the "sent" sound only on iOS 26+: the redesigned Mail sheet no
            //longer plays its own there, while older iOS does (gating avoids a double).
            if #available(iOS 26.0, *) {
                AudioServicesPlaySystemSound(1001)
            }
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

    //Sections: 0 protected cycles, 1 eligible cycles, 2 export step, 3 delete step.
    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Protected — latest \(DeleteOldCyclesViewController.cyclesToKeep) cycles"
        }
        if section == 1 {
            return "Older cycles eligible for deletion"
        }
        if section == 2 {
            return "Step 1 — Export all cycles"
        }
        return "Step 2 — Delete old cycles"
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
        if section == 2 {
            if hasEmailedExport {
                return "Export emailed — \(exportedRecordCount) records attached. Step 2 is now unlocked."
            }
            return "Emails a CSV of every record in every cycle to \(DeleteOldCyclesViewController.exportRecipient). Required before anything can be deleted."
        }
        if !hasEmailedExport {
            return "Email the export above first — this step stays locked until it has been sent."
        }
        if eligibleTotal == 0 {
            return "Nothing to delete."
        }
        return "Permanently deletes \(eligibleTotal) record\(eligibleTotal == 1 ? "" : "s") in \(eligibleCycleCounts.count) older cycles from CloudKit. This cannot be undone."
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return protectedCycles.count
        }
        if section == 1 {
            return max(eligibleCycleCounts.count, 1)
        }
        //Sections 2 (export) and 3 (delete) are single action rows.
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

        if indexPath.section == 3 {
            cell.textLabel?.text = "Delete \(eligibleTotal) Old Record\(eligibleTotal == 1 ? "" : "s")"
            //Destructive red only when armed; muted while locked so it doesn't
            //read as tappable before the export has been sent.
            cell.textLabel?.textColor = canDelete ? .systemRed : .secondaryLabel
            cell.detailTextLabel?.text = canDelete ? nil : "Locked"
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = canDelete ? .default : .none
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

    //Only the two action rows are selectable; the cycle lists stay read-only,
    //and the delete row stays inert until both interlocks are satisfied.
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 2 { return indexPath }
        if indexPath.section == 3 { return canDelete ? indexPath : nil }
        return nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2 {
            emailAllCyclesExport()
        } else if indexPath.section == 3 {
            confirmDelete()
        }
    }
}
