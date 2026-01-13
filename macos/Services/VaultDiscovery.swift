//
//  VaultDiscovery.swift
//  MonitorWatch
//
//  Automatically discovers Obsidian vaults on the system
//

import Foundation

class VaultDiscovery {
    
    /// Common locations where Obsidian vaults might be stored
    static let searchPaths: [String] = [
        // iCloud
        "~/Library/Mobile Documents/iCloud~md~obsidian/Documents",
        // Local
        "~/Documents",
        "~/Desktop",
        "~/Obsidian",
        // Dropbox
        "~/Dropbox",
        // OneDrive
        "~/OneDrive/Documents",
        "~/Library/CloudStorage/OneDrive-Personal/Documents",
        // Google Drive
        "~/Library/CloudStorage/GoogleDrive-*/My Drive",
    ]
    
    /// Discovers all Obsidian vaults on the system
    static func discoverVaults() -> [ObsidianVault] {
        var vaults: [ObsidianVault] = []
        let fileManager = FileManager.default
        
        for searchPath in searchPaths {
            let expandedPath = (searchPath as NSString).expandingTildeInPath
            
            // Handle wildcards in path (for Google Drive)
            if expandedPath.contains("*") {
                let basePath = (expandedPath as NSString).deletingLastPathComponent
                let pattern = (expandedPath as NSString).lastPathComponent
                
                if let contents = try? fileManager.contentsOfDirectory(atPath: (basePath as NSString).deletingLastPathComponent) {
                    for item in contents {
                        if item.contains(pattern.replacingOccurrences(of: "*", with: "")) {
                            let fullPath = ((basePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(item)
                            vaults.append(contentsOf: findVaultsInDirectory(fullPath + "/" + (expandedPath as NSString).lastPathComponent))
                        }
                    }
                }
            } else {
                vaults.append(contentsOf: findVaultsInDirectory(expandedPath))
            }
        }
        
        return vaults
    }
    
    /// Find vaults in a specific directory
    private static func findVaultsInDirectory(_ path: String) -> [ObsidianVault] {
        let fileManager = FileManager.default
        var vaults: [ObsidianVault] = []
        
        guard fileManager.fileExists(atPath: path) else {
            return vaults
        }
        
        // Check if this directory is a vault (has .obsidian folder)
        let obsidianPath = (path as NSString).appendingPathComponent(".obsidian")
        if fileManager.fileExists(atPath: obsidianPath) {
            let name = (path as NSString).lastPathComponent
            vaults.append(ObsidianVault(name: name, path: path))
        }
        
        // Search subdirectories (one level deep)
        if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
            for item in contents {
                let itemPath = (path as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false
                
                if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) && isDirectory.boolValue {
                    let obsidianConfigPath = (itemPath as NSString).appendingPathComponent(".obsidian")
                    if fileManager.fileExists(atPath: obsidianConfigPath) {
                        vaults.append(ObsidianVault(name: item, path: itemPath))
                    }
                }
            }
        }
        
        return vaults
    }
    
    /// Get the default vault (first discovered or iCloud vault named after user)
    static func getDefaultVault() -> ObsidianVault? {
        let vaults = discoverVaults()
        
        // Prefer iCloud vault
        if let iCloudVault = vaults.first(where: { $0.path.contains("iCloud~md~obsidian") }) {
            return iCloudVault
        }
        
        return vaults.first
    }
}

/// Represents an Obsidian vault
struct ObsidianVault: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    
    var isICloud: Bool {
        path.contains("iCloud~md~obsidian")
    }
    
    var displayName: String {
        if isICloud {
            return "☁️ \(name)"
        }
        return name
    }
}
