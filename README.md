<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Cloudflare-Workers-F38020?style=flat-square&logo=cloudflare" alt="Cloudflare">
  <img src="https://img.shields.io/badge/Built%20with-Vibe%20Coding-purple?style=flat-square" alt="Vibe Coding">
</p>

# MonitorWatch

**Intelligent Activity Monitoring for Obsidian**

A macOS menu bar app that silently observes your daily workflow and uses AI to generate beautifully structured notes in your Obsidian vault. Think of it as an automatic work journal that writes itself.

---

> **Built 100% through Vibe Coding**  
> This entire project — every line of Swift, TypeScript, and configuration — was created through conversational AI programming. No traditional coding. Just vibes.

---

## What It Does

MonitorWatch runs quietly in your menu bar, capturing the context of your workday:

| Capture Type | What's Recorded |
|--------------|-----------------|
| **App Usage** | Which apps you use and when |
| **Window Titles** | What you're working on |
| **Audio** | Meeting transcriptions, voice notes |
| **Screen Content** | OCR text from screenshots (optional) |

At the end of your day (or on-demand via voice command), all this context is sent to an AI that generates a comprehensive daily note — formatted perfectly for Obsidian with tags and wiki-links. Optionally, generate **Hour Notes** for granular tracking of your workday.

---

## Key Features

### Automated Note Scheduling

Never forget to generate your daily note again:

- **Flexible frequencies**: Every hour, 2h, 4h, daily, or at a specific time
- **Sleep-aware generation**: Automatically generates when you close your Mac
- **Smart rescheduling**: After generating at 22:00, automatically schedules for tomorrow at 22:00
- **Graceful failures**: Notifications let you know if generation succeeds or fails

### Smart Capture Modes

Different apps get different treatment:

| Mode | Behavior | Example Apps |
|------|----------|--------------|
| `full` | Screenshots + OCR + metadata | Browsers, research tools |
| `screenshot` | Visual capture, no OCR | Code editors, design apps |
| `audio` | Transcription only | Zoom, Google Meet, Teams |
| `metadata` | Window title only | General productivity apps |
| `ignore` | Nothing captured | Password managers, banking |

### Automatic Note Generation

Generate daily notes automatically based on your schedule:

| Frequency | Description |
|-----------|-------------|
| **Disabled** | Manual generation only (via menu or voice command) |
| **Every hour** | Generates every 60 minutes |
| **Every 2 hours** | Generates every 2 hours |
| **Every 4 hours** | Generates every 4 hours |
| **Once a day** | Generates once every 24 hours |
| **At scheduled time** | Generates at a specific time (e.g., 22:00) |

**Smart Triggers:**
- ⏰ **Sleep mode**: Automatically generates a note when your Mac goes to sleep or shuts down
- 📅 **Scheduled time**: Pick a specific time for daily generation
- 🔄 **Auto-reschedule**: After generating at a scheduled time, automatically schedules for the next day

**Protection:** Minimum 30-minute cooldown between automatic generations to prevent spam

### Hour Notes

Generate detailed notes for each hour of activity:

- **Automatic generation**: Creates notes every hour when Mac is active
- **Smart titles**: AI detects the main subject (e.g., "Refactoring CloudAPI Module")
- **WikiLinks**: Automatically links to related notes in your vault
- **Organized storage**: Saved to `Hour Notes/YYYY-MM-DD HHh - Subject.md`

Enable in **Settings → Schedule → Hour Notes**.

### Voice Commands

Say **"faz a nota"** (or customize your trigger phrase) to instantly generate a note. Perfect for:
- Ending meetings with automatic minutes
- Quick brain dumps throughout the day
- Capturing thoughts without touching keyboard

### Meeting Detection

MonitorWatch detects when you exit video conferencing apps and can automatically generate meeting notes with:
- Attendee detection (from transcription)
- Key points discussed
- Action items extracted

### Privacy-First Design

