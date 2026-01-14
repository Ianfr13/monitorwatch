//
//  AppDelegate.swift
//  MonitorWatch
//
//  Handles menu bar, status item, and app lifecycle
//

import Cocoa
import SwiftUI

import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var activityMonitor: ActivityMonitor!
    private var isMonitoring = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupNotifications()
        setupStatusItem()
        setupActivityMonitor()
        
        // Start monitoring automatically
        startMonitoring()
        
        // Start note scheduler for automatic generation
        NoteScheduler.shared.start()
    }
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // Register notification category
        let category = UNNotificationCategory(
            identifier: "MONITORWATCH",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        center.setNotificationCategories([category])
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                Logger.shared.log("AppDelegate: Notifications Allowed ✅")
            } else {
                Logger.shared.error("AppDelegate: Notifications Denied ❌")
            }
        }
    }
    
    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list, .badge])
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "MonitorWatch")
        }
        
        let menu = NSMenu()
        
        let statusMenuItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(title: "Start Monitoring", action: #selector(toggleMonitoring), keyEquivalent: "m")
        toggleItem.tag = 101
        menu.addItem(toggleItem)
        
        // Quick Note submenu with time options
        let quickNoteMenu = NSMenu()
        quickNoteMenu.addItem(NSMenuItem(title: "Last 10 minutes", action: #selector(generateQuickNote10), keyEquivalent: ""))
        quickNoteMenu.addItem(NSMenuItem(title: "Last 30 minutes", action: #selector(generateQuickNote30), keyEquivalent: ""))
        quickNoteMenu.addItem(NSMenuItem(title: "Last 1 hour", action: #selector(generateQuickNote60), keyEquivalent: ""))
        quickNoteMenu.addItem(NSMenuItem(title: "Last 2 hours", action: #selector(generateQuickNote120), keyEquivalent: ""))
        
        let quickNoteItem = NSMenuItem(title: "Generate Quick Note", action: nil, keyEquivalent: "g")
        quickNoteItem.submenu = quickNoteMenu
        menu.addItem(quickNoteItem)
        
        // Daily Note (for end of day)
        menu.addItem(NSMenuItem(title: "Generate Daily Note", action: #selector(generateDailyNote), keyEquivalent: "d"))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Quit MonitorWatch", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    private func setupActivityMonitor() {
        activityMonitor = ActivityMonitor()
    }
    
    private func startMonitoring() {
        activityMonitor.start()
        isMonitoring = true
        updateUI()
    }
    
    private func stopMonitoring() {
        activityMonitor.stop()
        isMonitoring = false
        updateUI()
    }
    
    private func updateUI() {
        if let menu = statusItem.menu {
            if let statusItem = menu.item(withTag: 100) {
                statusItem.title = isMonitoring ? "Status: Monitoring" : "Status: Paused"
            }
            if let toggleItem = menu.item(withTag: 101) {
                toggleItem.title = isMonitoring ? "Pause Monitoring" : "Start Monitoring"
            }
        }
        
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: isMonitoring ? "eye.circle.fill" : "eye.circle",
                accessibilityDescription: "MonitorWatch"
            )
        }
    }
    
    @objc private func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    @objc private func generateQuickNote10() { generateQuickNote(minutesBack: 10) }
    @objc private func generateQuickNote30() { generateQuickNote(minutesBack: 30) }
    @objc private func generateQuickNote60() { generateQuickNote(minutesBack: 60) }
    @objc private func generateQuickNote120() { generateQuickNote(minutesBack: 120) }
    
    private func generateQuickNote(minutesBack: Int) {
        showNotification(title: "MonitorWatch", message: "Generating note for last \(minutesBack) minutes...")
        
        Task {
            do {
                let result = try await CloudAPI.shared.generateQuickNote(minutesBack: minutesBack)
                if result.success {
                    showNotification(title: "Success", message: "Note generated: \(result.title)")
                } else {
                    showNotification(title: "Failed", message: "No data found for this period")
                }
            } catch {
                showNotification(title: "Error", message: "Failed: \(error.localizedDescription)")
            }
        }
    }
    
    @objc private func generateDailyNote() {
        showNotification(title: "MonitorWatch", message: "Generating daily note...")
        
        Task {
            do {
                let success = try await CloudAPI.shared.generateNote(for: Date())
                if success {
                    showNotification(title: "Success", message: "Daily note generated in Obsidian")
                } else {
                    showNotification(title: "Failed", message: "Could not generate note (check logs)")
                }
            } catch {
                showNotification(title: "Error", message: "Failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func showNotification(title: String, message: String) {
        Logger.shared.log("AppDelegate: Sending notification - \(title): \(message)")
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.error("AppDelegate: Notification error: \(error)")
            }
        }
    }
    
    @objc private func openSettings() {
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
        
        // Try to find and show existing settings window
        if let window = NSApp.windows.first(where: { $0.title.contains("Settings") || $0.title.contains("MonitorWatch") }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // If no window exists, create a new one
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MonitorWatch Settings"
        window.setContentSize(NSSize(width: 500, height: 400))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
