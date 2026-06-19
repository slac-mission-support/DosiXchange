//
//  Barcode.swift
//  LocationApp
//
//  Created by Ford, Ryan M. on 11/23/18.
//  Copyright © 2018 Ford, Ryan M. All rights reserved.
//

import AVFoundation
import UIKit
import CloudKit
import CoreLocation

//MARK:  Class
class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let reachability = Reachability()!
    let locations = container.locations
    let settingsService = container.settings
    var recordsupdate = RecordsUpdate()
    var zoomFactor:CGFloat = 3
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var counter:Int64 = 0
    let dispatchGroup = DispatchGroup()
    var records = [CKRecord]()
    var itemRecord:CKRecord?
    var tempRecords = [CKRecord]()
    var locationManager = CLLocationManager()
    var alertTextField: UITextField!
    var isRescan: Bool = false
    var outOfRangeCounter: Int = 0
    let numberOfGPSRetry: Int = 2
    var settings: Settings?
    var audioPlayer: AudioPlayer?
    var photo: UIImage?
    
    @IBOutlet weak var innerView: UIView!
    @IBOutlet weak var outerView: UIView!
    
    struct variables {  //key variables needed in other classes
        
        static var dosiNumber:String?
        static var QRCode:String?
        static var codeType:String?
        static var dosiLocation:String?
        static var collected:Int64?
        static var mismatch:Int64?
        static var active:Int64?
        static var cycle:String?
        static var latitude:String?
        static var longitude:String?
        static var moderator:Int64?
        
    } //end struct
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        view.backgroundColor = UIColor.white
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        //set zoom factor to 3x
        do {
            try    videoCaptureDevice.lockForConfiguration()
            
        } catch {
            // handle error
            return
        }
        
        // When this point is reached, we can be sure that the locking succeeded
        
        
        //end set zoom factor to 3X
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        }
        catch {
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
            
        }
        else {
            failed()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            //Location barcode is a QR Code (.qr)
            //Dosimeter barcoce is a CODE 128 barcode (.code128)
            metadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr, AVMetadataObject.ObjectType.code128]
        }
        
        else {
            failed()
            return
        }//end else
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame.size = innerView.frame.size
        innerView.layer.addSublayer(previewLayer)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        videoCaptureDevice.videoZoomFactor = zoomFactor
        videoCaptureDevice.unlockForConfiguration()
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
        configReachability()
        
        settingsService.getSettings(completionHandler: { self.settings = $0 })
        
        audioPlayer = AudioPlayer()
    }//end viewDidLoad()
    
    @IBAction func done(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func failed() {
        
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
        
    }//end failed
    
    override func viewWillAppear(_ animated: Bool) {
        
        super.viewWillAppear(animated)
        self.previewLayer?.frame.size = self.innerView.frame.size
        if (captureSession?.isRunning == false) {
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
        }
        
    }//end viewWillAppear
    
    override func viewWillDisappear(_ animated: Bool) {
        
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
        
    }//end viewWillDisappear
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        if let metadataObject = metadataObjects.first {
            
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            let stringValue = readableObject.stringValue
            
            switch readableObject.type {
                
            case .qr:
                
                variables.codeType = "QRCode"
                
            case .code128:
                if(stringValue?.count ?? 0 >= settings!.dosimeterMinimumLength && stringValue?.count ?? 0 <= settings!.dosimeterMaximumLength){
                    variables.codeType = "Code128"
                } else {
                    alert14()
                    return
                }
                
                
            default:
                print("Code not found")
                
            }//end switch
            
            scannerLogic(code: stringValue)
            
        }//end if let
        
    }//end function meetadataOutput
    
    
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
        
    } //end supportedInterfaceOrientations
    
}   //end class

/*
 
 @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 All methods, alerts, handlers and queries needed to
 implement the scanner logic (see figures under "other assets")
 by Ryan M. Ford 2019
 */
// MARK:  ScannerViewController
//MARK:  Extension
extension ScannerViewController {
    
