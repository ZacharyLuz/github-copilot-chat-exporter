<#
.SYNOPSIS
    Export GitHub Copilot CLI sessions to markdown.

.DESCRIPTION
    Net-new CLI-only exporter that leaves Save-CopilotChat-CLI.ps1 intact.

    The original script chooses the default session by session start time. That
    fails for resumed or long-running CLI sessions. This version chooses the
    default session by events.jsonl LastWriteTime, which matches the active CLI
    session most reliably.

.PARAMETER Topic
    Optional custom topic slug for the export filename.

.PARAMETER List
    Browse and select from recent CLI sessions sorted by LastWriteTime.

.PARAMETER Session
    Export a specific CLI session by full GUID or unique prefix.

.PARAMETER Current
    Export the most recently written CLI session. This is also the default.

.PARAMETER DryRun
    Show what would be exported without writing a file.

.PARAMETER PassThru
    Return the output file path object after a successful export.

.EXAMPLE
    .\Save-CopilotChat-CLI-v2.ps1 -DryRun

.EXAMPLE
    .\Save-CopilotChat-CLI-v2.ps1 -Session eaa20afb -Topic kb-attribution-phase2

.NOTES
    Output: ~/OneDrive - Microsoft/Documents/CopilotChatSessions/YYYY-MM/
#>

[CmdletBinding()]
param(
    [string]$Topic,
    [switch]$List,
    [string]$Session,
    [switch]$Current,
    [switch]$DryRun,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

$SessionStateDir = Join-Path $env:USERPROFILE ".copilot\session-state"
$OutputBaseDir = Join-Path $env:USERPROFILE "OneDrive - Microsoft\Documents\CopilotChatSessions"
$MinUserMessages = 1
$MaxToolResultLength = 3000

function ConvertTo-SafeSlug {
    param(
        [string]$Text,
        [string]$Fallback = "cli-session"
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Fallback
    }

    $slug = $Text.ToLowerInvariant()
    $slug = $slug -replace '<current_datetime>.*?</current_datetime>\s*', ''
    $slug = $slug -replace '(?s)<reminder>.*?</reminder>\s*', ''
    $slug = $slug -replace '(?s)<tools_changed_notice>.*?</tools_changed_notice>\s*', ''
    $slug = $slug -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')

    if ($slug.Length -gt 60) {
        $slug = $slug.Substring(0, 60).Trim('-')
    }

    if ($slug.Length -lt 3) {
        return $Fallback
    }

    return $slug
}

function Remove-CliMetaBlocks {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return ($Text `
        -replace '<current_datetime>.*?</current_datetime>\s*', '' `
        -replace '(?s)<reminder>.*?</reminder>\s*', '' `
        -replace '(?s)<tools_changed_notice>.*?</tools_changed_notice>\s*', '').Trim()
}

function Read-JsonLineEvents {
    param([string]$EventsFile)

    $events = New-Object System.Collections.Generic.List[object]
    $lineNumber = 0

    foreach ($line in Get-Content -LiteralPath $EventsFile) {
        $lineNumber += 1
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $events.Add(($line | ConvertFrom-Json))
        }
        catch {
            throw "Invalid JSON in $EventsFile at line $lineNumber`: $($_.Exception.Message)"
        }
    }

    return $events
}

