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
}
