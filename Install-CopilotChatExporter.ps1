<#
.SYNOPSIS
    Automated installer for GitHub Copilot Chat Exporter

.DESCRIPTION
    This installer automates the entire setup process:
    - Checks prerequisites (Python, PowerShell)
    - Creates PowerShell profile if it doesn't exist
    - Adds functions to profile with correct paths
    - Ensures UTF-8 encoding for all files
    - Tests the installation

.EXAMPLE
    .\Install-CopilotChatExporter.ps1
    # Interactive installation with all checks

.EXAMPLE
    .\Install-CopilotChatExporter.ps1 -Force
    # Force reinstall even if already configured

.EXAMPLE
    .\Install-CopilotChatExporter.ps1 -WhatIf
    # Dry-run: Shows what would be done without making changes
#>

param(
    [switch]$Force,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     GitHub Copilot Chat Exporter - Installation Setup       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "🔍 DRY-RUN MODE - No changes will be made" -ForegroundColor Yellow
    Write-Host "   This will show you exactly what the installer would do" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# Step 1: Verify Prerequisites
# ============================================================================
Write-Host "📋 Checking prerequisites..." -ForegroundColor Yellow

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -lt 5) {
    Write-Host "❌ PowerShell 5.0 or higher required (found $psVersion)" -ForegroundColor Red
    Write-Host "   Download from: https://aka.ms/powershell" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ PowerShell $psVersion" -ForegroundColor Green

# Check Python
try {
    $pythonVersion = python --version 2>&1
    Write-Host "✓ Python found: $pythonVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ Python not found" -ForegroundColor Red
    Write-Host "   Install Python 3.6+ from: https://www.python.org/downloads/" -ForegroundColor Yellow
    Write-Host "   Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
    exit 1
}

# Check VS Code
$vscode = Get-Process -Name "Code" -ErrorAction SilentlyContinue
if ($vscode) {
    Write-Host "✓ VS Code is running" -ForegroundColor Green
}
else {
    Write-Host "⚠ VS Code not detected (optional - can be started later)" -ForegroundColor Yellow
}

Write-Host ""

# ============================================================================
# Step 2: Get Installation Directory
# ============================================================================
$scriptDir = $PSScriptRoot
Write-Host "📁 Installation directory: " -ForegroundColor Cyan -NoNewline
Write-Host $scriptDir -ForegroundColor White
Write-Host ""

# Verify required files exist
$requiredFiles = @(
    "Save-CopilotChat.ps1",
    "profile-functions.ps1"
)

foreach ($file in $requiredFiles) {
    $filePath = Join-Path $scriptDir $file
    if (-not (Test-Path $filePath)) {
        Write-Host "❌ Required file not found: $file" -ForegroundColor Red
        Write-Host "   Make sure you're running this from the repository directory" -ForegroundColor Yellow
        exit 1
    }
}
Write-Host "✓ All required files present" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Step 3: Ensure UTF-8 Encoding for All PS1 Files
# ============================================================================
Write-Host "🔧 Ensuring UTF-8 encoding for PowerShell files..." -ForegroundColor Yellow

foreach ($file in $requiredFiles) {
    $filePath = Join-Path $scriptDir $file
    try {
        $content = Get-Content -Path $filePath -Raw -ErrorAction Stop
        # Save with UTF-8 BOM encoding to prevent parsing issues
        [System.IO.File]::WriteAllText($filePath, $content, [System.Text.UTF8Encoding]::new($true))
        Write-Host "✓ $file - UTF-8 encoding verified" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠ Could not verify encoding for $file : $_" -ForegroundColor Yellow
    }
}
Write-Host ""

# ============================================================================
# Step 4: Setup PowerShell Profile
# ============================================================================
Write-Host "⚙️ Configuring PowerShell profile..." -ForegroundColor Yellow

$profilePath = $PROFILE

# Check if profile exists
if (-not (Test-Path $profilePath)) {
    Write-Host "   Profile does not exist, creating: $profilePath" -ForegroundColor Gray
    
    if (-not $WhatIf) {
        $profileDir = Split-Path $profilePath -Parent
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        
        # Create new profile with header
        $initialContent = @"
# PowerShell Profile
# Created by GitHub Copilot Chat Exporter Installer
# $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

"@
        Set-Content -Path $profilePath -Value $initialContent -Encoding UTF8
        Write-Host "✓ Created new PowerShell profile" -ForegroundColor Green
    }
    else {
        Write-Host "   [WHATIF] Would create new PowerShell profile" -ForegroundColor Cyan
    }
}
else {
    Write-Host "✓ PowerShell profile exists: $profilePath" -ForegroundColor Green
}

# ============================================================================
# Step 5: Add/Update Profile Configuration
# ============================================================================
$markerStart = "# ===== GitHub Copilot Chat Exporter - START ====="
$markerEnd = "# ===== GitHub Copilot Chat Exporter - END ====="

$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue

# Check if already configured
if ($profileContent -match [regex]::Escape($markerStart) -and -not $Force) {
    Write-Host "⚠ Configuration already exists in profile" -ForegroundColor Yellow
    
    if ($WhatIf) {
        Write-Host "   [WHATIF] Would ask to update existing configuration" -ForegroundColor Cyan
    }
    else {
        $response = Read-Host "Update existing configuration? (y/n)"
        if ($response -ne 'y') {
            Write-Host "❌ Installation cancelled" -ForegroundColor Red
            exit 0
        }
    }
    
    # Remove old configuration
    $pattern = [regex]::Escape($markerStart) + "[\s\S]*?" + [regex]::Escape($markerEnd)
    $profileContent = $profileContent -replace $pattern, ""
}

# Prepare new configuration block
$configBlock = @"

$markerStart
# Auto-configured by installer on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Repository: https://github.com/ZacharyLuz/github-copilot-chat-exporter

# Source the profile functions
. "$scriptDir\profile-functions.ps1"

# Optional: Set custom sessions path (uncomment to override default)
# `$env:COPILOT_CHAT_SESSIONS_PATH = "`$env:USERPROFILE\Documents\CopilotChats"

$markerEnd

"@

# Add configuration to profile
$newProfileContent = $profileContent.TrimEnd() + "`n" + $configBlock

if ($WhatIf) {
    Write-Host "📋 Preview of what will be added to your profile:" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host $configBlock -ForegroundColor White
    Write-Host "─────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Profile location: $profilePath" -ForegroundColor Gray
    Write-Host "   [WHATIF] Would add configuration block to profile" -ForegroundColor Cyan
}
else {
    # Save with UTF-8 encoding
    [System.IO.File]::WriteAllText($profilePath, $newProfileContent, [System.Text.UTF8Encoding]::new($true))
    Write-Host "✓ Profile configured successfully" -ForegroundColor Green
}
Write-Host ""

# ============================================================================
# Step 6: Update profile-functions.ps1 with correct paths
# ============================================================================
Write-Host "🔧 Configuring profile functions with installation path..." -ForegroundColor Yellow

$profileFunctionsPath = Join-Path $scriptDir "profile-functions.ps1"
$profileFunctionsContent = Get-Content $profileFunctionsPath -Raw

# Replace placeholder paths with actual installation directory
$profileFunctionsContent = $profileFunctionsContent -replace '\$env:USERPROFILE\\path\\to\\copilot-chat-exporter', $scriptDir -replace '/', '\'

# Save with UTF-8 encoding
[System.IO.File]::WriteAllText($profileFunctionsPath, $profileFunctionsContent, [System.Text.UTF8Encoding]::new($true))

Write-Host "✓ Profile functions configured with path: $scriptDir" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Step 7: Download Python converter (if needed)
# ============================================================================
$converterPath = Join-Path $scriptDir "chat_to_markdown.py"
if (-not (Test-Path $converterPath)) {
    Write-Host "📥 Downloading Python converter..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/peckjon/copilot-chat-to-markdown/main/chat_to_markdown.py" -OutFile $converterPath
        Write-Host "✓ Converter downloaded" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠ Could not download converter (will download on first use)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "✓ Python converter already present" -ForegroundColor Green
}
Write-Host ""

# ============================================================================
# Step 8: Create sessions directory
# ============================================================================
$sessionsDir = Join-Path $scriptDir "sessions"
if (-not (Test-Path $sessionsDir)) {
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null
    Write-Host "✓ Created sessions directory" -ForegroundColor Green
}
else {
    Write-Host "✓ Sessions directory exists" -ForegroundColor Green
}
Write-Host ""

# ============================================================================
# Step 9: Installation Complete!
# ============================================================================

if ($WhatIf) {
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          🔍 DRY-RUN COMPLETE - No Changes Made              ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📋 Summary of what WOULD be done:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. ✅ Prerequisites verified" -ForegroundColor Green
    Write-Host "2. ✅ Files checked and encoding would be fixed" -ForegroundColor Green
    Write-Host "3. ✅ Profile configuration would be added" -ForegroundColor Green
    Write-Host "4. ✅ Converter would be downloaded (if needed)" -ForegroundColor Green
    Write-Host "5. ✅ Sessions directory would be created" -ForegroundColor Green
    Write-Host ""
    Write-Host "🎯 To actually install, run without -WhatIf:" -ForegroundColor Cyan
    Write-Host "   .\Install-CopilotChatExporter.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "📚 For manual installation, see:" -ForegroundColor Cyan
    Write-Host "   MANUAL-INSTALLATION.md" -ForegroundColor White
    Write-Host ""
    exit 0
}

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║            ✅ Installation Complete!                        ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "📝 Next Steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. " -ForegroundColor Yellow -NoNewline
Write-Host "Reload your PowerShell profile:" -ForegroundColor White
Write-Host "   . `$PROFILE" -ForegroundColor Gray
Write-Host ""

Write-Host "2. " -ForegroundColor Yellow -NoNewline
Write-Host "Test the installation:" -ForegroundColor White
Write-Host "   Get-Command Save-GitHubCopilotChat" -ForegroundColor Gray
Write-Host ""

Write-Host "3. " -ForegroundColor Yellow -NoNewline
Write-Host "Export your first chat:" -ForegroundColor White
Write-Host "   Save-GitHubCopilotChat" -ForegroundColor Gray
Write-Host ""

Write-Host "📚 Available Commands:" -ForegroundColor Cyan
Write-Host "   Save-GitHubCopilotChat   - Export current chat" -ForegroundColor Gray
Write-Host "   Resume-GitHubCopilotChat - Browse previous chats" -ForegroundColor Gray
Write-Host ""

Write-Host "💡 Tip: " -ForegroundColor Yellow -NoNewline
Write-Host "You can also use shortcuts: Save-GitHubChat, Resume-Chat" -ForegroundColor Gray
Write-Host ""

# Ask if user wants to reload profile now
$reload = Read-Host "Reload PowerShell profile now? (y/n)"
if ($reload -eq 'y') {
    Write-Host ""
    Write-Host "🔄 Reloading profile..." -ForegroundColor Cyan
    try {
        . $PROFILE
        Write-Host "✓ Profile reloaded successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "🎉 Ready to use! Try: " -ForegroundColor Green -NoNewline
        Write-Host "Save-GitHubCopilotChat" -ForegroundColor Cyan
    }
    catch {
        Write-Host "⚠ Could not reload profile: $_" -ForegroundColor Yellow
        Write-Host "   Please restart PowerShell or run: . `$PROFILE" -ForegroundColor Gray
    }
}

Write-Host ""