    func scannerLogic(code: String?) { //see Other Assets Scanner Logic diagrams
        
        switch self.counter {
            
        case 0: //first scan
            if(isRescan){
                isRescan = false
            } else {
                variables.QRCode = nil
                variables.dosiNumber = nil
                clearForQR()
            }
            
            switch variables.codeType {
                
            case "QRCode":
                
                if(code != nil ){
                    
                    variables.QRCode = code //store the QRCode
                    queryForQRFound() //use the QRCode to look up record & store values
                    
                    dispatchGroup.notify(queue: .main) {
                        print("1 - Dispatch QR Code Notify")
                        
                        //record found
                        if self.itemRecord != nil {
                            
                            //deployed dosimeter
                            if variables.collected == 0 {
                                self.audioPlayer?.beep()
                                if variables.active == 1 {
                                    
                                    if(RecordsUpdate.generateCycleDate() == variables.cycle){
                                        self.alert13(nextFunction: self.alert3a)
                                    } else {
                                        self.alert3a() //Exchange Dosimeter (active location)
                                    }
                                    
                                }
                                else {
                                    if(RecordsUpdate.generateCycleDate() == variables.cycle){
                                        self.alert13(nextFunction: self.alert3i)
                                    } else {
                                        self.alert3i() //Collect Dosimeter (inactive location)
                                    }
                                    
                                }
                            }
                            //collected or no dosimeter
                            else {
                                if variables.active == 1 {
                                    self.audioPlayer?.beep()
                                    self.alert2() //Location Found [cancel/deploy]
                                }
                                else {
                                    self.audioPlayer?.beepFail()
                                    self.alert2a() //Inactive Location (activate to deploy)
                                }
                            }
                        }
                        
                        //no record found
                        else {
                            self.audioPlayer?.beep()
                            self.alert2() //New Location [cancel/deploy]
                        }
                        
                    } //end dispatch group
                    
                } else {
                    self.alert12() //Invalid code (rescan)
                }
                
            case "Code128":
                
                if(code != nil ){
                    
                    variables.dosiNumber = code //store the dosi number
                    queryForDosiFound() //use the dosiNumber to look up record & store values
                    
                    dispatchGroup.notify(queue: .main) {
                        print("1 - Dispatch Code 128 Notify")
                        
                        //record found
                        if self.itemRecord != nil {
                            
                            //deployed dosimeter
                            if variables.collected == 0 {
                                self.audioPlayer?.beep()
                                if variables.active == 1 {
                                    if(RecordsUpdate.generateCycleDate() == variables.cycle){
                                        self.alert13(nextFunction: self.alert3a)
                                    } else {
                                        self.alert3a() //Exchange Dosimeter (active location)
                                    }
                                }
                                else {
                                    if(RecordsUpdate.generateCycleDate() == variables.cycle){
                                        self.alert13(nextFunction: self.alert3i)
                                    } else {
                                        self.alert3i() //Collect Dosimeter (inactive location)
                                    }
                                }
                            }
                            
                            //collected dosimeter
                            else {
                                self.audioPlayer?.beepFail()
                                self.alert9a() //Invalid Dosimeter (already collected)
                            }
                        }
                        
                        //no record found
                        else {
                            self.audioPlayer?.beep()
                            self.alert1() //Dosimeter Not Found [cancel/deploy]
                        }
                    }
                    
                } //end dispatch group
                else {
                    self.alert12() //Invalid code (rescan)
                }
                
            default:
                print("Invalid Code") //exhaustive
                alert9()
                
            } //end switch
            
        case 1: //second scan logic
            
            //self.captureSession.startRunning()
            if(isRescan){
                isRescan = false
            }
            switch variables.codeType {
                
            case "QRCode":
                
                if(code != nil ){
                    
                    //looking for QRCode
                    if variables.QRCode == nil {
                        clearForQR()
                        queryForQRUsed(tempQR: code!)
                        
                        dispatchGroup.notify(queue: .main) {
                            print("2 - Dispatch QR Code Notify")
                            
                            //existing location
                            if self.records != [] {
                                
                                //location in use/inactive location
                                if variables.collected == 0 || variables.active == 0 {
                                    self.audioPlayer?.beepFail()
                                    self.alert7b(code: code!)
                                }
                                
                                //valid location
                                else {
                                    self.audioPlayer?.beep()
                                    variables.QRCode = code
                                    self.save()
                                }
                            }
                            
                            //new location
                            else {
                                self.audioPlayer?.beep()
                                variables.QRCode = code
                                self.save()
                            }
                            
                        } //end dispatch group
                        
                    }
                    
                    //not looking for QRCode
                    else {
                        self.audioPlayer?.beepFail()
                        alert6b()
                    }
                    
                } else {
                    alert12()
                }
                
            case "Code128":
                if(code != nil ){
                    //looking for barcode
                    if variables.dosiNumber == nil {
                        queryForDosiUsed(tempDosi: code!)
                        
                        dispatchGroup.notify(queue: .main) {
                            print("2 - Dispatch Code 128 Notify")
                            
                            //duplicate dosimeter
                            if self.records != [] {
                                self.audioPlayer?.beepFail()
                                self.alert7a(code: code!)
                            }
                            
                            //new dosimeter
                            else {
                                self.audioPlayer?.beep()
                                variables.dosiNumber = code
                                self.save()
                            }
                            
                        } //end dispatch group
                        
                    } //looking for barcode
                    
                    //not looking for barcode
                    else {
                        self.audioPlayer?.beepFail()
                        alert6a()
                    }
                    
                } else {
                    alert12()
                }
                
            default:
                print("Invalid Code")
                if variables.QRCode == nil { alert6a() }
                else if variables.dosiNumber == nil { alert6b() }
            }
            
        default:
            if(isRescan){
                isRescan = false
            }
            print("Invalid Scan")
            counter = 0
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
        }
    } //end func
    
