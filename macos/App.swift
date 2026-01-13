//
//  MonitorWatchApp.swift
//  MonitorWatch
//
//  Open Source Activity Monitor + AI Note Generator
//

import SwiftUI

@main
struct MonitorWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // For menu bar apps (LSUIElement), we need WindowGroup instead of Settings
        WindowGroup("MonitorWatch Settings") {
            SettingsView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 500, height: 400)
        .commands {
            // Remove default menu items that don't apply to menu bar apps
            CommandGroup(replacing: .newItem) { }
        }
    }
}
