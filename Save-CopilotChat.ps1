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
    Author: Zachary Luz
    Version: 1.0.0
    Release Date: January 2026

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
    SessionsBasePath     = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CopilotChatSessions'
    DateFormat           = "yyyy-MM-dd"
    YearMonthFormat      = "yyyy-MM"
    TimestampFormat      = "HHmmss"
    TopicMaxLength       = 50

    # File naming
    JsonFilePrefix       = "CHAT-EXPORT"

    # Converter settings (pinned to specific commit for supply chain security)
    # Source: https://github.com/peckjon/copilot-chat-to-markdown
    ConverterFileName    = "chat_to_markdown.py"
    ConverterCommit      = "2af92df35aa0b06836e80ce1df55662f00b80dca"
    ConverterUrl         = "https://raw.githubusercontent.com/peckjon/copilot-chat-to-markdown/2af92df35aa0b06836e80ce1df55662f00b80dca/chat_to_markdown.py"

    # Timeouts (seconds)
    FileWatchTimeout     = 300  # 5 minutes
    FileWatchInterval    = 2
    StatusUpdateInterval = 10

    # Keyboard automation delays (milliseconds)
    KeyDelay_Initial     = 500
    KeyDelay_Command     = 500
    KeyDelay_Execute     = 2000
    KeyDelay_Paste       = 500
    KeyDelay_Save        = 500

    # Logging
    LogLevel             = 'Debug'      # Error, Warning, Info, Debug
    LogRetentionDays     = 30
}

# ============================================================================
# LOGGING
# ============================================================================

function Write-ExporterLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ERROR', 'WARN', 'INFO', 'DEBUG')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $levelMap = @{ 'ERROR' = 0; 'WARN' = 1; 'INFO' = 2; 'DEBUG' = 3 }
    $configLevelKey = switch ($Config.LogLevel) {
        'Error'   { 'ERROR' }
        'Warning' { 'WARN' }
        'Info'    { 'INFO' }
        'Debug'   { 'DEBUG' }
        default   { 'INFO' }
    }

    if ($levelMap[$Level] -gt $levelMap[$configLevelKey]) { return }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $paddedLevel = $Level.PadRight(5)
    $logLine = "$timestamp [$paddedLevel] $Message"

    if ($ErrorRecord) {
        $logLine += "`n$timestamp [$paddedLevel] Stack: $($ErrorRecord.ScriptStackTrace)"
    }

    try {
        $logsDir = Join-Path $Config.SessionsBasePath 'logs'
        if (-not (Test-Path $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }
        $logFile = Join-Path $logsDir "copilot-exporter-$(Get-Date -Format 'yyyy-MM-dd').log"
        Add-Content -Path $logFile -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # Logging should never crash the app
    }
}