    //MARK:  Collect
    
    func collect(collected: Int64, mismatch: Int64, modifiedDate: Date) {
        
        itemRecord!.setValue(collected, forKey: "collectedFlag")
        itemRecord!.setValue(mismatch, forKey: "mismatch")
        itemRecord!.setValue(modifiedDate, forKey: "modifiedDate")
        
        let item = LocationRecordCacheItem(withRecord: itemRecord!)!
        locations.save(item: item, completionHandler: nil)
        
    } //end collect
    
    
    func deploy() {
        
        self.counter = 1
        
    } //end deploy
    
    
    func clearData() {
        
        variables.codeType = nil
        variables.dosiNumber = nil
        variables.QRCode = nil
        variables.latitude = nil
        variables.longitude = nil
        variables.dosiLocation = nil
        variables.collected = nil
        variables.mismatch = nil
        variables.active = nil
        variables.moderator = nil
        variables.cycle = nil
        itemRecord = nil
        counter = 0
        
        self.photo = nil
        
    }  //end clear data
    
    
    func clearForQR() {
        variables.dosiLocation = nil
        variables.collected = nil
        variables.mismatch = nil
        variables.active = nil
        variables.moderator = nil
    }
    
    func save(){
        variables.cycle = RecordsUpdate.generateCycleDate()
        
        locationManager.requestAlwaysAuthorization()
        //location is nil when there is no GPS fix at all (e.g. WiFi-only iPads
        //with WiFi off). Retrying can't produce a fix, so assign the fallback
        //coordinates (configurable via the CloudKit Settings record) directly
        //instead of sending the user through the alert15 retry loop.
        guard (locationManager.authorizationStatus == .authorizedWhenInUse ||
               locationManager.authorizationStatus ==  .authorizedAlways),
              let currentLocation = locationManager.location else {
            setCoordinates(currentLocation: settings?.defaultCoordinates ?? Slac.defaultCoordinates)
            self.alert8()
            return
        }

        if(Slac.isLocationInRange(location: currentLocation) || outOfRangeCounter >= numberOfGPSRetry ) {
            setCoordinates(currentLocation: (outOfRangeCounter >= numberOfGPSRetry ? (settings?.defaultCoordinates ?? Slac.defaultCoordinates) : currentLocation))
            self.alert8()
        } else{
            //Wrong Location, Show Try Again alert
            self.outOfRangeCounter+=1
            self.alert15()
        }
    }
    
    func setCoordinates(currentLocation: CLLocation) {
        
        let latitude = String(format: "%.8f", currentLocation.coordinate.latitude)
        let longitude = String(format: "%.8f", currentLocation.coordinate.longitude)
        
        variables.latitude = latitude
        variables.longitude = longitude
    }
    
    fileprivate func configReachability() {
        reachability.whenReachable = { reachability in self.outerView.backgroundColor = UIColor(named: "MainOnline") }
        reachability.whenUnreachable = { reachability in self.outerView.backgroundColor = UIColor(named: "MainOffline") }
        
        do {
            try reachability.startNotifier()
        }
        catch {
            print("Unable to start notifier")
        }
    }
    
} //end extension methods
/*
 
 @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 
 */

//MARK:  Extension ScannerViewController

extension ScannerViewController {  //queries
    
