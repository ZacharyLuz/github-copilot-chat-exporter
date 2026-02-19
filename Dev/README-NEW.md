# GitHub Copilot Chat Exporter 💬📝

**Automatically export and archive your GitHub Copilot chat sessions from VS Code into beautifully formatted Markdown files.**

Never lose your valuable AI conversations again! Perfect for:
- 📚 Building a knowledge base of solutions
- 🔍 Searching past conversations
- 📊 Tracking AI assistance over time
- 🤝 Sharing solutions with team members

---

## ✨ Features

- ✅ **Fully Automated** - One command exports, converts, and organizes
- 🤖 **Auto-Topic Generation** - Intelligently names files from chat content
- 📁 **Organized Storage** - Saves in `sessions/YYYY-MM/` structure
- 🧹 **Auto Cleanup** - Removes temporary files after conversion
- ⚡ **Fast & Easy** - No manual JSON handling
- 🎯 **VS Code Integration** - Works seamlessly with GitHub Copilot

---

## 🚀 Quick Start (3 Methods)

Choose your comfort level:

### Method 1: 🎯 One-Click Installation (Recommended for Most Users)

**Best for: New users, quick setup**

```powershell
git clone https://github.com/ZacharyLuz/github-copilot-chat-exporter.git
cd github-copilot-chat-exporter

# Preview what it will do (optional, doesn't change anything)
.\Install-CopilotChatExporter.ps1 -WhatIf

# Install
.\Install-CopilotChatExporter.ps1

# Reload profile
. $PROFILE
```

**What it does:**
- ✅ Only adds ONE line to your profile (dot-source)
- ✅ Uses clear markers so you can easily find/remove it
- ✅ Asks before modifying existing configuration
- ✅ Preserves all existing profile content
- ✅ Can be completely reversed

**See exactly what gets added:** Check [MANUAL-INSTALLATION.md](MANUAL-INSTALLATION.md)

---

### Method 2: 🏃 Standalone Mode (No Installation Required)

**Best for: Testing, shared machines, users who don't want profile changes**

```powershell
.\Save-CopilotChat-Standalone.ps1
```

**Advantages:**
- ✅ Zero profile modification
- ✅ Works immediately
- ✅ Portable - run from anywhere
- ✅ Perfect for trying before installing

---

### Method 3: 🔧 Manual Installation (Full Control)

**Best for: Advanced users, profile purists, maximum control**

Just add this line to your `$PROFILE`:

```powershell
. "C:\path\to\github-copilot-chat-exporter\profile-functions.ps1"
```

**That's it!** One line that loads the functions.

**Want more options?** See [MANUAL-INSTALLATION.md](MANUAL-INSTALLATION.md) for:
- Conditional loading
- Custom module setup
- Profile protection strategies
- Advanced customizations
- And more...

---

## 📋 Prerequisites

