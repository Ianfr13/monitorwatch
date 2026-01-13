//
//  LaunchAtLogin.swift
//  MonitorWatch
//
//  Manages Login Items (launch at startup)
//

import Foundation
import ServiceManagement

class LaunchAtLogin {
    
    // Check if app is set to launch at login
    static func isEnabled() -> Bool {
        guard let jobDicts = SMCopyAllJobDictionaries(kSMDomainUserLaunchd) as? [[String: AnyObject]] else {
            return false
        }
        
        let bundleId = Bundle.main.bundleIdentifier ?? "com.monitorwatch.app"
        
        return jobDicts.contains { jobDict in
            (jobDict["Label"] as? String) == bundleId
        }
    }
    
    // Enable or disable launch at login
    static func setEnabled(_ enabled: Bool) {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.monitorwatch.app"
        let appUrl = Bundle.main.bundleURL as CFURL
        
        let success = SMLoginItemSetEnabled(bundleId as CFString, enabled)
        
        if success {
            Logger.shared.log("LaunchAtLogin: Launch at login \(enabled ? "enabled" : "disabled")")
        } else {
            Logger.shared.error("LaunchAtLogin: Failed to set launch at login to \(enabled)")
        }
    }
    
    // Toggle current state
    static func toggle() {
        setEnabled(!isEnabled())
    }
}
