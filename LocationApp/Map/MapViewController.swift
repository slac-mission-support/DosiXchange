//
//  MapViewController.swift
//  LocationApp
//
//  Created by Ford, Ryan M. on 11/24/18.
//  Copyright © 2018 Ford, Ryan M. All rights reserved.
//

import Foundation
import UIKit
import MapKit
import CloudKit
//import Contacts


//MARK:  Class
class MapViewController: UIViewController {
    let locations = container.locations
    @IBOutlet weak var MapView: MKMapView!
    @IBOutlet weak var filtersButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    var locationmanager = CLLocationManager()
    let database = CKContainer.default().publicCloudDatabase
    var cycleDate = RecordsUpdate()
    var checkQR = ""
    
    var filters:[UIColor:Bool] = [
        .red:true,
        .green:true,
        .orange:false,
        .purple:true,
        .blue:true,
        .yellow:false
    ]
    
    override func viewDidLoad() {
        
        locationmanager.delegate = self
        locationmanager.requestAlwaysAuthorization()
        locationmanager.startUpdatingLocation()
        let latitude = locationmanager.location?.coordinate.latitude ?? Slac.defaultCoordinates.coordinate.latitude
        let longitude = locationmanager.location?.coordinate.longitude ?? Slac.defaultCoordinates.coordinate.longitude
        self.MapView.delegate = self

        //format filters button
        filtersButton.layer.cornerRadius = 5
        
        //set initial map properties
        let initialLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(center: initialLocation, latitudinalMeters: 150, longitudinalMeters: 150)
        
        //query records
        
        self.MapView.setRegion(region, animated: true)
        self.MapView.mapType = MKMapType.standard
        self.MapView.showsUserLocation = true
        self.MapView.tintColor = UIColor.blue  //showing user location with blue dot.
        
        DispatchQueue.main.async {
            self.locationmanager.startUpdatingLocation()
        }
    }
    
    override func viewDidAppear(_ makk: Bool) {
        queryForMap()
    }
    
    @IBAction func done(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
	
}

//MapView and locationmanager delegate methods
//MARK:  Extension
extension MapViewController: MKMapViewDelegate, CLLocationManagerDelegate {
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        guard let annotation = annotation as? Artwork else { return nil }
        
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: "AnnotationView") as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "AnnotationView")
        }
        
        annotationView?.displayPriority = .required
        annotationView?.canShowCallout = true
        annotationView?.markerTintColor = annotation.markerTintColor
        
        annotationView?.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        
        let label = UILabel()
        label.text = annotation.subtitle
        label.font = UIFont(name: "Arial", size: 12)
        label.numberOfLines = 0
        label.lineBreakMode = NSLineBreakMode.byWordWrapping
        annotationView?.detailCalloutAccessoryView = label
        
        return annotationView
    }
    
    //implement failure methods as part of the delegate
    func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
        print(Error.self)
    }
    
    func mapView(_ mapView: MKMapView, didFailToLocateUserWithError error: Error) {
        print(Error.self)
    }
    
    //tells delegate that new location data is available
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(Error.self)
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print(Error.self)
    }
    
    func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        print(Error.self)
    }
    
    //runs when "i" key is pressed to the right of the pin info bubble
    //delegate method
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                 calloutAccessoryControlTapped control: UIControl) {
        let mainStoryboard: UIStoryboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newViewController = mainStoryboard.instantiateViewController(withIdentifier: "Scanner") as! ScannerViewController
        self.show(newViewController, sender: self)
        
    } //end mapView

}

//filters and switches
//MARK:  Extension 2
extension MapViewController {
    
    //runs when filters button is clicked
    @IBAction func didClickFilters(_ sender: Any) {
        
        DispatchQueue.main.async {
            self.MapView.removeAnnotations(self.MapView.annotations)
            self.filtersButton.isHidden = true
        }
        filtersAlert()
    }
    
