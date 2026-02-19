<#
.SYNOPSIS
    Export GitHub Copilot CLI sessions to organized markdown files.

.DESCRIPTION
    Reads Copilot CLI session data from ~/.copilot/session-state/ (events.jsonl),
    converts to clean markdown with full tool calls and results, and saves to
    the shared CopilotChatSessions/ folder alongside VS Code chat exports.

    Supports session browsing, topic naming, and matches the existing VS Code
    export format for a unified chat history.

.PARAMETER Topic
    Optional custom topic name for the export filename.

.PARAMETER List
    Browse and select from recent CLI sessions (paginated).

.PARAMETER Session
    Export a specific session by its GUID.

.PARAMETER Last
    Export the most recent session (default behavior when no params given).

.PARAMETER DryRun
    Show what would be exported without writing files.

.EXAMPLE
    Save-CopilotChat-CLI.ps1
    # Export the most recent CLI session

.EXAMPLE
    Save-CopilotChat-CLI.ps1 -List
    # Browse and pick from recent sessions

.EXAMPLE
    Save-CopilotChat-CLI.ps1 -Session "43ee20d4-6eb3-4104-90fb-0dc43fa61444" -Topic "knowledge-mcp-setup"
    # Export a specific session with a custom topic name

.NOTES
    Author: Zachary Luz
    Version: 1.0.0
    Date: February 2026
    Output: ~/OneDrive - Microsoft/Documents/CopilotChatSessions/YYYY-MM/
    Alias: save-chat -CLI
#>

[CmdletBinding()]
param(
    [string]$Topic,
    [switch]$List,
    [string]$Session,
    [switch]$Last,
    [switch]$DryRun
)

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

$SessionStateDir = Join-Path $env:USERPROFILE ".copilot\session-state"
$OutputBaseDir = Join-Path $env:USERPROFILE "OneDrive - Microsoft\Documents\CopilotChatSessions"

# Minimum number of user messages to consider a session worth exporting
$MinUserMessages = 1

# Maximum characters for tool results before truncating
$MaxToolResultLength = 3000

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Get-CliSessions {
    <#
    .SYNOPSIS
        Discovers all Copilot CLI sessions with metadata.
    #>
    $sessions = @()

    # Sessions can be in subdirectories (with events.jsonl) or as top-level .jsonl files
    $sessionDirs = Get-ChildItem $SessionStateDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "events.jsonl") }

    foreach ($dir in $sessionDirs) {
        $eventsFile = Join-Path $dir.FullName "events.jsonl"
        try {
            # Read just the first line to get session metadata
            $firstLine = Get-Content $eventsFile -TotalCount 1 -ErrorAction Stop
            $startEvent = $firstLine | ConvertFrom-Json

            if ($startEvent.type -ne 'session.start') { continue }

            # Count user messages for session quality filtering
            $userMsgCount = (Select-String -LiteralPath $eventsFile -Pattern '"type":\s*"user\.message"').Count
            $fileSize = (Get-Item $eventsFile).Length

            $sessions += [PSCustomObject]@{
                Id           = $dir.Name
                StartTime    = [DateTime]::Parse($startEvent.timestamp)
                Version      = $startEvent.data.copilotVersion
                Cwd          = $startEvent.data.context.cwd
                UserMessages = $userMsgCount
                SizeKB       = [math]::Round($fileSize / 1KB, 1)
                EventsFile   = $eventsFile
            }
        }
        catch { }
    }

    return $sessions | Sort-Object StartTime -Descending
}

function Get-TopicFromContent {
    <#
    .SYNOPSIS
        Auto-generates a topic slug from the first user message.
    #>
    param([string]$FirstUserMessage)

    # Take the first ~60 chars, lowercase, replace non-alphanum with hyphens
    $slug = $FirstUserMessage.Substring(0, [Math]::Min(60, $FirstUserMessage.Length))
    $slug = $slug.ToLower() -replace '[^a-z0-9\s]', '' -replace '\s+', '-' -replace '-{2,}', '-'
    $slug = $slug.Trim('-')

    if ($slug.Length -lt 3) { $slug = "cli-session" }
    return $slug
}

