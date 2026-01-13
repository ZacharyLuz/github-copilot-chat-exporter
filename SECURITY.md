# Security Policy

## Supported Versions

Currently supported versions of GitHub Copilot Chat Exporter:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

We take the security of GitHub Copilot Chat Exporter seriously. If you discover a security vulnerability, please follow these steps:

### How to Report

1. **DO NOT** open a public GitHub issue for security vulnerabilities
2. Report via one of these methods:
   - **GitHub Security Advisories**: Use the [Security tab](https://github.com/ZacharyLuz/github-copilot-chat-exporter/security/advisories/new) (preferred)
   - **Direct Contact**: Open a private discussion or email the maintainer

### What to Include

Please include the following information in your report:

- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact
- Suggested fix (if you have one)
- Your contact information

### What to Expect

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days with assessment
- **Fix Timeline**: Varies by severity
  - Critical: 24-48 hours
  - High: 1 week
  - Medium: 2 weeks
  - Low: 30 days

### Disclosure Policy

- Please allow us reasonable time to fix the issue before public disclosure
- We will credit you in the security advisory (unless you prefer anonymity)
- We will notify users via GitHub Security Advisories and release notes

## Security Best Practices for Users

When using this tool:

1. **Review Exported Chats**: Check for sensitive information before sharing
2. **Protect Sessions Folder**: The `sessions/` folder may contain proprietary information
3. **Keep Updated**: Use the latest version for security fixes
4. **Review Code**: This is open source - audit the code before use in sensitive environments

## Known Security Considerations

- This tool accesses VS Code's GitHub Copilot chat history
- Exported files may contain:
  - Code snippets
  - Project-specific information
  - Conversation history
- Ensure you have permission to export and store this data per your organization's policies

## Dependencies

This project uses:
- **peckjon/copilot-chat-to-markdown**: Auto-downloaded from GitHub
  - Review: https://github.com/peckjon/copilot-chat-to-markdown
  - License: MIT

We monitor dependencies for security issues and update as needed.

## Security Updates

Security updates will be announced via:
- GitHub Security Advisories
- GitHub Releases
- CHANGELOG.md

---

**Thank you for helping keep GitHub Copilot Chat Exporter secure!** 🛡️
