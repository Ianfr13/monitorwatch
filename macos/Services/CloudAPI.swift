//
//  CloudAPI.swift
//  MonitorWatch
//
//  Handles all communication with Cloudflare Workers backend
//

import Foundation

class CloudAPI {
    static let shared = CloudAPI()
    
    internal let configManager = ConfigManager.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Activity
    
    // Formatters for local date/hour extraction
    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    private static let localHourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    func sendActivity(_ activity: Activity) async {
        guard !configManager.config.apiUrl.isEmpty else {
            Logger.shared.error("CloudAPI: API URL not configured")
            return
        }
        
        // Extract local date and hour for timezone-correct filtering
        let localDate = CloudAPI.localDateFormatter.string(from: activity.timestamp)
        let localHour = Int(CloudAPI.localHourFormatter.string(from: activity.timestamp)) ?? 0
        
        let payload = ActivityPayload(
            timestamp: dateFormatter.string(from: activity.timestamp),
            localDate: localDate,
            localHour: localHour,
            appBundleId: activity.appBundleId,
            appName: activity.appName,
            windowTitle: activity.windowTitle,
            ocrText: activity.ocrText,
            captureMode: activity.captureMode.rawValue
        )
        
        do {
            try await post(endpoint: "/api/activity", body: payload)
            Logger.shared.api("Activity: \(activity.appName)", success: true)
        } catch {
            Logger.shared.error("CloudAPI Error (activity): \(error)")
        }
    }
    
    // MARK: - Transcript
    
    func sendTranscript(_ transcript: Transcript) async {
        guard !configManager.config.apiUrl.isEmpty else { return }
        
        // Extract local date and hour for timezone-correct filtering
        let localDate = CloudAPI.localDateFormatter.string(from: transcript.timestamp)
        let localHour = Int(CloudAPI.localHourFormatter.string(from: transcript.timestamp)) ?? 0
        
        let payload = TranscriptPayload(
            timestamp: dateFormatter.string(from: transcript.timestamp),
            localDate: localDate,
            localHour: localHour,
            text: transcript.text,
            source: transcript.source,
            durationSeconds: transcript.durationSeconds
        )
        
        do {
            try await post(endpoint: "/api/transcript", body: payload)
            Logger.shared.api("Transcript: \(transcript.text.prefix(20))...", success: true)
        } catch {
            Logger.shared.error("CloudAPI Error (transcript): \(error)")
        }
    }
    
    // MARK: - Notes
    
    func generateNote(for date: Date) async throws -> Bool {
        // Validate all required settings
        guard !configManager.config.apiUrl.isEmpty else {
            Logger.shared.error("CloudAPI: API URL not configured")
            throw APIError.serverError(message: "API URL not configured. Go to Settings > Connection.")
        }
        
        guard !configManager.config.apiKey.isEmpty else {
            Logger.shared.error("CloudAPI: API Key not configured")
            throw APIError.serverError(message: "API Key not configured. Go to Settings > Connection.")
        }
        
        guard !configManager.config.openRouterKey.isEmpty else {
            Logger.shared.error("CloudAPI: OpenRouter key not configured")
            throw APIError.serverError(message: "OpenRouter API key not configured. Go to Settings > Connection.")
        }
        
        guard !configManager.config.obsidianVaultPath.isEmpty else {
            Logger.shared.error("CloudAPI: Obsidian vault not configured")
            throw APIError.serverError(message: "Obsidian vault not selected. Go to Settings > General.")
        }
        
        let dateString = formatDate(date)
        
        struct GenerateRequest: Codable {
            let date: String
            let force: Bool
        }
        
        do {
            let response: NoteResponse = try await post(
                endpoint: "/api/notes/generate",
                body: GenerateRequest(date: dateString, force: true)
            )
            
            if response.success && !response.note.isEmpty {
                await writeToObsidian(note: response.note, date: date)
                Logger.shared.api("Note Generation", success: true)
                return true
            } else if !response.success {
                Logger.shared.error("CloudAPI: Note generation failed - no data or backend error")
                throw APIError.serverError(message: "No activities found for this date. Use the app for a while first.")
            }
            return false
        } catch let error as APIError {
            Logger.shared.error("CloudAPI Error (generate note): \(error.localizedDescription)")
            throw error
        } catch {
            Logger.shared.error("CloudAPI Error (generate note): \(error)")
            throw APIError.serverError(message: error.localizedDescription)
        }
    }
    
