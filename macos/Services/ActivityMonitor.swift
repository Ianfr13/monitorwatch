//
//  ActivityMonitor.swift
//  MonitorWatch
//
//  Monitors app switches and window changes using NSWorkspace
//

import Cocoa

class ActivityMonitor {
    private var isRunning = false
    private var currentApp: NSRunningApplication?
    private var lastWindowTitle = ""
    private var windowTitleTimer: Timer?
    
    // Meeting Detection State
    private var isInMeeting = false
    private var meetingStartTime: Date?
    private var meetingContext: String?
    
    private let configManager = ConfigManager.shared
    private let screenCapture = ScreenCapture()
    private let audioMonitor = AudioMonitor()
    private let ocrService = OCRService()
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Listen for app activation
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Poll window title every 5 seconds (lightweight)
        windowTitleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkWindowTitle()
        }
        
        // Always listen for voice triggers (recording disabled by default until mode enables it)
        audioMonitor.start()
        
        Logger.shared.log("ActivityMonitor: Started")
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        windowTitleTimer?.invalidate()
        windowTitleTimer = nil
        audioMonitor.stop()
        
        Logger.shared.log("ActivityMonitor: Stopped")
    }
    
    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        // Skip if same app
        if app.bundleIdentifier == currentApp?.bundleIdentifier {
            return
        }
        
        currentApp = app
        processAppChange(app: app)
    }

    @objc private func checkWindowTitle() {
        if let eventType = CGEventType(rawValue: UInt32.max) {
             let lastEvent = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType)
             if lastEvent > 60.0 {
                 Logger.shared.log("ActivityMonitor: User idle for \(Int(lastEvent))s. Skipping capture.")
                 return
             }
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        let title = getActiveWindowTitle() ?? ""
        
        // Only process if title changed significantly
        if title != lastWindowTitle && !title.isEmpty {
            lastWindowTitle = title
            processWindowChange(app: app, windowTitle: title)
        }
    }
    
    private func processAppChange(app: NSRunningApplication) {
        let bundleId = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "Unknown"
        let windowTitle = getActiveWindowTitle() ?? ""
        
        let mode = configManager.getCaptureMode(for: bundleId, context: windowTitle)
        
        // Skip ignored apps
        guard mode != .ignore else {
            audioMonitor.stop()
            return
        }
        
        Logger.shared.activity(appName, window: windowTitle, mode: mode.rawValue)
        
        // Check for Meeting State Transition
        if mode == .audio {
            // Meeting Started / Continued
            if !isInMeeting {
                Logger.shared.log("ActivityMonitor: Meeting Detected via Audio Mode (\(windowTitle))")
                isInMeeting = true
                meetingStartTime = Date()
                meetingContext = windowTitle
            } else {
                // Update context if it changed within the meeting app
                meetingContext = windowTitle
            }
        } else {
            // Meeting Ended?
            if isInMeeting, let startTime = meetingStartTime, let context = meetingContext {
                let duration = Date().timeIntervalSince(startTime)
                Logger.shared.log("ActivityMonitor: Meeting Ended. Duration: \(Int(duration))s")
                
                // Only generate if duration > 2 minutes (avoid false positives)
                if duration > 120 {
                    Task {
                        Logger.shared.log("ActivityMonitor: Triggering Automatic Meeting Note...")
                        do {
                            try await CloudAPI.shared.generateMeetingNote(
                                startTime: startTime,
                                endTime: Date(),
                                context: context
                            )
                        } catch {
                            Logger.shared.error("ActivityMonitor: Failed to generate auto-meeting note: \(error)")
                        }
                    }
                }
                
                // Reset State
                isInMeeting = false
                meetingStartTime = nil
                meetingContext = nil
            }
        }

        // Handle capture based on mode
        switch mode {
        case .full:
            captureScreenshot(app: app, windowTitle: windowTitle, mode: mode)
            audioMonitor.start() // Ensure started (if was ignored)
            audioMonitor.setRecording(true)
        case .screenshot:
            captureScreenshot(app: app, windowTitle: windowTitle, mode: mode)
            audioMonitor.start() // Ensure started
            audioMonitor.setRecording(false)
        case .audio:
            sendMetadata(app: app, windowTitle: windowTitle, mode: mode)
            audioMonitor.start() // Ensure started
            audioMonitor.setRecording(true)
        case .metadata:
            sendMetadata(app: app, windowTitle: windowTitle, mode: mode)
            audioMonitor.start() // Ensure started
            audioMonitor.setRecording(false)
        case .ignore:
            audioMonitor.stop() // Full stop for privacy
        }
    }
    
    private func processWindowChange(app: NSRunningApplication, windowTitle: String) {
        let bundleId = app.bundleIdentifier ?? "unknown"
        let mode = configManager.getCaptureMode(for: bundleId, context: windowTitle)
        
        guard mode != .ignore else { return }
        
        // For window changes, just send metadata (lightweight)
        sendMetadata(app: app, windowTitle: windowTitle, mode: mode)
    }
    
    private func captureScreenshot(app: NSRunningApplication, windowTitle: String, mode: CaptureMode) {
        Task {
            // Try capture screenshot
            var ocrText: String? = nil
            
            if let image = await screenCapture.capture() {
                // Extract OCR text if capture succeeded
                ocrText = await ocrService.extractText(from: image)
            } else {
                Logger.shared.log("ActivityMonitor: Screenshot capture failed (permissions?), sending metadata only", level: "WARN")
            }
            
            // Send to API regardless of screenshot success
            let activity = Activity(
                id: UUID(),
                timestamp: Date(),
                appBundleId: app.bundleIdentifier ?? "",
                appName: app.localizedName ?? "",
                windowTitle: windowTitle,
                ocrText: ocrText,
                captureMode: mode
            )
            
            await CloudAPI.shared.sendActivity(activity)
        }
    }
    
    private func sendMetadata(app: NSRunningApplication, windowTitle: String, mode: CaptureMode) {
        let activity = Activity(
            id: UUID(),
            timestamp: Date(),
            appBundleId: app.bundleIdentifier ?? "",
            appName: app.localizedName ?? "",
            windowTitle: windowTitle,
            ocrText: nil,
            captureMode: mode
        )
        
        Task {
            await CloudAPI.shared.sendActivity(activity)
        }
    }
    
    private func getActiveWindowTitle() -> String? {
        // Use Accessibility API to get window title
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success else {
            return nil
        }
        
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else {
            return nil
        }
        
        return title as? String
    }
    
    private func extractURL(from windowTitle: String) -> String? {
        // Try to extract URL from browser window titles
        // Common format: "Page Title - Google Chrome" or direct URL
        if windowTitle.contains("http://") || windowTitle.contains("https://") {
            return windowTitle
        }
        return nil
    }
}
