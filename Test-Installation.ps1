<#
.SYNOPSIS
    Diagnostic tool for GitHub Copilot Chat Exporter

.DESCRIPTION
    Runs comprehensive checks and fixes common issues automatically.
    Use this if you're having problems!

.EXAMPLE
    .\Test-Installation.ps1
    # Run diagnostics

.EXAMPLE
    .\Test-Installation.ps1 -Fix
    # Run diagnostics and fix issues automatically
#>

param(
    [switch]$Fix
)

$ErrorActionPreference = "Continue"

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     GitHub Copilot Chat Exporter - Diagnostics              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$issues = @()
$fixes = @()

# ============================================================================
# Test 1: PowerShell Version
# ============================================================================
Write-Host "🔍 Test 1: PowerShell Version" -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion

if ($psVersion.Major -ge 5) {
    Write-Host "✅ PASS - PowerShell $psVersion" -ForegroundColor Green
}
else {
    Write-Host "❌ FAIL - PowerShell $psVersion (need 5.0+)" -ForegroundColor Red
    $issues += "PowerShell version too old"
    Write-Host "   Fix: Download from https://aka.ms/powershell" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Test 2: Python Installation
# ============================================================================
Write-Host "🔍 Test 2: Python Installation" -ForegroundColor Yellow

try {
    $pythonVersion = python --version 2>&1
    Write-Host "✅ PASS - $pythonVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ FAIL - Python not found in PATH" -ForegroundColor Red
    $issues += "Python not installed or not in PATH"
    Write-Host "   Fix: Install from https://www.python.org/downloads/" -ForegroundColor Yellow
    Write-Host "   IMPORTANT: Check 'Add Python to PATH' during installation" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Test 3: VS Code Installation
# ============================================================================
Write-Host "🔍 Test 3: VS Code" -ForegroundColor Yellow

$vscode = Get-Process -Name "Code", "Code - Insiders" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($vscode) {
    Write-Host "✅ PASS - VS Code is running (PID: $($vscode.Id))" -ForegroundColor Green
}
else {
    Write-Host "⚠️  WARN - VS Code not running" -ForegroundColor Yellow
    Write-Host "   Note: This is OK, just start VS Code when you want to export" -ForegroundColor Gray
}
Write-Host ""

# ============================================================================
# Test 4: Required Files Present
# ============================================================================
Write-Host "🔍 Test 4: Required Files" -ForegroundColor Yellow

$scriptDir = $PSScriptRoot
$requiredFiles = @(
    "Save-CopilotChat.ps1",
    "profile-functions.ps1",
    "Install-CopilotChatExporter.ps1"
)

$allFilesPresent = $true
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $scriptDir $file
    if (Test-Path $filePath) {
        Write-Host "  ✅ $file" -ForegroundColor Green
    }
    else {
        Write-Host "  ❌ $file - MISSING" -ForegroundColor Red
        $allFilesPresent = $false
        $issues += "Missing file: $file"
    }
}

if ($allFilesPresent) {
    Write-Host "✅ PASS - All required files present" -ForegroundColor Green
}
else {
    Write-Host "❌ FAIL - Missing required files" -ForegroundColor Red
    Write-Host "   Fix: Re-clone the repository or download missing files" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Test 5: File Encoding (UTF-8)
# ============================================================================
Write-Host "🔍 Test 5: File Encoding" -ForegroundColor Yellow

$encodingIssues = $false
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $scriptDir $file
    if (Test-Path $filePath) {
        try {
            # Try to read and parse the file
            $content = Get-Content -Path $filePath -Raw -ErrorAction Stop

            # Check for common encoding issues
            if ($content -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
                Write-Host "  ⚠️  $file - Possible encoding issue" -ForegroundColor Yellow
                $encodingIssues = $true

                if ($Fix) {
                    # Fix encoding
                    [System.IO.File]::WriteAllText($filePath, $content, [System.Text.UTF8Encoding]::new($true))
                    Write-Host "     🔧 Fixed - Re-saved with UTF-8 BOM" -ForegroundColor Green
                    $fixes += "Fixed encoding for $file"
                }
            }
            else {
                Write-Host "  ✅ $file - OK" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  ❌ $file - Cannot read/parse: $_" -ForegroundColor Red
            $encodingIssues = $true
            $issues += "Encoding issue in $file"
        }
    }
}

if (-not $encodingIssues) {
    Write-Host "✅ PASS - All files readable" -ForegroundColor Green
}
elseif ($Fix) {
    Write-Host "✅ FIXED - Applied encoding fixes" -ForegroundColor Green
}
else {
    Write-Host "❌ FAIL - Encoding issues detected" -ForegroundColor Red
    Write-Host "   Fix: Run with -Fix flag: .\Test-Installation.ps1 -Fix" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Test 6: PowerShell Profile
# ============================================================================
Write-Host "🔍 Test 6: PowerShell Profile Configuration" -ForegroundColor Yellow

$profilePath = $PROFILE

if (Test-Path $profilePath) {
    Write-Host "✅ Profile exists: $profilePath" -ForegroundColor Green

    try {
        $profileContent = Get-Content $profilePath -Raw -ErrorAction Stop

        # Check if our tool is configured
        if ($profileContent -match "GitHub Copilot Chat Exporter") {
            Write-Host "✅ Tool is configured in profile" -ForegroundColor Green

            # Check if path is correct
            if ($profileContent -match [regex]::Escape($scriptDir)) {
                Write-Host "✅ Path is configured correctly" -ForegroundColor Green
            }
            else {
                Write-Host "⚠️  Path might be outdated in profile" -ForegroundColor Yellow
                $issues += "Profile path configuration might be incorrect"
                Write-Host "   Fix: Run installer: .\Install-CopilotChatExporter.ps1 -Force" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "⚠️  Tool not configured in profile" -ForegroundColor Yellow
            $issues += "Tool not added to PowerShell profile"
            Write-Host "   Fix: Run installer: .\Install-CopilotChatExporter.ps1" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "❌ Cannot read profile: $_" -ForegroundColor Red
        $issues += "Profile exists but cannot be read"
    }
}
else {
    Write-Host "⚠️  No PowerShell profile found" -ForegroundColor Yellow
    $issues += "PowerShell profile doesn't exist"
    Write-Host "   Fix: Run installer: .\Install-CopilotChatExporter.ps1" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Test 7: Functions Available
# ============================================================================
Write-Host "🔍 Test 7: Functions Loaded" -ForegroundColor Yellow

$expectedFunctions = @(
    "Save-GitHubCopilotChat",
    "Resume-GitHubCopilotChat"
)

$functionsLoaded = $true
foreach ($func in $expectedFunctions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "  ✅ $func" -ForegroundColor Green
    }
    else {
        Write-Host "  ❌ $func - Not found" -ForegroundColor Red
        $functionsLoaded = $false
    }
}

if ($functionsLoaded) {
    Write-Host "✅ PASS - All functions loaded" -ForegroundColor Green
}
else {
    Write-Host "❌ FAIL - Functions not loaded" -ForegroundColor Red
    $issues += "Functions not loaded in current session"
    Write-Host "   Fix: Reload profile: . `$PROFILE" -ForegroundColor Yellow
    Write-Host "   Or use standalone: .\Save-CopilotChat-Standalone.ps1" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Test 7b: Check for Placeholder Paths (Common Installation Bug)
# ============================================================================
Write-Host "🔍 Test 7b: Checking for Placeholder Paths" -ForegroundColor Yellow

$profileFunctionsPath = Join-Path $scriptDir "profile-functions.ps1"
if (Test-Path $profileFunctionsPath) {
    $pfContent = Get-Content $profileFunctionsPath -Raw

    # Use specific pattern to match only the literal placeholder path from the docs
    # Assumption: Real installations will not literally use "$env:USERPROFILE\path\to\copilot-chat-exporter"
    # as a directory name - this is a documentation placeholder only
    if ($pfContent -match '\$env:USERPROFILE[/\\]path[/\\]to[/\\](github-)?copilot-chat-exporter') {
        Write-Host "❌ FAIL - Placeholder paths not replaced!" -ForegroundColor Red
        $issues += "Placeholder paths still in profile-functions.ps1"
        Write-Host "   This is the most common installation issue." -ForegroundColor Yellow
        Write-Host "   The installer failed to update paths correctly." -ForegroundColor Yellow
        Write-Host ""

        if ($Fix) {
            Write-Host "🔧 Fixing placeholder paths..." -ForegroundColor Cyan

            # Replace known placeholder path variations
            $pfContent = $pfContent -replace '\$env:USERPROFILE\\path\\to\\github-copilot-chat-exporter', $scriptDir
            $pfContent = $pfContent -replace '\$env:USERPROFILE\\path\\to\\copilot-chat-exporter', $scriptDir

            [System.IO.File]::WriteAllText($profileFunctionsPath, $pfContent, [System.Text.UTF8Encoding]::new($true))

            Write-Host "✅ FIXED - Paths updated to: $scriptDir" -ForegroundColor Green
            $fixes += "Updated placeholder paths in profile-functions.ps1"
        }
        else {
            Write-Host "   Fix: Run with -Fix flag: .\Test-Installation.ps1 -Fix" -ForegroundColor Yellow
            Write-Host "   Or re-run installer: .\Install-CopilotChatExporter.ps1 -Force" -ForegroundColor Yellow
        }
    }
    else {
        # Count how many times the script directory appears
        $pathCount = ([regex]::Matches($pfContent, [regex]::Escape($scriptDir))).Count
        Write-Host "✅ PASS - Paths configured correctly ($pathCount references)" -ForegroundColor Green
    }
}
else {
    Write-Host "❌ FAIL - profile-functions.ps1 not found" -ForegroundColor Red
    $issues += "profile-functions.ps1 missing"
}
Write-Host ""

# ============================================================================
# Test 8: Sessions Directory
# ============================================================================
Write-Host "🔍 Test 8: Sessions Directory" -ForegroundColor Yellow

$sessionsDir = Join-Path $scriptDir "sessions"
if (Test-Path $sessionsDir) {
    $sessionCount = (Get-ChildItem -Path $sessionsDir -Filter "*.md" -File -Recurse).Count
    Write-Host "✅ PASS - Sessions directory exists ($sessionCount chats saved)" -ForegroundColor Green
}
else {
    Write-Host "⚠️  Sessions directory doesn't exist (will be created on first use)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Test 9: Python Converter
# ============================================================================
Write-Host "🔍 Test 9: Python Converter Script" -ForegroundColor Yellow

$converterPath = Join-Path $scriptDir "chat_to_markdown.py"
if (Test-Path $converterPath) {
    Write-Host "✅ PASS - Converter script present" -ForegroundColor Green
}
else {
    Write-Host "⚠️  Converter not downloaded (will download on first use)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# Summary
# ============================================================================
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                     DIAGNOSTIC SUMMARY                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($issues.Count -eq 0) {
    Write-Host "✅ ALL TESTS PASSED!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your installation is working correctly! 🎉" -ForegroundColor Green
    Write-Host ""
    Write-Host "Try it now:" -ForegroundColor Cyan
    Write-Host "  Save-GitHubCopilotChat" -ForegroundColor White
}
else {
    Write-Host "⚠️  Found $($issues.Count) issue(s):" -ForegroundColor Yellow
    Write-Host ""

    foreach ($issue in $issues) {
        Write-Host "  • $issue" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "📝 Recommended Actions:" -ForegroundColor Cyan
    Write-Host ""

    if ($issues -match "Python") {
        Write-Host "1. Install Python:" -ForegroundColor Yellow
        Write-Host "   https://www.python.org/downloads/" -ForegroundColor Gray
        Write-Host "   ⚠️  Check 'Add Python to PATH' during installation" -ForegroundColor Gray
        Write-Host ""
    }

    if ($issues -match "profile|path|configured") {
        Write-Host "2. Run the installer:" -ForegroundColor Yellow
        Write-Host "   .\Install-CopilotChatExporter.ps1 -Force" -ForegroundColor Gray
        Write-Host ""
    }

    if ($issues -match "encoding") {
        Write-Host "3. Fix encoding issues:" -ForegroundColor Yellow
        Write-Host "   .\Test-Installation.ps1 -Fix" -ForegroundColor Gray
        Write-Host ""
    }

    if ($issues -match "Functions not loaded") {
        Write-Host "4. Reload your profile:" -ForegroundColor Yellow
        Write-Host "   . `$PROFILE" -ForegroundColor Gray
        Write-Host ""
        Write-Host "   OR use standalone mode (no installation needed):" -ForegroundColor Yellow
        Write-Host "   .\Save-CopilotChat-Standalone.ps1" -ForegroundColor Gray
        Write-Host ""
    }
}

if ($fixes.Count -gt 0) {
    Write-Host "🔧 Applied Fixes:" -ForegroundColor Green
    foreach ($fix in $fixes) {
        Write-Host "  • $fix" -ForegroundColor Green
    }
    Write-Host ""
}

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($issues.Count -gt 0) {
    exit 1
}
else {
    exit 0
}