    // New: Meeting Note
    func generateMeetingNote(startTime: Date, endTime: Date, context: String) async throws {
        // Validate all required settings
        guard !configManager.config.apiUrl.isEmpty else {
            throw APIError.serverError(message: "API URL not configured. Go to Settings > Connection.")
        }
        guard !configManager.config.apiKey.isEmpty else {
            throw APIError.serverError(message: "API Key not configured. Go to Settings > Connection.")
        }
        guard !configManager.config.openRouterKey.isEmpty else {
            throw APIError.serverError(message: "OpenRouter API key not configured. Go to Settings > Connection.")
        }
        guard !configManager.config.obsidianVaultPath.isEmpty else {
            throw APIError.serverError(message: "Obsidian vault not selected. Go to Settings > General.")
        }
        
        struct MeetingRequest: Codable {
            let startTime: String
            let endTime: String
            let context: String
        }
        
        struct MeetingResponse: Codable {
            let success: Bool
            let note: String
            let filename: String
        }
        
        let startStr = dateFormatter.string(from: startTime)
        let endStr = dateFormatter.string(from: endTime)
        
        do {
            let response: MeetingResponse = try await post(
                endpoint: "/api/notes/meeting",
                body: MeetingRequest(startTime: startStr, endTime: endStr, context: context)
            )
            
            if response.success && !response.note.isEmpty {
                await writeMeetingToObsidian(note: response.note, filename: response.filename)
                Logger.shared.api("Meeting Note: \(context)", success: true)
            }
        } catch {
            Logger.shared.error("CloudAPI Error (meeting note): \(error)")
            throw error 
        }
    }
    
    private func writeMeetingToObsidian(note: String, filename: String) async {
        let vaultPath = (configManager.config.obsidianVaultPath as NSString).expandingTildeInPath
        // Filename comes from server like "Meetings/Meeting Title.md"
        // Ensure we respect the folder structure
        var filePath = "\(vaultPath)/\(filename)"
        
        // Append extension if missing (Worker should send it, but just in case)
        if !filePath.hasSuffix(".md") {
            filePath += ".md"
        }
        
        // Safe Check: If file exists, do NOT overwrite. Append timestamp.
        if FileManager.default.fileExists(atPath: filePath) {
            let fileURL = URL(fileURLWithPath: filePath)
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let dir = fileURL.deletingLastPathComponent().path
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH-mm-ss"
            let timestamp = timeFormatter.string(from: Date())
            
            filePath = "\(dir)/\(baseName) (\(timestamp)).md"
        }
        
        // Create directory if needed
        let directory = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        
        // Non-destructive write check logic could go here, but "filename" from server is usually unique enough
        // or we append time if needed. For now, trust the server's unique filename.
        
        do {
            try note.write(toFile: filePath, atomically: true, encoding: .utf8)
            Logger.shared.log("CloudAPI: Meeting Note written - \(filePath)")
        } catch {
            Logger.shared.error("CloudAPI Error (write meeting): \(error)")
        }
    }
    
    func getNote(for date: Date) async -> String? {
        guard !configManager.config.apiUrl.isEmpty else { return nil }
        
        let dateString = formatDate(date)
        
        do {
            let response: NoteResponse = try await get(endpoint: "/api/notes/\(dateString)")
            return response.note
        } catch {
            Logger.shared.error("CloudAPI Error (get note): \(error)")
            return nil
        }
    }
    
    // MARK: - Hourly Summaries
    
