# Security Policy

## Supported Versions

| Version | Supported          |
|---------|-------------------|
| 1.x.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please follow these guidelines:

### Do NOT

- Create a public issue or pull request
- Discuss the vulnerability publicly in forums, chats, or social media
- Exploit the vulnerability for any purpose

### DO

- Send an email to security@monitorwatch.dev or via GitHub's private vulnerability reporting feature
- Include a clear description of the issue
- Provide steps to reproduce if applicable
- Suggest a fix if possible (optional but appreciated)

### Response Timeline

- Within 48 hours: Initial response acknowledging receipt
- Within 7 days: Assessment and severity rating
- Within 14 days: Fix or mitigation plan
- Within 30 days: Public disclosure (after fix is deployed)

### What to Expect

1. We'll acknowledge your report within 48 hours
2. We'll work with you to understand and verify the issue
3. We'll determine severity and prioritize a fix
4. We'll keep you updated on progress
5. When the fix is deployed, we'll credit you in the release notes (if you want)

### Security Best Practices

This project follows these security practices:

#### Secrets Management

- **Never commit secrets**: API keys, tokens, passwords, or credentials
- **Use GitHub Secrets**: Store secrets in repository settings, not in code
- **Environment variables**: All sensitive configuration through environment variables
- **Secret rotation**: Regular rotation of API keys and credentials

#### Dependencies

- **Regular updates**: Dependencies are updated monthly
- **Security scanning**: GitHub Dependabot checks for vulnerabilities
- **Vetted packages**: Only using well-maintained packages

#### Code Review

- **Mandatory review**: All code changes require review
- **Code owner approval**: Sensitive files require owner approval
- **Security checks**: Automated security checks in CI/CD pipeline

#### macOS App

- **Code signing**: App is code signed and notarized
- **Sandboxing**: Running in macOS sandbox where possible
- **Permissions**: Minimal required permissions only
- **Local storage**: Sensitive data stored securely in Keychain

#### Backend (Cloudflare Workers)

- **HTTPS only**: All communication encrypted
- **Request validation**: All inputs validated and sanitized
- **Rate limiting**: Protection against abuse
- **No sensitive data in logs**: Logs exclude credentials and secrets

### Third-Party Services

This project integrates with:

- **Cloudflare Workers**: Compute platform with DDoS protection
- **OpenRouter AI**: AI model API (requires your API key)
- **OpenAI**: AI model API (requires your API key)
- **Gemini**: Google AI model API (requires your API key)

All API keys are stored locally on your machine in:
- macOS: `~/Library/Application Support/MonitorWatch/config.json`
- This file is never synced to git

### Public Disclosure Policy

Once a vulnerability is fixed:

1. Users are notified to update
2. Security advisory is published on GitHub
3. CVE is requested for high/critical severity
4. Release notes credit the reporter (with permission)

### Legal

We follow responsible disclosure practices and will not take legal action against researchers who follow this policy.

### Acknowledgments

We want to thank all security researchers who help keep MonitorWatch safe:

- (Your name could be here!)

---

**Questions?** Contact us at security@monitorwatch.dev
