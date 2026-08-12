<#
.SYNOPSIS
    Exports Copilot CLI terminal sessions from events.jsonl to Markdown.
.DESCRIPTION
    Parses the Copilot CLI events.jsonl file, converts 7 event types to Markdown,
    and supports filtering by session or topic.
.PARAMETER Path
    Path to the events.jsonl file. Defaults to .\events.jsonl in the current directory.
.PARAMETER List
    Lists available sessions and topics found in the log file.
.PARAMETER Session
    Specifies a session ID to export.
.PARAMETER Topic
    Filters events by a specific topic string.
.PARAMETER Output
    Specifies the output markdown file path. Defaults to .\copilot-session.md.
.EXAMPLE
    .\Save-CopilotChat-CLI.ps1 -List
    .\Save-CopilotChat-CLI.ps1 -Session "session-123" -Output "session-123.md"
    .\Save-CopilotChat-CLI.ps1 -Topic "deployment" -Output "deployment-chat.md"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Path = ".\events.jsonl",

    [Parameter(Mandatory=$false)]
    [switch]$List,

    [Parameter(Mandatory=$false)]
    [string]$Session,

    [Parameter(Mandatory=$false)]
    [string]$Topic,

    [Parameter(Mandatory=$false)]
    [string]$Output = ".\copilot-session.md"
)

$SupportedTypes = @(
    "session.start",
    "message.user",
    "message.assistant",
    "tool.call",
    "tool.output",
    "thought.processing",
    "session.end"
)

function Parse-Events {
    if (-not (Test-Path $Path)) {
        Write-Error "Events file not found: $Path"
        exit 1
    }
    Get-Content $Path | ForEach-Object {
        try {
            [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes($_)) | ConvertFrom-Json -ErrorAction Stop
        } catch {
            # Silently skip malformed lines
        }
    }
}

if ($List) {
    $events = Parse-Events
    $sessions = $events | Where-Object { $_.type -eq "session.start" } | Select-Object -ExpandProperty sessionId -Unique
    $topics = $events | Where-Object { $_.topic } | Select-Object -ExpandProperty topic -Unique

    if ($sessions) {
        Write-Host "Available Sessions:"
        $sessions | ForEach-Object { Write-Host "  - $_" }
    } else {
        Write-Host "No sessions found."
    }

    if ($topics) {
        Write-Host "`nAvailable Topics:"
        $topics | ForEach-Object { Write-Host "  - $_" }
    } else {
        Write-Host "`nNo topics found."
    }
    exit 0
}

$events = Parse-Events | Where-Object { $_.type -in $SupportedTypes }

if ($Session) {
    $events = $events | Where-Object { $_.sessionId -eq $Session }
}

if ($Topic) {
    $events = $events | Where-Object { $_.topic -like "*$Topic*" }
}

if (-not $events) {
    Write-Warning "No events matched the specified filters."
    exit 0
}

# Sort by timestamp if available
$events = $events | Sort-Object {
    if ($_.timestamp) {
        try { [datetime]::Parse($_.timestamp) } catch { [datetime]::MinValue }
    } else {
        [datetime]::MinValue
    }
}

$md = "# Copilot CLI Session Export`n`n"
$md += "---`n`n"

foreach ($event in $events) {
    $eventType = switch ($event.type) {
        "session.start"    { "Session Start" }
        "message.user"     { "User Input" }
        "message.assistant" { "Assistant Response" }
        "tool.call"        { "Tool Invocation" }
        "tool.output"      { "Tool Output" }
        "thought.processing" { "Reasoning" }
        "session.end"      { "Session End" }
        default            { "Unknown Event" }
    }

    $timestamp = if ($event.timestamp) { "`n> *$( $event.timestamp )*`n" } else { "" }

    $content = $event.content
    if (-not $content) { $content = $event.message }
    if (-not $content) { $content = $event.output }
    if (-not $content) { $content = $event.response }
    if (-not $content) { $content = $event.action }

    if ($content -is [object]) {
        $content = $content | ConvertTo-Json -Depth 5 -Compress -ErrorAction SilentlyContinue
    }

    $md += "## $eventType$timestamp`n`n"
    $md += "$content`n`n"
    $md += "---`n`n"
}

$md | Out-File -FilePath $Output -Encoding utf8
Write-Host "Exported $($events.Count) events to $Output"
