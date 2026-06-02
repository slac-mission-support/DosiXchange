//
//  DosimeterRecordCacheItem.swift
//  LocationApp
//
// Used to cache Location Cloudit records to disk.
//
//  Created by Matt Lintlop on 10/10/21.
//  Copyright © 2021 Ford, Ryan M. All rights reserved.
//

import Foundation
import CloudKit
import UIKit

protocol LocationRecordDelegate {

    func value(forKey key: String) -> Any?
    mutating func setValue(_ value: Any?, forKey key: String)

    subscript(key: String) -> CKRecordValue? {get set}
}

extension LocationRecordDelegate {
    
    subscript(key: String) -> CKRecordValue? {
        get {
            return self.value(forKey: key) as? CKRecordValue
        }
        set {
            self.setValue(newValue, forKey: key)
        }
    }
}

extension CKRecord: LocationRecordDelegate {
    // CKRecord already implements the DosimeterRecordDelegate protocol
    // to access properties with a subscript so this protocol is empty.
}

// Dosimetr Cache Item stores all of the properties of a dosimeter CloudKit record
class LocationRecordCacheItem: Codable, LocationRecordDelegate {

    // Location Record Fields
    var QRCode:String = ""              // QR Code
    var latitude:String = ""            // latitude
    var longitude:String = ""           // longitude
    var locdescription:String = ""      // location Description
    var active:Int64 = 0                // active
    var dosinumber:String?              // dosinumber field may contain nothing
    var collectedFlag:Int64?            // collectedFlag field may contain nothing
    var cycleDate:String?               // cycleDate field may contain nothing
    var mismatch:Int64?                 // mismatch field may contain nothing
    var moderator:Int64?                // moderator field may contain nothing
    var creationDate:Date?               // creation date
    var createdDate:Date?               // created date
    var modifiedDate:Date?              // modified date
    var modificationDate:Date?          // modification date
    var recordName: String?             // record name (record.recordID.recordName)
    var modifiedBy: String?
    var reportGroup: String?
    var hasPhoto: Bool
    var photo: CKAsset?
    
    private enum CodingKeys: String, CodingKey {
        case QRCode, latitude, longitude, locdescription, active, dosinumber, collectedFlag, cycleDate, mismatch, moderator, creationDate, createdDate, modifiedDate, modificationDate, recordName, modifiedBy, reportGroup, hasPhoto
    }

    // Nil-safe ordering key for createdDate. CloudKit can return a nil
    // createdDate for very old / partially-populated records; the UI sorts
    // newest-first and used to force-unwrap createdDate, which crashed on
    // those records. Treating nil as the oldest possible date keeps the same
    // newest-first ordering (nil lands last) without the force-unwrap — the
    // sort sibling of the skip-nil Dosimeter init (commit 931ccc2).
    var createdDateForSort: Date {
        return createdDate ?? .distantPast
    }

    // Location Record Metadata
    
    // Initialize with a CloudKit Record
    init?(withRecord record: CKRecord) {
          
        // set the QRCode
        guard let QRCode = record["QRCode"] as? String else {
            print("ERROR: Location record QRCode is empty")
            return nil
        }
        self.QRCode = QRCode

        // set the latitude
        guard let latitude = record["latitude"] as? String else {
            print("ERROR: Location record latitude is empty")
            return nil
        }
        self.latitude = latitude
        
        // set the longitude
        guard let longitude = record["longitude"] as? String else {
            print("ERROR: Location record longitude is empty")
            return nil
        }
        self.longitude = longitude
        
        // set the description
        guard let locdescription = record["locdescription"] as? NSString else {
            print("ERROR: Location record locdescription is empty")
            return nil
        }
        self.locdescription = locdescription as String
        
        // set the active state
        guard let active = record["active"] as? Int64 else {
            print("ERROR: Location record active is empty")
            return nil
        }
        self.active = active
        
        // set the dosimeter
        guard let dosinumber = record["dosinumber"] as? NSString else {
            print("ERROR: Location record dosinumber is empty")
           return nil
        }
        self.dosinumber = dosinumber as String

        // set the collected flag
        guard let collectedFlag = record["collectedFlag"] as? Int64 else {
            print("ERROR: Location record collectedFlag is empty")
            return nil
        }
        self.collectedFlag = collectedFlag

        // set the cycle date
        guard let cycleDate = record["cycleDate"] as? NSString else {
            print("ERROR: Location record cycleDate is empty")
            return nil
        }
        self.cycleDate = cycleDate as String

        // set the mismatch flag
        if let mismatch = record["mismatch"] as? Int64 {
            self.mismatch = mismatch
        }
        
        // set the moderator
        guard let moderator = record["moderator"] as? Int64 else {
            print("ERROR: Location record moderator is empty")
            return nil
        }
        self.moderator = moderator
        
        // set the creation date
        self.creationDate = record.creationDate
        // set the deploy date
        self.createdDate = record["createdDate"] as? Date

        // set the collection/exchange date
        self.modifiedDate = record["modifiedDate"] as? Date
 
        // set the modification date
        self.modificationDate = record.modificationDate
        
        self.modifiedBy = record["modifiedBy"] as? String
        
        self.reportGroup = record["reportGroup"] as? String
        
        self.hasPhoto = (record["hasPhoto"] ?? 0) == 0 ? false : true
        
        self.photo = record["photo"]
        
        // set the record name
        self.recordName = record.recordID.recordName
 }
    
