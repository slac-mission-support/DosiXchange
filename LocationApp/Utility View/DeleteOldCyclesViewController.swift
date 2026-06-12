//
//  DeleteOldCyclesViewController.swift
//  LocationApp
//
//  Created by Daniel Spady on 6/11/26.
//

import Foundation
import UIKit

//MARK:  Class

//Super-user admin screen, reached from Tools behind the passcode gate.
//Read-only preview of what a delete would affect: the latest cycles are
//listed as protected, older cycles with their record counts.
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

    //MARK:  View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Delete Old Cycles"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self,
                                                            action: #selector(done))

        tableView.dataSource = self
        tableView.allowsSelection = false
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
}

//MARK:  Table data source

extension DeleteOldCyclesViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Protected — latest \(DeleteOldCyclesViewController.cyclesToKeep) cycles"
        }
        return "Older cycles eligible for deletion"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return "Records in these cycles can never be deleted."
        }
        if eligibleTotal == 0 {
            return "No records older than the protected cycles were found."
        }
        return "\(eligibleTotal) records total. Deleting requires a fresh export of all cycles first — that step arrives in the next update."
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return protectedCycles.count
        }
        return max(eligibleCycleCounts.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cycleCell")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "cycleCell")

        if indexPath.section == 0 {
            cell.textLabel?.text = protectedCycles[indexPath.row]
            cell.detailTextLabel?.text = "Protected"
            cell.detailTextLabel?.textColor = .secondaryLabel
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