- **On-device processing**: Speech recognition and OCR run locally using Apple frameworks
- **Self-hosted backend**: Your data goes to YOUR Cloudflare Workers instance
- **24-hour retention**: All raw data auto-deletes after one day
- **Granular control**: Ignore any app, block any URL pattern
- **Smart chunking**: Data processed in 30-min chunks for better context

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         MonitorWatch App                             │
│                        (macOS Menu Bar)                              │
│                                                                      │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐               │
│   │  Activity   │   │    Audio    │   │     OCR     │               │
│   │  Monitor    │   │   Monitor   │   │   Service   │               │
│   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘               │
│          │                 │                  │                      │
│          └─────────────────┴──────────────────┘                      │
│                            │                                         │
│                     ┌──────▼──────┐                                  │
│                     │ NoteScheduler│ ◄─── Automatic generation       │
│                     └──────┬──────┘                                  │
│                            │                                         │
│                     ┌──────▼──────┐                                  │
│                     │  Cloud API  │                                  │
│                     └──────┬──────┘                                  │
└────────────────────────────┼─────────────────────────────────────────┘
                             │
                             │ HTTPS (encrypted)
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Cloudflare Workers                              │
│                                                                      │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐               │
│   │  REST API   │   │ D1 Database │   │  KV Config  │               │
│   │   Router    │   │  (SQLite)   │   │    Store    │               │
│   └──────┬──────┘   └─────────────┘   └─────────────┘               │
│          │                                                           │
│          ▼                                                           │
│   ┌─────────────┐                                                    │
│   │ OpenRouter  │───► AI Note Generation                             │
│   │     API     │    (Gemini, Claude, GPT, etc.)                     │
│   └─────────────┘                                                    │
└─────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Obsidian Vault                                │
│                                                                      │
│   📁 Daily Notes/                                                    │
│      └── 2024-01-15 19h30 - Development Session.md  ← Daily log     │
│   📁 Hour Notes/                                                     │
│      └── 2024-01-15 14h - Refactoring CloudAPI.md   ← Hourly notes  │
│   📁 Meetings/                                                       │
│      └── 2024-01-15 - Team Sync.md   ← Meeting minutes              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **macOS App** | Swift 5.9 + SwiftUI | Native menu bar application |
| **Backend** | Cloudflare Workers | Serverless API (TypeScript) |
| **Database** | Cloudflare D1 | SQLite-based activity storage |
| **Config** | Cloudflare KV | User preferences storage |
| **AI** | OpenRouter | Multi-model AI gateway |
| **Speech** | Apple Speech Framework | On-device transcription |
| **Vision** | Apple Vision Framework | On-device OCR |
| **Scheduling** | Timer + NSWorkspace | Auto note generation & sleep detection |

---

## Understanding API Keys

There are **three different API keys** used in MonitorWatch. Don't confuse them!