    func queryForDosiFound() {
        dispatchGroup.enter()
        
        locations.filter(by: { l in l.dosinumber == variables.dosiNumber!}, completionHandler: { items in
            var lrecords = [CKRecord]()
            for item in items {
                lrecords.append(item.to())
            }
            
            if lrecords != [] {
                variables.active = lrecords[0]["active"] as? Int64
                variables.collected = lrecords[0]["collectedFlag"] as? Int64
                variables.QRCode = lrecords[0]["QRCode"] as? String
                variables.dosiLocation = lrecords[0]["locdescription"] as? String
                variables.cycle = lrecords[0]["cycleDate"] as? String
                if lrecords[0]["moderator"] != nil { variables.moderator = lrecords[0]["moderator"] as? Int64 }
                if lrecords[0]["mismatch"] != nil { variables.mismatch = lrecords[0]["mismatch"] as? Int64 }
                
                self.itemRecord = lrecords[0]
            }
            
            self.records = lrecords
            self.dispatchGroup.leave()
        })
    } //end queryforDosiFound
    
    
    func queryForQRFound() {
        dispatchGroup.enter()
        
        locations.filter(by: { l in l.QRCode == variables.QRCode! && l.createdDate != nil}, completionHandler: { items in
            var litems = [LocationRecordCacheItem](items)
            litems.sort {
                $0.createdDateForSort > $1.createdDateForSort
            }
            var lrecords = [CKRecord]()
            for item in litems {
                lrecords.append(item.to())
            }
            if lrecords != [] {
                variables.active = lrecords[0]["active"] as? Int64
                variables.dosiLocation = lrecords[0]["locdescription"] as? String
                if lrecords[0]["collectedFlag"] != nil { variables.collected = lrecords[0]["collectedFlag"] as? Int64 }
                if lrecords[0]["dosinumber"] != nil { variables.dosiNumber = lrecords[0]["dosinumber"] as? String }
                if lrecords[0]["moderator"] != nil { variables.moderator = lrecords[0]["moderator"] as? Int64 }
                if lrecords[0]["mismatch"] != nil { variables.mismatch = lrecords[0]["mismatch"] as? Int64 }
                if lrecords[0]["cycleDate"] != nil { variables.cycle = lrecords[0]["cycleDate"] as? String }
                
                self.itemRecord = lrecords[0]
            }
            
            self.records = lrecords
            
            self.dispatchGroup.leave()
        })
    } //end queryForQRFound
    
    
    func queryForDosiUsed(tempDosi: String) {
        dispatchGroup.enter()
        
        locations.filter(by: { l in l.dosinumber == tempDosi}, completionHandler: { items in
            var lrecords = [CKRecord]()
            for item in items {
                lrecords.append(item.to())
            }
            
            self.records = lrecords
            self.dispatchGroup.leave()
        })
    } //end queryForDosiUsed
    
    
    func queryForQRUsed(tempQR: String) {
        dispatchGroup.enter()
        
        locations.filter(by: { l in l.QRCode == tempQR && l.createdDate != nil}, completionHandler: {items in
            var litems = [LocationRecordCacheItem](items)
            litems.sort {
                $0.createdDateForSort > $1.createdDateForSort
            }
            var lrecords = [CKRecord]()
            for item in litems {
                lrecords.append(item.to())
            }
            if lrecords != [] {
                variables.active = lrecords[0]["active"] as? Int64
                variables.dosiLocation = lrecords[0]["locdescription"] as? String
                if lrecords[0]["collectedFlag"] != nil { variables.collected = lrecords[0]["collectedFlag"] as? Int64}
                if lrecords[0]["moderator"] != nil { variables.moderator = lrecords[0]["moderator"] as? Int64 }
                if lrecords[0]["mismatch"] != nil { variables.mismatch = lrecords[0]["mismatch"] as? Int64 }
            }
            
            self.records = lrecords
            self.dispatchGroup.leave()
        })
        
    } //end queryForQRUsed
    
} //end extension queries

/*
 
 @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 
 */

extension ScannerViewController { //camera
    func openCamera(tempDesc: String?){
        if tempDesc != nil {
            variables.dosiLocation = tempDesc
        }
        
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.allowsEditing = true
        vc.delegate = self
        present(vc, animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        guard let image = info[.editedImage] as? UIImage else {
            print("No image found")
            return
        }

        self.photo = image
        
        self.alert8()
    }
}


extension ScannerViewController {  //alerts
    
    
    func alert1() {
        
        let alert = UIAlertController(title: "Dosimeter Not Found:\n\(variables.dosiNumber ?? "Nil Dosi")", message: nil, preferredStyle: .alert)
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: handlerCancel)
        
        let deployDosimeter = UIAlertAction(title: "Deploy", style: .default) { (_) in
            variables.QRCode = nil
            self.deploy()
            self.alert4()
        } //end let
        
