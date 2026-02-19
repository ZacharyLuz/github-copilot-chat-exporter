# Installation Guide

> Get GitHub Copilot Chat Exporter up and running in under 5 minutes

## Prerequisites

Before you begin, make sure you have:

- ✅ **Windows OS**
- ✅ **PowerShell 7+** - [Download here](https://github.com/PowerShell/PowerShell/releases)
- ✅ **Python 3.6+** - [Download here](https://www.python.org/downloads/)
- ✅ **VS Code** with GitHub Copilot extension

### Quick Check

```powershell
# Check PowerShell version (should be 7.0+)
$PSVersionTable.PSVersion

# Check Python version (should be 3.6+)
python --version
```

---

## Step 1: Download the Project

### Option A: Clone with Git

```powershell
# Clone to your preferred location
cd "$env:USERPROFILE\Documents\Scripts"
git clone https://github.com/YOUR-USERNAME/copilot-chat-exporter.git
cd copilot-chat-exporter
```

### Option B: Download ZIP

1. Go to the [GitHub repository](https://github.com/YOUR-USERNAME/copilot-chat-exporter)
2. Click **Code** → **Download ZIP**
3. Extract to: `C:\Users\YourName\Documents\Scripts\copilot-chat-exporter`

---

## Step 2: Add Functions to Your PowerShell Profile

### Find Your Profile Location

```powershell
# Show your profile path
$PROFILE

# Typical location:
# C:\Users\YourName\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

### Open Your Profile for Editing

```powershell
# Create profile if it doesn't exist
if (!(Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force
}

# Open in VS Code
code $PROFILE

# Or use notepad
notepad $PROFILE
```

### Add This Code to Your Profile

Copy and paste this **at the end** of your `$PROFILE` file:

```powershell
# ============================================
# GitHub Copilot Chat Exporter Functions
# ============================================

function Save-GitHubCopilotChat {
    <#
    .SYNOPSIS
        Export and convert GitHub Copilot chat (VS Code) to organized markdown

    .DESCRIPTION
        Fully automated workflow to export GitHub Copilot chat sessions,
        convert to formatted markdown, and organize in dated folders.

        ⚠️ ONLY WORKS WITH GITHUB COPILOT CHAT IN VS CODE
        This does NOT work with M365 Copilot, Copilot Studio, or other variants.

    .PARAMETER Topic
        Optional custom topic name for the saved chat.
        If not provided, will auto-generate from first message content.

    .EXAMPLE
        Save-GitHubCopilotChat
        # Fully automated: exports, generates topic, converts, organizes

    .EXAMPLE
        Save-GitHubCopilotChat -Topic "azure-deployment"
        # Uses custom topic name instead of auto-generation

    .NOTES
        Output: sessions/YYYY-MM/YYYY-MM-DD_HHMMSS_topic.md
        Auto-cleanup: Removes temporary JSON files after conversion
    #>

    param(
        [Parameter(Mandatory = $false)]
        [string]$Topic
    )

    # ⚠️ UPDATE THIS PATH to match where you extracted the files
    & "$env:USERPROFILE\Documents\Scripts\copilot-chat-exporter\Save-CopilotChat.ps1" @PSBoundParameters
}

# Convenient aliases
Set-Alias -Name Save-GitHubChat -Value Save-GitHubCopilotChat
Set-Alias -Name Export-GitHubCopilotChat -Value Save-GitHubCopilotChat
Set-Alias -Name Save-GHCopilot -Value Save-GitHubCopilotChat

function Resume-GitHubCopilotChat {
    <#
    .SYNOPSIS
        Browse and resume previous GitHub Copilot chat sessions

    .DESCRIPTION
        Shows a list of your recent chat exports and opens the selected one.
        Perfect for picking up where you left off!

    .EXAMPLE
        Resume-GitHubCopilotChat
        # Shows last 10 sessions with interactive menu
    #>

    # ⚠️ UPDATE THIS PATH to match where you extracted the files
    $sessionsPath = "$env:USERPROFILE\Documents\Scripts\copilot-chat-exporter\sessions"

    if (-not (Test-Path $sessionsPath)) {
        Write-Host "❌ Sessions folder not found: $sessionsPath" -ForegroundColor Red
        Write-Host "   Export a chat first using: Save-GitHubChat" -ForegroundColor Gray
        return
    }

    $sessions = Get-ChildItem -Path $sessionsPath -Filter "*.md" -File -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10

    if ($sessions.Count -eq 0) {
        Write-Host "📭 No previous chat sessions found." -ForegroundColor Yellow
        Write-Host "   Export a chat first using: Save-GitHubChat" -ForegroundColor Gray
        return
    }

    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║        Resume Previous GitHub Copilot Chat Session          ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    for ($i = 0; $i -lt $sessions.Count; $i++) {
        $session = $sessions[$i]
        $num = $i + 1
        $date = $session.LastWriteTime.ToString("MM/dd HH:mm")
        $name = $session.BaseName -replace '^\d{4}-\d{2}-\d{2}_\d{6}_', ''

        Write-Host "  [$num] " -ForegroundColor Yellow -NoNewline
        Write-Host "$date  " -ForegroundColor Gray -NoNewline
        Write-Host $name -ForegroundColor White
    }

    Write-Host "`n  [0] Cancel" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Read-Host "Select a session (0-$($sessions.Count))"

    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) {
        Write-Host "❌ Cancelled" -ForegroundColor Yellow
        return
    }

    $index = [int]$choice - 1
    if ($index -ge 0 -and $index -lt $sessions.Count) {
        $selectedFile = $sessions[$index].FullName
        Write-Host "✓ Opening: " -ForegroundColor Green -NoNewline
        Write-Host $sessions[$index].Name -ForegroundColor Cyan
        code $selectedFile
    }
    else {
        Write-Host "❌ Invalid selection" -ForegroundColor Red
    }
}

# Convenient aliases
Set-Alias -Name Resume-Chat -Value Resume-GitHubCopilotChat
Set-Alias -Name Resume-Session -Value Resume-GitHubCopilotChat
```

### ⚠️ Important: Update the Paths

In the code you just pasted, find these two lines and update them to match where you saved the files:

```powershell
# Line ~42 - Update this path:
& "$env:USERPROFILE\Documents\Scripts\copilot-chat-exporter\Save-CopilotChat.ps1" @PSBoundParameters

# Line ~68 - Update this path:
$sessionsPath = "$env:USERPROFILE\Documents\Scripts\copilot-chat-exporter\sessions"
```

**Example paths:**
- If you saved to `D:\Tools\copilot-chat-exporter`, use:
  - `D:\Tools\copilot-chat-exporter\Save-CopilotChat.ps1`
  - `D:\Tools\copilot-chat-exporter\sessions`

---

## Step 3: Reload Your Profile

Close and reopen PowerShell, or reload your profile:

```powershell
# Reload profile in current session
. $PROFILE
```

---

## Step 4: Test It!

### Test the Save Function

1. Open **VS Code**
2. Have a conversation with **GitHub Copilot** (in the Chat view)
3. In VS Code's integrated terminal (PowerShell), type:

```powershell
Save-GitHubChat
```

**What happens:**
- VS Code automatically opens "Chat: Export Chat" dialog
- Filename is auto-pasted
- File is saved and converted to Markdown
- Opens in VS Code when complete

### Test the Resume Function

```powershell
Resume-Chat
```

You should see a menu like this:

```
╔══════════════════════════════════════════════════════════════╗
║        Resume Previous GitHub Copilot Chat Session          ║
╚══════════════════════════════════════════════════════════════╝

  [1] 01/13 14:30  terraform-state-fix
  [2] 01/12 19:28  infrastructure-setup

  [0] Cancel

Select a session (0-2): _
```

---

## Usage Examples

### Save with Auto-Generated Topic

```powershell
# Just run it - topic will be generated from your first message
Save-GitHubChat
```

### Save with Custom Topic

```powershell
# Specify a custom topic name
Save-GitHubChat -Topic "azure-deployment"

# Or use any alias
Save-GHCopilot -Topic "debugging-pipeline"
Export-GitHubCopilotChat -Topic "code-review"
```

### Browse Recent Sessions

```powershell
# Any of these work:
Resume-Chat
Resume-Session
Resume-GitHubCopilotChat
```

---

## File Structure

After your first export, you'll see:

```
copilot-chat-exporter/
├── Save-CopilotChat.ps1          # Main automation script
├── chat_to_markdown.py            # Auto-downloaded on first run
└── sessions/                      # Your saved chats
    └── 2026-01/
        ├── 2026-01-13_142156_debugging-pipeline.md
        ├── 2026-01-13_153042_azure-deployment.md
        └── ...
```

---

## Troubleshooting

### "Script not found" Error

**Problem:** `❌ Script not found: C:\Users\...\Save-CopilotChat.ps1`

**Solution:** Update the path in your `$PROFILE`:
```powershell
# Edit your profile
code $PROFILE

# Find the line with Save-CopilotChat.ps1 and fix the path
```

### Python Not Found

**Problem:** `❌ Python not found`

**Solution:**
```powershell
# Install Python
winget install Python.Python.3.12

# Verify
python --version
```

### Automation Doesn't Work

**Problem:** Export dialog doesn't auto-open

**Solution:**
- Make sure VS Code is the **active window**
- Try running manually: Press `F1` → "Chat: Export Chat"
- Check PowerShell version is 7+: `$PSVersionTable.PSVersion`

### Sessions Folder Not Found

**Problem:** `❌ Sessions folder not found`

**Solution:**
1. Run `Save-GitHubChat` at least once to create the folder
2. Or create it manually:
   ```powershell
   New-Item -ItemType Directory -Path "$env:USERPROFILE\Documents\Scripts\copilot-chat-exporter\sessions" -Force
   ```

---

## Next Steps

✅ **You're all set!** Try it out:

1. Have a conversation with GitHub Copilot in VS Code
2. Run `Save-GitHubChat` in the terminal
3. Watch the magic happen ✨

**Pro tips:**
- Use descriptive first messages for better auto-generated topics
- Run `Resume-Chat` when you return to VS Code to see your last session
- Sessions are organized by month automatically

---

## Need Help?

- 📝 [Full Documentation](README.md)
- 🐛 [Report an Issue](https://github.com/YOUR-USERNAME/copilot-chat-exporter/issues)
- 💬 [Discussions](https://github.com/YOUR-USERNAME/copilot-chat-exporter/discussions)

**Happy chatting!** 🚀