function Convert-EventsToMarkdown {
    <#
    .SYNOPSIS
        Converts a Copilot CLI events.jsonl file to markdown.
    #>
    param(
        [string]$EventsFile,
        [string]$CustomTopic
    )

    $events = Get-Content -LiteralPath $EventsFile | ForEach-Object { $_ | ConvertFrom-Json }
    $md = [System.Text.StringBuilder]::new()

    # Extract session metadata from first event
    $startEvent = $events | Where-Object { $_.type -eq 'session.start' } | Select-Object -First 1
    if (-not $startEvent) {
        Write-Host "  ❌ No session.start event found" -ForegroundColor Red
        return $null
    }

    $startTime = [DateTime]::Parse($startEvent.data.startTime)
    $lastEvent = $events[-1]
    $endTime = [DateTime]::Parse($lastEvent.timestamp)
    $duration = $endTime - $startTime
    $sessionId = $startEvent.data.sessionId
    $version = $startEvent.data.copilotVersion
    $cwd = $startEvent.data.context.cwd

    # Count messages for stats
    $userCount = ($events | Where-Object { $_.type -eq 'user.message' }).Count
    $assistantCount = ($events | Where-Object { $_.type -eq 'assistant.message' }).Count
    $toolCount = ($events | Where-Object { $_.type -eq 'tool.execution_start' }).Count

    # Get first user message for topic extraction
    $firstUserEvent = $events | Where-Object { $_.type -eq 'user.message' } | Select-Object -First 1
    $firstUserMsg = if ($firstUserEvent) {
        # Strip system XML tags from the content
        $firstUserEvent.data.content -replace '<current_datetime>.*?</current_datetime>\s*', '' `
            -replace '<reminder>[\s\S]*?</reminder>\s*', '' `
            -replace '<tools_changed_notice>[\s\S]*?</tools_changed_notice>\s*', '' |
            ForEach-Object { $_.Trim() }
    } else { "cli-session" }

    $topic = if ($CustomTopic) { $CustomTopic } else { Get-TopicFromContent $firstUserMsg }

    # Format duration
    $durationStr = if ($duration.TotalHours -ge 1) {
        "$([math]::Floor($duration.TotalHours))h $($duration.Minutes)m"
    } else {
        "$($duration.Minutes)m $($duration.Seconds)s"
    }

    # Build header
    [void]$md.AppendLine("# 💬 Copilot CLI Session — $topic")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("> **Session ID:** ``$sessionId``")
    [void]$md.AppendLine("> **Started:** $($startTime.ToString('M/d/yyyy, h:mm:ss tt'))")
    [void]$md.AppendLine("> **Duration:** $durationStr")
    [void]$md.AppendLine("> **Source:** Copilot CLI v$version")
    [void]$md.AppendLine("> **Working Directory:** $cwd")
    [void]$md.AppendLine("> **Stats:** $userCount user messages, $assistantCount assistant responses, $toolCount tool calls")
    [void]$md.AppendLine("> **Exported:** $(Get-Date -Format 'M/d/yyyy h:mm:ss tt')")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("---")

    # Process each event
    foreach ($evt in $events) {
        $ts = if ($evt.timestamp) {
            [DateTime]::Parse($evt.timestamp).ToString('HH:mm UTC')
        } else { "" }

        switch ($evt.type) {
            'user.message' {
                $content = $evt.data.content `
                    -replace '<current_datetime>.*?</current_datetime>\s*', '' `
                    -replace '(?s)<reminder>.*?</reminder>\s*', '' `
                    -replace '(?s)<tools_changed_notice>.*?</tools_changed_notice>\s*', ''
                $content = $content.Trim()
                if ($content) {
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("## 🧑 User *($ts)*")
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine($content)
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("---")
                }
            }

            'assistant.message' {
                $content = $evt.data.content
                if ($content -and $content.Trim()) {
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("## 🤖 Assistant *($ts)*")
                    [void]$md.AppendLine("")
                    # Include reasoning as a collapsible section
                    if ($evt.data.reasoningText) {
                        [void]$md.AppendLine("<details><summary>💭 Reasoning</summary>")
                        [void]$md.AppendLine("")
                        [void]$md.AppendLine($evt.data.reasoningText)
                        [void]$md.AppendLine("")
                        [void]$md.AppendLine("</details>")
                        [void]$md.AppendLine("")
                    }
                    [void]$md.AppendLine($content.Trim())
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("---")
                }
            }

            'tool.execution_start' {
                $toolName = $evt.data.toolName
                # Skip noisy internal tools
                if ($toolName -eq 'report_intent') { continue }

                [void]$md.AppendLine("")
                [void]$md.AppendLine("## 🔧 Tool: $toolName *($ts)*")
                [void]$md.AppendLine("")
                if ($evt.data.arguments) {
                    $argsJson = $evt.data.arguments | ConvertTo-Json -Depth 5 -Compress
                    if ($argsJson.Length -gt 500) {
                        $argsJson = $argsJson.Substring(0, 500) + "... (truncated)"
                    }
                    [void]$md.AppendLine('```json')
                    [void]$md.AppendLine($argsJson)
                    [void]$md.AppendLine('```')
                }
            }

            'tool.execution_complete' {
                # Skip results for report_intent
                if ($evt.data.toolName -eq 'report_intent') { continue }

                if ($evt.data.result) {
                    # Ensure result is a string (can be object for some tool responses)
                    $resultText = if ($evt.data.result -is [string]) {
                        $evt.data.result
                    } else {
                        $evt.data.result | ConvertTo-Json -Depth 3 -Compress
                    }
                    $truncated = $false
                    if ($resultText.Length -gt $MaxToolResultLength) {
                        $resultText = $resultText.Substring(0, $MaxToolResultLength)
                        $truncated = $true
                    }
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("**Result:**")
                    [void]$md.AppendLine('```')
                    [void]$md.AppendLine([string]$resultText)
                    if ($truncated) { [void]$md.AppendLine("... (truncated)") }
                    [void]$md.AppendLine('```')
                }
                [void]$md.AppendLine("")
                [void]$md.AppendLine("---")
            }

            # Skip structural events
            default { }
        }
    }

    return @{
        Markdown     = $md.ToString()
        Topic        = $topic
        SessionId    = $sessionId
        StartTime    = $startTime
        Duration     = $durationStr
        UserMessages = $userCount
        ToolCalls    = $toolCount
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN LOGIC
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  🤖 Copilot CLI Chat Exporter                       ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $SessionStateDir)) {
    Write-Host "  ❌ Session state directory not found: $SessionStateDir" -ForegroundColor Red
    Write-Host "     Have you used Copilot CLI before?" -ForegroundColor Gray
    exit 1
}

