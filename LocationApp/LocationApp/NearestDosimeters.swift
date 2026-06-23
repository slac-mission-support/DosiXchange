//
//  NearestDosimeters.swift
//  LocationApp
//
//  Created by Ford, Ryan M. on 2/22/19.
//  Copyright © 2019 Ford, Ryan M. All rights reserved.
//  Working from branch

import Foundation
import UIKit
import CoreLocation
import CloudKit

class NearestLocations: UIViewController, UITableViewDataSource, UITableViewDelegate, CLLocationManagerDelegate {
    class Location {
        let id: String
        let distance: Int
        let qrCode: String
        let details: String
        let hasPhoto: Bool
        
        init(id: String, distance: Int, qrCode: String, details: String, hasPhoto: Bool) {
            self.id = id
            self.distance = distance
            self.qrCode = qrCode
            self.details = details
            self.hasPhoto = hasPhoto
        }
    }

    let dispatchGroup = DispatchGroup()
    let recordsupdate = RecordsUpdate()
    var locations: Locations = container.locations

    var locationManager:CLLocationManager = CLLocationManager()
    var startLocation: CLLocation!
    
    var latitude:String = ""
    var longitude:String = ""
    var distance:Int = 0
    var loc:String = ""
    var QRCode:String = ""
    var dosimeter:String = ""
    var mod:Int64 = 0
    var segment:Int = 0
    
    var preSortedRecords = [Location]()
    var sortedRecords = [Location]()
    var abcRecords = [Location]()
    var selected: Location?
    
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var nearestTableView: UITableView!

    override func viewDidLoad() {
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .light
        } else {
            // Fallback on earlier versions
        }
        super.viewDidLoad()
        nearestTableView.delegate = self
        nearestTableView.dataSource = self
        segmentedControl.selectedSegmentIndex = segment
        
        //Core Location
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        startLocation = locationManager.location ?? Slac.defaultCoordinates
        
        //get data
        queryAscendLocations()
        
        //wait for query to finish
        dispatchGroup.wait()
        self.nearestTableView.reloadData()

        let refreshControl = UIRefreshControl()
        refreshControl.attributedTitle = NSAttributedString(string: "Pull to Refresh Locations")
        //pulling the table syncs from CloudKit first, then repopulates with fresh data.
        refreshControl.addTarget(self, action: #selector(refreshFromCloud), for: .valueChanged)
        refreshControl.beginRefreshing()
        self.nearestTableView.refreshControl = refreshControl

    } //end viewDidLoad
    
    @IBAction func done(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    //segment control
    @IBAction func tableSwitch(_ sender: UISegmentedControl) {
        segment = sender.selectedSegmentIndex
        nearestTableView.reloadData()
    }
    
    //location manager stubs
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        //start location is needed to compute distance
        let latestLocation: CLLocation = locations[locations.count - 1]
        
        if startLocation == nil {
            startLocation = latestLocation
        }
        
    }//end func
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location permission denied.")
        if startLocation == nil {
            startLocation = Slac.defaultCoordinates
        }
    } //end func
    
    
    @IBAction func dismissNearest(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    //tableView protocol stubs
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let location = segment == 1 ? abcRecords[indexPath.row] : sortedRecords[indexPath.row]
        if location.hasPhoto {
            selected = location
            self.performSegue(withIdentifier: "ShowPhoto", sender: self)
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedRecords.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: "PlainCell", for: indexPath)
        
        //dynamic cell height sizing
        nearestTableView.estimatedRowHeight = 90
        nearestTableView.rowHeight = UITableView.automaticDimension
        
        //wait for query to finish
        dispatchGroup.wait()
        
        //fill the textLabel with the relevant text
        var distanceText = ""
        var qrText = ""
        var detailsText = ""
        var hasPhoto = false
        
        switch segment {
        case 1:
            distanceText = "\(self.abcRecords[indexPath.row].distance)"
            qrText =  "\(self.abcRecords[indexPath.row].qrCode)"
            detailsText = "\(self.abcRecords[indexPath.row].details)"
            hasPhoto = self.abcRecords[indexPath.row].hasPhoto
        default:
            distanceText = "\(self.sortedRecords[indexPath.row].distance)"
            qrText =  "\(self.sortedRecords[indexPath.row].qrCode)"
            detailsText = "\(self.sortedRecords[indexPath.row].details)"
            hasPhoto = self.sortedRecords[indexPath.row].hasPhoto
        }
        
        //configure the cell
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.text = "\(qrText) (\(distanceText) meters)"
        
        cell.detailTextLabel?.font = UIFont(name: "Arial", size: 15)
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.lineBreakMode = NSLineBreakMode.byWordWrapping
        cell.detailTextLabel?.text = "\(detailsText)"

        if #available(iOS 13.0, *) {
            cell.accessoryView = hasPhoto ? UIImageView(image: UIImage(systemName: "camera")) : nil
        } else {
            // Fallback on earlier versions
        }
        cell.accessoryType = hasPhoto ? .disclosureIndicator : .none
        
        
        return cell
        
    } //end function
    
} //end class