        alert.addAction(deployDosimeter)
        alert.addAction(cancel)
        
        DispatchQueue.main.async { //UIAlerts need to be shown on the main thread.
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert1
    
    
    func alert2() {
        
        let title = itemRecord != nil ? "Location Found:\n\(variables.QRCode ?? "Nil QRCode")" : "New Location:\n\(variables.QRCode ?? "Nil QRCode")"
        
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: handlerCancel)
        
        let deployDosimeter = UIAlertAction(title: "Deploy", style: .default) { (_) in
            variables.dosiNumber = nil
            self.deploy()
            self.alert5()
        } //end let
        
        alert.addAction(deployDosimeter)
        alert.addAction(cancel)
        
        DispatchQueue.main.async { //UIAlerts need to be shown on the main thread.
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert2
    
    
    func alert2a() {
        
        let message = "Please activate this location to deploy a dosimeter."
        
        //set up alert
        let alert = UIAlertController.init(title: "Inactive Location:\n\(variables.QRCode ?? "Nil QRCode")", message: message, preferredStyle: .alert)
        let OK = UIAlertAction(title: "OK", style: .default, handler: handlerCancel)
        
        alert.addAction(OK)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
    //MARK:  Alert 3a Exchange
    func alert3a() {
        
        let message = "\nCycle Date: \(variables.cycle ?? "Nil Cycle")"
        let alert = PopupAlertController(title: "Exchange Dosimeter:\n\(variables.dosiNumber ?? "Nil Dosi")\n\nLocation:\n\(variables.QRCode ?? "Nil QRCode")", message: message)
        // The RGD toggle is now a proper switch row, replacing the old combo of an
        // RGD reopen-action with a UISwitch floated at a fixed frame. The backend
        // mismatch key is unchanged.
        alert.addSwitch(title: "RGD", isOn: variables.mismatch == 1) { variables.mismatch = $0 ? 1 : 0 }
        alert.addAction(PopupAction(title: "Exchange") { [weak self] in
            self?.collect(collected: 1, mismatch: variables.mismatch ?? 0, modifiedDate: Date(timeInterval: 0, since: Date()))
            self?.alert11a()
        })
        alert.addAction(PopupAction(title: "Cancel", style: .cancel) { [weak self] in self?.handlerCancel(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert3a
    
    //MARK:  Alert 3i Collect
    func alert3i() {
        
        let message = "\nCycle Date: \(variables.cycle ?? "Nil Cycle")"
        let alert = PopupAlertController(title: "Collect Dosimeter:\n\(variables.dosiNumber ?? "Nil Dosi")\n\nLocation:\n\(variables.QRCode ?? "Nil QRCode")", message: message)
        // RGD toggle as a switch row, replacing the floated-UISwitch hack. The
        // backend mismatch key is unchanged.
        alert.addSwitch(title: "RGD", isOn: variables.mismatch == 1) { variables.mismatch = $0 ? 1 : 0 }
        alert.addAction(PopupAction(title: "Collect") { [weak self] in
            self?.collect(collected: 1, mismatch: variables.mismatch ?? 0, modifiedDate: Date(timeInterval: 0, since: Date()))
            self?.alert11()
        })
        alert.addAction(PopupAction(title: "Cancel", style: .cancel) { [weak self] in self?.handlerCancel(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }

    } //end alert3i
    
    
    func alert3() {
        
        let message = "Please scan the new dosimeter for location \(variables.QRCode ?? "Nil Dosi")."
        let alert = PopupAlertController(title: "Replace Dosimeter", message: message)
        alert.setImage(scannerImage(named: "Inlight", ofType: "jpg"))
        alert.addAction(PopupAction(title: "OK") { [weak self] in self?.handlerOK(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert3
    
    
    func alert4() {
        
        let message = "Dosimeter barcode accepted \(variables.dosiNumber ?? "Nil Dosi"). Please scan the corresponding location code."
        let alert = PopupAlertController(title: "Scan Accepted", message: message)
        alert.setImage(scannerImage(named: "QRCodeImage", ofType: "png"))
        alert.addAction(PopupAction(title: "OK") { [weak self] in self?.handlerOK(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert4
    
    
    func alert5() {
        
        let message = "Location code accepted \(variables.QRCode ?? "Nil QR"). Please scan the corresponding dosimeter."
        let alert = PopupAlertController(title: "Scan Accepted", message: message)
        alert.setImage(scannerImage(named: "Inlight", ofType: "jpg"))
        alert.addAction(PopupAction(title: "OK") { [weak self] in self?.handlerOK(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert5
    
    
    func alert6a() {
        
        let message = "Try again...Please scan the corresponding location code."
        let alert = PopupAlertController(title: "Error", message: message)
        alert.setImage(scannerImage(named: "QRCodeImage", ofType: "png"))
        alert.addAction(PopupAction(title: "OK", style: .cancel) { [weak self] in self?.handlerOK(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert6a
    
    
    func alert6b() {
        
        let message = "Try again...Please scan the corresponding dosimeter."
        let alert = PopupAlertController(title: "Error", message: message)
        alert.setImage(scannerImage(named: "Inlight", ofType: "jpg"))
        alert.addAction(PopupAction(title: "OK", style: .cancel) { [weak self] in self?.handlerOK(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert6b
    
    
    func alert7a(code: String) {
        
        let message = "Try again...Please scan a new dosimeter."
        let alert = PopupAlertController(title: "Duplicate Dosimeter:\n\(code)", message: message)
        alert.setImage(scannerImage(named: "Inlight", ofType: "jpg"))
        alert.addAction(PopupAction(title: "OK", style: .cancel) { [weak self] in self?.handlerOK(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert7a
    
    
    func alert7b(code: String) {
        
        let title = variables.collected == 0 ? "Location In Use:\n\(code)" : "Inactive Location:\n\(variables.QRCode ?? "Nil QRCode")"
        let message = "Try again...Please scan a different location."
        let alert = PopupAlertController(title: title, message: message)
        alert.setImage(scannerImage(named: "QRCodeImage", ofType: "png"))
        alert.addAction(PopupAction(title: "OK", style: .cancel) { [weak self] in self?.handlerOK(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    } //end alert7b
    
    //MARK:  Alert8
    func alert8() {
        let alert = PopupAlertController(title: "Deploy Dosimeter:\n\(variables.dosiNumber ?? "Nil Dosi")",
                                         message: "\nLocation: \(variables.QRCode ?? "Nil QRCode")")
        // Location field, Moderator toggle, and RGD toggle are proper rows. The field
        // writes variables.dosiLocation on every edit, so Save and the camera flow read
        // the current value without the old reopen-the-alert hack or a floated UISwitch.
        alert.addTextField(text: variables.dosiLocation, placeholder: "Type or dictate location details") {
            variables.dosiLocation = $0
        }
        alert.addSwitch(title: "Moderator", isOn: variables.moderator == 1) { variables.moderator = $0 ? 1 : 0 }
        // RGD flags a dosimeter placed on a Radiation Generating Device. Same backend
        // column (mismatch) as the Exchange/Collect RGD toggles; saveDeployedLocation
        // already persists it.
        alert.addSwitch(title: "RGD", isOn: variables.mismatch == 1) { variables.mismatch = $0 ? 1 : 0 }
        if reachability.isReachable {
            alert.addAction(PopupAction(title: (self.photo == nil) ? "Add photo" : "Replace photo") { [weak self] in
                self?.openCamera(tempDesc: variables.dosiLocation)
            })
        }
        alert.addAction(PopupAction(title: "Save") { [weak self] in self?.saveDeployedLocation() })
        alert.addAction(PopupAction(title: "Cancel", style: .cancel) { [weak self] in self?.handlerCancel(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert8

    // Validates and saves a deployed location from alert8. An empty location or a
    // missing QR code each bounce to an explanatory popup instead of saving.
    func saveDeployedLocation() {
        let text = variables.dosiLocation ?? ""
        if text.isEmpty {
            let prompt = PopupAlertController(title: "Location Required", message: "Please enter a location.")
            prompt.addAction(PopupAction(title: "OK") { [weak self] in self?.alert8() })
            DispatchQueue.main.async { self.present(prompt, animated: true, completion: nil) }
            return
        }
        if variables.QRCode == nil {
            // Refuse to deploy a location whose QR code never got captured. Saving
            // the "Nil QRCode" placeholder can't be reconciled later, so bounce back
            // to the scanner to rescan.
            let qrError = PopupAlertController(title: "Location QR Code Missing",
                                               message: "The location QR code wasn't captured. Please scan the location QR code again before deploying.")
            qrError.addAction(PopupAction(title: "OK") { [weak self] in self?.handlerCancel(alert: nil) })
            DispatchQueue.main.async { self.present(qrError, animated: true, completion: nil) }
            return
        }

        let description = text.replacingOccurrences(of: ",", with: "-")
        let newRecord = CKRecord(recordType: "Location")
        newRecord.setValue(variables.latitude ?? "Nil Latitude", forKey: "latitude")
        newRecord.setValue(variables.longitude ?? "Nil Longitude", forKey: "longitude")
        newRecord.setValue(description, forKey: "locdescription")
        newRecord.setValue(variables.dosiNumber ?? "Nil Dosi", forKey: "dosinumber")
        newRecord.setValue(0, forKey: "collectedFlag")
        newRecord.setValue(variables.cycle, forKey: "cycleDate")
        newRecord.setValue(variables.QRCode ?? "Nil QRCode", forKey: "QRCode")
        newRecord.setValue(variables.moderator ?? 0, forKey: "moderator")
        newRecord.setValue(1, forKey: "active")
        newRecord.setValue(Date(timeInterval: 0, since: Date()), forKey: "createdDate")
        newRecord.setValue(Date(timeInterval: 0, since: Date()), forKey: "modifiedDate")
        newRecord.setValue(variables.mismatch ?? 0, forKey: "mismatch")

        if let qrCode = variables.QRCode {
            let reportGroup = Groups[qrCode]
            newRecord.setValue(reportGroup, forKey: "reportGroup")
        }

        var locationRecordCacheItem = LocationRecordCacheItem(withRecord: newRecord)!

        if let photo = self.photo {
            do {
                try locationRecordCacheItem.setPhoto(photo: photo)
            } catch {
                print("Unexpected error: \(error).")
            }
        }

        self.locations.save(item: locationRecordCacheItem, completionHandler: nil)
        self.photo = nil
        self.outOfRangeCounter = 0
        self.alert10() //Success
    }
    
    
    func alert9() {  //invalid barcode type
        
        let message = "Please scan either a location barcode or a dosimeter."
        
        //set up alert
        let alert = UIAlertController.init(title: "Invalid Barcode Type", message: message, preferredStyle: .alert)
        let OK = UIAlertAction(title: "OK", style: .cancel, handler: handlerCancel)
        
        alert.addAction(OK)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert9
    
    
    func alert9a() {  //already collected dosimeter
        
        let message = "This dosimeter has already been collected."
        
        //set up alert
        let alert = UIAlertController.init(title: "Invalid Dosimeter:\n\(variables.dosiNumber ?? "Nil Dosi")", message: message, preferredStyle: .alert)
        let OK = UIAlertAction(title: "OK", style: .cancel, handler: handlerCancel)
        alert.addAction(OK)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert9
    
    
    func alert10(){  //Success! (Deploy)
        
        //let message = "Data saved: \nQR Code: \(variables.QRCode ?? "Nil QRCode")\nDosimeter: \(variables.dosiNumber ?? "Nil Dosi")\nLocation: \(variables.dosiLocation ?? "Nil location")\nFlag (Depl'y = 0, Collected = 1): 0\nLatitude: \(variables.latitude ?? "Nil Latitude")\nLongitude: \(variables.longitude ?? "Nil Longitude")\nWear Date: \(variables.cycle ?? "Nil cycle")\nMismatch (No = 0 Yes = 1): \(variables.mismatch ?? 0)\nModerator (No = 0 Yes = 1): \(variables.moderator ?? 0)"
        
        let message = "QR Code: \(variables.QRCode ?? "Nil QRCode")\nDosimeter: \(variables.dosiNumber ?? "Nil Dosi")"
        
        //set up alert
        let alert = UIAlertController.init(title: "Save Successful!", message: message, preferredStyle: .alert)
        let OK = UIAlertAction(title: "OK", style: .default, handler: handlerCancel)
        
        alert.addAction(OK)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert10
    
    
    func alert11() {  //Success! (Collect)
        
        //let message = "Data Saved:\nQR Code: \(variables.QRCode ?? "Nil QRCode")\nDosimeter: \(variables.dosiNumber ?? "Nil Dosi")\nLocation: \(variables.dosiLocation ?? "Nil location")\nFlag (Depl'y = 0, Collected = 1): 1 \nMismatch (No = 0 Yes = 1): \(variables.mismatch ?? 0)"
        
        let message = "QR Code: \(variables.QRCode ?? "Nil QRCode")\nDosimeter: \(variables.dosiNumber ?? "Nil Dosi")"
        
        //set up alert
        let alert = UIAlertController.init(title: "Collection Successful!", message: message, preferredStyle: .alert)
        let OK = UIAlertAction(title: "OK", style: .default, handler: handlerCancel)
        
        alert.addAction(OK)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert11
    
    
    func alert11a() {  //Success! (Exchange)
        
        //let message = "Data Saved:\nQR Code: \(variables.QRCode ?? "Nil QRCode")\nDosimeter: \(variables.dosiNumber ?? "Nil Dosi")\nLocation: \(variables.dosiLocation ?? "Nil location")\nFlag (Depl'y = 0, Collected = 1): 1 \nMismatch (No = 0 Yes = 1): \(variables.mismatch ?? 0)"
        
        let message = "QR Code: \(variables.QRCode ?? "Nil QRCode")\nDosimeter: \(variables.dosiNumber ?? "Nil Dosi")"
        
        //set up alert
        let alert = UIAlertController.init(title: "Collection Successful!", message: message, preferredStyle: .alert)
        let OK = UIAlertAction(title: "OK", style: .default) { (_) in
            self.deploy()
            variables.mismatch = 0
            variables.dosiNumber = nil
            self.alert3()
        }
        
        alert.addAction(OK)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert11a
    
    //MARK:  Alert12
    func alert12() {  //invalid code, rescan
        
        let message = "Invalid barcode, please rescan!"
        
        //set up alert
        let alert = UIAlertController.init(title: "Invalid code", message: message, preferredStyle: .alert)
        let rescan = UIAlertAction(title: "Rescan", style: .default) { (_) in
            self.isRescan = true
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
        }
        
        alert.addAction(rescan)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert12
    
    //MARK:  Alert13
    func alert13(nextFunction: @escaping () -> Void) {  //invalid cycle date
        
        let message = "This dosimeter already exchanged in the current cycle. Are you sure you want to continue?"

        let alert = PopupAlertController(title: "Warning", message: message)
        alert.setBackgroundColor(UIColor(named: "WarningDialogBackground"))
        alert.addAction(PopupAction(title: "Continue", style: .destructive) { nextFunction() })
        alert.addAction(PopupAction(title: "Cancel", style: .cancel) { [weak self] in self?.handlerCancel(alert: nil) })

        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert13
    
    //MARK:  Alert14
    func alert14() {  //invalid code length, rescan
        let min = settings!.dosimeterMinimumLength
        let max = settings!.dosimeterMaximumLength
        var message = "The length of the dosimeter barcodes must be "
        message += min == max ? "\(min) "
                                : "between \(min) and \(max) "
        message += "characters. Please rescan!"
        
        self.audioPlayer?.beepFail()
        
        //set up alert
        let alert = UIAlertController.init(title: "Invalid length", message: message, preferredStyle: .alert)
        let rescan = UIAlertAction(title: "Rescan", style: .default) { (_) in
            self.isRescan = true
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
        }
        
        alert.addAction(rescan)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }  //end alert14
    
    //MARK:  Alert15
    func alert15() { //Outside of SLAC
        let message = (outOfRangeCounter == numberOfGPSRetry) ? "Your fix is still outside of SLAC property. Please tap Try Again for a final attempt, and if it’s still out of range then standard coordinates will be assigned.  These can be adjusted later in the Tools menu. " : "Your fix is not on SLAC property.  Please tap Try Again."
        
        self.audioPlayer?.beepFail()
        
        let alert = UIAlertController(title: "GPS Coordinate Error\n", message: message, preferredStyle: .alert)
        
        let tryAgain = UIAlertAction(title: "Try Again", style: .cancel){ (_) in
            self.save()
        }
        
        alert.addAction(tryAgain)
        
        DispatchQueue.main.async {   //UIAlerts need to be shown on the main thread.
            
            self.present(alert, animated: true){
                alert.view.superview?.subviews[0].isUserInteractionEnabled = false
            }
        }
    } //end alert15
    
    //Loads a scanner alert image from the app bundle, or nil if it is missing.
    func scannerImage(named name: String, ofType ext: String) -> UIImage? {
        guard let path = Bundle.main.path(forResource: name, ofType: ext) else { return nil }
        return UIImage(contentsOfFile: path)
    }

}//end extension alerts

/*
 
 @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 
 */

extension ScannerViewController {  //handlers
    
    func handlerOK(alert: UIAlertAction!) {  //used for OK in the alert prompt.
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
        
    } //end handler
    
    func handlerCancel(alert: UIAlertAction!) {
        
        self.clearData()
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }
    
} //end extension
