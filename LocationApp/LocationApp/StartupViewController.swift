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

        #if DEBUG
        // Debug-only: long-press the version label to open the alert gallery for
        // on-device QA of every pop-up. Excluded from release builds.
        let galleryPress = UILongPressGestureRecognizer(target: self, action: #selector(showAlertGallery))
        versionLabel.isUserInteractionEnabled = true
        versionLabel.addGestureRecognizer(galleryPress)
        #endif

    } //end viewDidLoad

    #if DEBUG
    @objc private func showAlertGallery(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let gallery = UINavigationController(rootViewController: AlertGalleryViewController())
        gallery.modalPresentationStyle = .fullScreen
        present(gallery, animated: true)
    }
    #endif
    
    
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
            }})
        }
        
    }// end setProgress

    
} // end class