function Get-CliSessions {
    if (-not (Test-Path $SessionStateDir)) {
        throw "Session state directory not found: $SessionStateDir"
    }

    $sessions = @()
    $sessionDirs = Get-ChildItem $SessionStateDir -Directory -ErrorAction Stop |
        Where-Object { Test-Path (Join-Path $_.FullName "events.jsonl") }

    foreach ($dir in $sessionDirs) {
        $eventsFile = Join-Path $dir.FullName "events.jsonl"
        $fileInfo = Get-Item -LiteralPath $eventsFile

        try {
            $firstLine = Get-Content -LiteralPath $eventsFile -TotalCount 1
            if ([string]::IsNullOrWhiteSpace($firstLine)) {
                continue
            }

            $startEvent = $firstLine | ConvertFrom-Json
            if ($startEvent.type -ne "session.start") {
                continue
            }

            $startRaw = if ($startEvent.data.startTime) { $startEvent.data.startTime } else { $startEvent.timestamp }
            $userMsgCount = (Select-String -LiteralPath $eventsFile -Pattern '"type":\s*"user\.message"').Count
            if ($userMsgCount -lt $MinUserMessages) {
                continue
            }

            $sessions += [PSCustomObject]@{
                Id            = $dir.Name
                IdShort       = $dir.Name.Substring(0, [Math]::Min(8, $dir.Name.Length))
                StartTime     = [DateTime]::Parse($startRaw)
                LastWriteTime = $fileInfo.LastWriteTime
                Version       = $startEvent.data.copilotVersion
                Cwd           = $startEvent.data.context.cwd
                UserMessages  = $userMsgCount
                SizeKB        = [Math]::Round($fileInfo.Length / 1KB, 1)
                EventsFile    = $eventsFile
            }
        }
        catch {
            Write-Warning "Skipping $($dir.Name): $($_.Exception.Message)"
        }
    }

    return $sessions | Sort-Object LastWriteTime -Descending
}

