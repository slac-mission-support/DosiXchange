//
//  ManagedAppConfig.swift
//  LocationApp
//
//  Created by Daniel Spady on 6/22/26.
//

import Foundation

/// Reads the field-worker username from the MDM (JAMF) Managed App Configuration
/// payload. iOS surfaces that payload under a fixed UserDefaults key; values pushed
/// by JAMF arrive as a dictionary. Returns "" on unmanaged devices (no payload).
enum ManagedAppConfig {

    /// iOS-defined UserDefaults key holding the MDM-pushed managed configuration.
    static let managedConfigKey = "com.apple.configuration.managed"

    /// Key inside the managed-config dictionary that holds the worker's name.
    /// PLACEHOLDER — must match the JAMF payload key SLAC defines for the rollout.
    /// Examples: "userDisplayName", "username", "fullName", "assignedUser".
    static let usernameKey = "userDisplayName"

    /// Pure decision: extract the username from a managed-config dictionary.
    /// Trims whitespace; returns "" when the key is absent, empty, or not a String.
    static func username(from managedConfig: [String: Any]?) -> String {
        guard let value = managedConfig?[usernameKey] as? String else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads the live managed configuration from UserDefaults and returns the username.
    static func currentUsername(defaults: UserDefaults = .standard) -> String {
        username(from: defaults.dictionary(forKey: managedConfigKey))
    }
}
