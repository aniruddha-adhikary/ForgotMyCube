//
//  UserPreferences.swift
//  ForgotMyCube
//
//  Created by Aniruddha Adhikary on 2/3/25.
//

import Foundation

/// Class for storing and retrieving user preferences
class UserPreferences {
    private static let defaults = UserDefaults.standard
    
    // Device ID keys
    private static let deviceIdKey = "com.forgotmycube.deviceId"
    
    // Default device ID
    private static let defaultDeviceId = "0139300"
    
    /// Get current device ID or default
    static func getDeviceId() -> String {
        return defaults.string(forKey: deviceIdKey) ?? defaultDeviceId
    }
    
    /// Save device ID
    static func saveDeviceId(_ id: String) {
        defaults.set(id, forKey: deviceIdKey)
    }
}