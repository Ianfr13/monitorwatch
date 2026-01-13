//
//  SettingsView.swift
//  MonitorWatch
//

import SwiftUI

struct SettingsView: View {
    @State private var config = ConfigManager.shared.config
    
    var body: some View {
        TabView {
            // General Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupBox("Capture Mode") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $config.performanceProfile) {
                                Text("Economy").tag("max_economy")
                                Text("Balanced").tag("balanced")
                                Text("Quality").tag("max_quality")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            Text("Economy saves battery, Quality captures more detail")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                    
                    GroupBox("Obsidian Vault") {
                        VStack(alignment: .leading, spacing: 8) {
                            let vaults = VaultDiscovery.discoverVaults()
                            if vaults.isEmpty {
                                TextField("Path", text: $config.obsidianVaultPath)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("", selection: $config.obsidianVaultPath) {
                                    ForEach(vaults, id: \.path) { vault in
                                        Text(vault.name).tag(vault.path)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                        .padding(4)
                    }
                    
                    GroupBox("Voice Command") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Trigger phrase", text: $config.voiceTriggerPhrase)
                                .textFieldStyle(.roundedBorder)
                            Text("Say this phrase to create a note")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                    
                    GroupBox("Note Language") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $config.noteLanguage) {
                                Text("English").tag(NoteLanguage.en)
                                Text("Portugues").tag(NoteLanguage.pt)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            Text("Language for generated notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                    
                    saveButton
                }
                .padding(20)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            
            // Connection Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupBox("Backend API") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledField("URL", text: $config.apiUrl)
                            LabeledSecureField("API Key", text: $config.apiKey)
                        }
                        .padding(4)
                    }
                    
                    GroupBox("OpenRouter") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledSecureField("API Key", text: $config.openRouterKey)
                            Text("Required for AI note generation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                    
                    saveButton
                }
                .padding(20)
            }
            .tabItem { Label("Connection", systemImage: "network") }
            
            // Processing Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupBox("Audio Transcription") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $config.audioProvider) {
                                Text("Apple (Free)").tag("apple")
                                Text("OpenRouter").tag("openrouter")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            if config.audioProvider == "openrouter" {
                                TextField("Model ID", text: $config.audioModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(4)
                    }
                    
                    GroupBox("Vision / OCR") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $config.visionProvider) {
                                Text("Apple (Free)").tag("apple")
                                Text("OpenRouter").tag("openrouter")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            if config.visionProvider == "openrouter" {
                                TextField("Model ID", text: $config.visionModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(4)
                    }
                    
                    saveButton
                }
                .padding(20)
            }
            .tabItem { Label("Processing", systemImage: "waveform") }
            
            // Schedule Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupBox("Automatic Generation") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Frequency", selection: $config.noteFrequency) {
                                ForEach(NoteFrequency.allCases, id: \.self) { freq in
                                    Text(freq.displayName).tag(freq)
                                }
                            }
                            .labelsHidden()
                            
                            Text("How often to generate daily notes automatically")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                    
                    if config.noteFrequency == .atScheduledTime {
                        GroupBox("Scheduled Time") {
                            VStack(alignment: .leading, spacing: 8) {
                                DatePicker(
                                    "Generate at",
                                    selection: Binding(
                                        get: {
                                            // Parse "HH:mm" to Date
                                            let components = config.scheduledTime.split(separator: ":").compactMap { Int($0) }
                                            let calendar = Calendar.current
                                            return calendar.date(bySettingHour: components[0], minute: components[1], second: 0, of: Date()) ?? Date()
                                        },
                                        set: { date in
                                            // Convert Date to "HH:mm"
                                            let formatter = DateFormatter()
                                            formatter.dateFormat = "HH:mm"
                                            config.scheduledTime = formatter.string(from: date)
                                        }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                
                                Text("Notes will be generated daily at this time")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(4)
                        }
                    }
                    
                    GroupBox("Triggers") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Generate when Mac sleeps", isOn: $config.generateOnSleep)
                            
                            Text("Also generate a note when your Mac goes to sleep or shuts down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                    
                    GroupBox("Hour Notes") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Hour Notes", isOn: $config.hourNotesEnabled)
                            
                            Text("Automatically generate a separate note for each hour of activity. Notes are saved to Hour Notes folder with descriptive titles based on what you worked on.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                    
                    GroupBox("Status") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Scheduler Active")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(config.noteFrequency == .disabled
                                        ? "Automatic generation is disabled"
                                        : "Notes will be generated according to your schedule")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                Image(systemName: "zzz")
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sleep Mode")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(config.generateOnSleep
                                        ? "Notes will be generated when Mac sleeps"
                                        : "Sleep mode generation is disabled")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(4)
                    }
                    
                    GroupBox("Launch at Login") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Launch MonitorWatch when I log in", isOn: $config.launchAtLogin)
                            
                            Text("MonitorWatch will automatically start when you turn on your Mac or log in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                    
                    saveButton
                }
                .padding(20)
            }
            .tabItem { Label("Schedule", systemImage: "calendar") }
        }
        .frame(width: 450, height: 380)
    }
    
    private var saveButton: some View {
        HStack {
            Spacer()
            Button("Save") {
                ConfigManager.shared.update(config)
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Helper Views

struct LabeledField: View {
    let label: String
    @Binding var text: String
    
    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct LabeledSecureField: View {
    let label: String
    @Binding var text: String
    
    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            SecureField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
