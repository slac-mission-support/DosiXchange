//
//  Location.swift
//  LocationApp
//
//  Created by Ford, Ryan M. on 11/23/18.
//  Copyright © 2018 Ford, Ryan M. All rights reserved.
//

import Foundation
import UIKit
import MessageUI
import CloudKit
import CoreLocation

class StartupViewController: UIViewController, MFMailComposeViewControllerDelegate, CLLocationManagerDelegate {
    
    let reachability = Reachability()!
    let locations = container.locations
    let location = CLLocationManager()
    let query = Queries()
    let dispatchGroup = DispatchGroup()
    
    let borderColorUp = UIColor(red: 0.887175, green: 0.887175, blue: 0.887175, alpha: 1).cgColor
    let borderColorDown = UIColor(red: 0.887175, green: 0.887175, blue: 0.887175, alpha: 0.2).cgColor

    @IBOutlet var mainView: UIView!
    @IBOutlet weak var scanButton: UIButton!
    @IBOutlet weak var mapButton: UIButton!
    @IBOutlet weak var nearestDosiButton: UIButton!
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var refreshButton: UIButton!
    
    @IBOutlet weak var versionLabel: UILabel!
    @IBOutlet weak var Tools: UIImageView!

    //warning label for iCloud/upload problems that used to fail silently
    //(built in code so the storyboard stays untouched)
    let syncWarningLabel = UILabel()
    
    override func viewDidLoad() {
        
        //turn on the location manager
        self.location.delegate = self
        location.requestAlwaysAuthorization()
        //location.startUpdatingLocation()    
        //end location manager setup
        
        //version
        versionLabel.text = "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?")"
        
        //format buttons
        scanButton.layer.borderWidth = 1.5
        scanButton.layer.borderColor = borderColorUp
        scanButton.layer.cornerRadius = 22

        mapButton.layer.borderWidth = 1.5
        mapButton.layer.borderColor = borderColorUp
        mapButton.layer.cornerRadius = 22

        nearestDosiButton.layer.borderWidth = 1.5
        nearestDosiButton.layer.borderColor = borderColorUp
        nearestDosiButton.layer.cornerRadius = 22
        
        //progress view
        progressView.setProgress(0, animated: true)
        
        //tools button
        let toolsTap = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
        Tools.isUserInteractionEnabled = true
        Tools.addGestureRecognizer(toolsTap)
        
        //refresh count button (replaces the hidden tap-to-refresh on the status label)
        refreshButton.layer.borderWidth = 1.5
        refreshButton.layer.borderColor = borderColorUp
        refreshButton.layer.cornerRadius = 22
        refreshButton.addTarget(self, action: #selector(setProgress), for: .touchUpInside)

        //sync warning label: hidden until there is something to say
        syncWarningLabel.translatesAutoresizingMaskIntoConstraints = false
        syncWarningLabel.numberOfLines = 0
        syncWarningLabel.textAlignment = .center
        syncWarningLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        syncWarningLabel.textColor = .systemYellow
        syncWarningLabel.accessibilityIdentifier = "syncWarningLabel"
        syncWarningLabel.isHidden = true
        mainView.addSubview(syncWarningLabel)
        NSLayoutConstraint.activate([
            syncWarningLabel.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 24),
            syncWarningLabel.leadingAnchor.constraint(equalTo: progressView.leadingAnchor),
            syncWarningLabel.trailingAnchor.constraint(equalTo: progressView.trailingAnchor)
        ])

        // Do any additional setup after loading the view, typically from a nib.
        // Detect Wifi:
        reachability.whenReachable = { reachability in
            self.mainView.backgroundColor = UIColor(named: "MainOnline")
            if reachability.connection == .wifi {
                print("Reachable via WiFi")
            }
            else {
                print("Reachable via Cellular")
            }
            self.setProgress()
        }
        
        reachability.whenUnreachable = { _ in
            self.mainView.backgroundColor = UIColor(named: "MainOffline")
            print("Not reachable")
            let alert = UIAlertController(title: "WiFi Connection Error", message: "Must be connected to WiFi to identify position and save data to the cloud.  Working in offline mode until connection reestablished.", preferredStyle: .alert)
            let OK = UIAlertAction(title: "OK", style: .default) { (_) in return }
            alert.addAction(OK)
            
            DispatchQueue.main.async {
                self.present(alert, animated: true, completion: { self.setProgress()})
            } //async end
        
        }//end when unreachable
        
