//
//  Models.swift
//  MonitorWatch
//
//  Data models for activities, transcripts, and config
//

import Foundation

// MARK: - Capture Mode

enum CaptureMode: String, Codable, CaseIterable {
    case full       // Screenshot + Audio + OCR
    case screenshot // Image + OCR only
    case audio      // Transcription only
    case metadata   // Window title only
    case ignore     // Nothing
}

// MARK: - Activity

struct Activity: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let appBundleId: String
    let appName: String
    let windowTitle: String
    var ocrText: String?
    let captureMode: CaptureMode
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case appBundleId = "app_bundle_id"
        case appName = "app_name"
        case windowTitle = "window_title"
        case ocrText = "ocr_text"
        case captureMode = "capture_mode"
    }
}

// MARK: - Transcript

struct Transcript: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let source: String
    let durationSeconds: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case text
        case source
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - Config

// MARK: - Performance Profile
enum PerformanceProfile: String, Codable, CaseIterable {
    case low    // Economy: Metadata mostly, Audio for meetings
    case mid    // Balanced: Screenshots for Work, Metadata for rest
    case high   // Recall: Full context for everything
}

// MARK: - Note Language
enum NoteLanguage: String, Codable, CaseIterable {
    case en = "en"
    case pt = "pt"
    
    var displayName: String {
        switch self {
        case .en: return "English"
        case .pt: return "Portugues"
        }
    }
}

// MARK: - Auto Note Generation Frequency
enum NoteFrequency: String, Codable, CaseIterable {
    case disabled = "disabled"
    case everyHour = "every_hour"
    case every2Hours = "every_2_hours"
    case every4Hours = "every_4_hours"
    case onceDaily = "once_daily"
    case atScheduledTime = "at_scheduled_time"
    
    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .everyHour: return "Every hour"
        case .every2Hours: return "Every 2 hours"
        case .every4Hours: return "Every 4 hours"
        case .onceDaily: return "Once a day"
        case .atScheduledTime: return "At scheduled time"
        }
    }
    
    var intervalSeconds: TimeInterval? {
        switch self {
        case .disabled: return nil
        case .everyHour: return 3600
        case .every2Hours: return 7200
        case .every4Hours: return 14400
        case .onceDaily: return 86400
        case .atScheduledTime: return nil // Use scheduled time instead
        }
    }
}

// MARK: - Config

struct UserConfig: Codable {
    var obsidianVaultPath: String
    var performanceProfile: PerformanceProfile // Replaces complex maps
    var apiUrl: String
    var apiKey: String
    var voiceTriggerPhrase: String = "faz a nota"
    var noteLanguage: NoteLanguage = .en
    
    // Auto Note Generation
    var noteFrequency: NoteFrequency = .disabled
    var generateOnSleep: Bool = true  // Generate when Mac goes to sleep
    var scheduledTime: String = "22:00"  // Format: "HH:mm" for scheduled generation
    var launchAtLogin: Bool = false  // Launch app automatically on login
    
    // AI Provider Configuration
    var aiProvider: String = "gemini"
    var openRouterKey: String = ""
    var geminiKey: String = ""
    var dailyModel: String = "gemini-2.0-flash-exp"
    var meetingModel: String = "gemini-2.0-flash-exp"
    
    // Media Processing Configuration
    var audioProvider: String = "apple"
    var audioModel: String = "whisper-1"
    var visionProvider: String = "apple"
    var visionModel: String = "gpt-4o"
    var videoProvider: String = "apple"
    var videoModel: String = "gpt-4o"
    
    // Legacy maps kept for migration safety but unused in new logic
    var captureModes: [String: CaptureMode] = [:]
    var urlPatterns: [String: CaptureMode] = [:]
    
    enum CodingKeys: String, CodingKey {
        case obsidianVaultPath = "obsidian_vault_path"
        case performanceProfile = "performance_profile"
        case apiUrl = "api_url"
        case apiKey = "api_key"
        case voiceTriggerPhrase = "voice_trigger_phrase"
        case noteLanguage = "note_language"
        case noteFrequency = "note_frequency"
        case generateOnSleep = "generate_on_sleep"
        case scheduledTime = "scheduled_time"
        case launchAtLogin = "launch_at_login"
        case aiProvider = "ai_provider"
        case openRouterKey = "openrouter_key"
        case geminiKey = "gemini_key"
        case dailyModel = "daily_model"
        case meetingModel = "meeting_model"
        case audioProvider = "audio_provider"
        case audioModel = "audio_model"
        case visionProvider = "vision_provider"
        case visionModel = "vision_model"
        case videoProvider = "video_provider"
        case videoModel = "video_model"
        case captureModes = "capture_modes"
        case urlPatterns = "url_patterns"
    }
    
    static let `default` = UserConfig(
        obsidianVaultPath: "~/Documents/Obsidian",
        performanceProfile: .mid,
        apiUrl: "",
        apiKey: "",
        voiceTriggerPhrase: "faz a nota"
    )
    
    // The "Brain" - Intelligent Decision Matrix
    static func determineCaptureMode(for bundleId: String, context: String, profile: PerformanceProfile) -> CaptureMode {
        let text = context.lowercased()
        
        // 1. Always Ignore / Privacy (Hardcoded safety)
        if text.contains("password") || text.contains("bank") || bundleId.contains("1password") {
            return .ignore
        }
        
        // 2. Meetings (Always Audio if profile > low, or explicit in Low)
        let isMeeting = text.contains("zoom") || text.contains("meet.google") || text.contains("teams")
        if isMeeting {
            return .audio
        }
        
        // 3. Videos / Passive
        let isVideo = text.contains("youtube") || text.contains("netflix") || text.contains("twitch") || text.contains("spotify")
        
        // 4. Work / Research
        let isWork = text.contains("comet") || text.contains("github") || text.contains("vscode") || text.contains("figma") || text.contains("chatgpt") || text.contains("claude") || text.contains("stack overflow")
        
        
        // --- Decision Matrix ---
        switch profile {
        case .low:
            // Economy: Only Audio for meetings, Metadata for EVERYTHING else
            if isMeeting { return .audio }
            return .metadata
            
        case .mid:
            // Balanced:
            // - Meetings -> Audio
            // - Work -> Screenshot (Visual context)
            // - Video -> Metadata (Don't waste CPU)
            // - Reading/Browsing -> Metadata (Title usually enough)
            if isMeeting { return .audio }
            if isWork { return .screenshot } // Capture visuals of work
            return .metadata
            
        case .high:
            // Full Recall:
            // - Work -> Full (OCR + Screenshot)
            // - Reading -> Full (OCR is key for reading)
            // - Video -> Audio (Transcription of video content!)
            if isMeeting { return .audio }
            if isVideo { return .audio } // Transcribe YouTube!
            if isWork { return .full }
            return .full // Default to Full for maximum context
        }
    }
}

// MARK: - API Payloads

struct ActivityPayload: Codable {
    let timestamp: String
    let appBundleId: String
    let appName: String
    let windowTitle: String
    let ocrText: String?
    let captureMode: String
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case appBundleId = "app_bundle_id"
        case appName = "app_name"
        case windowTitle = "window_title"
        case ocrText = "ocr_text"
        case captureMode = "capture_mode"
    }
}

struct TranscriptPayload: Codable {
    let timestamp: String
    let text: String
    let source: String
    let durationSeconds: Int
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case text
        case source
        case durationSeconds = "duration_seconds"
    }
}
