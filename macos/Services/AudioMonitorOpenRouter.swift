//
//  AudioMonitorOpenRouter.swift
//  MonitorWatch
//
//  OpenRouter audio transcription extension
//

import AVFoundation
import Foundation

extension AudioMonitor {
    
    // MARK: - OpenRouter Recording
    
    func startOpenRouterRecording() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        audioBuffers = []
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            self?.audioBuffers.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            Logger.shared.log("AudioMonitor: Started OpenRouter recording")
            
            // Send audio every 30 seconds
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                self?.processOpenRouterAudio()
            }
        } catch {
            Logger.shared.error("AudioMonitor OpenRouter Error: \\(error)")
        }
    }
    
    func processOpenRouterAudio() {
        guard !audioBuffers.isEmpty else { return }
        
        Logger.shared.log("AudioMonitor: Processing \\(audioBuffers.count) audio buffers with OpenRouter")
        
        // Convert buffers to audio file
        guard let audioData = convertBuffersToM4A(audioBuffers) else {
            Logger.shared.error("AudioMonitor: Failed to convert buffers")
            audioBuffers = []
            return
        }
        
        audioBuffers = []
        
        // Send to OpenRouter
        Task {
            do {
                let config = ConfigManager.shared.config
                let text = try await CloudAPI.shared.transcribeAudio(audioData, model: config.audioModel)
                
                if !text.isEmpty {
                    Logger.shared.log("AudioMonitor: OpenRouter transcribed: \\(text.prefix(50))...")
                    await self.sendTranscriptText(text)
                }
            } catch {
                Logger.shared.error("AudioMonitor: OpenRouter transcription failed: \\(error)")
            }
        }
    }
    
    func convertBuffersToM4A(_ buffers: [AVAudioPCMBuffer]) -> Data? {
        guard let firstBuffer = buffers.first else { return nil }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("audio_\\(UUID().uuidString).m4a")
        
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: firstBuffer.format.sampleRate,
                AVNumberOfChannelsKey: firstBuffer.format.channelCount,
                AVEncoderBitRateKey: 64000
            ]
            
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
            
            for buffer in buffers {
                try audioFile.write(from: buffer)
            }
            
            let data = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            
            return data
        } catch {
            Logger.shared.error("AudioMonitor: Failed to create audio file: \\(error)")
            return nil
        }
    }
    
    func sendTranscriptText(_ text: String) async {
        let transcript = Transcript(
            id: UUID(),
            timestamp: Date(),
            text: text,
            source: "openrouter",
            durationSeconds: 30
        )
        
        await CloudAPI.shared.sendTranscript(transcript)
    }
}