        do {
            try reachability.startNotifier()
        }
        catch {
            print("Unable to start notifier")
        }  //end catch
        //end Detect Wifi...

    } //end viewDidLoad

    override func viewDidAppear(_ animated: Bool) {
        //setProgress()
    }
    
    @IBAction func scanButtonDown(_ sender: Any) {
        scanButton.layer.borderColor = borderColorDown
    }
    
    @IBAction func scanButtonUp(_ sender: Any) {
        scanButton.layer.borderColor = borderColorUp
    }
    
    @IBAction func mapButtonDown(_ sender: Any) {
        mapButton.layer.borderColor = borderColorDown
    }
    
    @IBAction func mapButtonUp(_ sender: Any) {
        mapButton.layer.borderColor = borderColorUp
    }
    
    @IBAction func nearestButtonDown(_ sender: Any) {
        nearestDosiButton.layer.borderColor = borderColorDown
    }
    
    @IBAction func nearestButtonUp(_ sender: Any) {
        nearestDosiButton.layer.borderColor = borderColorUp
    }
    
    
    
    @objc func imageTapped() {
        performSegue(withIdentifier: "segueToTools", sender: "")
    } //end imageTapped
    
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Error")
    } //end location manager fail.


    //MARK:  Sync warning

    // Maps iCloud account status + queued-upload count to the startup warning,
    // or nil when there is nothing to warn about. Internal (not private) so
    // LocationAppTests can drive the wording matrix offline.
    internal static func syncWarningMessage(accountStatus: CKAccountStatus, pendingChangeCount: Int) -> String? {
        let pending = pendingChangeCount == 1
            ? "1 scan waiting to upload"
            : "\(pendingChangeCount) scans waiting to upload"
        switch accountStatus {
        case .available:
            return pendingChangeCount > 0 ? "\(pending) — will retry automatically." : nil
        case .noAccount:
            return "Sign in to iCloud in Settings — "
                + (pendingChangeCount > 0 ? "\(pending)." : "scans cannot upload.")
        case .restricted:
            return "iCloud is restricted on this device — "
                + (pendingChangeCount > 0 ? "\(pending)." : "scans cannot upload.")
        case .temporarilyUnavailable:
            return "iCloud needs attention — open Settings and accept any iCloud prompts"
                + (pendingChangeCount > 0 ? " (\(pending))." : ".")
        default: // .couldNotDetermine and future cases
            return pendingChangeCount > 0 ? "iCloud status unknown — \(pending)." : nil
        }
    }

    // Refreshes the warning label after each sync. pendingChangeCount takes the
    // cache semaphore, so both reads run off the main thread.
    func updateSyncWarning() {
        DispatchQueue.global(qos: .background).async {
            let pending = self.locations.pendingChangeCount
            self.locations.accountStatus { status in
                let message = StartupViewController.syncWarningMessage(accountStatus: status,
                                                                       pendingChangeCount: pending)
                DispatchQueue.main.async {
                    self.syncWarningLabel.text = message
                    self.syncWarningLabel.isHidden = (message == nil)
                }
            }
        }
    }


    
    @objc func setProgress() {
        
        //start activityIndicator
        activityIndicator.startAnimating()
        
        
        DispatchQueue.global(qos: .background).async {
            self.locations.synchronize(loaded: { _ in
                let numberCompleted:Float = Float(self.query.getCollectedNum())
                let numberRemaining:Float = Float(self.query.getNotCollectedNum())
                let numberDeployed:Float = numberCompleted + numberRemaining
                let progress = (numberCompleted / numberDeployed)
                
                DispatchQueue.main.async {
                    switch progress {
                        
                        case 0:
                            self.statusLabel.text = "Ready to begin collection of \(Int(numberRemaining)) dosimeters!"
                        
                        case 1:
                            self.statusLabel.text = "All dosimeters from the prior period have been collected!"
                            print("Completed: \(numberCompleted)")
                            print("Deployed: \(numberDeployed)")
                            print("Progress: \(progress)")
                        
                        default:
                            self.statusLabel.text = "Green Pins: \(Int(numberRemaining)) remaining out of \(Int(numberDeployed)) are ready for collection"
                            print("Completed: \(numberCompleted)")
                            print("Deployed: \(numberDeployed)")
                            print("Progress: \(progress)")
                        
                    } //end switch
                    
                    self.progressView.progress = progress
                    
                    //stop activityIndicator
                    self.activityIndicator.stopAnimating()

                    self.updateSyncWarning()
            }})
        }
        
    }// end setProgress

    
} // end class
