//
//  ActiveLocationsViewController.swift
//  LocationApp
//
//  Created by Choi, Helen B on 7/1/19.
//  Copyright © 2019 Ford, Ryan M. All rights reserved.
//

import UIKit

//MARK:  Class
class ActiveLocations: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    
    let locations = container.locations
    
    var segment:Int = 0
    var displayInfo :[[(LocationRecordDelegate, String, String)]] = [[],[]]
    var searches : [[(LocationRecordDelegate, String, String)]] = [[],[]]
    var searching = false
    let refreshControl = UIRefreshControl()
    
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var activesTableView: UITableView!
    @IBOutlet weak var searchBar: UISearchBar!
    let dispatchGroup = DispatchGroup()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .light
        } else {
            // Fallback on earlier versions
        }
        
        
        //Do any additional setup after loading the view.
        activesTableView.delegate = self
        activesTableView.dataSource = self
        searchBar.delegate = self
        segmentedControl.selectedSegmentIndex = segment
        
        //Table View SetUp
        refreshControl.attributedTitle = NSAttributedString(string: "Pull to Refresh Locations")
        //this query will populate the table when the table is pulled.
        refreshControl.addTarget(self, action: #selector(queryDatabase), for: .valueChanged)
        self.activesTableView.refreshControl = refreshControl
        
        //this query will populate the tableView when the view loads.
       // queryDatabase()
        
    } //end viewDidLoad
    
    @IBAction func done(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    //MARK:  Table View
    @IBAction func tableSwitch(_ sender: UISegmentedControl) {
        segment = sender.selectedSegmentIndex
        activesTableView.reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        queryDatabase()
    }
    
    //table functions
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searching ? searches[segment].count : displayInfo[segment].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "QRCell", for: indexPath)
        
        activesTableView.estimatedRowHeight = 60
        activesTableView.rowHeight = UITableView.automaticDimension
        
        let QRCode = searching ? searches[segment][indexPath.row].1 : displayInfo[segment][indexPath.row].1
        let locdescription = searching ? searches[segment][indexPath.row].2 : displayInfo[segment][indexPath.row].2
        
        //format cell title
        cell.textLabel?.font = UIFont(name: "Arial", size: 16)
        cell.textLabel?.text = "\(QRCode)"
        //format cell subtitle
        cell.detailTextLabel?.font = UIFont(name: "Arial", size: 12)
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.lineBreakMode = NSLineBreakMode.byWordWrapping
        cell.detailTextLabel?.text = "\(locdescription)"
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        let mainStoryboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let vc = mainStoryboard.instantiateViewController(withIdentifier: "LocationDetails") as! LocationDetails
        
        vc.record = searching ? searches[segment][indexPath.row].0 : displayInfo[segment][indexPath.row].0
        vc.transitioningDelegate = self
        vc.locationDetailDelegate = self
        
        self.present(vc, animated: true)
    }
    
    fileprivate func clearSearchedItems() {
        searches = [[(LocationRecordDelegate, String, String)]]()
        searches.append([(LocationRecordDelegate, String, String)]())
        searches.append([(LocationRecordDelegate, String, String)]())
    }
    
    fileprivate func clearLocationItems() {
        displayInfo = [[],[]]
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searching = true

        clearSearchedItems()
        
        searches[0] = displayInfo[0].filter( { $0.1.range(of: searchText, options: .caseInsensitive) != nil
                                            || $0.2.range(of: searchText, options: .caseInsensitive) != nil})
        searches[1] = displayInfo[1].filter( { $0.1.range(of: searchText, options: .caseInsensitive) != nil
                                            || $0.2.range(of: searchText, options: .caseInsensitive) != nil})
        activesTableView.reloadData()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searching = false
        searchBar.text = ""
        searchBar.endEditing(true)
        activesTableView.reloadData()
        queryDatabase()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.endEditing(true)
    }

}

//query and helper functions
//MARK:  Extensions
extension ActiveLocations : UIViewControllerTransitioningDelegate{
    
    @objc func queryDatabase() {
        dispatchGroup.wait()
        dispatchGroup.enter()
        clearLocationItems()
        activityIndicator.startAnimating()
        let items = locations.filter(by: { l in l.createdDate != nil })
        let dictionary = Dictionary(grouping: items, by: {i in i.QRCode})
        for item in dictionary {
            addLocation(item.value.filter({ $0.createdDate != nil }))
        }
        displayInfo[0].sort { ($0.1, $0.2) < ($1.1, $1.2) }
        displayInfo[1].sort { ($0.1, $0.2) < ($1.1, $1.2) }
        activesTableView.reloadData()
        activityIndicator.stopAnimating()
        dispatchGroup.leave()
        refreshControl.endRefreshing()
   } //end func
        
    func addLocation(_ records: [LocationRecordCacheItem]) {
        if let item = records.max(by: { $0.createdDateForSort < $1.createdDateForSort }) {
            let flag = item.active == 1 ? 0 : 1
            displayInfo[flag].append((item, item.QRCode, item.locdescription))
        }
    }
      
//MARK:  Alert 12
    
    //Handle nils in active field (rare - set by system)
    func alert12() {
        DispatchQueue.main.async { //UIAlerts need to be shown on the main thread.
            
        let alert = UIAlertController(title: "Contact Administrator", message: "Incomplete records were suppressed from this view. \n You can continue using the app.", preferredStyle: .alert)
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(cancel)
        self.present(alert, animated: true, completion: nil)
        
        }
    } //end alert12

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        queryDatabase()
        return nil
    }
}

extension ActiveLocations: LocationDetailDelegate {
    func activeStatusChanged(active: Bool) {
        segment = active ? 0 : 1
        segmentedControl.selectedSegmentIndex = segment
    }
}
