<#
.SYNOPSIS
    Complete automated Copilot chat export and conversion

.DESCRIPTION
    Single unified script that handles the entire workflow:
    1. Prompts for topic (or accepts as parameter)
    2. Guides through VS Code chat export
    3. Auto-downloads Python converter if needed
    4. Converts JSON to beautiful markdown
    5. Saves in organized sessions/YYYY-MM/ structure
    6. Cleans up temporary files

.EXAMPLE
    .\dev\Save-CopilotChat.ps1
    # Interactive mode with prompts

.EXAMPLE
    .\dev\Save-CopilotChat.ps1 -Topic "azure deployment"
    # Direct execution with topic specified

.NOTES
    Requires: Python 3.6+
    Auto-downloads: https://github.com/peckjon/copilot-chat-to-markdown

    FUTURE IMPROVEMENT IDEAS:
    - Consider forking or creating custom version of chat_to_markdown.py
    - Potential enhancements:
      * Better error handling for file operations
      * Progress indicator for large chat exports
      * Improved topic extraction (skip system metadata)
      * Alternative output formats (HTML, PDF)
      * Configurable options (code syntax, theme, formatting)
    - Current tool works well but could be customized for specific needs
#>

param(
    [string]$Topic = ""
)

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION - All customizable settings in one place
# ============================================================================
$Config = @{
    # Output settings
    SessionsFolderName   = "sessions"
    DateFormat           = "yyyy-MM-dd"
    YearMonthFormat      = "yyyy-MM"
    TimestampFormat      = "HHmmss"
    TopicMaxLength       = 50

    # File naming
    JsonFilePrefix       = "CHAT-EXPORT"

    # Converter settings
    ConverterFileName    = "chat_to_markdown.py"
    ConverterUrl         = "https://raw.githubusercontent.com/peckjon/copilot-chat-to-markdown/main/chat_to_markdown.py"

    # Timeouts (seconds)
    FileWatchTimeout     = 300  # 5 minutes
    FileWatchInterval    = 2
    StatusUpdateInterval = 10

    # Keyboard automation delays (milliseconds)
    KeyDelay_Initial     = 300
    KeyDelay_Command     = 200
    KeyDelay_Execute     = 1500
    KeyDelay_Paste       = 300
    KeyDelay_Save        = 300
}

Write-Host "`n💬 Copilot Chat Export & Conversion" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# STEP 1: Get Topic (Optional - will auto-generate if not provided)
# ============================================================================
$autoGenerateTopic = $false

if ([string]::IsNullOrWhiteSpace($Topic)) {
    Write-Host "💡 No topic provided - will auto-generate from chat content" -ForegroundColor Yellow
    $autoGenerateTopic = $true
    $safeTopic = "temp"  # Temporary placeholder
}
else {
    # Sanitize topic for filename
    $safeTopic = $Topic -replace '[\\\/:*?"<>|]', '-' -replace '\s+', '-' -replace '-+', '-'
    $safeTopic = $safeTopic.ToLower().Trim('-')
}

# ============================================================================
# STEP 2: Setup Paths
# ============================================================================
$scriptDir = $PSScriptRoot
$date = Get-Date -Format $Config.DateFormat
$yearMonth = Get-Date -Format $Config.YearMonthFormat
$filename = "${date}_${safeTopic}.md"

$sessionsDir = Join-Path $scriptDir "$($Config.SessionsFolderName)\$yearMonth"
$converterScript = Join-Path $scriptDir $Config.ConverterFileName
$outputPath = Join-Path $sessionsDir $filename

# Create sessions directory
if (-not (Test-Path $sessionsDir)) {
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null
    Write-Host "✓ Created: sessions\$yearMonth\" -ForegroundColor Green
    Write-Host ""
}