function Invoke-LogMaintenance {
    $logsDir = Join-Path $Config.SessionsBasePath 'logs'
    if (-not (Test-Path $logsDir)) { return }

    $cutoff = (Get-Date).AddDays(-$Config.LogRetentionDays)
    Get-ChildItem -Path $logsDir -Filter 'copilot-exporter-*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host "`n💬 Copilot Chat Export & Conversion" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-ExporterLog -Level INFO -Message "Export started. Topic='$Topic' SessionsBasePath='$($Config.SessionsBasePath)'"
Invoke-LogMaintenance

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

$sessionsDir = Join-Path $Config.SessionsBasePath $yearMonth
$converterScript = Join-Path $scriptDir $Config.ConverterFileName
$outputPath = Join-Path $sessionsDir $filename

# Create sessions directory
if (-not (Test-Path $sessionsDir)) {
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null
    Write-Host "✓ Created: $sessionsDir" -ForegroundColor Green
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
$jsonFullPath = Join-Path $env:TEMP $jsonFilename
$jsonFullPath | Set-Clipboard

Write-Host "💡 Using filename: " -ForegroundColor Yellow -NoNewline
Write-Host $jsonFilename -ForegroundColor Cyan
Write-Host "   Location: $env:TEMP" -ForegroundColor Gray
Write-Host ""

# Auto-trigger with robust error handling and retry logic
$autoTriggered = $false
$scriptStartTime = Get-Date

try {
    $vscode = Get-Process -Name "Code", "Code - Insiders" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1

    if (-not $vscode) {
        Write-ExporterLog -Level WARN -Message 'VS Code process not found for SendKeys automation'
        Write-Host "⚠ VS Code not found - please export manually:" -ForegroundColor Yellow
    }
    else {
        Write-ExporterLog -Level DEBUG -Message "Found VS Code: $($vscode.ProcessName) PID=$($vscode.Id) HWND=$($vscode.MainWindowHandle)"

        # Load WinAPI only if not already loaded (prevents Add-Type crash on re-runs)
        if (-not ([System.Management.Automation.PSTypeName]'WinAPI').Type) {
            Add-Type -TypeDefinition @"
                using System;
                using System.Runtime.InteropServices;
                public class WinAPI {
                    [DllImport("user32.dll")]
                    public static extern bool SetForegroundWindow(IntPtr hWnd);
                    [DllImport("user32.dll")]
                    public static extern IntPtr GetForegroundWindow();
                }
"@
            Write-ExporterLog -Level DEBUG -Message 'Loaded WinAPI type definition'
        }

        # Load System.Windows.Forms assembly
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

        # SendKeys with retry (attempt up to 2 times)
        $maxAttempts = 2
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Write-ExporterLog -Level DEBUG -Message "SendKeys attempt $attempt of $maxAttempts"

                # Focus VS Code window
                $focused = [WinAPI]::SetForegroundWindow($vscode.MainWindowHandle)
                Write-ExporterLog -Level DEBUG -Message "SetForegroundWindow returned: $focused"
                Start-Sleep -Milliseconds 500

                # Verify focus was acquired
                $foregroundHwnd = [WinAPI]::GetForegroundWindow()
                if ($foregroundHwnd -ne $vscode.MainWindowHandle) {
                    Write-ExporterLog -Level WARN -Message "Focus check: expected HWND $($vscode.MainWindowHandle), got $foregroundHwnd"
                }

                # Dismiss any existing dialogs first
                [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
                Start-Sleep -Milliseconds 200

                # Open Command Palette
                [System.Windows.Forms.SendKeys]::SendWait("{F1}")
                Start-Sleep -Milliseconds $Config.KeyDelay_Initial

                # Type export command
                [System.Windows.Forms.SendKeys]::SendWait("Chat: Export Chat")
                Start-Sleep -Milliseconds $Config.KeyDelay_Command

                # Execute command
                [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Write-Host "✓ Sent export command to VS Code" -ForegroundColor Green

                # Wait for save dialog
                Start-Sleep -Milliseconds $Config.KeyDelay_Execute

                # Paste filename and save
                [System.Windows.Forms.SendKeys]::SendWait("^v")
                Start-Sleep -Milliseconds $Config.KeyDelay_Paste
                [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

                Write-Host "✓ Auto-pasted filename and saved!" -ForegroundColor Green
                Write-Host ""
                $autoTriggered = $true
                Write-ExporterLog -Level INFO -Message "SendKeys automation succeeded on attempt $attempt"
                break
            }
            catch {
                Write-ExporterLog -Level WARN -Message "SendKeys attempt $attempt failed: $($_.Exception.Message)" -ErrorRecord $_
                if ($attempt -lt $maxAttempts) {
                    Write-Host "⚠ Retrying automation..." -ForegroundColor Yellow
                    Start-Sleep -Milliseconds 1000
                }
            }
        }
    }
}
catch {
    Write-ExporterLog -Level ERROR -Message "Auto-trigger error: $($_.Exception.Message)" -ErrorRecord $_
}

if (-not $autoTriggered) {
    Write-Host "⚠ Please export the chat manually:" -ForegroundColor Yellow
    Write-Host "  1. Press F1 in VS Code" -ForegroundColor Gray
    Write-Host "  2. Type 'Chat: Export Chat' and press Enter" -ForegroundColor Gray
    Write-Host "  3. Press Ctrl+V to paste the filename, then Enter to save" -ForegroundColor Gray
    Write-Host ""
}

# STEP 6: Wait for Export File at Expected Location
# ============================================================================
Write-Host "⏳ Watching for chat export file..." -ForegroundColor Yellow
Write-Host "(Expected: $jsonFullPath)" -ForegroundColor Gray
Write-Host ""

$timeout = $Config.FileWatchTimeout
$elapsed = 0

while ($elapsed -lt $timeout) {
    # Check for exact expected file
    if (Test-Path $jsonFullPath) {
        Write-ExporterLog -Level DEBUG -Message "Found exact export file: $jsonFullPath"
        break
    }

    # Also check for any newer CHAT-EXPORT files (user may have saved manually)
    $newExport = Get-ChildItem -Path $env:TEMP -Filter "$($Config.JsonFilePrefix)-*.json" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.CreationTime -gt $scriptStartTime } |
        Sort-Object CreationTime -Descending |
        Select-Object -First 1

    if ($newExport) {
        $jsonFullPath = $newExport.FullName
        Write-ExporterLog -Level INFO -Message "Found export file via pattern match: $jsonFullPath"
        break
    }

    Start-Sleep -Seconds $Config.FileWatchInterval
    $elapsed += $Config.FileWatchInterval

    if ($elapsed % $Config.StatusUpdateInterval -eq 0) {
        Write-Host "." -NoNewline -ForegroundColor Gray
    }
}

Write-Host ""

if (-not (Test-Path $jsonFullPath)) {
    Write-ExporterLog -Level ERROR -Message "Timeout after ${elapsed}s waiting for export file: $jsonFullPath"
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

        # Also clean up any other old chat export JSON files from temp (FILES ONLY, not folders)
        Get-ChildItem -Path $env:TEMP -Filter "CHAT-EXPORT-*.json" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host "✓ Cleaned up old export files" -ForegroundColor Green
        Write-Host ""

        # Ask to open
        $open = Read-Host "Open file in VS Code? (y/n)"
        if ($open -eq 'y') {
            code $outputPath
        }

        Write-Host ""
        Write-Host "🎉 Done! Chat saved to $sessionsDir" -ForegroundColor Green
        Write-ExporterLog -Level INFO -Message "Export completed: $outputPath ($fileSize KB)"

    }
    else {
        Write-ExporterLog -Level ERROR -Message 'Conversion failed - output file not created'
        Write-Host "❌ Conversion failed - output file not created" -ForegroundColor Red
        exit 1
    }

}
catch {
    Write-ExporterLog -Level ERROR -Message "Conversion error: $_" -ErrorRecord $_
    Write-Host "❌ Conversion error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Verify JSON is valid: python -c `"import json; json.load(open('$tempJson'))`"" -ForegroundColor Gray
    Write-Host "2. Check Python version: python --version (need 3.6+)" -ForegroundColor Gray
    Write-Host "3. Try manually: python $converterScript $tempJson $outputPath" -ForegroundColor Gray
    exit 1
}