# Discover sessions
$allSessions = Get-CliSessions
$exportable = $allSessions | Where-Object { $_.UserMessages -ge $MinUserMessages }

if ($exportable.Count -eq 0) {
    Write-Host "  ⚠️  No exportable CLI sessions found (need at least $MinUserMessages user message)" -ForegroundColor Yellow
    exit 0
}

Write-Host "  Found $($allSessions.Count) sessions ($($exportable.Count) with content)" -ForegroundColor White
Write-Host ""

# ─── Session Selection ───────────────────────────────────────────────────────

$selectedSession = $null

if ($Session) {
    # Specific session by GUID
    $selectedSession = $allSessions | Where-Object { $_.Id -eq $Session }
    if (-not $selectedSession) {
        Write-Host "  ❌ Session not found: $Session" -ForegroundColor Red
        exit 1
    }
}
elseif ($List) {
    # Interactive session picker
    Write-Host "  Recent Copilot CLI Sessions:" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $pageSize = 10
    $sessions = @($exportable)

    for ($i = 0; $i -lt [Math]::Min($sessions.Count, 30); $i++) {
        $s = $sessions[$i]
        $age = (Get-Date) - $s.StartTime
        $ageStr = if ($age.TotalHours -lt 24) { "$([math]::Floor($age.TotalHours))h ago" }
                  elseif ($age.TotalDays -lt 7) { "$([math]::Floor($age.TotalDays))d ago" }
                  else { $s.StartTime.ToString("MMM d") }

        $color = if ($i -eq 0) { "White" } else { "Gray" }
        Write-Host "  [$($i+1)] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($s.StartTime.ToString('MM/dd HH:mm'))" -NoNewline -ForegroundColor $color
        Write-Host " │ $($s.UserMessages) msgs │ $($s.SizeKB) KB │ " -NoNewline -ForegroundColor DarkGray
        Write-Host "$ageStr" -ForegroundColor DarkGray
    }

    Write-Host ""
    $choice = Read-Host "  Select session number (1-$([Math]::Min($sessions.Count, 30)), or Enter for latest)"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $selectedSession = $sessions[0]
    }
    elseif ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $sessions.Count) {
            $selectedSession = $sessions[$idx]
        }
    }

    if (-not $selectedSession) {
        Write-Host "  ❌ Invalid selection" -ForegroundColor Red
        exit 1
    }
}
else {
    # Default: export the most recent session
    $selectedSession = $exportable[0]
}

