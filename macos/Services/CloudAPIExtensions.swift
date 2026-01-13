//
//  CloudAPIExtensions.swift
//  MonitorWatch
//
//  OpenRouter media processing extensions
//

import Foundation

extension CloudAPI {
    
    // MARK: - OpenRouter Media Processing
    
    /// Transcribe audio using OpenRouter (Whisper or other models)
    func transcribeAudio(_ audioData: Data, model: String) async throws -> String {
        guard !configManager.config.apiUrl.isEmpty else {
            throw APIError.serverError(message: "API URL not configured")
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(configManager.config.apiUrl)/api/transcribe")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configManager.config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append(model.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }
        
        struct TranscribeResponse: Codable {
            let text: String
        }
        
        let result = try JSONDecoder().decode(TranscribeResponse.self, from: data)
        return result.text
    }
    
    /// Analyze image using OpenRouter (GPT-4V, Claude, etc.)
    func analyzeImage(_ imageData: Data, model: String, prompt: String? = nil) async throws -> String {
        guard !configManager.config.apiUrl.isEmpty else {
            throw APIError.serverError(message: "API URL not configured")
        }
        
        struct VisionRequest: Codable {
            let image: String
            let model: String
            let prompt: String?
        }
        
        struct VisionResponse: Codable {
            let text: String
        }
        
        let base64Image = imageData.base64EncodedString()
        let requestBody = VisionRequest(
            image: "data:image/jpeg;base64,\(base64Image)",
            model: model,
            prompt: prompt
        )
        
        var request = URLRequest(url: URL(string: "\(configManager.config.apiUrl)/api/vision")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configManager.config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(VisionResponse.self, from: data)
        return result.text
    }
}