    // Subscript operator overload used to access properties.
    subscript(key: String) -> CKRecordValue? {
        get {
            switch key {
                case "QRCode":
                    return QRCode as CKRecordValue
                   
                case "active":
                  return active as CKRecordValue
                   
                case "latitude":
                  return latitude as CKRecordValue
               
                case "longitude":
                   return longitude as CKRecordValue
                   
                case "locdescription":
                   return locdescription as CKRecordValue

                case "dosinumber":
                    if dosinumber != nil {
                        return dosinumber! as CKRecordValue
                    }
                    else {
                        return nil
                    }

                case "collectedFlag":
                    if collectedFlag != nil {
                        return collectedFlag! as CKRecordValue
                    }
                    else {
                        return nil
                    }

                case "cycleDate":
                    if cycleDate != nil {
                        return cycleDate! as CKRecordValue
                    }
                    else {
                        return nil
                    }

               case "mismatch":
                    if mismatch != nil {
                        return mismatch! as CKRecordValue
                    }
                    else {
                        return nil
                    }

               case "moderator":
                    if moderator != nil {
                        return moderator! as CKRecordValue
                    }
                    else {
                        return nil
                    }

               case "createdDate":
                    if createdDate != nil {
                        return createdDate! as CKRecordValue
                    }
                    else {
                        return nil
                    }

               case "modifiedDate":
                    if modifiedDate != nil {
                        return modifiedDate! as CKRecordValue
                    }
                    else {
                        return nil
                    }
               case "modifiedby":
                    if modifiedBy != nil {
                        return modifiedBy! as CKRecordValue
                    }
                    return nil
                
            case "reportGroup":
                 if reportGroup != nil {
                     return reportGroup! as CKRecordValue
                 }
                 else {
                     return nil
                 }

               default:
                  return nil
               }
           }
        set {
            switch key {
                case "QRCode":
                    QRCode = newValue as! String
                   
                case "active":
                    active = newValue as! Int64
                   
                case "latitude":
                    latitude = newValue as! String
               
                case "longitude":
                    longitude = newValue as! String
                   
                case "locdescription":
                    locdescription = newValue as! String

                case "dosinumber":
                    dosinumber = newValue as? String
                
                case "collectedFlag":
                    collectedFlag = newValue as? Int64
                
                case "cycleDate":
                    cycleDate = newValue as? String

               case "mismatch":
                    mismatch = newValue as? Int64

               case "moderator":
                    moderator = newValue as? Int64

               case "createdDate":
                    createdDate = newValue as? Date

               case "modifiedDate":
                    modifiedDate = newValue as? Date
               
                case "modifiedBy":
                    modifiedBy = newValue as? String
                
                case "reportGroup":
                    reportGroup = newValue as? String

            default:
                    print("Unknown key = \(key) in LocationRecordCacheItem subscript setter")
               }
        }
    }

    func value(forKey key: String) -> Any? {
        return self[key]
    }
    
    func setValue(_ value: AnyObject?, forKey key: String) {
        self[key] = value as? CKRecordValue
    }

    func setValue(_ value: Any?, forKey key: String) {
        self[key] = value as? CKRecordValue
    }
    
    func setPhoto(photo: UIImage) throws {
        if let fileUrl = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(NSUUID().uuidString+".raw"), let data = photo.pngData() {
            do {
                try data.write(to: fileUrl)
            } catch let error as NSError {
                throw error
            }
            self.photo = CKAsset(fileURL: fileUrl)
            self.hasPhoto = true
        }
        else {
            throw NSError(domain: "LocationApp", code: 500, userInfo: ["Save error":"Unable to save the image file"])
        }
    }
    
    func update(newRecord:CKRecord) {
        newRecord.setValue(self.latitude, forKey: "latitude")
        newRecord.setValue(self.longitude, forKey: "longitude")
        newRecord.setValue(self.locdescription, forKey: "locdescription")
        newRecord.setValue(self.dosinumber, forKey: "dosinumber")
        newRecord.setValue(self.collectedFlag, forKey: "collectedFlag")
        newRecord.setValue(self.cycleDate, forKey: "cycleDate")
        newRecord.setValue(self.QRCode, forKey: "QRCode")
        newRecord.setValue(self.moderator, forKey: "moderator")
        newRecord.setValue(self.active, forKey: "active")
        newRecord.setValue(self.createdDate, forKey: "createdDate")
        newRecord.setValue(self.modifiedDate, forKey: "modifiedDate")
        newRecord.setValue(self.mismatch, forKey: "mismatch")
        newRecord.setValue(self.modifiedBy, forKey: "modifiedBy")
        newRecord.setValue(self.reportGroup, forKey: "reportGroup")
        newRecord.setValue(self.photo, forKey: "photo")
        newRecord.setValue(self.hasPhoto ? 1 : 0, forKey: "hasPhoto")
    }
    
    func to() -> CKRecord {
        let result = CKRecord(recordType: "Location", recordID: CKRecord.ID(recordName: self.recordName!))
        self.update(newRecord: result)
        
        return result
    }
}
