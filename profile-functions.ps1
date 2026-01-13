# PowerShell Profile Functions for GitHub Copilot Chat Exporter
# Author: Zachary Luz
# Version: 1.0.0
# Release Date: January 2026
#
# Add these functions to your PowerShell profile ($PROFILE)

# ============================================================================
# OPTION 1: Source the script (Recommended)
# ============================================================================
# Place this in your $PROFILE to load all functions:
# . "C:\Github\Personal\copilot-chat-exporter\profile-functions.ps1"

# ============================================================================
# OPTION 2: Copy these functions directly into your $PROFILE
# ============================================================================

# Save GitHub Copilot Chat Session
function Save-GitHubCopilotChat {
    <#
    .SYNOPSIS
        Export and convert GitHub Copilot chat (VS Code) to organized markdown

    .DESCRIPTION
        Fully automated workflow to export GitHub Copilot chat sessions,
        convert to formatted markdown, and organize in dated folders.

        ⚠️ ONLY WORKS WITH GITHUB COPILOT CHAT IN VS CODE
        This does NOT work with M365 Copilot, Copilot Studio, or other Copilot variants.

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
        Requires: Python 3.6+, PowerShell 7+, VS Code
        Output: sessions/YYYY-MM/YYYY-MM-DD_HHMMSS_topic.md
        Auto-cleanup: Removes temporary JSON files after conversion
    #>

    param(
        [Parameter(Mandatory = $false)]
        [string]$Topic
    )

    # ⚠️ UPDATE THIS PATH if you cloned to a different location
    $scriptPath = "C:\Github\Personal\copilot-chat-exporter\Save-CopilotChat.ps1"

    if (-not (Test-Path $scriptPath)) {
        Write-Host "❌ Script not found: $scriptPath" -ForegroundColor Red
        Write-Host "   Update the path in your profile function" -ForegroundColor Yellow
        return
    }

    & $scriptPath @PSBoundParameters
}

# Aliases for convenience
Set-Alias -Name Save-GitHubChat -Value Save-GitHubCopilotChat
Set-Alias -Name Export-GitHubCopilotChat -Value Save-GitHubCopilotChat
Set-Alias -Name Save-GHCopilot -Value Save-GitHubCopilotChat

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

    # ⚠️ UPDATE THIS PATH if you cloned to a different location
    $sessionsPath = "C:\Github\Personal\copilot-chat-exporter\sessions"

    if (-not (Test-Path $sessionsPath)) {
        Write-Host "❌ Sessions folder not found: $sessionsPath" -ForegroundColor Red
        Write-Host "   Update the path in your profile function" -ForegroundColor Yellow
        Write-Host "   Or export a chat first using: Save-GitHubChat" -ForegroundColor Gray
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
    $sessionsPath = "C:\Github\Personal\copilot-chat-exporter\sessions"

    if (Test-Path $sessionsPath) {
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
