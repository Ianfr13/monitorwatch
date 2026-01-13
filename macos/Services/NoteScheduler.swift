//
//  NoteScheduler.swift
//  MonitorWatch
//
//  Handles automatic note generation scheduling and sleep detection
//

import Foundation
import Cocoa
import UserNotifications

class NoteScheduler {
    static let shared = NoteScheduler()
    
    private var scheduledTimer: Timer?
    private var lastGenerationDate: Date?
    private let configManager = ConfigManager.shared
    
    private init() {
        setupSleepWakeNotifications()
    }
    
    // MARK: - Public API
    
    func start() {
        updateSchedule()
        Logger.shared.log("NoteScheduler: Started")
    }
    
    func stop() {
        scheduledTimer?.invalidate()
        scheduledTimer = nil
        Logger.shared.log("NoteScheduler: Stopped")
    }
    
    func updateSchedule() {
        // Cancel existing timer
        scheduledTimer?.invalidate()
        scheduledTimer = nil
        
        let frequency = configManager.config.noteFrequency
        
        // Handle scheduled time mode
        if frequency == .atScheduledTime {
            scheduleAtSpecificTime()
            return
        }
        
        guard let interval = frequency.intervalSeconds else {
            Logger.shared.log("NoteScheduler: Auto-generation disabled")
            return
        }
        
        // Schedule recurring timer
        scheduledTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.generateNoteIfNeeded(reason: "Scheduled (\(frequency.displayName))")
        }
        
        // Keep timer running when app is in background
        RunLoop.current.add(scheduledTimer!, forMode: .common)
        
        Logger.shared.log("NoteScheduler: Scheduled for \(frequency.displayName)")
    }
    
    private func scheduleAtSpecificTime() {
        let timeString = configManager.config.scheduledTime
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        
        guard components.count == 2 else {
            Logger.shared.error("NoteScheduler: Invalid scheduled time format: \(timeString)")
            return
        }
        
        let targetHour = components[0]
        let targetMinute = components[1]
        
        let now = Date()
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        dateComponents.hour = targetHour
        dateComponents.minute = targetMinute
        dateComponents.second = 0
        
        var scheduledDate = calendar.date(from: dateComponents)!
        
        // If the time has passed today, schedule for tomorrow
        if scheduledDate <= now {
            scheduledDate = calendar.date(byAdding: .day, value: 1, to: scheduledDate)!
        }
        
        let timeInterval = scheduledDate.timeIntervalSince(now)
        
        // Schedule single timer for the specific time
        scheduledTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            self?.generateNoteIfNeeded(reason: "Scheduled at \(timeString)")
            // Reschedule for next day after generation
            self?.scheduleAtSpecificTime()
        }
        
        RunLoop.current.add(scheduledTimer!, forMode: .common)
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        Logger.shared.log("NoteScheduler: Scheduled for \(formatter.string(from: scheduledDate)) (\(timeString))")
    }
    
    // MARK: - Sleep/Wake Detection
    
    private func setupSleepWakeNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        // Mac is going to sleep
        notificationCenter.addObserver(
            self,
            selector: #selector(handleSleepNotification),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        // Mac woke up
        notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Screen is being locked (user stepping away)
        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenLock),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        // App will terminate
        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTermination),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
        
        Logger.shared.log("NoteScheduler: Sleep/Wake notifications registered")
    }
    
    @objc private func handleSleepNotification() {
        Logger.shared.log("NoteScheduler: Mac going to sleep")
        
        if configManager.config.generateOnSleep {
            generateNoteIfNeeded(reason: "Mac Sleep")
        }
    }
    
    @objc private func handleWakeNotification() {
        Logger.shared.log("NoteScheduler: Mac woke up")
        // Could add logic here if needed (e.g., generate morning summary)
    }
    
    @objc private func handleScreenLock() {
        Logger.shared.log("NoteScheduler: Screen locked")
        // Optional: Could generate note on screen lock too
    }
    
    @objc private func handleAppTermination() {
        Logger.shared.log("NoteScheduler: System shutting down")
        
        if configManager.config.generateOnSleep {
            // Synchronous generation before shutdown
            generateNoteSync(reason: "Shutdown")
        }
    }
    
    // MARK: - Note Generation
    
    private func generateNoteIfNeeded(reason: String) {
        // Prevent generating too frequently (minimum 30 min between generations)
        if let lastGen = lastGenerationDate, Date().timeIntervalSince(lastGen) < 1800 {
            Logger.shared.log("NoteScheduler: Skipping - generated recently")
            return
        }
        
        Logger.shared.log("NoteScheduler: Generating note - \(reason)")
        
        Task {
            await generateNote(reason: reason)
        }
    }
    
    private func generateNoteSync(reason: String) {
        Logger.shared.log("NoteScheduler: Sync generation - \(reason)")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            await generateNote(reason: reason)
            semaphore.signal()
        }
        
        // Wait up to 30 seconds for generation to complete
        _ = semaphore.wait(timeout: .now() + 30)
    }
    
    @MainActor
    private func generateNote(reason: String) async {
        do {
            let success = try await CloudAPI.shared.generateNote(for: Date())
            
            if success {
                lastGenerationDate = Date()
                showNotification(
                    title: "Note Generated",
                    message: "Daily note saved to Obsidian (\(reason))"
                )
                Logger.shared.api("Auto Note Generation (\(reason))", success: true)
            } else {
                Logger.shared.error("NoteScheduler: Generation returned false")
            }
        } catch {
            Logger.shared.error("NoteScheduler: Generation failed - \(error.localizedDescription)")
            showNotification(
                title: "Note Generation Failed",
                message: error.localizedDescription
            )
        }
    }
    
    private func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
