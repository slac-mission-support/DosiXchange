//
//  ToolsViewController.swift
//  LocationApp
//
//  Created by Choi, Helen B on 7/12/19.
//  Copyright © 2019 Ford, Ryan M. All rights reserved.
//

import Foundation
import UIKit
import MessageUI
import AVFoundation
//MARK:  Class
class ToolsViewController: UIViewController, MFMailComposeViewControllerDelegate {
    
    let locations = container.locations
    let readwrite = readWriteText()  //make external class available locally
    let dispatchGroup = DispatchGroup()
    let saveToCloud = Save()
    let queries = Queries()
    let repair = RepairCycleDate()
    
    var QRCode:String = ""
    var latitude:String = ""
    var longitude:String = ""
    var loc:String = ""
    var active:Int64 = 0
    var dosimeter:String = ""
    var collectedFlag:Int64?
    var cycle:String = ""
    var mismatch:Int64?
    var collectedFlagStr:String = ""
    var mismatchStr:String = ""
    var csvText = ""
    var moderator = ""
    var mycreatedDate:Date?  //during testing the date field may contain nothing
    var myDateModified:Date?

    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var buildDateLabel: UILabel!
    @IBOutlet weak var button1: UIButton!
    @IBOutlet weak var button3: UIButton!
    @IBOutlet weak var resetCacheButton: UIButton!
    @IBOutlet weak var dosimeters: UIButton!
    @IBOutlet weak var deleteOldCyclesButton: UIButton!
    
    let borderColorUp = UIColor(red: 0.580723, green: 0.0667341, blue: 0, alpha: 1).cgColor
    let borderColorDown = UIColor(red: 0.580723, green: 0.0667341, blue: 0, alpha: 0.25).cgColor
    
