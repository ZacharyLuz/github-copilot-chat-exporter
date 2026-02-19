# PowerShell Profile Functions for GitHub Copilot Chat Exporter
# Author: Zachary Luz
# Version: 2.0.0
# Release Date: February 2026
#
# Add these functions to your PowerShell profile ($PROFILE)

# ============================================================================
# OPTION 1: Source the script (Recommended)
# ============================================================================
# Place this in your $PROFILE to load all functions:
# . "$env:USERPROFILE\path\to\github-copilot-chat-exporter\profile-functions.ps1"

# ============================================================================
# OPTION 2: Copy these functions directly into your $PROFILE
# ============================================================================

# Save GitHub Copilot Chat Session
function Save-GitHubCopilotChat {
    <#
    .SYNOPSIS
        Export GitHub Copilot chat sessions to organized markdown.

    .DESCRIPTION
        Unified exporter for both VS Code Copilot Chat and Copilot CLI terminal
        sessions. When called with no parameters, shows an interactive menu.

        Supports VS Code (v2 engine with direct file read) and Copilot CLI
        (events.jsonl parser with full tool call export).

    .PARAMETER CLI
        Export a Copilot CLI terminal session (from ~/.copilot/session-state/).

    .PARAMETER Topic
        Optional custom topic name for the saved chat.

    .PARAMETER List
        Browse and select from recent sessions (paginated).

    .PARAMETER Session
        Export a specific session by ID.

    .PARAMETER All
        Export all VS Code sessions.

    .EXAMPLE
        Save-GitHubCopilotChat
        # Interactive menu — pick CLI or VS Code

    .EXAMPLE
        save-chat -CLI
        # Export the most recent Copilot CLI session

    .EXAMPLE
        save-chat -CLI -List
        # Browse and pick from recent CLI sessions

    .EXAMPLE
        save-chat -List
        # Browse and pick from recent VS Code sessions

    .NOTES
        Output: ~/Documents/CopilotChatSessions/YYYY-MM/YYYY-MM-DD_topic.md
        Alias: save-chat
    #>

    [CmdletBinding()]
    param(
        [switch]$CLI,
        [Parameter(Mandatory = $false)]
        [string]$Topic,
        [switch]$List,
        [switch]$All,
        [string]$Session,
        [switch]$Catalog,
        [switch]$Update,
        [switch]$UseSendKeys,
        [switch]$NoWorkspaceLink,
        [switch]$SkipSecretScan,
        [switch]$Force,
        [switch]$Check,
        [switch]$Rollback,
        [string]$LogLevel,
        [switch]$NoLog
    )

    # Resolve script directory — works whether sourced or copied
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else {
        # Fallback: try common install locations
        $candidates = @(
            "$env:USERPROFILE\OneDrive - Microsoft\Documents\Scripts\dev\copilot-chat-exporter",
            "$env:USERPROFILE\github-copilot-chat-exporter",
            "$env:USERPROFILE\Documents\github-copilot-chat-exporter"
        )
        $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if (-not $scriptDir -or -not (Test-Path $scriptDir)) {
        Write-Host "❌ Copilot Chat Exporter not found." -ForegroundColor Red
        Write-Host "   Re-run the installer or update the path in your profile." -ForegroundColor Gray
        Write-Host "   See: https://github.com/ZacharyLuz/github-copilot-chat-exporter" -ForegroundColor DarkGray
        return
    }

    # If no flags provided, show an interactive menu
    $hasExplicitChoice = $CLI -or $List -or $All -or $Session -or $Topic -or $Catalog -or $Update -or $Check -or $Rollback

    if (-not $hasExplicitChoice) {
        Write-Host ""
        Write-Host "  💬 Save Chat — What would you like to export?" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [1] " -NoNewline -ForegroundColor Yellow; Write-Host "🤖 Copilot CLI session " -NoNewline; Write-Host "(terminal chat with Copilot)" -ForegroundColor DarkGray
        Write-Host "  [2] " -NoNewline -ForegroundColor Yellow; Write-Host "📝 VS Code Copilot Chat " -NoNewline; Write-Host "(editor chat panel)" -ForegroundColor DarkGray
        Write-Host "  [3] " -NoNewline -ForegroundColor Yellow; Write-Host "📋 Browse all CLI sessions " -NoNewline; Write-Host "(pick from a list)" -ForegroundColor DarkGray
        Write-Host "  [4] " -NoNewline -ForegroundColor Yellow; Write-Host "📋 Browse all VS Code sessions " -NoNewline; Write-Host "(pick from a list)" -ForegroundColor DarkGray
        Write-Host ""
        $choice = Read-Host "  Select (1-4, or Enter to cancel)"

        switch ($choice) {
            '1' { $CLI = $true }
            '2' { <# falls through to VS Code path #> }
            '3' { $CLI = $true; $List = $true }
            '4' { $List = $true }
            default {
                Write-Host "  Cancelled." -ForegroundColor DarkGray
                return
            }
        }
        Write-Host ""
    }

    if ($CLI) {
        # Route to the Copilot CLI exporter
        $cliScript = Join-Path $scriptDir "Save-CopilotChat-CLI.ps1"
        if (-not (Test-Path $cliScript)) {
            Write-Host "❌ CLI export script not found: $cliScript" -ForegroundColor Red
            return
        }
        $cliParams = @{}
        if ($Topic) { $cliParams['Topic'] = $Topic }
        if ($List) { $cliParams['List'] = $true }
        if ($Session) { $cliParams['Session'] = $Session }
        & $cliScript @cliParams
    }
    else {
        # Route to the VS Code v2 exporter
        $v2Script = Join-Path $scriptDir "Save-CopilotChat-v2.ps1"
        if (-not (Test-Path $v2Script)) {
            Write-Host "❌ v2 script not found: $v2Script" -ForegroundColor Red
            return
        }
        $v2Params = @{}
        $PSBoundParameters.GetEnumerator() | Where-Object { $_.Key -ne 'CLI' } | ForEach-Object {
            $v2Params[$_.Key] = $_.Value
        }
        & $v2Script @v2Params
    }
}

# Aliases — clean, short, memorable
Set-Alias -Name save-chat -Value Save-GitHubCopilotChat
Set-Alias -Name Save-GitHubChat -Value Save-GitHubCopilotChat
Set-Alias -Name Export-GitHubCopilotChat -Value Save-GitHubCopilotChat

# Resume previous GitHub Copilot chat session
function Resume-GitHubCopilotChat {
    <#
    .SYNOPSIS
        Browse and resume previous GitHub Copilot chat sessions

    .DESCRIPTION
        Shows a list of your recent chat exports and opens the selected one.
        Perfect for picking up where you left off after closing VS Code!

    .EXAMPLE
        Resume-GitHubCopilotChat
        # Shows last 10 sessions and opens selected file
    #>

    # ⚠️ UPDATE THIS PATH to where you cloned the repository
    $sessionsPath = "$env:USERPROFILE\path\to\github-copilot-chat-exporter\sessions"

    if (-not (Test-Path $sessionsPath)) {
        # Check if this looks like a placeholder path (installation issue)
        if ($sessionsPath -match 'path.*to.*copilot') {
            Write-Host "" -ForegroundColor Red
            Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
            Write-Host "║  ❌ Installation Not Complete - Path Configuration Needed    ║" -ForegroundColor Red
            Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
            Write-Host ""
            Write-Host "The installation did not complete properly." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "🔧 Quick Fix: Re-run the installer" -ForegroundColor Cyan
            Write-Host "    cd <your-repo-path>" -ForegroundColor Gray
            Write-Host "    .\Install-CopilotChatExporter.ps1 -Force" -ForegroundColor Gray
            Write-Host ""
            Write-Host "📚 Need help? See: https://github.com/ZacharyLuz/github-copilot-chat-exporter" -ForegroundColor DarkGray
            Write-Host ""
        } else {
            Write-Host "📭 Sessions folder not found: $sessionsPath" -ForegroundColor Yellow
            Write-Host "   This folder will be created when you export your first chat." -ForegroundColor Gray
            Write-Host "   Run: Save-GitHubChat" -ForegroundColor Cyan
        }
        return
    }

    # Find all markdown files in sessions folder
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

    # Display numbered list of sessions
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

        # Open in VS Code
        code $selectedFile
    }
    else {
        Write-Host "❌ Invalid selection" -ForegroundColor Red
    }
}

# Aliases for quick access
Set-Alias -Name Resume-Chat -Value Resume-GitHubCopilotChat
Set-Alias -Name Resume-Session -Value Resume-GitHubCopilotChat

# ============================================================================
# OPTIONAL: Auto-Reminder Feature
# ============================================================================
# This shows a reminder about your last chat session when you open VS Code terminal
# Comment out if you don't want this feature

if ($env:TERM_PROGRAM -eq "vscode" -or $env:VSCODE_GIT_IPC_HANDLE) {
    $sessionsPath = "$env:USERPROFILE\path\to\github-copilot-chat-exporter\sessions"

    # Skip the reminder if paths aren't configured (avoid confusing error on startup)
    if ($sessionsPath -notmatch 'path.*to.*copilot' -and (Test-Path $sessionsPath)) {
        $lastSession = Get-ChildItem -Path $sessionsPath -Filter "*.md" -File -Recurse |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($lastSession) {
            $sessionAge = (Get-Date) - $lastSession.LastWriteTime
            $sessionName = $lastSession.BaseName -replace '^\d{4}-\d{2}-\d{2}_\d{6}_', ''

            Write-Host ""
            Write-Host "💡 " -ForegroundColor Yellow -NoNewline
            Write-Host "Last chat session: " -ForegroundColor Gray -NoNewline
            Write-Host $sessionName -ForegroundColor Cyan
            Write-Host "   Saved: " -ForegroundColor Gray -NoNewline

            if ($sessionAge.TotalHours -lt 1) {
                Write-Host "$([int]$sessionAge.TotalMinutes) minutes ago" -ForegroundColor Green
            }
            elseif ($sessionAge.TotalDays -lt 1) {
                Write-Host "$([int]$sessionAge.TotalHours) hours ago" -ForegroundColor Yellow
            }
            else {
                Write-Host "$([int]$sessionAge.TotalDays) days ago" -ForegroundColor DarkGray
            }

            Write-Host ""
            Write-Host "   Type: " -ForegroundColor Gray -NoNewline
            Write-Host "Resume-Chat" -ForegroundColor Cyan -NoNewline
            Write-Host " to pick up where you left off!" -ForegroundColor Gray
            Write-Host ""
        }
    }
}