| Key Type | What it's for | Where to get it |
|-----------|----------------|-----------------|
| **API_SECRET_KEY** | Password between your macOS app and your Cloudflare Workers backend | **You create it yourself!** Run `npx wrangler secret put API_SECRET_KEY` and choose any secure string |
| **OpenRouter API Key** | AI model access (for generating notes) | Get from [openrouter.ai/keys](https://openrouter.ai/keys) |
| **GEMINI_API_KEY** (optional) | Direct access to Google's Gemini AI | Get from [aistudio.google.com](https://aistudio.google.com) |

### Creating Your API_SECRET_KEY

This is the most confusing part - you create this key yourself:

```bash
cd workers
npx wrangler secret put API_SECRET_KEY

# You'll see this prompt:
# ⛅️ wrangler 3.x.x
# Enter the secret value:
#
# Type any secure string, for example:
# monitorwatch-secret-2024-abc123
#
# Then press Enter
```

**Important:** Remember this exact string! You'll need to enter it in your macOS app settings later.

---

## Installation

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15+ (for building from source)
- Node.js 18+ (for backend deployment)
- [OpenRouter](https://openrouter.ai) API key
- [Cloudflare](https://cloudflare.com) account (free tier works)

### Step 1: Deploy the Backend

```bash
# Clone the repository
git clone https://github.com/ianfr13/monitorwatch.git
cd monitorwatch/workers

# Install dependencies
npm install

# Login to Cloudflare
npx wrangler login

# Create D1 database
npx wrangler d1 create monitorwatch
# Copy the database_id to wrangler.toml

# Create KV namespace
npx wrangler kv:namespace create CONFIG
# Copy the id to wrangler.toml

# Set API_SECRET_KEY (for authentication between app and backend)
npx wrangler secret put API_SECRET_KEY
# You'll be prompted to enter a secret - choose any secure string
# Example: my-secret-key-12345
# REMEMBER THIS KEY - you'll need it in the macOS app settings

# Set GEMINI_API_KEY (optional, if you want to use Gemini directly)
npx wrangler secret put GEMINI_API_KEY
# Enter your Google AI API key if you have one

# Initialize database schema
npx wrangler d1 execute monitorwatch --remote --file=schema.sql

# Deploy to production
npx wrangler deploy
```

Save your deployed URL (it will look like):
```
https://monitorwatch-api.YOUR_CLOUDFLARE_ACCOUNT.workers.dev
```

### Step 2: Build the macOS App

```bash
cd ../macos

# Build for production (optimized, signed)
xcodebuild -scheme MonitorWatch -configuration Release build

# Or open in Xcode for debugging
open MonitorWatch.xcodeproj
# Press Cmd+B to build, Cmd+R to run
```

The built app will be in:
```
~/Library/Developer/Xcode/DerivedData/MonitorWatch-xxx/Build/Products/Release/MonitorWatch.app
```

**Copy to Applications:**
```bash
# Move to Applications folder for easy access
cp -R ~/Library/Developer/Xcode/DerivedData/MonitorWatch-xxx/Build/Products/Release/MonitorWatch.app /Applications/
```

### Step 3: Configure the App

1. Launch MonitorWatch (appears in menu bar as an eye icon)
2. Click the icon → **Settings**
3. **Connection tab**: Configure your API:
   - **API URL**: Your Cloudflare Workers URL (from Step 1)
   - **API Key**: The secret you chose when running `wrangler secret put API_SECRET_KEY`
     - This authenticates your macOS app with your Cloudflare Workers
     - It must match exactly what you entered in the backend setup
   - **OpenRouter Key**: Your OpenRouter API key (get from [openrouter.ai](https://openrouter.ai))
4. **General tab**: Set up your preferences:
   - Obsidian Vault: Select from detected vaults
   - Note Language: English or Portugues
   - Capture Mode: Economy, Balanced, or Quality
5. **Schedule tab**: Configure automatic generation:
   - Frequency: Choose how often to generate notes
   - Scheduled Time: Set specific time (e.g., 22:20)
   - Generate on Sleep: Enable to generate when Mac sleeps
   - Launch at Login: Enable to auto-start when you turn on your Mac
6. Click **Save**

### Step 4: Grant Permissions

On first run, macOS will ask for permissions:

| Permission | Why Needed |
|------------|------------|
| **Accessibility** | Read window titles |
| **Screen Recording** | Capture screenshots (optional) |
| **Microphone** | Voice commands & transcription |
| **Speech Recognition** | Process audio locally |

---

## Configuration Options

### General Settings

| Option | Default | Description |
|--------|---------|-------------|
| Capture Mode | Balanced | Economy (less data) / Balanced / Quality (more detail) |
| Voice Trigger | "faz a nota" | Phrase to generate instant notes |
| Note Language | English | Language for AI-generated notes (English / Portugues) |
| Obsidian Vault | Auto-detected | Where notes are saved |

### Schedule Settings

| Option | Default | Description |
|--------|---------|-------------|
| Frequency | Disabled | How often to generate daily notes automatically |
| Scheduled Time | 22:00 | Specific time for daily generation (when "At scheduled time" is selected) |
| Generate on Sleep | Enabled | Generate note when Mac sleeps or shuts down |
| Hour Notes | Disabled | Generate separate notes for each hour of activity |
| Launch at Login | Disabled | Auto-start app when you turn on Mac or log in |

---

## Launch at Login (Auto-Start)

MonitorWatch can automatically start every time you turn on your Mac or log in to your account.

### How to Enable

1. Open MonitorWatch Settings (click eye icon in menu bar)
2. Go to **Schedule** tab
3. Enable **"Launch MonitorWatch when I log in"**
4. Click **Save**

### How It Works

When enabled:
- ✅ App starts automatically on system boot
- ✅ App starts when you log in to your account
- ✅ Note scheduler runs immediately on startup
- ✅ All your configured triggers (sleep, scheduled time) remain active

### To Disable

Uncheck the toggle in Settings → Schedule tab and save.

> **Note:** macOS may ask for permission the first time. Grant it to allow auto-start to work.
| Launch at Login | Disabled | Auto-start app when you turn on Mac or log in |

### Connection Settings

| Option | Description |
|--------|-------------|
| API URL | Your Cloudflare Workers endpoint (e.g., `https://monitorwatch-api.yourname.workers.dev`) |
| API Key | Authentication secret - **must match** what you set with `wrangler secret put API_SECRET_KEY` |
| OpenRouter Key | For AI note generation - get from [openrouter.ai/keys](https://openrouter.ai/keys) |

> **Note:** The API Key is NOT something you get from Cloudflare or OpenRouter. It's a secret password YOU create to secure your own backend. For example, you could choose `monitorwatch-2024-secure` - just use the same string in both places (backend secret and macOS app settings).

### Processing Settings

| Option | Choices | Description |
|--------|---------|-------------|
| Audio Provider | Apple / OpenRouter | Apple is free and local |
| Vision Provider | Apple / OpenRouter | Apple is free and local |

---

## Generated Notes

### Daily Log Example

```markdown
# MonitorWatch Development Session #3

*15/01/2024 - Generated: 2024-01-15 19:30:45*

## Summary

Deep work session on the #MonitorWatch project. Spent the morning in 
[[Xcode]] refactoring the Settings UI, afternoon on backend deployment. 
Quick sync with the team about launch timeline.

## Deliverables & Focus

> [!SUCCESS] Highlights
> - [x] Redesigned Settings interface
> - [x] Fixed notification delivery bug  
> - [x] Deployed backend v2.1

### Projects & Tasks

- **MonitorWatch**: SwiftUI Settings view refactoring
- **Backend**: Workers TypeScript deployment
- **Research**: Cloudflare docs, OpenRouter API reference

## Meetings & Insights

> [!quote] Conversations
> Team Sync (15 min) - Discussed Friday soft launch. Need demo video by Thursday.

## Learning

- [[SwiftUI]] state management patterns
- #tech/CloudflareWorkers deployment strategies

## Reflection

> [!question] Questions
> - How to improve voice trigger accuracy in noisy environments?
> - Should we add global keyboard shortcuts?

---
*Generated by MonitorWatch*
```

### Hour Note Example

```markdown
# Refactoring CloudAPI Module

*Generated: 2024-01-15 14:05:23*

This hour was focused on improving the CloudAPI module in the MonitorWatch 
macOS app. The main changes involved restructuring the HTTP request handling 
and adding support for the new hourly summaries endpoint.

Key modifications included updating the post() method to handle the new 
response format from the backend, and implementing the scanVaultForNotes() 
function that scans the Obsidian vault for existing notes to enable 
intelligent WikiLinks.

Related: [[CloudAPI]], [[MonitorWatch Architecture]]

#dev #swift #refactoring
```

### Meeting Notes Example

```markdown
---
date: 2024-01-15
type: meeting
participants: [Ian, Sarah, Mike]
tags: [meeting, planning, Q1]
---

# Project Planning Sync

## Summary

Quarterly planning session to align on Q1 priorities and resource allocation.

## Key Points

- Launch target moved to February 1st
- Design system audit scheduled for next week
- New hire starting January 22nd

## Action Items

> [!todo] Follow-ups
> - [ ] Ian: Prepare demo video by Thursday
> - [ ] Sarah: Finalize design specs
> - [ ] Mike: Set up staging environment

---
*Generated by MonitorWatch*
```

---

## Cost Breakdown

MonitorWatch is designed to be extremely affordable:

| Service | Monthly Cost |
|---------|--------------|
| Cloudflare Workers | **$0** (100k req/day free) |
| Cloudflare D1 | **$0** (5GB free) |
| Cloudflare KV | **$0** (100k reads/day free) |
| OpenRouter (Gemini Flash) | **~$2-3** |
| **Total** | **~$2-3/month** |

---

## Project Structure

```
monitorwatch/
│
├── macos/                      # macOS Application
│   ├── App.swift               # App entry point
│   ├── AppDelegate.swift       # Menu bar & lifecycle
│   ├── Info.plist              # App configuration
│   ├── MonitorWatch.entitlements
│   ├── MonitorWatch.xcodeproj/
│   │
│   ├── Models/
│   │   └── Models.swift        # Data structures
│   │
│   ├── Views/
│   │   └── SettingsView.swift  # Settings UI
│   │
│   └── Services/
│       ├── ActivityMonitor.swift    # App/window tracking
│       ├── AudioMonitor.swift       # Speech recognition
│       ├── CloudAPI.swift           # Backend communication
│       ├── ConfigManager.swift      # Settings persistence
│       ├── Logger.swift             # Debug logging
│       ├── NoteScheduler.swift      # Auto note generation
│       ├── OCRService.swift         # Text extraction
│       ├── ScreenCapture.swift      # Screenshot capture
│       └── VaultDiscovery.swift     # Find Obsidian vaults
│
├── workers/                    # Cloudflare Workers Backend
│   ├── src/
│   │   ├── index.ts            # API routes
│   │   ├── ai.ts               # OpenRouter integration
│   │   ├── types.ts            # TypeScript types
│   │   ├── utils.ts            # Helpers
│   │   └── handlers/
│   │       ├── activity.ts     # Activity endpoints
│   │       ├── transcript.ts   # Transcript endpoints
│   │       ├── notes.ts        # Note generation
│   │       ├── summaries.ts    # Hourly summaries processing
│   │       └── config.ts       # Config endpoints
│   │
│   ├── db/
│   │   ├── schema.sql          # Database schema
│   │   └── migrations/         # Database migrations
│   │
│   ├── wrangler.toml           # Cloudflare config
│   └── package.json
│
└── README.md
```

---

## Troubleshooting

### App not capturing activities

1. Check **System Preferences → Privacy & Security → Accessibility**
2. Ensure MonitorWatch is listed and enabled
3. Try removing and re-adding the permission

### Voice commands not working

1. Check **System Preferences → Privacy & Security → Microphone**
2. Check **System Preferences → Privacy & Security → Speech Recognition**
3. Speak clearly and wait for the trigger phrase to register

### Notes not appearing in Obsidian

1. Verify vault path in Settings
2. Check that `Daily Notes` folder exists (will be created automatically)
3. Look at logs: `~/Downloads/MonitorWatch.log`
4. For automatic generation, check Schedule settings

### Automatic generation not working

1. Check **Settings → Schedule** tab
2. Verify frequency is not set to "Disabled"
3. Check that "Generate on Sleep" is enabled if you want sleep-triggered notes
4. Review logs: `~/Downloads/MonitorWatch.log` for scheduler errors
5. Ensure all API keys are configured (Connection tab)

### API errors

1. **"Unauthorized" (401 error)**
   - Check that API Key in macOS app settings **exactly matches** what you set with `wrangler secret put API_SECRET_KEY`
   - Common mistake: using different strings in backend and app
   - Solution: Re-run `wrangler secret put API_SECRET_KEY` with a new value, then update app settings

2. **"OpenRouter API key not configured"**
   - Get a key from [openrouter.ai/keys](https://openrouter.ai/keys)
   - Enter it in Settings → Connection → OpenRouter Key
   - Make sure you have credits (Gemini Flash is very cheap)

3. Verify your Workers URL is correct (no trailing slash)
4. Check OpenRouter API key is valid and has credits

---

## Roadmap

- [x] Hour Notes for granular tracking
- [x] Intelligent WikiLinks to existing notes
- [x] Smart chunking (30-min intervals)
- [x] OCR error correction
- [ ] iOS companion app for mobile activity
- [ ] Global keyboard shortcuts
- [ ] Weekly/monthly summary generation
- [ ] Custom prompt templates
- [ ] Obsidian plugin for bidirectional sync
- [ ] Multi-vault support
- [ ] Export to Notion, Logseq, Apple Notes

---

## Contributing

This project was built through vibe coding, and contributions are welcome in the same spirit:

1. Fork the repository
2. Describe your feature idea to an AI
3. Vibe code it into existence
4. Submit a PR with a clear description

---

## License

MIT License — use it, modify it, ship it, sell it. See [LICENSE](./LICENSE) for details.

---

<p align="center">
  <br>
  <sub>Built with vibes, curiosity, and a lot of AI conversations</sub>
  <br>
  <br>
  <a href="#monitorwatch">Back to top</a>
</p>
