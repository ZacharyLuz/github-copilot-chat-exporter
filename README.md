# GitHub Copilot Chat Exporter

[![Author](https://img.shields.io/badge/Author-Zachary%20Luz-blue.svg)](https://github.com/zacharyluz)
[![Version](https://img.shields.io/badge/Version-1.0.0-brightgreen.svg)](https://github.com/zacharyluz/github-copilot-chat-exporter/releases)

> **Automated export, conversion, and organization of GitHub Copilot chat sessions from VS Code**

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Python](https://img.shields.io/badge/Python-3.6%2B-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![VS Code](https://img.shields.io/badge/VS%20Code-1.85%2B-007ACC.svg)](https://code.visualstudio.com/)

Never lose context between coding sessions! This tool provides a fully automated workflow to save, organize, and resume your GitHub Copilot chat conversations.

## ✨ Features

- 🚀 **One-Command Export** - Single command triggers full automation
- 🤖 **Auto-Topic Generation** - Intelligently names sessions from chat content
- 📅 **Smart Organization** - Auto-sorts into dated folders (`sessions/YYYY-MM/`)
- 🔄 **JSON → Markdown** - Converts to human-readable format
- 🧹 **Auto-Cleanup** - Removes temporary files automatically
- 📚 **Session Browser** - Quickly find and resume previous conversations
- 💡 **Context Reminders** - See your last session when opening VS Code
- ⌨️ **Keyboard Automation** - Fully hands-free export process

## 📋 Requirements

- **Windows** (uses Windows API for automation)
- **PowerShell 7+** ([Install](https://github.com/PowerShell/PowerShell))
- **Python 3.6+** ([Install](https://www.python.org/downloads/))
- **VS Code** with GitHub Copilot extension

## 📦 Dependencies

This project leverages the following open source tool:

- **[peckjon/copilot-chat-to-markdown](https://github.com/peckjon/copilot-chat-to-markdown)** (MIT License)
  - Converts GitHub Copilot chat JSON exports to formatted Markdown
  - Automatically downloaded on first run
  - Credit to [@peckjon](https://github.com/peckjon) for the excellent converter

## 🚀 Quick Start

### 1. Clone or Download

```powershell
git clone https://github.com/zacharyluz/github-copilot-chat-exporter.git
cd github-copilot-chat-exporter
```

### 2. Add Functions to PowerShell Profile

Edit your PowerShell profile:

```powershell
notepad $PROFILE
```

Add the following:

```powershell
# Import Copilot Chat functions
. "$env:USERPROFILE\path\to\github-copilot-chat-exporter\profile-functions.ps1"
```

Or copy the functions directly from [`profile-functions.ps1`](profile-functions.ps1) into your profile.

### 3. Reload Profile

```powershell
. $PROFILE
```

### 4. Use It!

In VS Code's integrated terminal:

```powershell
# Export current chat session
Save-GitHubChat

# Or specify a custom topic
Save-GitHubChat -Topic "azure-deployment"

# Resume previous sessions
Resume-Chat
```

## 📖 Usage

### Saving a Chat Session

When you have an active GitHub Copilot chat in VS Code:

```powershell
Save-GitHubChat
```

**What happens:**
1. Automatically triggers VS Code's "Chat: Export Chat" command
2. Generates filename with date and topic
3. Waits for JSON export to complete
4. Converts JSON to formatted Markdown
5. Saves to `sessions/YYYY-MM/YYYY-MM-DD_HHMMSS_topic.md`
6. Cleans up temporary files
7. Optionally opens the result

### Resuming Previous Sessions

```powershell
Resume-Chat
```

**Shows an interactive menu:**
```
╔══════════════════════════════════════════════════════════════╗
║        Resume Previous GitHub Copilot Chat Session          ║
╚══════════════════════════════════════════════════════════════╝

  [1] 01/13 14:30  terraform-state-fix
  [2] 01/12 19:28  infrastructure-setup
  [3] 01/10 16:45  debugging-pipeline
  ...

  [0] Cancel

Select a session (0-10): _
```

### Available Commands

| Command                    | Aliases                                                             | Description                       |
| -------------------------- | ------------------------------------------------------------------- | --------------------------------- |
| `Save-GitHubCopilotChat`   | `Save-GitHubChat`<br>`Export-GitHubCopilotChat`<br>`Save-GHCopilot` | Export and save current chat      |
| `Resume-GitHubCopilotChat` | `Resume-Chat`<br>`Resume-Session`                                   | Browse and open previous sessions |

## 📁 Output Structure

```
github-copilot-chat-exporter/
├── Save-CopilotChat.ps1          # Main automation script
├── profile-functions.ps1          # Functions to add to $PROFILE
├── chat_to_markdown.py            # Converter (auto-downloaded)
└── sessions/
    ├── 2026-01/
    │   ├── 2026-01-12_193024_infrastructure-setup.md
    │   ├── 2026-01-13_142156_debugging-pipeline.md
    │   └── ...
    └── 2026-02/
        └── ...
```

## ⚙️ Configuration

Edit configuration in [`Save-CopilotChat.ps1`](Save-CopilotChat.ps1):

```powershell
$Config = @{
    SessionsFolderName   = "sessions"      # Output folder name
    DateFormat           = "yyyy-MM-dd"    # Date format for filenames
    TopicMaxLength       = 50              # Max topic length in filename
    FileWatchTimeout     = 300             # Seconds to wait for export
    # ... more options
}
```

## 🔧 How It Works

### The Save Process

1. **Keyboard Automation**: Uses Windows API to:
   - Focus VS Code window
   - Send `F1` to open Command Palette
   - Type "Chat: Export Chat"
   - Auto-paste pre-generated filename
   - Hit Enter to save

2. **File Monitoring**: Watches for the exported JSON file (up to 5 minutes)

3. **Topic Extraction**: If no topic specified:
   - Parses the JSON file
   - Extracts first user message
   - Sanitizes for filename use
   - Truncates to configured length

4. **Conversion**: Runs Python converter to transform JSON → Markdown

5. **Organization**: Saves to dated folder structure

6. **Cleanup**: Removes temporary JSON files

### The Resume Process

- Scans `sessions/` folder recursively
- Finds 10 most recent `.md` files
- Displays with cleaned topic names and timestamps
- Opens selection in VS Code

## 🤝 Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 🐛 Troubleshooting

### Export automation doesn't work
- Ensure VS Code is the active window
- Try manual export: `F1` → "Chat: Export Chat"
- Check PowerShell version: `$PSVersionTable.PSVersion`

### Python not found
```powershell
# Install Python
winget install Python.Python.3.12

# Verify installation
python --version
```

### Converter fails
The Python converter auto-downloads from [peckjon/copilot-chat-to-markdown](https://github.com/peckjon/copilot-chat-to-markdown). If download fails:
- Check internet connection
- Manually download `chat_to_markdown.py` to the script directory

### Sessions not showing in Resume-Chat
- Check `sessions/` folder exists
- Verify `.md` files are present
- Ensure filenames follow format: `YYYY-MM-DD_HHMMSS_topic.md`

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Credits

- **JSON to Markdown Converter**: [peckjon/copilot-chat-to-markdown](https://github.com/peckjon/copilot-chat-to-markdown)
  - This project would not be possible without peckjon's excellent conversion tool
  - See the [📦 Dependencies](#-dependencies) section for details
- **Inspiration**: The need to maintain context across ADHD-friendly coding sessions

## 🔗 Related

- [VS Code Copilot Chat Documentation](https://code.visualstudio.com/docs/copilot/chat/chat-sessions)
- [PowerShell Gallery](https://www.powershellgallery.com/)

---

**Made with ☕ and 🤖 by developers who forget what they were doing 5 minutes ago**

