//
//  AudioMonitor.swift
//  MonitorWatch
//
//  Monitors system and microphone audio with speech-to-text
//

import AVFoundation
import Speech
import UserNotifications
import AppKit

class AudioMonitor {
    private var isRunning = false
    private var isRecordingEnabled = false
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // OpenRouter audio recording (internal for extension access)
    internal var audioEngine: AVAudioEngine?
    internal var audioBuffers: [AVAudioPCMBuffer] = []
    internal var recordingTimer: Timer?
    
    // Try pt-BR first, then current, then en-US
    private let speechRecognizer: SFSpeechRecognizer? = {
        let locales = [Locale(identifier: "pt-BR"), Locale.current, Locale(identifier: "en-US")]
        for locale in locales {
            if let rec = SFSpeechRecognizer(locale: locale), rec.isAvailable {
                Logger.shared.log("AudioMonitor: Initialized with Locale: \(locale.identifier)")
                return rec
            }
        }
        Logger.shared.error("AudioMonitor: Failed to find valid locale")
        return nil
    }()
    
    init() {
        if speechRecognizer == nil {
            Logger.shared.error("AudioMonitor: FATAL - No Speech Recognizer available")
        }
    }
    
    private var currentTranscript = ""
    private var transcriptStartTime: Date?
    private var silenceTimer: Timer?
    
    func start() {
        guard !isRunning else { return }
        
        // Check current status first to avoid spamming "Requesting..." loop
        let status = SFSpeechRecognizer.authorizationStatus()
        
        switch status {
        case .authorized:
            // Just start, don't notify every time (it creates spam on app switching)
            // Logger.shared.log("AudioMonitor: Auth already granted, starting...")
            self.startListening()
            
        case .notDetermined:
            // Only request if not determined
            SFSpeechRecognizer.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if newStatus == .authorized {
                        self.sendNotification(title: "MonitorWatch", text: "✅ Permissão concedida!")
                        self.startListening()
                    } else {
                         self.sendNotification(title: "⚠️ Erro", text: "Permissão de fala negada.")
                    }
                }
            }
            
        case .denied, .restricted:
            Logger.shared.error("AudioMonitor: Auth Denied/Restricted. Cannot start.")
            // self.sendNotification(title: "⚠️ Erro", text: "Permissão negada. Verifique Ajustes.")
            
        @unknown default:
            break
        }
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        silenceTimer?.invalidate()
        
        // Send final transcript if any
        if !currentTranscript.isEmpty {
            sendTranscript()
        }
        
        Logger.shared.log("AudioMonitor: Stopped")
    }
    
    private func startListening() {
        isRunning = true
        currentTranscript = ""
        transcriptStartTime = Date()
        
        audioEngine = AVAudioEngine()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let audioEngine = audioEngine,
              let recognitionRequest = recognitionRequest,
              let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else {
            Logger.shared.error("AudioMonitor: Setup failed")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.retryCount = 0 // Reset retries on successful data
                self.currentTranscript = result.bestTranscription.formattedString.lowercased()
                self.resetSilenceTimer()
                
                // Hotword Detection
                let lowerText = self.currentTranscript
                let trigger = ConfigManager.shared.config.voiceTriggerPhrase.lowercased()
                
                // Debug Log
                // Logger.shared.log("AudioMonitor: Heard: '\(lowerText)' vs '\(trigger)'", level: "DEBUG")
                
                if !trigger.isEmpty && lowerText.contains(trigger) {
                    Logger.shared.log("AudioMonitor: 🎤 Trigger detected: '\(trigger)' in '\(lowerText)'")
                    
                    // Feedback to User
                    NSSound.beep() // Audible confirmation
                    DispatchQueue.main.async {
                        self.sendNotification(title: "MonitorWatch", text: "Fazendo a nota... 📝")
                    }
                    
                    // Trigger Action
                    self.handleVoiceTrigger()
                    
                    // Reset to avoid multiple triggers
                    self.restartListening() 
                    return
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                // If error, don't spam sendTranscript if we are just listening for hotword
                self.sendTranscript()
                
                // Restart if still running
                if self.isRunning {
                     // Add slight delay to prevent tight loop on error (backoff handled in restartListening)
                     self.restartListening()
                }
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            Logger.shared.log("AudioMonitor: Started listening")
        } catch {
            Logger.shared.error("AudioMonitor Error: \(error)")
        }
    }
    
    private var retryCount = 0
    private func restartListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        
        // Prevent infinite rapid loops
        retryCount += 1
        if retryCount > 5 {
            Logger.shared.error("AudioMonitor: 🛑 Too many restarts/errors (\(retryCount)). Stopping AudioMonitor.")
            self.stop()
            return
        }
        
        // Backoff delay
        let delay = Double(retryCount) * 1.5 // 1.5s, 3s, 4.5s...
        Logger.shared.log("AudioMonitor: Restarting in \(delay)s (Attempt \(retryCount))...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startListening()
        }
    }
    
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            // 3 seconds of silence - send transcript if enabled
            self?.sendTranscript()
        }
    }
    
    func setRecording(_ enabled: Bool) {
        self.isRecordingEnabled = enabled
        Logger.shared.log("AudioMonitor: Recording \(enabled ? "Enabled" : "Disabled") (Hotword Detection Active)")
    }
    
    private func sendTranscript() {
        guard isRecordingEnabled else { return }
        forceSendTranscript()
    }
    
    private func forceSendTranscript() {
        guard !currentTranscript.isEmpty else { return }
        
        let transcript = Transcript(
            id: UUID(),
            timestamp: transcriptStartTime ?? Date(),
            text: currentTranscript,
            source: "microphone",
            durationSeconds: Int(Date().timeIntervalSince(transcriptStartTime ?? Date()))
        )
        
        Task {
            await CloudAPI.shared.sendTranscript(transcript)
        }
        
        currentTranscript = ""
        transcriptStartTime = Date()
    }
    
    private func handleVoiceTrigger() {
        // 1. Send what we have so far (context)
        forceSendTranscript()
        
        Logger.shared.log("AudioMonitor: Initiating Meeting Note Generation via Voice...")
        
        // 2. Trigger Generation
        Task {
            // Use "Voice Command" context and let AI infer from transcript.
            let now = Date()
            let context = "Voice Command (Faz a nota)"
            
            // Send feedback
            DispatchQueue.main.async {
               self.sendNotification(title: "MonitorWatch", text: "Gerando nota... 🤖")
            }
            
            do {
                try await CloudAPI.shared.generateMeetingNote(
                    startTime: now.addingTimeInterval(-7200), // Last 2 hours (Let AI filter)
                    endTime: now,
                    context: context
                )
                
                // Success Feedback
                DispatchQueue.main.async {
                   self.sendNotification(title: "MonitorWatch", text: "Nota criada com sucesso! ✅")
                   NSSound(named: "Glass")?.play()
                }
            } catch {
                 // Error Feedback
                DispatchQueue.main.async {
                   self.sendNotification(title: "MonitorWatch", text: "Erro ao criar nota ❌")
                   NSSound(named: "Basso")?.play()
                }
                Logger.shared.error("AudioMonitor: Note generation failed: \(error)")
            }
        }
    }
    
    private func sendNotification(title: String, text: String) {
        Logger.shared.log("AudioMonitor: Sending Notification - Title: \(title), Body: \(text)")
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.error("AudioMonitor: Notification error: \(error)")
            }
        }
    }
}
