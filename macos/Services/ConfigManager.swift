//
//  ConfigManager.swift
//  MonitorWatch
//
//  Manages user configuration with persistence
//

import Foundation

class ConfigManager {
    static let shared = ConfigManager()
    
    private let defaults = UserDefaults.standard
    private let configKey = "MonitorWatchConfig"
    
    private(set) var config: UserConfig
    
    private init() {
        if let data = defaults.data(forKey: configKey),
           var decoded = try? JSONDecoder().decode(UserConfig.self, from: data) {
            // Sanitize on load
            decoded.apiUrl = decoded.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if decoded.apiUrl.hasSuffix("/") { decoded.apiUrl = String(decoded.apiUrl.dropLast()) }
            decoded.apiKey = decoded.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            
            self.config = decoded
            Logger.shared.log("ConfigManager: Loaded existing config. API URL: \(config.apiUrl.isEmpty ? "EMPTY" : config.apiUrl)")
        } else {
            self.config = .default
            Logger.shared.log("ConfigManager: Loaded DEFAULT config (No saved settings found)")
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(config) {
            defaults.set(encoded, forKey: configKey)
        }
    }
    
    func update(_ config: UserConfig) {
        var newConfig = config
        // Sanitize API URL
        newConfig.apiUrl = config.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ensure no trailing slash
        if newConfig.apiUrl.hasSuffix("/") {
            newConfig.apiUrl = String(newConfig.apiUrl.dropLast())
        }
        
        // Sanitize API Key
        newConfig.apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        self.config = newConfig
        save()
        Logger.shared.log("ConfigManager: Config updated. API URL: \(newConfig.apiUrl)")
        
        // Update NoteScheduler with new settings
        NoteScheduler.shared.updateSchedule()
    }
    
    func getCaptureMode(for bundleId: String, context: String?) -> CaptureMode {
        // Delegate to the intelligent "Brain" in UserConfig
        return UserConfig.determineCaptureMode(
            for: bundleId,
            context: context ?? "",
            profile: config.performanceProfile
        )
    }
}