    //alert to filter pins
    func filtersAlert() {
        
        //configure alert message
        let font1 = [NSAttributedString.Key.font: UIFont(name: "Arial-BoldMT", size: 22)!,
                     NSAttributedString.Key.paragraphStyle: NSMutableParagraphStyle()]
        let font2 = [NSAttributedString.Key.font: UIFont(name: "ArialMT", size: 18)!,
                     NSAttributedString.Key.paragraphStyle: NSMutableParagraphStyle()]
        let message = NSMutableAttributedString(string: "", attributes: font1)
        message.append(NSAttributedString(string: "Active\n\n", attributes: font1))
        message.append(NSAttributedString(string: "\tCurrent Cycle:\n\n\tPrior Cycle:\n\n\tNo Dosimeter:\n\n\n", attributes: font2))
        message.append(NSAttributedString(string: "Inactive\n\n", attributes: font1))
        message.append(NSAttributedString(string: "\tCurrent Cycle:\n\n\tPrior Cycle:\n\n\tNo Dosimeter:\n", attributes: font2))
        
        //set up alert
        let alert = UIAlertController.init(title: nil, message: nil, preferredStyle: .alert)
        alert.setValue(message, forKey: "attributedMessage")
        let OK = UIAlertAction(title: "OK", style: .default, handler: handlerOK)
        
        alert.view.addSubview(redSwitch())
        alert.view.addSubview(greenSwitch())
        alert.view.addSubview(orangeSwitch())
        alert.view.addSubview(purpleSwitch())
        alert.view.addSubview(blueSwitch())
        alert.view.addSubview(yellowSwitch())
        alert.addAction(OK)
        
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    
    //RED PINS - current cycle, active (stop)
    func redSwitch() -> UISwitch {
        let redSwitch = UISwitch(frame: CGRect(x: 170, y: 62, width: 0, height: 0))
        redSwitch.onTintColor = UIColor.red
        redSwitch.tintColor = UIColor.gray
        redSwitch.setOn(filters[.red]!, animated: false)
        redSwitch.addTarget(self, action: #selector(redSwitchDidChange(_:)), for: .valueChanged)
        return redSwitch
    }
    
    @objc func redSwitchDidChange(_ sender: UISwitch!) {
        filters[.red] = sender.isOn
    }
    
    //GREEN PINS - prior cycle, active (exchange)
    func greenSwitch() -> UISwitch {
        let greenSwitch = UISwitch(frame: CGRect(x: 170, y: 102, width: 0, height: 0))
        greenSwitch.onTintColor = UIColor.green
        greenSwitch.tintColor = UIColor.gray
        greenSwitch.setOn(filters[.green]!, animated: false)
        greenSwitch.addTarget(self, action: #selector(greenSwitchDidChange(_:)), for: .valueChanged)
        return greenSwitch
    }
    
    @objc func greenSwitchDidChange(_ sender: UISwitch!) {
        filters[.green] = sender.isOn
    }
    
    
    //ORANGE PINS - active, no dosimeter (deploy)
    func orangeSwitch() -> UISwitch {
        let orangeSwitch = UISwitch(frame: CGRect(x: 170, y: 142, width: 0, height: 0))
        orangeSwitch.onTintColor = UIColor.orange
        orangeSwitch.tintColor = UIColor.gray
        orangeSwitch.setOn(filters[.orange]!, animated: false)
        orangeSwitch.addTarget(self, action: #selector(orangeSwitchDidChange(_:)), for: .valueChanged)
        return orangeSwitch
    }
    
    @objc func orangeSwitchDidChange(_ sender: UISwitch!) {
        filters[.orange] = sender.isOn
    }
    
    
    //PURPLE PINS - current cycle, inactive (stop)
    func purpleSwitch() -> UISwitch {
        let purpleSwitch = UISwitch(frame: CGRect(x: 170, y: 251, width: 0, height: 0))
        purpleSwitch.onTintColor = UIColor.purple
        purpleSwitch.tintColor = UIColor.gray
        purpleSwitch.setOn(filters[.purple]!, animated: false)
        purpleSwitch.addTarget(self, action: #selector(purpleSwitchDidChange(_:)), for: .valueChanged)
        return purpleSwitch
    }
    
    @objc func purpleSwitchDidChange(_ sender: UISwitch!) {
        filters[.purple] = sender.isOn
    }
    
    
    //BLUE PINS - prior cycle, inactive (collect)
    func blueSwitch() -> UISwitch {
        let blueSwitch = UISwitch(frame: CGRect(x: 170, y: 291, width: 0, height: 0))
        blueSwitch.onTintColor = UIColor.blue
        blueSwitch.tintColor = UIColor.gray
        blueSwitch.setOn(filters[.blue]!, animated: false)
        blueSwitch.addTarget(self, action: #selector(blueSwitchDidChange(_:)), for: .valueChanged)
        return blueSwitch
    }
    
    @objc func blueSwitchDidChange(_ sender: UISwitch!) {
        filters[.blue] = sender.isOn
    }
    
    
    //YELLOW PINS - inactive, no dosimeter
    func yellowSwitch() -> UISwitch {
        let yellowSwitch = UISwitch(frame: CGRect(x: 170, y: 331, width: 0, height: 0))
        yellowSwitch.onTintColor = UIColor.yellow
        yellowSwitch.tintColor = UIColor.gray
        yellowSwitch.setOn(filters[.yellow]!, animated: false)
        yellowSwitch.addTarget(self, action: #selector(yellowSwitchDidChange(_:)), for: .valueChanged)
        return yellowSwitch
    }
    
    @objc func yellowSwitchDidChange(_ sender: UISwitch!) {
        filters[.yellow] = sender.isOn
    }
    

    func handlerOK(alert: UIAlertAction!) {
        self.activityIndicator.startAnimating()
        queryForMap()
    }
    
}

//query functions
//MARK:  Extension 3
extension MapViewController {
    
    //query active locations
    func queryForMap() {
        DispatchQueue.main.async {
            self.activityIndicator.startAnimating()
        }
                    
        var items = self.locations.filter(by: { i in i.createdDate != nil })
        items.sort {
            if $0.QRCode == $1.QRCode {
                return $0.createdDateForSort > $1.createdDateForSort
            }
            return $0.QRCode < $1.QRCode
        }
    
        for item in items {
            self.processLocationRecord(item)
        }
        self.finishedLoadingCachedLocationRecords()
    }

    func finishedLoadingCachedLocationRecords() {
        DispatchQueue.main.async {
            self.activityIndicator.stopAnimating()
            self.filtersButton.isHidden = false
        }
    }
    
    // Process a Location record that was fetched from CloudKit
    // or thr local location records cache.
    func processLocationRecord(_ record: LocationRecordDelegate) {
           
        var showErrorAlert = false
        defer {
            //handle rare cases when active is nil.  Notify administrator.
            if showErrorAlert {
                self.alert13()
                print("record skipped")
            }
         }
        
        //fetch QRCode
        guard let QRCode:String = record["QRCode"] as? String else {
            showErrorAlert = true
            return
        }
        
        //if record has the same QRCode as the previous record, skip record
        if QRCode == self.checkQR { return  }
        
        //run whole thing on main thread to prevent "let artwork" line from producing error
        switch record["active"] {
        //handle rare cases when active is nil.  Notify administrator.
        case nil:
            showErrorAlert = true
            return
        default:
            guard let active:Int64 = record["active"] as? Int64,
                  let latitude:String = record["latitude"] as? String,
                  let longitude:String = record["longitude"] as? String,
                  let description:String = record["locdescription"] as? String else {
                      showErrorAlert = true
                      return
            }
                
            let dosimeter = record["dosinumber"] as? String
            let cycleDate = record["cycleDate"] as? String
            let collected = record["collectedFlag"] as? Int64
            
            var fullTitle = "\(QRCode)"
            if collected == 0 && dosimeter != "" {
                fullTitle.append(contentsOf: "\n\(dosimeter ?? "Dosi Nil")")
            }
            self.checkQR = QRCode
            
            let dosiLocations = CLLocationCoordinate2D(latitude: CLLocationDegrees(latitude)!, longitude: CLLocationDegrees(longitude)!)
            DispatchQueue.main.async {
                let artwork = Artwork(title: fullTitle, locDescription: description, active: active, coordinate: dosiLocations, cycleDate: cycleDate, collected: collected) //this has a location manager and needs main thread.
                if(self.filters[artwork.markerTintColor]!) {
                    self.MapView.addAnnotation(artwork)
                }
            }
            return
        }
    }
    
    //MARK:  Alert 13
        
        //Handle nils in active field (rare - set by system)
        func alert13() {
            DispatchQueue.main.async { //UIAlerts need to be shown on the main thread.
                
            let alert = UIAlertController(title: "Contact Administrator", message: "Incomplete records were suppressed from this view. \n You can continue using the app.", preferredStyle: .alert)
            let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                alert.addAction(cancel)
                self.present(alert, animated: true, completion: nil)
            }
        } //end alert12
}