Write-Host "  📋 Exporting session: $($selectedSession.Id)" -ForegroundColor Cyan
Write-Host "     Started: $($selectedSession.StartTime.ToString('M/d/yyyy h:mm tt'))" -ForegroundColor Gray
Write-Host "     Messages: $($selectedSession.UserMessages) user, $($selectedSession.SizeKB) KB" -ForegroundColor Gray
Write-Host ""

# ─── Convert to Markdown ────────────────────────────────────────────────────

$result = Convert-EventsToMarkdown -EventsFile $selectedSession.EventsFile -CustomTopic $Topic

if (-not $result) {
    Write-Host "  ❌ Conversion failed" -ForegroundColor Red
    exit 1
}

# ─── Save to File ───────────────────────────────────────────────────────────

$monthFolder = $result.StartTime.ToString("yyyy-MM")
$datePrefix = $result.StartTime.ToString("yyyy-MM-dd")
$safeTopicSlug = $result.Topic -replace '[\\/:*?"<>|]', '-'
$filename = "${datePrefix}_${safeTopicSlug}.md"
$outputDir = Join-Path $OutputBaseDir $monthFolder
$outputPath = Join-Path $outputDir $filename

if ($DryRun) {
    Write-Host "  ⚠️  DRY RUN — would save to:" -ForegroundColor Yellow
    Write-Host "     $outputPath" -ForegroundColor White
    Write-Host "     Topic: $($result.Topic)" -ForegroundColor Gray
    Write-Host "     Size: ~$([math]::Round($result.Markdown.Length / 1KB, 1)) KB" -ForegroundColor Gray
    exit 0
}

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Avoid overwriting existing exports
if (Test-Path $outputPath) {
    $timestamp = Get-Date -Format "HHmmss"
    $filename = "${datePrefix}_${timestamp}_${safeTopicSlug}.md"
    $outputPath = Join-Path $outputDir $filename
}

$result.Markdown | Out-File -FilePath $outputPath -Encoding utf8

$fileSize = [math]::Round((Get-Item $outputPath).Length / 1KB, 1)

Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║  ✅ Export Complete                                   ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  📄 File: $filename" -ForegroundColor White
Write-Host "  📁 Path: $outputDir" -ForegroundColor Gray
Write-Host "  📊 Size: $fileSize KB ($($result.UserMessages) user msgs, $($result.ToolCalls) tool calls)" -ForegroundColor Gray
Write-Host "  🏷️  Topic: $($result.Topic)" -ForegroundColor Gray
Write-Host ""
