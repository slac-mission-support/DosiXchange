//
//  UpdateGroups.swift
//  LocationApp
//
//  Created by Szöllősi László on 2023. 05. 23..
//  Copyright © 2023. Ford, Ryan M. All rights reserved.
//

import Foundation

class UpdateGroups {
    
    static func update(completionHandler: (() -> Void)?) {
        let locations = container.locations
        
        let items = locations.filter(by: { _ in true })
        var changed = [LocationRecordCacheItem]()
        for item in items {
            if let group = Groups[item.QRCode], group != item.reportGroup {
                item.setValue(group, forKey: "reportGroup")
                changed.append(item)
            }
        }
        if !changed.isEmpty {
            locations.save(items: changed, completionHandler: completionHandler)
        }
        else {
            DispatchQueue.main.async {
                completionHandler?()
            }
        }
    }
    
    static func updateRGFromPreviousLocations(completionHandler: (() -> Void)?) {
        print("updateRGFromPreviousLocations")
        let locations = container.locations
               
        let all = locations.filter(by: { _ in true })

        var changes = [LocationRecordCacheItem]()
        for item in all {
            if item.reportGroup == nil || item.reportGroup!.isEmpty {
                let donor = all.first(where: { l in l.reportGroup != nil && !l.reportGroup!.isEmpty && l.QRCode == item.QRCode })?.reportGroup
                if let group = ReportGroups.resolvedGroup(donor: donor, qrCode: item.QRCode) {
                    item.reportGroup = group
                    changes.append(item)
                }
            }
            else if let fixed = ReportGroups.canonicalCaseFix(current: item.reportGroup, qrCode: item.QRCode) {
                item.reportGroup = fixed
                changes.append(item)
            }
        }

        if !changes.isEmpty {
            locations.save(items: changes, completionHandler: completionHandler)
        }
        else {
            completionHandler?()
        }
    }
}