    /// Process hourly summary for a specific hour (called every hour to pre-process data)
    func processHourlySummary(for date: Date, hour: Int) async {
        guard !configManager.config.apiUrl.isEmpty,
              !configManager.config.apiKey.isEmpty,
              !configManager.config.openRouterKey.isEmpty else {
            return
        }
        
        let dateString = formatDate(date)
        
        struct SummaryRequest: Codable {
            let date: String
            let hour: Int
        }
        
        struct SummaryResponse: Codable {
            let success: Bool
            let summary: String?
        }
        
        do {
            let _: SummaryResponse = try await post(
                endpoint: "/api/summaries/process",
                body: SummaryRequest(date: dateString, hour: hour)
            )
            Logger.shared.api("Hourly Summary: \(dateString) \(hour):00", success: true)
        } catch {
            Logger.shared.error("CloudAPI Error (hourly summary): \(error)")
        }
    }
    
    /// Process the previous hour's summary (convenience method)
    func processLastHourSummary() async {
        let now = Date()
        let calendar = Calendar.current
        let previousHour = calendar.component(.hour, from: now.addingTimeInterval(-3600))
        let date = calendar.component(.hour, from: now) == 0 
            ? calendar.date(byAdding: .day, value: -1, to: now)! 
            : now
        
        await processHourlySummary(for: date, hour: previousHour)
    }
    
    // MARK: - Hour Notes
    
    /// Generate a note for a specific hour and save to Hour Notes folder
    func generateHourNote(for date: Date, hour: Int) async {
        guard !configManager.config.apiUrl.isEmpty,
              !configManager.config.apiKey.isEmpty,
              !configManager.config.openRouterKey.isEmpty,
              !configManager.config.obsidianVaultPath.isEmpty else {
            Logger.shared.error("CloudAPI: Missing configuration for hour note")
            return
        }
        
        let dateString = formatDate(date)
        
        // Get existing notes from vault for WikiLinks
        let vaultNotes = scanVaultForNotes()
        
        struct HourNoteRequest: Codable {
            let date: String
            let hour: Int
            let vaultNotes: [String]
        }
        
        struct HourNoteResponse: Codable {
            let success: Bool
            let note: String
            let title: String?
        }
        
        do {
            let response: HourNoteResponse = try await post(
                endpoint: "/api/notes/hour",
                body: HourNoteRequest(date: dateString, hour: hour, vaultNotes: vaultNotes)
            )
            
            if response.success && !response.note.isEmpty {
                let title = response.title ?? "Note \(dateString) \(hour)h"
                await writeHourNoteToObsidian(note: response.note, title: title, date: date, hour: hour)
                Logger.shared.api("Hour Note: \(title)", success: true)
            }
        } catch {
            Logger.shared.error("CloudAPI Error (hour note): \(error)")
        }
    }
    
    /// Generate hour note for the previous hour
    func generateLastHourNote() async {
        let now = Date()
        let calendar = Calendar.current
        let previousHour = calendar.component(.hour, from: now.addingTimeInterval(-3600))
        let date = calendar.component(.hour, from: now) == 0 
            ? calendar.date(byAdding: .day, value: -1, to: now)! 
            : now
        
        await generateHourNote(for: date, hour: previousHour)
    }
    
    // MARK: - Quick Notes
    
    /// Result from quick note generation
    struct QuickNoteResult {
        let success: Bool
        let title: String
    }
    
