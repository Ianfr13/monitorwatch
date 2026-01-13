//
//  OCRService.swift
//  MonitorWatch
//
//  Extracts text from images using Apple Vision framework or OpenRouter
//

import Cocoa
import Vision

class OCRService {
    
    /// Extract text from an image using Vision OCR or OpenRouter
    func extractText(from image: NSImage) async -> String? {
        let config = ConfigManager.shared.config
        
        // Route to appropriate provider
        if config.visionProvider == "openrouter" {
            let text = await performOpenRouterOCR(on: image)
            return text.isEmpty ? nil : text
        } else {
            return await performAppleVisionOCR(on: image)
        }
    }
    
    // MARK: - Apple Vision OCR
    
    private func performAppleVisionOCR(on image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            
            // Configure for speed over accuracy
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("OCRService Error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - OpenRouter Vision/OCR
    
    private func performOpenRouterOCR(on image: NSImage) async -> String {
        // Convert NSImage to JPEG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            Logger.shared.error("OCRService: Failed to convert image to JPEG")
            return ""
        }
        
        do {
            let config = ConfigManager.shared.config
            let text = try await CloudAPI.shared.analyzeImage(
                jpegData,
                model: config.visionModel,
                prompt: "Extract all visible text from this screenshot. Return only the text, no commentary."
            )
            
            Logger.shared.log("OCRService: OpenRouter extracted \\(text.count) characters")
            return text
        } catch {
            Logger.shared.error("OCRService: OpenRouter OCR failed: \\(error)")
            return ""
        }
    }
}