    fileprivate func registerDevMode() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.devTap(_:)))
        tap.numberOfTapsRequired = 5
        self.view.addGestureRecognizer(tap)
        
        view.isUserInteractionEnabled = true        
    }
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        activityIndicator.hidesWhenStopped = true

        //format buttons
        addBorderToButton(button: button1)
        addBorderToButton(button: button3)
        addBorderToButton(button: resetCacheButton)
        addBorderToButton(button: dosimeters)
        addBorderToButton(button: deleteOldCyclesButton)
        
        registerDevMode()

        //show the build date (auto-derived) instead of a hardcoded string
        buildDateLabel.text = ToolsViewController.buildDateString()

        // function which is triggered when handleTap is called
    }

    //Auto-derived build date for the Tools footer. Reads the modification date
    //of the compiled executable (stamped fresh on every build), falling back to
    //the Info.plist date, then to nil if neither is readable.
    static func buildDateString() -> String {
        let candidates = [Bundle.main.executableURL,
                          Bundle.main.url(forResource: "Info", withExtension: "plist")]
        for url in candidates.compactMap({ $0 }) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let date = attrs[.modificationDate] as? Date {
                return buildDateString(from: date)
            }
        }
        return ""
    }

    //Formats a build date as e.g. "May, 2023" to match the label this replaces.
    //Pure (offline-testable) — kept separate from the bundle read above.
    static func buildDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter.string(from: date)
    }
    
    private func addBorderToButton(button: UIButton) {
        button.layer.borderWidth = 1.5
        button.layer.borderColor = borderColorUp
        button.layer.cornerRadius = 22
    }
    
    //@IBAction func uploadToCloud(_ sender: Any) {
     //   activityIndicator.startAnimating()
      //  saveToCloud.uploadToCloud()
     //   activityIndicator.stopAnimating()
        
    @IBAction func done(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func buttondown(_ sender: Any) {
        if let button = sender as? UIButton {
            button.layer.borderColor = borderColorDown
        }
    }
    
    @IBAction func buttonup(_ sender: Any) {
        if let button = sender as? UIButton {
            button.layer.borderColor = borderColorUp
        }
    }
    
    @IBAction func button3down(_ sender: Any) {
        button3.layer.borderColor = borderColorDown
        //start activityIndicator
        activityIndicator.startAnimating()
    }
    
    @IBAction func button3up(_ sender: Any) {
        button3.layer.borderColor = borderColorUp
        //release Email Data button from outside
        //stop activityIndicator
        activityIndicator.stopAnimating()
    }
/*
    @IBAction func UploadtoCloud(_ sender: Any) {
        let n:Save = Save()
        n.uploadToCloud()
    } */
    
    @IBAction func emailTouchUp(_ sender: Any) {
        
        showExportAlert()
        button3.layer.borderColor = borderColorUp
    }
    
    @IBAction func resetCacheTouchUp(_ sender: Any) {
        let pending = locations.pendingChangeCount
        let pendingLine = pending > 0
            ? "\n\nYou have \(pending) unsynced edit\(pending == 1 ? "" : "s") that will sync first."
            : ""
        let alert = UIAlertController(
            title: "Reset Cache?",
            message: "This will discard the local cache and reload all location data from CloudKit. Use this only if records appear out of sync.\(pendingLine)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive, handler: { _ in
            self.activityIndicator.startAnimating()
            self.locations.reset { _ in
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                }
            }
        }))
        present(alert, animated: true)
    }
    
    //MARK:  Super-user delete

    //Passcode gate for the delete-old-cycles admin screen. The integer
    //passcode is checked against the cached Settings record, so it can be
    //rotated from CloudKit without an app update ("04299" matches by design).
    @IBAction func deleteOldCyclesTouchUp(_ sender: Any) {
        let alert = UIAlertController(title: "Super User Access",
                                      message: "Enter the passcode to manage old cycles.",
                                      preferredStyle: .alert)
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
            textField.isSecureTextEntry = true
            textField.placeholder = "Passcode"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let entered = Int(alert.textFields?.first?.text ?? "")
            container.settings.getSettings { settings in
                DispatchQueue.main.async {
                    if let entered = entered, entered == settings.superUserPasscodeValue {
                        print("Super-user gate: passcode accepted, opening Delete Old Cycles")
                        self.presentDeleteOldCycles()
                    } else {
                        print("Super-user gate: passcode rejected")
                        self.presentWrongPasscode()
                    }
                }
            }
        }))
        present(alert, animated: true)
    }

    func presentDeleteOldCycles() {
        let controller = UINavigationController(rootViewController: DeleteOldCyclesViewController())
        present(controller, animated: true)
    }

    func presentWrongPasscode() {
        let alert = UIAlertController(title: "Incorrect Passcode",
                                      message: "The passcode you entered is not correct.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }

    //MARK:  Send Email
    func sendEmail() {
        
        let URL =  readwrite.messageURL
        
        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            //mail.setToRecipients(["ryanford@slac.stanford.edu"])
            mail.setSubject("Area Dosimeter Data")
            mail.setMessageBody("The dosimeter data is attached to this e-mail.", isHTML: true)
            
            if let fileAttachment = NSData(contentsOf: URL!) {
                mail.addAttachmentData(fileAttachment as Data, mimeType: "text/csv", fileName: "Dosi_Data.csv")
            } //end if let
            
            present(mail, animated: true)
        }
            
        else {
            //show failure alert
        }
        
    } //end func sendEmail
    
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        
        //Play email sent sound
        let systemSoundID: SystemSoundID =  1001
        AudioServicesPlaySystemSound(systemSoundID)
        controller.dismiss(animated: true)
    } //end func mailComposeController
    
    func showExportAlert() {
        let alert = UIAlertController(title: "Export Exchange Data", message: "Export current cycle plus:", preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "2 cycles", style: .default, handler: { _ in self.sendEmail(2) }))
        alert.addAction(UIAlertAction(title: "3 cycles", style: .default, handler: { _ in self.sendEmail(3) }))
        alert.addAction(UIAlertAction(title: "4 cycles", style: .default, handler: { _ in self.sendEmail(4) }))
        alert.addAction(UIAlertAction(title: "All cycles", style: .default, handler: { _ in self.sendEmail(0) }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in self.activityIndicator.stopAnimating() }))
        
        self.present(alert, animated: true)
    }
    
    func sendEmail(_ cycle: Int) {
        queryDatabaseForCSV(cycle) //takes up to 5 seconds
        
        dispatchGroup.wait() //wait for query to finish
        
        self.readwrite.writeText(someText: "\(csvText)")
        self.sendEmail()
        //stop activityIndicator
        activityIndicator.stopAnimating()
        button3.layer.borderColor = borderColorUp
    }
}


//query and helper functions
//MARK:  Extension
extension ToolsViewController {
    