// query and helper functions
extension NearestLocations {
    
    @objc func queryAscendLocations() {
        //clear out buffer
        self.preSortedRecords = [Location]()
        self.sortedRecords = [Location]()

        let cycleDate = RecordsUpdate.generateCycleDate()
        let priorCycleDate = RecordsUpdate.generatePriorCycleDate(cycleDate: cycleDate)
        let items = locations.filter(by: { $0.collectedFlag == 0 && $0.cycleDate == priorCycleDate && $0.active == 1})
        for item in items {
            recordFetchedBlock(record: item)
        }
        
        self.sortedRecords = self.preSortedRecords.sorted { $0.distance < $1.distance }
        self.abcRecords = self.preSortedRecords.sorted { $0.qrCode < $1.qrCode }
        
        //refresh table
        DispatchQueue.main.async {
            if self.nearestTableView != nil {
                self.nearestTableView.refreshControl?.endRefreshing()
                self.nearestTableView.reloadData()
            }
        }
    } //end func

    //pull-to-refresh: pull the latest records from CloudKit, then re-filter and reload.
    //synchronize() no-ops while offline (returns the cached count), so an offline pull still
    //falls through to queryAscendLocations, which ends refreshing and reloads from the cache.
    @objc func refreshFromCloud() {
        DispatchQueue.global(qos: .background).async {
            self.locations.synchronize(loaded: { _ in
                self.queryAscendLocations()
            })
        }
    }


    //to be executed for each fetched record
    func recordFetchedBlock(record: LocationRecordCacheItem) {
        //changed nils in string fields to "".
        if record.QRCode != "" {self.QRCode = record.QRCode }
        if record.latitude != "" {self.latitude = record.latitude }
        if record.longitude != "" {self.longitude = record.longitude }
        if record.dosinumber != "" {self.dosimeter = record.dosinumber!
        } else if record.dosinumber == "" {
            self.dosimeter = "Active without Dosimeter!"  //show "active no dosimeter" in lists Ver 1.2
        }
        if record.locdescription != "" {self.loc = record.locdescription}
        if record.moderator != nil {self.mod = record.moderator! }
        
        //compute distance between start location and the point
        let rowCoordinates = CLLocation(latitude: Double(self.latitude)!, longitude: Double(self.longitude)!)
        let distanceBetween:CLLocationDistance = self.startLocation.distance(from: rowCoordinates)
        let distanceBetweenFormatted = String(format: "%.0f", distanceBetween)
        self.distance = Int(distanceBetweenFormatted)!
        
        let details = "Dosimeter: \(self.dosimeter)\nModerator: \(self.mod == 1 ? "Yes" : "No")\n\(self.loc)"
        
        //in order to be able to sort by distance as an integer (not a string).
        //let line = self.getLine(distance: self.distance, QRCode: self.QRCode, dosimeter: self.dosimeter, detail: details)
        //build the array
        self.preSortedRecords.append(Location(id: record.recordName!, distance: distance, qrCode: record.QRCode, details: details, hasPhoto: record.hasPhoto))
        
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)  {
      if segue.identifier == "ShowPhoto", let vc = segue.destination as? PhotoViewController {
          locations.fetch(id: selected!.id, completionHandler: { location, error in
              if let url = location?.photo?.fileURL?.path {
                  DispatchQueue.main.async {
                      vc.photoView.image = UIImage(contentsOfFile: url)
                  }
              }
          })
      }
    }
    
} //end extension