# ============================================================================
# STEP 3: Check Python
# ============================================================================
try {
    $pythonVersion = python --version 2>&1
    Write-Host "✓ Python found: $pythonVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ Python not found. Install Python 3.6+ first." -ForegroundColor Red
    Write-Host "   Download from: https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 4: Download Converter (if needed)
# ============================================================================
if (-not (Test-Path $converterScript)) {
    Write-Host "📥 Downloading $($Config.ConverterFileName)..." -ForegroundColor Yellow

    try {
        Invoke-WebRequest -Uri $Config.ConverterUrl -OutFile $converterScript
        Write-Host "✓ Downloaded converter script" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to download converter: $_" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# ============================================================================
# STEP 5: Auto-trigger Export in VS Code
# ============================================================================
Write-Host "🚀 Auto-triggering export in VS Code..." -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Create FULL PATH with timestamp for uniqueness - paste complete path so VS Code saves exactly where we expect
$timestamp = Get-Date -Format $Config.TimestampFormat
$jsonFilename = "$($Config.JsonFilePrefix)-${date}_${timestamp}.json"
$jsonFullPath = Join-Path $scriptDir $jsonFilename
$jsonFullPath | Set-Clipboard

Write-Host "💡 Using filename: " -ForegroundColor Yellow -NoNewline
Write-Host $jsonFilename -ForegroundColor Cyan
Write-Host "   Location: $scriptDir" -ForegroundColor Gray
Write-Host ""

# Try to focus VS Code window and send keyboard commands
try {
    $vscode = Get-Process -Name "Code" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vscode) {
        # Focus VS Code window
        Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class WinAPI {
                [DllImport("user32.dll")]
                public static extern bool SetForegroundWindow(IntPtr hWnd);
            }
"@
        [WinAPI]::SetForegroundWindow($vscode.MainWindowHandle)
        Start-Sleep -Milliseconds 500

        # Send keyboard commands to open Command Palette and trigger export
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait("{F1}")  # Open Command Palette
        Start-Sleep -Milliseconds $Config.KeyDelay_Initial
        [System.Windows.Forms.SendKeys]::SendWait("Chat: Export Chat")  # Type command
        Start-Sleep -Milliseconds $Config.KeyDelay_Command
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")  # Execute command

        Write-Host "✓ Sent export command to VS Code!" -ForegroundColor Green

        # Wait for save dialog to open, then auto-paste filename and save
        Start-Sleep -Milliseconds $Config.KeyDelay_Execute
        [System.Windows.Forms.SendKeys]::SendWait("^v")  # Ctrl+V to paste
        Start-Sleep -Milliseconds $Config.KeyDelay_Paste
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")  # Save file

        Write-Host "✓ Auto-pasted filename and saved!" -ForegroundColor Green
        Write-Host ""
        Write-Host "🚀 Automation complete - waiting for file..." -ForegroundColor Cyan
        Write-Host ""
    }
    else {
        Write-Host "⚠ VS Code not found - please open manually:" -ForegroundColor Yellow
        Write-Host "  F1 → Chat: Export Chat" -ForegroundColor Gray
        Write-Host ""
    }
}
catch {
    Write-Host "⚠ Auto-trigger failed - please open manually:" -ForegroundColor Yellow
    Write-Host "  F1 → Chat: Export Chat" -ForegroundColor Gray
    Write-Host ""
}

# STEP 6: Wait for Export File at Expected Location
# ============================================================================
Write-Host "⏳ Watching for chat export file..." -ForegroundColor Yellow
Write-Host "(Expected: $jsonFullPath)" -ForegroundColor Gray
Write-Host ""

$timeout = $Config.FileWatchTimeout
$elapsed = 0

while (-not (Test-Path $jsonFullPath) -and $elapsed -lt $timeout) {
    Start-Sleep -Seconds $Config.FileWatchInterval
    $elapsed += $Config.FileWatchInterval

    if ($elapsed % $Config.StatusUpdateInterval -eq 0) {
        Write-Host "." -NoNewline -ForegroundColor Gray
    }
}

Write-Host ""

if (-not (Test-Path $jsonFullPath)) {
    Write-Host "❌ Timeout waiting for export file" -ForegroundColor Red
    Write-Host "   Expected: $jsonFullPath" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Export file detected: $(Split-Path $jsonFullPath -Leaf)" -ForegroundColor Green
Write-Host ""

# ============================================================================
# STEP 6.5: Auto-generate Topic from Chat Content (if needed)
# ============================================================================
if ($autoGenerateTopic) {
    Write-Host "🤖 Generating topic from chat content..." -ForegroundColor Cyan
    try {
        $chatData = Get-Content $jsonFullPath -Raw | ConvertFrom-Json

        # Get first user message - extract actual text from message structure
        $firstMessage = ""
        if ($chatData.requests -and $chatData.requests.Count -gt 0) {
            $messageObj = $chatData.requests[0].message

            # Try different message structures:
            # 1. Direct .text property (most common)
            if ($messageObj.text -and $messageObj.text -is [string]) {
                $firstMessage = $messageObj.text
            }
            # 2. Array of parts with .value
            elseif ($messageObj -is [Array] -and $messageObj.Count -gt 0) {
                foreach ($part in $messageObj) {
                    if ($part.value -and $part.value -is [string]) {
                        $firstMessage = $part.value
                        break
                    }
                    elseif ($part.text -and $part.text -is [string]) {
                        $firstMessage = $part.text
                        break
                    }
                }
            }
            # 3. Direct .value property
            elseif ($messageObj.value) {
                $firstMessage = $messageObj.value
            }
            # 4. Plain string
            if ([string]::IsNullOrWhiteSpace($firstMessage)) {
                $firstMessage = "chat-session"
            }

            # Clean and truncate for filename
            $generatedTopic = $firstMessage -replace '[\\\/:*?"<>|]', '' -replace '\s+', '-' -replace '[^\w-]', ''
            $generatedTopic = $generatedTopic.ToLower().Trim('-')

            # Limit to configured maximum length
            if ($generatedTopic.Length -gt $Config.TopicMaxLength) {
                $generatedTopic = $generatedTopic.Substring(0, $Config.TopicMaxLength).TrimEnd('-')
            }

            $safeTopic = $generatedTopic
            Write-Host "✓ Generated topic: " -ForegroundColor Green -NoNewline
            Write-Host $safeTopic -ForegroundColor Cyan
        }
    }
    catch {
        Write-Host "⚠ Could not parse chat - using timestamp" -ForegroundColor Yellow
        $safeTopic = "chat-$(Get-Date -Format 'HHmmss')"
    }

    # Update output path with new topic (include timestamp for uniqueness)
    $timestamp = Get-Date -Format "HHmmss"
    $filename = "${date}_${timestamp}_${safeTopic}.md"
    $outputPath = Join-Path $sessionsDir $filename
    Write-Host ""
}

# ============================================================================
# STEP 7: Convert JSON to Markdown
# ============================================================================
Write-Host "🔄 Converting to markdown..." -ForegroundColor Cyan

try {
    python $converterScript $jsonFullPath $outputPath

    if (Test-Path $outputPath) {
        $fileSize = [math]::Round((Get-Item $outputPath).Length / 1KB, 2)
        Write-Host ""
        Write-Host "✅ Chat exported successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "📁 Location: $outputPath" -ForegroundColor Cyan
        Write-Host "📏 Size: $fileSize KB" -ForegroundColor Gray
        Write-Host ""

        # Clean up ONLY the specific JSON file that was just converted (FILES ONLY, not folders)
        if (Test-Path $jsonFullPath) {
            Remove-Item -Path $jsonFullPath -Force -ErrorAction SilentlyContinue
            Write-Host "✓ Cleaned up temporary JSON file" -ForegroundColor Green
        }

        # Also clean up any other old chat export JSON files (FILES ONLY, not folders)
        Get-ChildItem -Path $scriptDir -Filter "CHAT-EXPORT-*.json" -File -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $scriptDir -Filter "chat.json" -File -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host "✓ Cleaned up old export files" -ForegroundColor Green
        Write-Host ""

        # Ask to open
        $open = Read-Host "Open file in VS Code? (y/n)"
        if ($open -eq 'y') {
            code $outputPath
        }

        Write-Host ""
        Write-Host "🎉 Done! Chat saved to sessions\$yearMonth\" -ForegroundColor Green

    }
    else {
        Write-Host "❌ Conversion failed - output file not created" -ForegroundColor Red
        exit 1
    }

}
catch {
    Write-Host "❌ Conversion error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Verify JSON is valid: python -c `"import json; json.load(open('$tempJson'))`"" -ForegroundColor Gray
    Write-Host "2. Check Python version: python --version (need 3.6+)" -ForegroundColor Gray
    Write-Host "3. Try manually: python $converterScript $tempJson $outputPath" -ForegroundColor Gray
    exit 1
}