    func queryDatabaseForCSV(_ cycles: Int) {
        
        //set first line of text file
        //should separate text file from query
        dispatchGroup.enter()
        self.csvText = "LocationID (QRCode),Latitude,Longitude,Description,Moderator (0/1),Active (0/1),Dosimeter,Collected Flag (0/1),Wear Period,System_Date Deployed,System_Date Collected,Mismatch (0/1), my_Date Deployed, my_Date Collected, recordID, ModifiedBy, Report Group\n"
        
        var filter: ((LocationRecordCacheItem) -> Bool) = { l in l.createdDate != nil }
        if cycles > 0 {
            let cycleDates = RecordsUpdate.getLastCycles(cycles: cycles)
            filter = { l in l.cycleDate != nil && cycleDates.contains(l.cycleDate!) && l.createdDate != nil }
        }
        var items = locations.filter(by: filter)
        items.sort {
            if $0.QRCode == $1.QRCode {
                return $0.createdDateForSort > $1.createdDateForSort
            }
            return $0.QRCode < $1.QRCode
        }
        for item in items {
            recordFetchedBlock(record: item)
        }

        csvText.append("End of File\n")
        dispatchGroup.leave()
    } //end function
    
    
    
    // to be executed for each fetched record
    func recordFetchedBlock(record: LocationRecordCacheItem) {
        //Careful use of optionals to prevent crashes.
        
        //block 1:  these fields always have a value
        QRCode = record.QRCode
        latitude = record.latitude
        longitude = record.longitude
        loc = record.locdescription
        active = record.active
        
        //block 2:  these fields sometimes have a value
        if record.dosinumber != nil {dosimeter = record.dosinumber!}
        if record.cycleDate != nil {cycle = record.cycleDate!}
        if record.collectedFlag != nil {collectedFlagStr = String(describing: record.collectedFlag!)}
        if record.mismatch != nil {mismatchStr = String(describing: record.mismatch!)}
        if record.moderator != nil {moderator = String(describing: record.moderator!)}
        
        //my fields for created and modified dates:

        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .none
        dateFormatter.dateFormat = "MM/dd/yyyy"
        
        //system dates - createdDate and modifiedDate Ver 1.2
        
        //block 3: these fields always have a value and are called differently than my date fields
        let date = Date(timeInterval: 0, since: record.creationDate!)
        //let date = Date(timeInterval: 0, since: record["createdDate"] as! Date) //Ver 1.2
        let formattedDate = dateFormatter.string(from: date)
        let dateModified = Date(timeInterval: 0, since: record.modificationDate!)
        //let dateModified = Date(timeInterval: 0, since: record["modifiedDate"] as! Date)
        let formattedDateModified = dateFormatter.string(from: dateModified)
        
        //block 4: may not have a value when initially set up and tested
        //but will eventually always have a value
        if record["createdDate"] != nil {
            mycreatedDate = Date(timeInterval: 0, since: record["createdDate"] as! Date)
        } else {
                //can't set the date as nil
                //but if the date is old enough it populates a nil in the field.
                //the cutoff is around -1E10 seconds ago where it stops showing dates
            mycreatedDate = Date(timeInterval: -1E15, since: Date())
        }
        let myformattedCreatedDate = dateFormatter.string(from: mycreatedDate!)
        
        if record["modifiedDate"] != nil {
            myDateModified = Date(timeInterval: 0, since: record["modifiedDate"] as! Date)
        } else {
            myDateModified = Date(timeInterval: -1E15, since: Date())
        }
        let myformattedDateModified = dateFormatter.string(from: myDateModified!)
        let recordID = record.recordName!
        let modifiedBy = record.modifiedBy ?? ""
        let group = record.reportGroup ?? ""
        
        //write the data into the file.
        let newline = "\(QRCode),\(latitude),\(longitude),\(loc),\(moderator),\(active),\(dosimeter),\(collectedFlagStr),\(cycle),\(formattedDate),\(formattedDateModified),\(mismatchStr),\(myformattedCreatedDate),\(myformattedDateModified),\(recordID),\(modifiedBy),\(group)\n"
        csvText.append(contentsOf: newline)
        clear()
    }
    
    // clear variable data
    func clear() {
        QRCode = ""
        latitude = ""
        longitude = ""
        loc = ""
        active = 0
        dosimeter = ""
        collectedFlag = nil
        cycle = ""
        mismatch = nil
        collectedFlagStr = ""
        mismatchStr = ""
        //not clearing date fields?
    }
    
    @objc func devTap(_ sender: UITapGestureRecognizer) {
        activityIndicator.startAnimating()
        UpdateGroups.updateRGFromPreviousLocations(completionHandler: {
            self.activityIndicator.stopAnimating()
        })
    }
} //end class
