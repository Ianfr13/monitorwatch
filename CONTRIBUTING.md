# Contributing to MonitorWatch

Thanks for your interest in contributing! This project was built through **vibe coding** - conversational AI programming. We encourage the same spirit of collaboration.

## 🎯 How to Contribute

### Reporting Issues

Before creating an issue, please check:

1. **Search existing issues** - Your problem might already be reported
2. **Check the [Troubleshooting](README.md#troubleshooting) section** - Common problems are documented
3. **Include details**:
   ```markdown
   ### System
   - macOS Version: 13.5 (Ventura)
   - MonitorWatch Version: 1.0
   
   ### Problem
   [Describe what's happening vs what you expect]
   
   ### Steps to Reproduce
   1. Go to Settings
   2. Configure API URL
   3. Click Save
   4. [What happens?]
   
   ### Logs
   [Relevant output from ~/Downloads/MonitorWatch.log]
   ```

### Submitting Code

1. **Fork the repository**
   ```bash
   # Fork button on GitHub, then:
   git clone https://github.com/YOUR_USERNAME/monitorwatch.git
   cd monitorwatch
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing code style (Swift, TypeScript)
   - Add comments for complex logic
   - Test thoroughly

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "Add: feature description
   
   - Implemented feature X
   - Fixed bug Y
   - Updated documentation"
   ```

5. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request**
   - Describe what changed and why
   - Link to any related issues
   - Mention this is built via vibe coding!

## 📝 Code Style

### Swift (macOS App)
- Use SwiftUI for all UI
- Prefer `async/await` over completion handlers
- Use `Logger.shared.log()` for debug output
- Follow Swift naming conventions (camelCase for variables, PascalCase for types)

### TypeScript (Workers Backend)
- Use strict mode
- Type all functions and interfaces
- Follow existing patterns for API routes
- Use async/await consistently

## 🏗️ Project Structure

```
monitorwatch/
├── macos/              # Native macOS application
│   ├── Models/          # Data structures
│   ├── Views/           # SwiftUI views
│   └── Services/        # Core functionality
│       ├── ActivityMonitor.swift
│       ├── AudioMonitor.swift
│       ├── CloudAPI.swift
│       ├── ConfigManager.swift
│       ├── NoteScheduler.swift
│       └── LaunchAtLogin.swift
│
├── workers/            # Cloudflare Workers backend
│   └── src/
│       ├── handlers/      # API route handlers
│       ├── ai.ts         # OpenRouter integration
│       ├── types.ts       # TypeScript interfaces
│       └── utils.ts       # Helper functions
│
└── .github/            # GitHub workflows and config
    └── workflows/
        └── deploy.yml   # Auto-deploy to Cloudflare
```

## 🧪 Testing

### macOS App
```bash
cd macos
xcodebuild -scheme MonitorWatch test
# Or open in Xcode and run tests (Cmd+U)
```

### Workers Backend
```bash
cd workers
npm test
# (We need to add tests!)
```

## 🔒 Security Guidelines

### NEVER Commit

- `.env` files containing secrets
- API keys (OpenRouter, Gemini, etc.)
- Personal credentials
- Database files with real data

### Secrets Management

- All secrets go in **GitHub Repository Secrets**
- For Cloudflare Workers: `wrangler secret put VARIABLE_NAME`
- For macOS app: Settings → Connection → Enter manually
- See [README.md](README.md#understanding-api-keys) for details

## 🎨 Vibe Coding Philosophy

This project embraces the "vibe coding" approach:

1. **Converse with AI** - Describe your feature, ask for implementation
2. **Review together** - AI explains code, you review and iterate
3. **Iterate quickly** - Small changes, frequent commits
4. **Learn continuously** - Understand what's being built, don't just copy-paste

### Example Prompt

> "I want to add support for custom prompt templates. Users should be able to save different note templates in Settings and choose which one to use when generating notes. The templates should be stored in the same config file we're using. Can you implement this?"

## 📚 Documentation Updates

- Keep [README.md](README.md) in sync with code changes
- Update [CODEOWNERS](CODEOWNERS) when adding new files/sections
- Document new features with examples
- Add troubleshooting steps for common issues

## 🤝 Developer Certificate

Contributing to MonitorWatch means:

- [ ] I've read the [Code of Conduct](CODE_OF_CONDUCT.md)
- [ ] I've tested my changes thoroughly
- [ ] I've updated relevant documentation
- [ ] I've added tests where applicable
- [ ] I've respected the existing code style
- [ ] My commits follow semantic versioning (Conventional Commits)

## 🚀 Getting Started

New contributors? Start here:

1. **Clone and build**
   ```bash
   git clone https://github.com/ianfr13/monitorwatch.git
   cd monitorwatch
   
   # Backend
   cd workers && npm install
   
   # macOS app
   cd ../macos && xcodebuild -scheme MonitorWatch -configuration Debug build
   ```

2. **Set up secrets** (see README)
3. **Run locally** - Make the app work on your machine
4. **Choose an issue** - Pick something that interests you
5. **Reach out** - Ask questions in issues or via AI coding!

## 💡 Feature Ideas

Looking for something to work on? Check these:

- [ ] **iOS companion app** - Sync with macOS version
- [ ] **Weekly/monthly summaries** - Aggregate daily notes
- [ ] **Custom prompt templates** - Let users define AI prompts
- [ ] **Obsidian plugin** - Bidirectional sync with vault
- [ ] **Multi-vault support** - Manage multiple vaults
- [ ] **Export formats** - Notion, Logseq, Apple Notes
- [ ] **Global hotkeys** - Quick note generation anywhere
- [ ] **Meeting assistant** - Real-time note-taking during meetings
- [ ] **Analytics dashboard** - Visualize productivity patterns
- [ ] **Tests** - Unit and integration tests for backend and app

## 📞 Contact

- **GitHub Issues**: For bug reports and feature requests
- **Pull Requests**: For code contributions
- **Security**: security@monitorwatch.dev (if you find a vulnerability)

---

**Happy vibing!** 🎸✨
