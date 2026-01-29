# Manual Installation Guide for Advanced Users

**For users who prefer full control over their PowerShell profile.**

This guide explains exactly what gets added to your profile and gives you multiple options for manual installation.

---

## 🎯 What Actually Gets Added to Your Profile

The installer adds **only one line** to your profile, wrapped in clearly marked comments:

```powershell
# ===== GitHub Copilot Chat Exporter - START =====
# Auto-configured by installer on 2026-01-23 14:30:00
# Repository: https://github.com/ZacharyLuz/github-copilot-chat-exporter

# Source the profile functions
. "C:\path\to\github-copilot-chat-exporter\profile-functions.ps1"

# Optional: Set custom sessions path (uncomment to override default)
# $env:COPILOT_CHAT_SESSIONS_PATH = "$env:USERPROFILE\Documents\CopilotChats"

# ===== GitHub Copilot Chat Exporter - END =====
```

That's it! Just a dot-source line that loads functions from `profile-functions.ps1`.

---

## 📋 Manual Installation Options

### Option 1: Copy-Paste (Simplest)

1. Open your PowerShell profile:
   ```powershell
   code $PROFILE
   ```

2. Add this at the bottom (update the path):
   ```powershell
   # GitHub Copilot Chat Exporter
   . "C:\Users\YourName\repos\github-copilot-chat-exporter\profile-functions.ps1"
   ```

3. Save and reload:
   ```powershell
   . $PROFILE
   ```

**That's it!** No other changes needed.

---

### Option 2: Conditional Loading (Safer)

If you want to make sure the script exists before loading:

```powershell
# GitHub Copilot Chat Exporter (with safety check)
$copilotExporterPath = "$env:USERPROFILE\repos\github-copilot-chat-exporter\profile-functions.ps1"
if (Test-Path $copilotExporterPath) {
    . $copilotExporterPath
}
else {
    Write-Host "⚠ Copilot Chat Exporter not found: $copilotExporterPath" -ForegroundColor Yellow
}
```

---

### Option 3: Custom Module (Most Organized)

Create a dedicated module in your PowerShell modules folder:

1. Create module directory:
   ```powershell
   $modulePath = "$HOME\Documents\PowerShell\Modules\CopilotChatExporter"
   New-Item -ItemType Directory -Path $modulePath -Force
   ```

2. Copy the profile functions:
   ```powershell
   Copy-Item ".\profile-functions.ps1" "$modulePath\CopilotChatExporter.psm1"
   ```

3. Create module manifest:
   ```powershell
   New-ModuleManifest -Path "$modulePath\CopilotChatExporter.psd1" `
       -RootModule "CopilotChatExporter.psm1" `
       -FunctionsToExport @('Save-GitHubCopilotChat', 'Resume-GitHubCopilotChat') `
       -AliasesToExport @('Save-GitHubChat', 'Resume-Chat')
   ```

4. Add to profile:
   ```powershell
   Import-Module CopilotChatExporter
   ```

**Advantage:** Cleaner profile, easier to manage and unload.

---

### Option 4: Custom Functions (Full Control)

Copy the functions directly into your profile for maximum control:

1. Open `profile-functions.ps1` and copy the function definitions
2. Paste them into your `$PROFILE`
3. Update the hardcoded paths to point to your installation directory
4. Modify functions as needed

**Advantage:** Everything in one file, easy to customize.

---

## 🔍 What the Installer Actually Does

For transparency, here's the complete installer workflow:

1. **Checks prerequisites** (PowerShell version, Python, VS Code)
2. **Verifies required files exist** (doesn't download anything new)
3. **Fixes UTF-8 encoding** on existing PS1 files (prevents parsing errors)
4. **Checks if profile exists**
   - If not, creates minimal profile with header
   - If yes, leaves it completely intact
5. **Checks if already configured**
   - If yes, asks permission before updating
   - If no, continues
6. **Adds configuration block**
   - Uses clear markers: `# ===== START =====` and `# ===== END =====`
   - Only adds dot-source line
   - Preserves all existing profile content
7. **Updates profile-functions.ps1** with correct installation path
8. **Offers to reload profile** (optional)

### Safety Features

- ✅ **Never overwrites** existing profile content
- ✅ **Always asks** before modifying existing configuration
- ✅ **Uses markers** so you can easily find and remove it
- ✅ **Preserves encoding** when modifying files
- ✅ **Creates backup** timestamp in comments
- ✅ **Can be run with `-Force`** to update if needed

---

## 🔬 Inspect Before Installing

Want to see exactly what will be added? Run this:

```powershell
# Preview what the installer will add (doesn't modify anything)
$scriptDir = Get-Location
$configBlock = @"

# ===== GitHub Copilot Chat Exporter - START =====
# Repository: https://github.com/ZacharyLuz/github-copilot-chat-exporter

. "$scriptDir\profile-functions.ps1"

# ===== GitHub Copilot Chat Exporter - END =====
"@

Write-Host "This will be added to your profile:" -ForegroundColor Cyan
Write-Host $configBlock -ForegroundColor Gray
```

---

## 🛡️ Profile Protection Strategies

### Strategy 1: Keep Profile in Git

```powershell
# In your profile directory
git init
git add $PROFILE
git commit -m "Backup profile before changes"

# Now install or modify
.\Install-CopilotChatExporter.ps1

# Review changes
git diff

# Rollback if needed
git checkout $PROFILE
```

### Strategy 2: Manual Backup

```powershell
# Backup profile
Copy-Item $PROFILE "$PROFILE.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# Now install or modify
.\Install-CopilotChatExporter.ps1

# Restore if needed
Copy-Item "$PROFILE.backup-*" $PROFILE
```