### Required:
- ✅ **PowerShell 5.0+** (pre-installed on Windows 10/11)
- ✅ **Python 3.6+** - [Download here](https://www.python.org/downloads/)
  - ⚠️ Make sure to check "Add Python to PATH" during installation
- ✅ **VS Code** with GitHub Copilot extension

### Verify Prerequisites:
```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Check Python
python --version

# Check VS Code (should show running process)
Get-Process -Name "Code" -ErrorAction SilentlyContinue
```

---

## 🎮 Usage

### Export Current Chat

```powershell
# Simple - auto-generates topic from chat
Save-GitHubCopilotChat

# With custom topic
Save-GitHubCopilotChat -Topic "azure-deployment-fix"
```

**What happens:**
1. 🔍 Checks prerequisites
2. 🚀 Auto-triggers export in VS Code
3. 💾 Saves JSON temporarily
4. 🤖 Generates topic from first message (or uses your custom topic)
5. 📝 Converts to beautiful Markdown
6. 📁 Saves to `sessions/YYYY-MM/YYYY-MM-DD_HHMMSS_topic.md`
7. 🧹 Cleans up temporary files
8. ✅ Done!

### Browse & Resume Previous Chats

```powershell
Resume-GitHubCopilotChat
```

Shows your last 10 chat sessions and lets you pick one to open in VS Code!

### Available Commands & Aliases

| Command                    | Aliases                             | Description           |
| -------------------------- | ----------------------------------- | --------------------- |
| `Save-GitHubCopilotChat`   | `Save-GitHubChat`, `Save-GHCopilot` | Export current chat   |
| `Resume-GitHubCopilotChat` | `Resume-Chat`, `Resume-Session`     | Browse previous chats |

---

## 📁 File Organization

Your chats are automatically organized:

```
github-copilot-chat-exporter/
├── sessions/
│   ├── 2026-01/
│   │   ├── 2026-01-23_143022_azure-deployment-fix.md
│   │   ├── 2026-01-23_151534_python-error-handling.md
│   │   └── 2026-01-24_091245_react-hooks-question.md
│   └── 2026-02/
│       └── 2026-02-01_103042_docker-compose-setup.md
├── Save-CopilotChat.ps1
├── Save-CopilotChat-Standalone.ps1
├── Install-CopilotChatExporter.ps1
├── profile-functions.ps1
├── chat_to_markdown.py (auto-downloaded)
└── README.md
```

---

## 🔧 Troubleshooting

### Issue: "Python not found"

**Solution:**
1. Install Python from [python.org](https://www.python.org/downloads/)
2. ⚠️ **Important:** Check "Add Python to PATH" during installation
3. Restart PowerShell
4. Test: `python --version`

### Issue: "Script not found" or "Path not configured"

**Solution:** Use the automated installer:
```powershell
.\Install-CopilotChatExporter.ps1
```

This automatically configures all paths correctly.

### Issue: PowerShell syntax errors with emoji or special characters

**Cause:** File encoding issues (common when copying code)

**Solution:** The installer automatically fixes this! Or manually:
```powershell
# Re-save files with proper encoding
$files = @("Save-CopilotChat.ps1", "profile-functions.ps1")
foreach ($file in $files) {
    $content = Get-Content $file -Raw
    [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($true))
}
```

### Issue: "VS Code export not working"

**Manual Steps:**
1. In VS Code, press `F1`
2. Type: `Chat: Export Chat`
3. Press `Enter`
4. Paste the filename (already in clipboard)
5. Save

### Issue: Profile not loading after installation

**Solution:**
```powershell
# Check if profile exists
Test-Path $PROFILE

# View profile location
$PROFILE

# Manually reload
. $PROFILE

# Test if functions loaded
Get-Command Save-GitHubCopilotChat
```

### Issue: "Already configured" during installation

**Solution:**
```powershell
# Force reinstall
.\Install-CopilotChatExporter.ps1 -Force
```

---

## 🎯 Common Scenarios

### Scenario 1: First Time User
```powershell
# Clone and install
git clone https://github.com/ZacharyLuz/github-copilot-chat-exporter.git
cd github-copilot-chat-exporter
.\Install-CopilotChatExporter.ps1

# Reload profile
. $PROFILE

# Export your first chat!
Save-GitHubCopilotChat
```

### Scenario 2: Quick Test (No Installation)
```powershell
# Just run standalone
.\Save-CopilotChat-Standalone.ps1
```

### Scenario 3: Updating After Git Pull
```powershell
# Pull latest changes
git pull

# Reinstall to update profile
.\Install-CopilotChatExporter.ps1 -Force

# Reload
. $PROFILE
```

---

## 🤝 Contributing

Contributions welcome! Feel free to:
- 🐛 Report bugs
- 💡 Suggest features
- 🔧 Submit pull requests

---

## 📝 License

MIT License - See [LICENSE](LICENSE) file for details

---

## 🙏 Credits

- **Chat to Markdown Converter:** [peckjon/copilot-chat-to-markdown](https://github.com/peckjon/copilot-chat-to-markdown)
- **Created by:** Zachary Luz

---

## 📧 Support

Having issues?
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review [Issues](https://github.com/ZacharyLuz/github-copilot-chat-exporter/issues) for similar problems
3. Open a new issue with:
   - PowerShell version (`$PSVersionTable.PSVersion`)
   - Python version (`python --version`)
   - Error messages
   - Steps to reproduce

---

## 🚀 Quick Links

- [Installation](#-quick-start-3-methods)
- [Usage Examples](#-usage)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

---

**⭐ If this tool helped you, consider starring the repository!**
