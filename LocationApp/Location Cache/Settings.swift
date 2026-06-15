//
//  Settings.swift
//  LocationApp
//
//  Created by László Szöllősi on 2023. 06. 01..
//  Copyright © 2023. Ford, Ryan M. All rights reserved.
//

import Foundation
import CoreLocation

class Settings : Codable {
    var dosimeterMinimumLength : Int = 11
    var dosimeterMaximumLength : Int = 11
    //Fallback scan coordinates for when there is no GPS fix (e.g. WiFi-only
    //iPads with WiFi off). Configurable via the CloudKit Settings record;
    //optional so caches saved before these fields existed still decode.
    var defaultLatitude : Double?
    var defaultLongitude : Double?

    var defaultCoordinates: CLLocation {
        return CLLocation(latitude: defaultLatitude ?? 37.41927542738301,
                          longitude: defaultLongitude ?? -122.20517033784913)
    }

    //Super-user passcode for the delete-old-cycles screen, configurable via
    //the CloudKit Settings record. Optional like the coordinates above so
    //caches saved before this field existed still decode.
    var superUserPasscode : Int?

    var superUserPasscodeValue: Int {
        return superUserPasscode ?? 4299
    }
}
