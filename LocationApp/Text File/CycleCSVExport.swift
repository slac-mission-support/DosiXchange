//
//  CycleCSVExport.swift
//  LocationApp
//
//  Created by Daniel Spady on 6/12/26.
//

import Foundation

//MARK:  All-cycles CSV export

//Builds the CSV attached to the export email required before deleting old
//cycles. Same columns and ordering as the Tools email export, but it covers
//every cached record and renders missing fields as blank cells, so the file
//is a complete audit copy of anything a delete could touch.
struct CycleCSVExport {

    static let header = "LocationID (QRCode),Latitude,Longitude,Description,Moderator (0/1),Active (0/1),Dosimeter,Collected Flag (0/1),Wear Period,System_Date Deployed,System_Date Collected,RGD (0/1), my_Date Deployed, my_Date Collected, recordID, ModifiedBy, Report Group\n"

    //Whole-file build: header, one row per record (QRCode ascending, newest
    //deploy first within a QRCode — same ordering as the Tools export), then
    //the End of File marker line.
    static func csvText(for items: [LocationRecordCacheItem]) -> String {
        let sorted = items.sorted {
            if $0.QRCode == $1.QRCode {
                return $0.createdDateForSort > $1.createdDateForSort
            }
            return $0.QRCode < $1.QRCode
        }
        var text = header
        for item in sorted {
            text.append(row(for: item))
        }
        text.append("End of File\n")
        return text
    }

    //One CSV line per record. Optional fields become empty cells — no
    //force-unwraps, so the export survives any record the cache can hold.
    static func row(for item: LocationRecordCacheItem) -> String {
        let moderator = item.moderator.map { String($0) } ?? ""
        let dosimeter = item.dosinumber ?? ""
        let collected = item.collectedFlag.map { String($0) } ?? ""
        let cycle = item.cycleDate ?? ""
        let mismatch = item.mismatch.map { String($0) } ?? ""
        let recordID = item.recordName ?? ""
        let modifiedBy = item.modifiedBy ?? ""
        let group = item.reportGroup ?? ""

        return "\(item.QRCode),\(item.latitude),\(item.longitude),\(quoted(item.locdescription)),\(moderator),\(item.active),\(dosimeter),\(collected),\(cycle),\(format(item.creationDate)),\(format(item.modificationDate)),\(mismatch),\(format(item.createdDate)),\(format(item.modifiedDate)),\(recordID),\(modifiedBy),\(quoted(group))\n"
    }

    //Wraps a free-text cell in quotes so an embedded comma or newline can't
    //shift columns; any embedded quote is doubled, per RFC 4180.
    private static func quoted(_ value: String) -> String {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()

    private static func format(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return dateFormatter.string(from: date)
    }
}
