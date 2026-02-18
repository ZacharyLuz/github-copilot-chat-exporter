# GitHub Copilot Chat Exporter – Copilot Instructions

## Tech Stack & Architecture
- **Primary Language:** PowerShell 7+ (Windows API automation, scripting)
- **Secondary:** Python 3.6+ (for JSON→Markdown conversion)
- **Platform:** Windows (automation), cross-platform for some scripts
- **Key Dependency:** [peckjon/copilot-chat-to-markdown](https://github.com/peckjon/copilot-chat-to-markdown) (auto-downloaded Python script)

## Key Files & Directories
- `Save-CopilotChat.ps1` – Main automation script for exporting and converting chats
- `Save-CopilotChat-Standalone.ps1` – Standalone export (no profile changes)
- `profile-functions.ps1` – Functions to add to your PowerShell profile
- `chat_to_markdown.py` – Python converter (auto-downloaded)
- `sessions/` – Output folder for organized Markdown chat exports
- `Test-Installation.ps1` – Diagnostic and troubleshooting tool
- `Dev/` – Developer scripts, alternate READMEs, and test assets

## Installation & Setup
- **Automated:**  
  Run `.\Install-CopilotChatExporter.ps1` to set up profile and dependencies.
- **Manual:**  
  Source `profile-functions.ps1` in your PowerShell `$PROFILE` or run scripts directly.
- **Standalone:**  
  Use `.\Save-CopilotChat-Standalone.ps1` for no-profile, one-off exports.

## Usage
- **Export Current Chat:**  
  `Save-GitHubChat` or `Save-GitHubCopilotChat [-Topic "custom-topic"]`
- **Resume Previous Session:**  
  `Resume-Chat` (interactive menu)
- **Output:**  
  Markdown files saved to `sessions/YYYY-MM/YYYY-MM-DD_HHMMSS_topic.md`

## Build & Test
- **No build step required.**
- **Diagnostics:**  
  Run `.\Test-Installation.ps1` (add `-Fix` for auto-remediation)
- **Python Dependency:**  
  Ensure Python 3.6+ is installed and on PATH.

## Project Conventions
- **PowerShell Best Practices:**  
  - Use approved verbs (Get-, Set-, Save-, etc.)
  - Comment-based help for all exported functions
  - Use `Join-Path` for file paths
  - No hardcoded secrets; use environment variables for sensitive data
- **File/Folder Naming:**  
  - Sessions organized by month, filenames include timestamp and topic
  - All configuration in `$Config` at the top of `Save-CopilotChat.ps1`

## Troubleshooting
- Run `Test-Installation.ps1` for environment checks.
- Ensure VS Code is active for export automation.
- If Python or converter issues, see README and Dev/README.md for manual steps.

## References
- See `README.md`, `QUICKSTART.md`, and `Dev/README.md` for full documentation and advanced usage.