### Strategy 3: Use Separate Profile File

Instead of modifying your main profile:

1. Create a separate file:
   ```powershell
   $customProfile = "$HOME\.config\powershell\copilot-exporter.ps1"
   ". `"$customProfile`"" | Add-Content $PROFILE
   ```

2. Put all Copilot exporter config in the separate file
3. Your main profile stays clean with just one dot-source line

---

## 🗑️ Easy Removal

### Remove from Profile

Simply delete the section between the markers:

```powershell
# Open profile
code $PROFILE

# Delete everything between these lines:
# ===== GitHub Copilot Chat Exporter - START =====
# ... remove this entire section ...
# ===== GitHub Copilot Chat Exporter - END =====

# Save and reload
. $PROFILE
```

### Automated Removal

```powershell
# Remove configuration automatically
$profileContent = Get-Content $PROFILE -Raw
$markerStart = "# ===== GitHub Copilot Chat Exporter - START ====="
$markerEnd = "# ===== GitHub Copilot Chat Exporter - END ====="
$pattern = [regex]::Escape($markerStart) + "[\s\S]*?" + [regex]::Escape($markerEnd)
$newContent = $profileContent -replace $pattern, ""
Set-Content -Path $PROFILE -Value $newContent.TrimEnd()

# Reload
. $PROFILE
```

---

## 📊 Comparison: Installation Methods

| Method                  | Profile Modified    | Reversible          | Best For                  |
| ----------------------- | ------------------- | ------------------- | ------------------------- |
| **Automated Installer** | Yes (adds 1 line)   | Yes (clear markers) | Most users                |
| **Manual Copy-Paste**   | Yes (adds 1 line)   | Yes                 | Advanced users            |
| **Standalone Script**   | No                  | N/A                 | Testing, temporary use    |
| **Custom Module**       | Yes (1 import line) | Yes                 | Organization, portability |
| **Copy Functions**      | Yes (many lines)    | Harder              | Maximum customization     |

---

## 🎓 Advanced Customizations

### Custom Sessions Path

```powershell
# In your profile, before sourcing functions
$env:COPILOT_CHAT_SESSIONS_PATH = "D:\MyBackups\CopilotChats"
. "C:\path\to\profile-functions.ps1"
```

### Custom Aliases

```powershell
# After sourcing functions, add your own aliases
. "C:\path\to\profile-functions.ps1"

Set-Alias -Name scc -Value Save-GitHubCopilotChat
Set-Alias -Name rcc -Value Resume-GitHubCopilotChat
```

### Disable Auto-Reminder

The profile functions include an auto-reminder feature. To disable:

```powershell
# Before sourcing
$env:COPILOT_EXPORTER_DISABLE_REMINDER = $true
. "C:\path\to\profile-functions.ps1"
```

Or edit `profile-functions.ps1` and comment out the reminder section at the bottom.

### Custom Function Wrapper

```powershell
# Wrap the function with your own logic
. "C:\path\to\profile-functions.ps1"

function My-SaveChat {
    param([string]$Topic)

    # Your custom pre-processing
    Write-Host "🎯 Saving chat with custom logic..." -ForegroundColor Magenta

    # Call original function
    Save-GitHubCopilotChat -Topic $Topic

    # Your custom post-processing
    Write-Host "✅ Custom processing complete!" -ForegroundColor Green
}
```

---

## 🔧 Modifying profile-functions.ps1

The `profile-functions.ps1` file contains two main functions:

1. **Save-GitHubCopilotChat** - Main export function
2. **Resume-GitHubCopilotChat** - Browse previous chats

You can safely modify these functions:
- Change default paths
- Modify aliases
- Adjust behavior
- Add custom logic

The file is designed to be edited. Just maintain the function names for compatibility.

---

## 💡 Pro Tips

### Tip 1: Profile Modularization

```powershell
# In your main profile
$profileModules = @(
    "$HOME\.config\powershell\modules\git.ps1"
    "$HOME\.config\powershell\modules\azure.ps1"
    "$HOME\.config\powershell\modules\copilot-exporter.ps1"
)

foreach ($module in $profileModules) {
    if (Test-Path $module) { . $module }
}
```

### Tip 2: Lazy Loading

```powershell
# Only load when needed
function Save-GitHubCopilotChat {
    # Load on first use
    . "C:\path\to\profile-functions.ps1"

    # Call the real function (now loaded)
    Save-GitHubCopilotChat @args
}
```

### Tip 3: Profile Performance

```powershell
# Measure impact
Measure-Command { . "C:\path\to\profile-functions.ps1" }

# Usually < 50ms, negligible impact
```

---

## 📞 Questions?

- **Q: Can I use the installer and still customize?**
  A: Yes! Install first, then edit `profile-functions.ps1` or your profile.

- **Q: Will the installer overwrite my customizations?**
  A: Only if you run with `-Force`. It preserves existing configuration by default.

- **Q: Can I uninstall completely?**
  A: Yes, just remove the marked section from your profile. The tool leaves no traces.

- **Q: Is the standalone version slower?**
  A: No, it's the same code, just not loaded in your profile.

---

## 🎯 Recommendation by User Type

| User Type      | Recommended Method                              |
| -------------- | ----------------------------------------------- |
| **Cautious**   | Standalone script first, then manual copy-paste |
| **Advanced**   | Manual installation with conditional loading    |
| **Organized**  | Custom module approach                          |
| **Customizer** | Copy functions directly, modify as needed       |
| **Beginner**   | Automated installer (it's safe!)                |

---

**Remember:** All methods achieve the same result. Choose what makes you comfortable! 🚀