    /// Generate a quick note for the last X minutes
    func generateQuickNote(minutesBack: Int) async throws -> QuickNoteResult {
        guard !configManager.config.apiUrl.isEmpty else {
            throw APIError.serverError(message: "API URL not configured. Go to Settings > Connection.")
        }
        guard !configManager.config.apiKey.isEmpty else {
            throw APIError.serverError(message: "API Key not configured. Go to Settings > Connection.")
        }
        guard !configManager.config.openRouterKey.isEmpty else {
            throw APIError.serverError(message: "OpenRouter API key not configured. Go to Settings > Connection.")
        }
        guard !configManager.config.obsidianVaultPath.isEmpty else {
            throw APIError.serverError(message: "Obsidian vault not selected. Go to Settings > General.")
        }
        
        struct QuickNoteRequest: Codable {
            let minutesBack: Int
            let timezoneOffset: Int  // Minutes from UTC (e.g., -180 for GMT-3)
            let localTime: String    // Current local time "HH:mm"
            let localDate: String    // Current local date "yyyy-MM-dd"
        }
        
        struct QuickNoteResponse: Codable {
            let success: Bool
            let note: String
            let title: String?
        }
        
        // Get timezone info from macOS
        let now = Date()
        let tzOffsetSeconds = TimeZone.current.secondsFromGMT(for: now)
        let tzOffsetMinutes = tzOffsetSeconds / 60
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        
        let response: QuickNoteResponse = try await post(
            endpoint: "/api/notes/quick",
            body: QuickNoteRequest(
                minutesBack: minutesBack,
                timezoneOffset: tzOffsetMinutes,
                localTime: timeFormatter.string(from: now),
                localDate: dateFormatter.string(from: now)
            )
        )
        
        if response.success && !response.note.isEmpty {
            let title = response.title ?? "Quick Note"
            await writeQuickNoteToObsidian(note: response.note, title: title)
            Logger.shared.api("Quick Note: \(title)", success: true)
            return QuickNoteResult(success: true, title: title)
        }
        
        return QuickNoteResult(success: false, title: "")
    }
    
    /// Write quick note to Notes/ folder in Obsidian vault
    private func writeQuickNoteToObsidian(note: String, title: String) async {
        let vaultPath = (configManager.config.obsidianVaultPath as NSString).expandingTildeInPath
        
        // Get current date and time for filename
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH'h'mm"
        let timeString = timeFormatter.string(from: now)
        
        // Clean title for filename
        let cleanTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        
        // Format: "Notes/2026-01-13 14h30 - Title Here.md"
        let filePath = "\(vaultPath)/Notes/\(dateString) \(timeString) - \(cleanTitle).md"
        
        // Create directory if needed
        let directory = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        
        // If file exists, append timestamp to make unique
        var finalPath = filePath
        if FileManager.default.fileExists(atPath: finalPath) {
            let secondFormatter = DateFormatter()
            secondFormatter.dateFormat = "ss"
            let seconds = secondFormatter.string(from: now)
            finalPath = "\(vaultPath)/Notes/\(dateString) \(timeString)-\(seconds) - \(cleanTitle).md"
        }
        
        do {
            try note.write(toFile: finalPath, atomically: true, encoding: .utf8)
            Logger.shared.log("CloudAPI: Quick note written - \(finalPath)")
        } catch {
            Logger.shared.error("CloudAPI Error (write quick note): \(error)")
        }
    }
    