function Select-CliSession {
    param([object[]]$Sessions)

    if (-not $Sessions -or $Sessions.Count -eq 0) {
        throw "No exportable CLI sessions found under $SessionStateDir"
    }

    if ($Session) {
        $matches = @($Sessions | Where-Object { $_.Id -eq $Session -or $_.Id.StartsWith($Session) })
        if ($matches.Count -eq 0) {
            throw "Session not found: $Session"
        }
        if ($matches.Count -gt 1) {
            $ids = ($matches | Select-Object -ExpandProperty IdShort) -join ", "
            throw "Session prefix '$Session' is ambiguous. Matches: $ids"
        }
        return $matches[0]
    }

    if ($List) {
        Write-Host ""
        Write-Host "Recent Copilot CLI sessions (sorted by events.jsonl LastWriteTime):" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray

        $limit = [Math]::Min($Sessions.Count, 30)
        for ($i = 0; $i -lt $limit; $i++) {
            $s = $Sessions[$i]
            $age = (Get-Date) - $s.LastWriteTime
            $ageStr = if ($age.TotalHours -lt 24) {
                "$([Math]::Floor($age.TotalHours))h ago"
            }
            elseif ($age.TotalDays -lt 7) {
                "$([Math]::Floor($age.TotalDays))d ago"
            }
            else {
                $s.LastWriteTime.ToString("MMM d")
            }

            Write-Host ("[{0,2}] {1} | updated {2} | {3} user msgs | {4} KB | {5}" -f `
                ($i + 1), $s.IdShort, $ageStr, $s.UserMessages, $s.SizeKB, $s.Cwd)
        }

        Write-Host ""
        $choice = Read-Host "Select session number (1-$limit), or Enter for most recently written"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return $Sessions[0]
        }
        if ($choice -notmatch '^\d+$') {
            throw "Invalid selection: $choice"
        }

        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $limit) {
            throw "Selection out of range: $choice"
        }

        return $Sessions[$idx]
    }

    return $Sessions[0]
}

function Convert-EventsToMarkdown {
    param(
        [object]$SelectedSession,
        [string]$CustomTopic
    )

    $events = @(Read-JsonLineEvents -EventsFile $SelectedSession.EventsFile)
    if ($events.Count -eq 0) {
        throw "No events found in $($SelectedSession.EventsFile)"
    }

    $startEvent = $events | Where-Object { $_.type -eq "session.start" } | Select-Object -First 1
    if (-not $startEvent) {
        throw "No session.start event found in $($SelectedSession.EventsFile)"
    }

    $lastEvent = $events[-1]
    $startRaw = if ($startEvent.data.startTime) { $startEvent.data.startTime } else { $startEvent.timestamp }
    $startTime = [DateTime]::Parse($startRaw)
    $endTime = if ($lastEvent.timestamp) { [DateTime]::Parse($lastEvent.timestamp) } else { $SelectedSession.LastWriteTime }
    $duration = $endTime - $startTime
    $sessionId = if ($startEvent.data.sessionId) { $startEvent.data.sessionId } else { $SelectedSession.Id }
    $version = $startEvent.data.copilotVersion
    $cwd = $startEvent.data.context.cwd

    $userCount = ($events | Where-Object { $_.type -eq "user.message" }).Count
    $assistantCount = ($events | Where-Object { $_.type -eq "assistant.message" }).Count
    $toolCount = ($events | Where-Object { $_.type -eq "tool.execution_start" }).Count

    $firstUserEvent = $events | Where-Object { $_.type -eq "user.message" } | Select-Object -First 1
    $firstUserMsg = if ($firstUserEvent) { Remove-CliMetaBlocks $firstUserEvent.data.content } else { "cli-session" }
    $topicSlug = if ($CustomTopic) { ConvertTo-SafeSlug -Text $CustomTopic } else { ConvertTo-SafeSlug -Text $firstUserMsg }

    $durationStr = if ($duration.TotalHours -ge 1) {
        "$([Math]::Floor($duration.TotalHours))h $($duration.Minutes)m"
    }
    else {
        "$($duration.Minutes)m $($duration.Seconds)s"
    }

    $md = [System.Text.StringBuilder]::new()
    [void]$md.AppendLine("---")
    [void]$md.AppendLine("source: copilot-cli")
    [void]$md.AppendLine("cli_session_id: $sessionId")
    [void]$md.AppendLine("cli_session_guid: $($SelectedSession.Id)")
    [void]$md.AppendLine("started: $($startTime.ToString('o'))")
    [void]$md.AppendLine("last_write: $($SelectedSession.LastWriteTime.ToString('o'))")
    [void]$md.AppendLine("events_file: `"$($SelectedSession.EventsFile)`"")
    [void]$md.AppendLine("topic: $topicSlug")
    [void]$md.AppendLine("---")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("# Copilot CLI Session - $topicSlug")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("> **Session ID:** ``$sessionId``")
    [void]$md.AppendLine("> **Started:** $($startTime.ToString('M/d/yyyy, h:mm:ss tt'))")
    [void]$md.AppendLine("> **Last Write:** $($SelectedSession.LastWriteTime.ToString('M/d/yyyy, h:mm:ss tt'))")
    [void]$md.AppendLine("> **Duration:** $durationStr")
    [void]$md.AppendLine("> **Source:** Copilot CLI v$version")
    [void]$md.AppendLine("> **Working Directory:** $cwd")
    [void]$md.AppendLine("> **Stats:** $userCount user messages, $assistantCount assistant responses, $toolCount tool calls")
    [void]$md.AppendLine("> **Exported:** $(Get-Date -Format 'M/d/yyyy h:mm:ss tt')")
    [void]$md.AppendLine("")
    [void]$md.AppendLine("---")

    foreach ($evt in $events) {
        $ts = if ($evt.timestamp) { [DateTime]::Parse($evt.timestamp).ToString("HH:mm UTC") } else { "" }

        switch ($evt.type) {
            "user.message" {
                $content = Remove-CliMetaBlocks $evt.data.content
                if ($content) {
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("## User ($ts)")
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine($content)
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("---")
                }
            }

            "assistant.message" {
                $content = if ($evt.data.content) { [string]$evt.data.content } else { "" }
                if ($content.Trim()) {
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("## Assistant ($ts)")
                    [void]$md.AppendLine("")
                    if ($evt.data.reasoningText) {
                        [void]$md.AppendLine("<details><summary>Reasoning</summary>")
                        [void]$md.AppendLine("")
                        [void]$md.AppendLine([string]$evt.data.reasoningText)
                        [void]$md.AppendLine("")
                        [void]$md.AppendLine("</details>")
                        [void]$md.AppendLine("")
                    }
                    [void]$md.AppendLine($content.Trim())
                    [void]$md.AppendLine("")
                    [void]$md.AppendLine("---")
                }
            }

            "tool.execution_start" {
                $toolName = $evt.data.toolName
                if ($toolName -eq "report_intent") { continue }

                [void]$md.AppendLine("")
                [void]$md.AppendLine("## Tool: $toolName ($ts)")
                [void]$md.AppendLine("")
                if ($evt.data.arguments) {
                    $argsJson = $evt.data.arguments | ConvertTo-Json -Depth 8
                    if ($argsJson.Length -gt 1000) {
                        $argsJson = $argsJson.Substring(0, 1000) + "... (truncated)"
                    }
                    [void]$md.AppendLine('```json')
                    [void]$md.AppendLine($argsJson)
                    [void]$md.AppendLine('```')
                }
            }

            "tool.execution_complete" {
                if ($evt.data.toolName -eq "report_intent") { continue }

                if ($evt.data.result) {
                    $resultText = if ($evt.data.result -is [string]) {
                        $evt.data.result
                    }
                    else {
                        $evt.data.result | ConvertTo-Json -Depth 5
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
        }
    }

    return [PSCustomObject]@{
        Markdown     = $md.ToString()
        Topic        = $topicSlug
        SessionId    = $sessionId
        StartTime    = $startTime
        LastWrite    = $SelectedSession.LastWriteTime
        UserMessages = $userCount
        ToolCalls    = $toolCount
    }
}

Write-Host ""
Write-Host "Copilot CLI Chat Exporter v2" -ForegroundColor Cyan
Write-Host "Default selection: most recently written events.jsonl" -ForegroundColor DarkGray
Write-Host ""

$allSessions = @(Get-CliSessions)
$selectedSession = Select-CliSession -Sessions $allSessions

Write-Host "Exporting CLI session: $($selectedSession.Id)" -ForegroundColor Cyan
Write-Host "  Started:    $($selectedSession.StartTime.ToString('M/d/yyyy h:mm tt'))" -ForegroundColor Gray
Write-Host "  Last write: $($selectedSession.LastWriteTime.ToString('M/d/yyyy h:mm tt'))" -ForegroundColor Gray
Write-Host "  Messages:   $($selectedSession.UserMessages) user, $($selectedSession.SizeKB) KB" -ForegroundColor Gray
Write-Host ""

$result = Convert-EventsToMarkdown -SelectedSession $selectedSession -CustomTopic $Topic

$monthFolder = $result.StartTime.ToString("yyyy-MM")
$datePrefix = $result.StartTime.ToString("yyyy-MM-dd")
$timePrefix = $result.StartTime.ToString("HHmmss")
$topicPart = $result.Topic
$filename = "${datePrefix}_${timePrefix}_${topicPart}.md"
$outputDir = Join-Path $OutputBaseDir $monthFolder
$outputPath = Join-Path $outputDir $filename

if ($DryRun) {
    Write-Host "DRY RUN - would save to:" -ForegroundColor Yellow
    Write-Host "  $outputPath" -ForegroundColor White
    Write-Host "  Topic: $($result.Topic)" -ForegroundColor Gray
    Write-Host "  Size:  ~$([Math]::Round($result.Markdown.Length / 1KB, 1)) KB" -ForegroundColor Gray
    return
}

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if (Test-Path $outputPath) {
    $exportStamp = Get-Date -Format "HHmmss"
    $filename = "${datePrefix}_${timePrefix}_${exportStamp}_${topicPart}.md"
    $outputPath = Join-Path $outputDir $filename
}

$result.Markdown | Out-File -FilePath $outputPath -Encoding utf8

$written = Get-Item -LiteralPath $outputPath -ErrorAction Stop
if ($written.Length -le 0) {
    throw "Export wrote an empty file: $outputPath"
}

Write-Host "Export complete" -ForegroundColor Green
Write-Host "  File: $filename" -ForegroundColor White
Write-Host "  Path: $outputDir" -ForegroundColor Gray
Write-Host "  Size: $([Math]::Round($written.Length / 1KB, 1)) KB ($($result.UserMessages) user msgs, $($result.ToolCalls) tool calls)" -ForegroundColor Gray
Write-Host "  Topic: $($result.Topic)" -ForegroundColor Gray

if ($PassThru) {
    [PSCustomObject]@{
        Path         = $outputPath
        FileName     = $filename
        SessionId    = $result.SessionId
        SessionGuid  = $selectedSession.Id
        LastWrite    = $result.LastWrite
        UserMessages = $result.UserMessages
        ToolCalls    = $result.ToolCalls
        SizeBytes    = $written.Length
    }
}
