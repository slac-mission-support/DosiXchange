//
//  ReportGroups.swift
//  LocationApp
//
//  Created by Daniel Spady on 7/24/26.
//

import Foundation

//Resolves a QRCode to its report group. Exact table match first, then a
//prefix wildcard: a new location inherits the group of the highest-numbered
//existing entry with the same prefix. Unknown prefixes stay nil — never guess.
class ReportGroups {

    //Substring before the LAST dash; a dashless code is its own prefix.
    static func prefix(of qrCode: String) -> String {
        guard let dash = qrCode.lastIndex(of: "-") else { return qrCode }
        return String(qrCode[..<dash])
    }

    //Leading digits after the last dash ("005A" -> 5). -1 when there is no
    //dash or no leading digit, so numbered entries always outrank it.
    static func suffixNumber(of qrCode: String) -> Int {
        guard let dash = qrCode.lastIndex(of: "-") else { return -1 }
        let suffix = qrCode[qrCode.index(after: dash)...]
        let digits = suffix.prefix(while: { $0.isNumber })
        return Int(digits) ?? -1
    }

    static func group(for qrCode: String) -> String? {
        if let exact = Groups[qrCode] {
            return exact
        }
        let target = prefix(of: qrCode)
        let sharedPrefix = Groups.keys.filter { prefix(of: $0) == target }
        guard let donor = sharedPrefix.max(by: { suffixNumber(of: $0) < suffixNumber(of: $1) }) else {
            return nil
        }
        return Groups[donor]
    }

    //Backfill helper: a same-QRCode donor record wins so manual dashboard
    //assignments are preserved; the wildcard runs only when nothing else exists.
    static func resolvedGroup(donor: String?, qrCode: String) -> String? {
        if let donor = donor, !donor.isEmpty {
            return donor
        }
        return group(for: qrCode)
    }

    //Returns the table value only when the stored group differs from it by
    //case alone (heals "Gen" vs "GEN"); a genuinely different manual override
    //or an already-exact value returns nil (no change).
    static func canonicalCaseFix(current: String?, qrCode: String) -> String? {
        guard let current = current, !current.isEmpty,
              let exact = Groups[qrCode],
              exact != current,
              exact.lowercased() == current.lowercased() else {
            return nil
        }
        return exact
    }
}