    /// Scan Obsidian vault for existing note titles (for WikiLinks)
    private func scanVaultForNotes() -> [String] {
        let vaultPath = (configManager.config.obsidianVaultPath as NSString).expandingTildeInPath
        var notes: [String] = []
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: vaultPath) else {
            return notes
        }
        
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".md") {
                // Extract note name without extension and path
                let noteName = (file as NSString).lastPathComponent
                    .replacingOccurrences(of: ".md", with: "")
                notes.append(noteName)
            }
        }
        
        // Limit to prevent huge payloads
        return Array(notes.prefix(500))
    }
    
    private func writeHourNoteToObsidian(note: String, title: String, date: Date, hour: Int) async {
        let vaultPath = (configManager.config.obsidianVaultPath as NSString).expandingTildeInPath
        let dateString = formatDate(date)
        let hourString = String(format: "%02d", hour)
        
        // Clean title for filename
        let cleanTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Format: "Hour Notes/2026-01-13 14h - Refactoring CloudAPI Module.md"
        let filePath = "\(vaultPath)/Hour Notes/\(dateString) \(hourString)h - \(cleanTitle).md"
        
        // Create directory if needed
        let directory = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        
        // Don't overwrite if exists
        if FileManager.default.fileExists(atPath: filePath) {
            Logger.shared.log("CloudAPI: Hour note already exists - \(filePath)")
            return
        }
        
        do {
            try note.write(toFile: filePath, atomically: true, encoding: .utf8)
            Logger.shared.log("CloudAPI: Hour note written - \(filePath)")
        } catch {
            Logger.shared.error("CloudAPI Error (write hour note): \(error)")
        }
    }
    
    // MARK: - Obsidian
    
    private func writeToObsidian(note: String, date: Date) async {
        let vaultPath = (configManager.config.obsidianVaultPath as NSString).expandingTildeInPath
        let dateString = formatDate(date)
        
        // Extract title from the note content (first H1 line)
        var title = "Daily Note"
        let lines = note.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("# ") {
                title = line
                    .replacingOccurrences(of: "# ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        // Clean title for filename
        let cleanTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        
        // Get local time for filename
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH'h'mm"
        timeFormatter.timeZone = TimeZone.current
        let timeString = timeFormatter.string(from: Date())
        
        // Format: "Daily Notes/2026-01-13 19h23 - Desenvolvimento do MonitorWatch.md"
        let filePath = "\(vaultPath)/Daily Notes/\(dateString) \(timeString) - \(cleanTitle).md"
        
        // Create directory if needed
        let directory = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        
        // Write note
        do {
            try note.write(toFile: filePath, atomically: true, encoding: .utf8)
            Logger.shared.log("CloudAPI: Note written to Obsidian - \(filePath)")
        } catch {
            Logger.shared.error("CloudAPI Error (write obsidian): \(error)")
        }
    }
    
    // MARK: - HTTP Helpers
    
    private func post<T: Encodable, R: Decodable>(endpoint: String, body: T) async throws -> R {
        guard let url = URL(string: configManager.config.apiUrl + endpoint) else {
            Logger.shared.error("CloudAPI: Invalid URL structure: \(configManager.config.apiUrl + endpoint)")
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configManager.config.apiKey)", forHTTPHeaderField: "Authorization")
        
        // Send OpenRouter key for AI generation
        if !configManager.config.openRouterKey.isEmpty {
            request.setValue(configManager.config.openRouterKey, forHTTPHeaderField: "X-OpenRouter-Key")
        }
        
        // Send note language preference
        request.setValue(configManager.config.noteLanguage.rawValue, forHTTPHeaderField: "X-Note-Language")
        
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to decode error message
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detailMessage = errorJson["message"] as? String {
                    throw APIError.serverError(message: detailMessage)
                }
                if let errorMessage = errorJson["error"] as? String {
                     throw APIError.serverError(message: errorMessage)
                }
            }
            throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }
        
        return try decoder.decode(R.self, from: data)
    }
    
    private func post<T: Encodable>(endpoint: String, body: T) async throws {
        guard let url = URL(string: configManager.config.apiUrl + endpoint) else {
            Logger.shared.error("CloudAPI: Invalid URL structure: \(configManager.config.apiUrl + endpoint)")
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configManager.config.apiKey)", forHTTPHeaderField: "Authorization")
        
        // Send OpenRouter key for AI generation
        if !configManager.config.openRouterKey.isEmpty {
            request.setValue(configManager.config.openRouterKey, forHTTPHeaderField: "X-OpenRouter-Key")
        }
        
        // Send note language preference
        request.setValue(configManager.config.noteLanguage.rawValue, forHTTPHeaderField: "X-Note-Language")
        
        request.httpBody = try encoder.encode(body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw APIError.invalidResponse
        }
         
        guard httpResponse.statusCode == 200 else {
             throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }
    
    private func get<R: Decodable>(endpoint: String) async throws -> R {
        guard let url = URL(string: configManager.config.apiUrl + endpoint) else {
            Logger.shared.error("CloudAPI: Invalid URL structure: \(configManager.config.apiUrl + endpoint)")
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let cleanKey = configManager.config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return try decoder.decode(R.self, from: data)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Response Types

struct NoteResponse: Codable {
    let success: Bool
    let note: String
    
    // Handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

enum APIError: LocalizedError {
    case requestFailed(statusCode: Int)
    case invalidResponse
    case serverError(message: String)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode):
            return "Request failed with status: \(statusCode)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
