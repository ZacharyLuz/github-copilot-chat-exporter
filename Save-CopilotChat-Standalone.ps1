<#
.SYNOPSIS
    Standalone GitHub Copilot chat exporter (no profile installation required)

.DESCRIPTION
    Complete portable version that works without any profile configuration.
    Just run this script directly from anywhere!

    Perfect for:
    - First-time users
    - Testing before installing
    - Shared/temporary machines
    - Users who don't want to modify their profile

.PARAMETER Topic
    Optional custom topic name for the saved chat

.PARAMETER OutputPath
    Optional custom output directory (defaults to .\sessions)

.EXAMPLE
    .\Save-CopilotChat-Standalone.ps1
    # Interactive mode with auto-topic generation

.EXAMPLE
    .\Save-CopilotChat-Standalone.ps1 -Topic "azure-deployment"
    # Specify custom topic

.EXAMPLE
    .\Save-CopilotChat-Standalone.ps1 -OutputPath "C:\MyChatBackups"
    # Save to custom location

.NOTES
    Version: 2.0 - Standalone
    Requires: Python 3.6+, VS Code with GitHub Copilot
    Author: Zachary Luz
    URL: https://github.com/ZacharyLuz/github-copilot-chat-exporter
#>

param(
    [string]$Topic = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================
$Config = @{
    DateFormat           = "yyyy-MM-dd"
    YearMonthFormat      = "yyyy-MM"
    TimestampFormat      = "HHmmss"
    TopicMaxLength       = 50
    JsonFilePrefix       = "CHAT-EXPORT"
    # Converter settings (pinned to specific commit for supply chain security)
    # Source: https://github.com/peckjon/copilot-chat-to-markdown
    ConverterFileName    = "chat_to_markdown.py"
    ConverterCommit      = "2af92df35aa0b06836e80ce1df55662f00b80dca"
    ConverterUrl         = "https://raw.githubusercontent.com/peckjon/copilot-chat-to-markdown/2af92df35aa0b06836e80ce1df55662f00b80dca/chat_to_markdown.py"
    FileWatchTimeout     = 300
    FileWatchInterval    = 2
    StatusUpdateInterval = 10
    KeyDelay_Initial     = 300
    KeyDelay_Command     = 200
    KeyDelay_Execute     = 1500
    KeyDelay_Paste       = 300
}

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-ColorHost {
    param($Message, $Color = "White", [switch]$NoNewline)
    if ($NoNewline) {
        Write-Host $Message -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Test-Prerequisite {
    Write-ColorHost "`n📋 Checking prerequisites..." "Yellow"

    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5) {
        Write-ColorHost "❌ PowerShell 5.0+ required (found $psVersion)" "Red"
        Write-ColorHost "   Download: https://aka.ms/powershell" "Yellow"
        return $false
    }
    Write-ColorHost "✓ PowerShell $psVersion" "Green"

    # Check Python
    try {
        $pythonVersion = python --version 2>&1
        Write-ColorHost "✓ Python: $pythonVersion" "Green"
    }
    catch {
        Write-ColorHost "❌ Python not found" "Red"
        Write-ColorHost "   Install from: https://www.python.org/downloads/" "Yellow"
        Write-ColorHost "   Make sure to add Python to PATH" "Yellow"
        return $false
    }

    # Check VS Code (warning only)
    $vscode = Get-Process -Name "Code" -ErrorAction SilentlyContinue
    if (-not $vscode) {
        Write-ColorHost "⚠ VS Code not running (start it for auto-export)" "Yellow"
    }
    else {
        Write-ColorHost "✓ VS Code is running" "Green"
    }

    Write-Host ""
    return $true
}

function Get-ConverterScript {
    param($ScriptDir)

    $converterPath = Join-Path $ScriptDir $Config.ConverterFileName

    if (-not (Test-Path $converterPath)) {
        Write-ColorHost "📥 Downloading converter script..." "Yellow"
        try {
            Invoke-WebRequest -Uri $Config.ConverterUrl -OutFile $converterPath
            Write-ColorHost "✓ Downloaded converter" "Green"
        }
        catch {
            Write-ColorHost "❌ Download failed: $_" "Red"
            return $null
        }
    }

    return $converterPath
}

function Start-VsCodeExport {
    [CmdletBinding(SupportsShouldProcess)]
    param($JsonFullPath)

    Write-ColorHost "🚀 Triggering export in VS Code..." "Yellow"
    Write-Host ""

    # Copy path to clipboard
    $JsonFullPath | Set-Clipboard
    Write-ColorHost "💡 Filename copied to clipboard: " "Yellow" -NoNewline
    Write-ColorHost (Split-Path $JsonFullPath -Leaf) "Cyan"
    Write-Host ""

    try {
        $vscode = Get-Process -Name "Code" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($vscode) {
            # Focus VS Code
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

            # Send keyboard commands
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.SendKeys]::SendWait("{F1}")
            Start-Sleep -Milliseconds $Config.KeyDelay_Initial
            [System.Windows.Forms.SendKeys]::SendWait("Chat: Export Chat")
            Start-Sleep -Milliseconds $Config.KeyDelay_Command
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            Start-Sleep -Milliseconds $Config.KeyDelay_Execute
            [System.Windows.Forms.SendKeys]::SendWait("^v")
            Start-Sleep -Milliseconds $Config.KeyDelay_Paste
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

            Write-ColorHost "✓ Export command sent!" "Green"
            Write-Host ""
            return $true
        }
        else {
            Write-ColorHost "⚠ VS Code not found - Manual steps:" "Yellow"
            Write-ColorHost "  1. Press F1 in VS Code" "Gray"
            Write-ColorHost "  2. Type: Chat: Export Chat" "Gray"
            Write-ColorHost "  3. Press Enter" "Gray"
            Write-ColorHost "  4. Paste filename (Ctrl+V)" "Gray"
            Write-ColorHost "  5. Save" "Gray"
            Write-Host ""
            return $false
        }
    }
    catch {
        Write-ColorHost "⚠ Auto-trigger failed - use manual steps above" "Yellow"
        return $false
    }
}

function Wait-ForExportFile {
    param($JsonFullPath, $Timeout)

    Write-ColorHost "⏳ Waiting for export file..." "Yellow"
    Write-ColorHost "(Expected: $(Split-Path $JsonFullPath -Leaf))" "Gray"
    Write-Host ""

    $elapsed = 0
    while (-not (Test-Path $JsonFullPath) -and $elapsed -lt $Timeout) {
        Start-Sleep -Seconds $Config.FileWatchInterval
        $elapsed += $Config.FileWatchInterval

        if ($elapsed % $Config.StatusUpdateInterval -eq 0) {
            Write-Host "." -NoNewline -ForegroundColor Gray
        }
    }

    Write-Host ""

    if (Test-Path $JsonFullPath) {
        Write-ColorHost "✓ Export file detected!" "Green"
        Write-Host ""
        return $true
    }
    else {
        Write-ColorHost "❌ Timeout waiting for file" "Red"
        Write-ColorHost "   Expected: $JsonFullPath" "Yellow"
        return $false
    }
}

function Get-TopicFromChat {
    param($JsonPath)

    try {
        $chatData = Get-Content $JsonPath -Raw | ConvertFrom-Json
        $firstMessage = ""

        if ($chatData.requests -and $chatData.requests.Count -gt 0) {
            $messageObj = $chatData.requests[0].message

            # Try different message structures
            if ($messageObj.text -and $messageObj.text -is [string]) {
                $firstMessage = $messageObj.text
            }
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
            elseif ($messageObj.value) {
                $firstMessage = $messageObj.value
            }
        }

        if ([string]::IsNullOrWhiteSpace($firstMessage)) {
            return "chat-session"
        }

        # Clean for filename
        $topic = $firstMessage -replace '[\\\/:*?"<>|]', '' -replace '\s+', '-' -replace '[^\w-]', ''
        $topic = $topic.ToLower().Trim('-')

        if ($topic.Length -gt $Config.TopicMaxLength) {
            $topic = $topic.Substring(0, $Config.TopicMaxLength).TrimEnd('-')
        }

        return $topic
    }
    catch {
        return "chat-$(Get-Date -Format 'HHmmss')"
    }
}

function Convert-ChatToMarkdown {
    param($JsonPath, $OutputPath, $ConverterScript)

    Write-ColorHost "🔄 Converting to markdown..." "Cyan"

    try {
        python $ConverterScript $JsonPath $OutputPath

        if (Test-Path $OutputPath) {
            $fileSize = [math]::Round((Get-Item $OutputPath).Length / 1KB, 2)
            Write-Host ""
            Write-ColorHost "✅ Success!" "Green"
            Write-Host ""
            Write-ColorHost "📁 Location: " "Cyan" -NoNewline
            Write-Host $OutputPath
            Write-ColorHost "📏 Size: $fileSize KB" "Gray"
            Write-Host ""

            # Cleanup
            if (Test-Path $JsonPath) {
                Remove-Item -Path $JsonPath -Force -ErrorAction SilentlyContinue
            }

            return $true
        }
        else {
            Write-ColorHost "❌ Conversion failed" "Red"
            return $false
        }
    }
    catch {
        Write-ColorHost "❌ Error: $_" "Red"
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host ""
Write-ColorHost "╔══════════════════════════════════════════════════════════════╗" "Cyan"
Write-ColorHost "║     GitHub Copilot Chat Exporter (Standalone Mode)          ║" "Cyan"
Write-ColorHost "╚══════════════════════════════════════════════════════════════╝" "Cyan"

# Check prerequisites
if (-not (Test-Prerequisite)) {
    exit 1
}

# Setup paths
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $scriptDir "sessions"
}

$date = Get-Date -Format $Config.DateFormat
$yearMonth = Get-Date -Format $Config.YearMonthFormat
$timestamp = Get-Date -Format $Config.TimestampFormat

# Determine topic
$autoGenerateTopic = [string]::IsNullOrWhiteSpace($Topic)
if ($autoGenerateTopic) {
    Write-ColorHost "💡 Topic will be auto-generated from chat" "Yellow"
    $safeTopic = "temp"
}
else {
    $safeTopic = $Topic -replace '[\\\/:*?"<>|]', '-' -replace '\s+', '-' -replace '-+', '-'
    $safeTopic = $safeTopic.ToLower().Trim('-')
}

# Create output directory
$sessionsDir = Join-Path $OutputPath $yearMonth
if (-not (Test-Path $sessionsDir)) {
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null
    Write-ColorHost "✓ Created directory: sessions\$yearMonth\" "Green"
}
Write-Host ""

# Get converter script
$converterScript = Get-ConverterScript -ScriptDir $scriptDir
if (-not $converterScript) {
    exit 1
}
Write-Host ""

# Setup export file path
$jsonFilename = "$($Config.JsonFilePrefix)-${date}_${timestamp}.json"
$jsonFullPath = Join-Path $scriptDir $jsonFilename

# Trigger export in VS Code
$null = Start-VsCodeExport -JsonFullPath $jsonFullPath

# Wait for file
$fileReceived = Wait-ForExportFile -JsonFullPath $jsonFullPath -Timeout $Config.FileWatchTimeout
if (-not $fileReceived) {
    exit 1
}

# Auto-generate topic if needed
if ($autoGenerateTopic) {
    Write-ColorHost "🤖 Generating topic..." "Cyan"
    $generatedTopic = Get-TopicFromChat -JsonPath $jsonFullPath
    Write-ColorHost "✓ Topic: " "Green" -NoNewline
    Write-ColorHost $generatedTopic "Cyan"
    $safeTopic = $generatedTopic
    Write-Host ""
}

# Final filename with timestamp for uniqueness
$filename = "${date}_${timestamp}_${safeTopic}.md"
$outputPath = Join-Path $sessionsDir $filename

# Convert
$success = Convert-ChatToMarkdown -JsonPath $jsonFullPath -OutputPath $outputPath -ConverterScript $converterScript

if ($success) {
    # Cleanup old exports
    Get-ChildItem -Path $scriptDir -Filter "CHAT-EXPORT-*.json" -File | Remove-Item -Force -ErrorAction SilentlyContinue

    # Offer to open
    $open = Read-Host "Open in VS Code? (y/n)"
    if ($open -eq 'y') {
        code $outputPath
    }

    Write-Host ""
    Write-ColorHost "🎉 Done! Saved to: sessions\$yearMonth\" "Green"
    Write-Host ""
}
else {
    exit 1
}
