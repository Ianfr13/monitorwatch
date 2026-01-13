//
//  Logger.swift
//  MonitorWatch
//
//  Simple logging system with file output for debugging
//

import Foundation
import os.log

class Logger {
    static let shared = Logger()
    
    private let logFile: URL
    private let queue = DispatchQueue(label: "com.monitorwatch.logger")
    private let osLog = OSLog(subsystem: "com.monitorwatch", category: "activity")
    
    init() {
        // Log to ~/Downloads/MonitorWatch.log for easier debugging
        let downloadsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        logFile = downloadsDir.appendingPathComponent("MonitorWatch.log")
        
        // Create file if needed
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        
        log("=== MonitorWatch Started ===")
    }
    
    func log(_ message: String, level: String = "INFO") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formatted = "[\(timestamp)] [\(level)] \(message)"
        
        // Print to console
        print(formatted)
        
        // Log to system log
        os_log("%{public}@", log: osLog, type: .default, message)
        
        // Write to file
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if let handle = try? FileHandle(forWritingTo: self.logFile) {
                handle.seekToEndOfFile()
                if let data = (formatted + "\n").data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        }
    }
    
    func activity(_ app: String, window: String, mode: String) {
        log("📱 ACTIVITY: \(app) | \(window) | mode=\(mode)")
    }
    
    func capture(_ type: String, success: Bool) {
        let status = success ? "✅" : "❌"
        log("\(status) CAPTURE: \(type)")
    }
    
    func api(_ action: String, success: Bool) {
        let status = success ? "✅" : "❌"
        log("\(status) API: \(action)")
    }
    
    func error(_ message: String) {
        log("❌ ERROR: \(message)", level: "ERROR")
    }
}
