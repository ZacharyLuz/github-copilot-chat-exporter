<#
.SYNOPSIS
    Autosave all active Copilot chat sessions every 10 minutes.

.DESCRIPTION
    Background scheduled script that captures ALL changed Copilot sessions
    across VS Code Stable, VS Code Insiders, and Copilot CLI.

    Unlike manual save-chat (V1), this runs headlessly — no SendKeys,
    no user interaction. It reads session files directly from VS Code's
    on-disk storage (same approach as V2) and saves markdown snapshots
    with SHA256 content hashing for dedup.

    Strategy: Save EVERYTHING that changed. Don't try to pick the "right"
    session — capture all of them. This guarantees the active session is
    always included.

    Integrates with:
    - Collect-Knowledge.ps1 (auto-indexed into KnowledgeBase)
    - knowledge-mcp (searchable via search_knowledge / get_session_context)
    - workflow-mcp (session context for Focus Guard)

.PARAMETER Force
    Run even if another instance is already running (skip lock check).

.PARAMETER DryRun
    Show what would be saved without writing any files.

.PARAMETER Verbose
    Enable verbose logging output.

.NOTES
    Author: Zachary Luz
    Version: 1.0.0
    Date: February 2026

    Scheduled Task: CopilotSessionAutosave (every 10 minutes, 24/7)
    Output: ~/Documents/CopilotChatSessions/autosave/YYYY-MM-DD/
    Index:  ~/Documents/CopilotChatSessions/autosave/autosave-index.json
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

$Config = @{
    # Where autosaved snapshots go
    AutosaveBase        = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CopilotChatSessions\autosave'

    # Lock file to prevent overlapping runs
    LockFile            = Join-Path $env:TEMP 'copilot-autosave.lock'

    # Index file tracking all snapshots and hashes
    IndexFile           = $null  # Set after AutosaveBase is resolved

    # Logging
    LogDir              = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CopilotChatSessions\logs'
    LogRetentionDays    = 14

    # Limits
    MaxSessionSizeBytes = 200MB   # Skip sessions larger than this
    MinSessionRequests  = 1       # Skip empty sessions
    MaxSnapshotsPerDay  = 500     # Safety limit

    # Stale session cutoff — don't snapshot sessions not modified in 7 days
    StaleSessionDays    = 7
}

$Config.IndexFile = Join-Path $Config.AutosaveBase 'autosave-index.json'

# ═══════════════════════════════════════════════════════════════════════════════
# LOGGING
# ═══════════════════════════════════════════════════════════════════════════════

function Write-AutosaveLog {
    param(
        [ValidateSet('ERROR', 'WARN', 'INFO', 'DEBUG')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts [$($Level.PadRight(5))] $Message"

    # Console output for interactive runs
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN' { 'Yellow' }
        'DEBUG' { 'DarkGray' }
        default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color

    # File log
    try {
        if (-not (Test-Path $Config.LogDir)) {
            New-Item -ItemType Directory -Path $Config.LogDir -Force | Out-Null
        }
        $logFile = Join-Path $Config.LogDir "autosave-$(Get-Date -Format 'yyyy-MM-dd').log"
        Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch { }
}

function Invoke-LogCleanup {
    try {
        $cutoff = (Get-Date).AddDays(-$Config.LogRetentionDays)
        Get-ChildItem -Path $Config.LogDir -Filter 'autosave-*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch { }
}

# ═══════════════════════════════════════════════════════════════════════════════
# LOCK FILE — prevent overlapping runs
# ═══════════════════════════════════════════════════════════════════════════════

function Test-LockFile {
    if ($Force) { return $false }
    if (-not (Test-Path $Config.LockFile)) { return $false }

    try {
        $lockContent = Get-Content $Config.LockFile -Raw | ConvertFrom-Json
        $lockAge = (Get-Date) - [datetime]$lockContent.started
        # Stale lock (> 4 minutes) — previous run crashed (interval is 3 min, allow 1 min buffer)
        if ($lockAge.TotalMinutes -gt 4) {
            Write-AutosaveLog -Level WARN -Message "Stale lock file detected (age: $([math]::Round($lockAge.TotalMinutes, 1)) min), removing"
            Remove-Item $Config.LockFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        Write-AutosaveLog -Level INFO -Message "Another autosave is running (PID $($lockContent.pid), started $($lockContent.started)). Skipping."
        return $true
    }
    catch {
        Remove-Item $Config.LockFile -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Set-LockFile {
    @{ pid = $PID; started = (Get-Date).ToString('o') } |
    ConvertTo-Json | Set-Content $Config.LockFile -Encoding UTF8
}

function Remove-LockFile {
    Remove-Item $Config.LockFile -Force -ErrorAction SilentlyContinue
}

# ═══════════════════════════════════════════════════════════════════════════════
# INDEX — tracks snapshots and content hashes for dedup
# ═══════════════════════════════════════════════════════════════════════════════

function Get-AutosaveIndex {
    if (-not (Test-Path $Config.IndexFile)) {
        return @{
            version   = 1
            lastRun   = $null
            snapshots = @()
            hashCache = @{}  # sessionId → last known SHA256
        }
    }
    try {
        $raw = Get-Content $Config.IndexFile -Raw | ConvertFrom-Json
        # Ensure hashCache is a proper hashtable
        $hc = @{}
        if ($raw.hashCache) {
            $raw.hashCache.PSObject.Properties | ForEach-Object { $hc[$_.Name] = $_.Value }
        }
        return @{
            version   = $raw.version ?? 1
            lastRun   = $raw.lastRun
            snapshots = @($raw.snapshots)
            hashCache = $hc
        }
    }
    catch {
        Write-AutosaveLog -Level WARN -Message "Index corrupted, starting fresh: $_"
        return @{ version = 1; lastRun = $null; snapshots = @(); hashCache = @{} }
    }
}

function Save-AutosaveIndex {
    param([Parameter(Mandatory)]$Index)
    try {
        $dir = Split-Path $Config.IndexFile -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $tmp = "$($Config.IndexFile).tmp.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
        $Index | ConvertTo-Json -Depth 10 | Set-Content $tmp -Encoding UTF8
        Move-Item $tmp $Config.IndexFile -Force
    }
    catch {
        Write-AutosaveLog -Level ERROR -Message "Failed to save index: $_"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION DISCOVERY — scans VS Code Stable, Insiders, and CLI
# ═══════════════════════════════════════════════════════════════════════════════

function Get-AllSessionFiles {
    $staleCutoff = (Get-Date).AddDays(-$Config.StaleSessionDays)
    $results = @()

    # ─── VS Code editions ────────────────────────────────────────────────
    $editions = @(
        @{ Name = 'Code'; AppData = Join-Path $env:APPDATA 'Code' }
        @{ Name = 'Code - Insiders'; AppData = Join-Path $env:APPDATA 'Code - Insiders' }
    )

    foreach ($edition in $editions) {
        $userDir = Join-Path $edition.AppData 'User'
        if (-not (Test-Path $userDir)) { continue }

        # Global (empty window) sessions
        $globalDir = Join-Path $userDir 'globalStorage\emptyWindowChatSessions'
        if (Test-Path $globalDir) {
            Get-ChildItem $globalDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.json', '.jsonl' -and $_.LastWriteTime -ge $staleCutoff -and $_.Length -le $Config.MaxSessionSizeBytes } |
            ForEach-Object {
                $results += @{
                    Path      = $_.FullName
                    Edition   = $edition.Name
                    Scope     = 'global'
                    Workspace = '(empty window)'
                    Modified  = $_.LastWriteTime
                    SizeKB    = [math]::Round($_.Length / 1KB)
                    SessionId = $_.BaseName
                }
            }
        }

        # Workspace sessions
        $wsRoot = Join-Path $userDir 'workspaceStorage'
        if (Test-Path $wsRoot) {
            Get-ChildItem $wsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $chatDir = Join-Path $_.FullName 'chatSessions'
                if (-not (Test-Path $chatDir)) { return }

                # Resolve workspace name
                $wsName = '(unknown workspace)'
                $wsJson = Join-Path $_.FullName 'workspace.json'
                if (Test-Path $wsJson) {
                    try {
                        $ws = Get-Content $wsJson -Raw | ConvertFrom-Json
                        if ($ws.folder) {
                            $wsName = [Uri]::UnescapeDataString(($ws.folder -replace '^file:///', '' -replace '/', '\'))
                        }
                        elseif ($ws.workspace) {
                            $wsName = [Uri]::UnescapeDataString(($ws.workspace -replace '^file:///', '' -replace '/', '\'))
                        }
                    }
                    catch { }
                }

                Get-ChildItem $chatDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.json', '.jsonl' -and $_.LastWriteTime -ge $staleCutoff -and $_.Length -le $Config.MaxSessionSizeBytes } |
                ForEach-Object {
                    $results += @{
                        Path      = $_.FullName
                        Edition   = $edition.Name
                        Scope     = 'workspace'
                        Workspace = $wsName
                        Modified  = $_.LastWriteTime
                        SizeKB    = [math]::Round($_.Length / 1KB)
                        SessionId = $_.BaseName
                    }
                }
            }
        }
    }

    # ─── Copilot CLI sessions ────────────────────────────────────────────
    $cliPath = Join-Path $env:USERPROFILE '.copilot\session-state'
    if (Test-Path $cliPath) {
        Get-ChildItem $cliPath -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.json', '.jsonl' -and $_.LastWriteTime -ge $staleCutoff -and $_.Length -le $Config.MaxSessionSizeBytes } |
        ForEach-Object {
            $results += @{
                Path      = $_.FullName
                Edition   = 'CLI'
                Scope     = 'cli'
                Workspace = '(Copilot CLI)'
                Modified  = $_.LastWriteTime
                SizeKB    = [math]::Round($_.Length / 1KB)
                SessionId = $_.BaseName
            }
        }
    }

    return $results
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONTENT HASHING — SHA256 for dedup
# ═══════════════════════════════════════════════════════════════════════════════

function Get-FileContentHash {
    param([Parameter(Mandatory)][string]$FilePath)
    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop
        return $hash.Hash
    }
    catch {
        return $null
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION READER — lightweight metadata + full read for markdown conversion
# ═══════════════════════════════════════════════════════════════════════════════

function Read-SessionMetadata {
    <#
    .SYNOPSIS
        Fast metadata extraction without full session parse.
        Returns title, request count, model, creation date.
    #>
    param([Parameter(Mandatory)][string]$FilePath)

    try {
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()

        if ($extension -eq '.jsonl') {
            # JSONL: read first line (kind:0 init) + scan for request count
            $requestCount = 0
            $title = $null
            $model = $null
            $session = $null
            $lineNum = 0

            foreach ($line in [System.IO.File]::ReadLines($FilePath, [System.Text.Encoding]::UTF8)) {
                if ($lineNum -eq 0) {
                    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
                    $init = $line | ConvertFrom-Json -Depth 64
                    if ($init.kind -ne 0) { return $null }
                    $session = $init.v
                }
                else {
                    # Count kind:2 request replacements
                    if ($line -match '"kind"\s*:\s*2\b' -and $line -match '"k"\s*:\s*\[\s*"requests"\s*\]') {
                        $requestCount++
                        if (-not $model -and $requestCount -eq 1 -and $line -match '"modelId"\s*:\s*"([^"]+)"') {
                            $model = ($Matches[1] -replace '^copilot/', '')
                        }
                    }
                    # Extract customTitle
                    if (-not $title -and $line -match '"kind"\s*:\s*1\b' -and $line -match '"k"\s*:\s*\[\s*"customTitle"\s*\]') {
                        try {
                            $tp = $line | ConvertFrom-Json -Depth 5
                            $title = [string]$tp.v
                        }
                        catch { }
                    }
                }
                $lineNum++
            }

            if (-not $session) { return $null }

            # Fallback count from init data
            $initCount = 0
            if ($session.requests -is [array]) { $initCount = $session.requests.Count }
            if ($requestCount -lt $initCount) { $requestCount = $initCount }

            # Fallback model from init
            if (-not $model -and $session.inputState -and $session.inputState.selectedModel) {
                $model = ($session.inputState.selectedModel.identifier -replace '^copilot/', '')
            }

            $creationDate = if ($session.creationDate) {
                [DateTimeOffset]::FromUnixTimeMilliseconds([long]$session.creationDate).LocalDateTime
            }
            else { [DateTime]::Now }

            # Preview
            $preview = ''
            if ($session.requests -is [array] -and $session.requests.Count -gt 0) {
                $firstReq = $session.requests[0]
                if ($firstReq.message -and $firstReq.message.text) {
                    $preview = $firstReq.message.text
                    if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
                }
            }

            return @{
                Title        = $title ?? $session.customTitle ?? ''
                RequestCount = $requestCount
                Model        = $model ?? 'unknown'
                CreationDate = $creationDate
                Preview      = $preview
            }
        }
        else {
            # Plain JSON
            $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
            $session = $content | ConvertFrom-Json -Depth 64

            $requestCount = 0
            if ($session.requests -is [array]) { $requestCount = $session.requests.Count }

            $model = 'unknown'
            if ($session.inputState -and $session.inputState.selectedModel -and $session.inputState.selectedModel.identifier) {
                $model = ($session.inputState.selectedModel.identifier -replace '^copilot/', '')
            }
            elseif ($session.requests -and $session.requests.Count -gt 0 -and $session.requests[0].modelId) {
                $model = ($session.requests[0].modelId -replace '^copilot/', '')
            }

            $creationDate = if ($session.creationDate) {
                [DateTimeOffset]::FromUnixTimeMilliseconds([long]$session.creationDate).LocalDateTime
            }
            else { [DateTime]::Now }

            $preview = ''
            if ($session.requests -is [array] -and $session.requests.Count -gt 0) {
                $firstReq = $session.requests[0]
                if ($firstReq.message -and $firstReq.message.text) {
                    $preview = $firstReq.message.text
                    if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
                }
            }

            return @{
                Title        = $session.customTitle ?? ''
                RequestCount = $requestCount
                Model        = $model
                CreationDate = $creationDate
                Preview      = $preview
            }
        }
    }
    catch {
        Write-AutosaveLog -Level DEBUG -Message "Metadata read failed for $(Split-Path $FilePath -Leaf): $_"
        return $null
    }
}

function Read-FullSession {
    <#
    .SYNOPSIS
        Full session read with JSONL patch replay for markdown conversion.
        Reuses the proven V2 JSONL replay logic.
    #>
    param([Parameter(Mandatory)][string]$FilePath)

    try {
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()

        if ($extension -eq '.jsonl') {
            $lines = [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)
            if ($lines.Count -eq 0) { return $null }

            $initEntry = $lines[0] | ConvertFrom-Json -Depth 50
            if ($initEntry.kind -ne 0) { return $null }
            $session = $initEntry.v

            $requestAccumulator = [ordered]@{}
            $patchCount = 0

            for ($i = 1; $i -lt $lines.Count; $i++) {
                $line = $lines[$i].Trim()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                try { $patch = $line | ConvertFrom-Json -Depth 50 } catch { continue }
                if ($null -eq $patch.k) { continue }

                $keyPath = @($patch.k)
                $target = $session
                $parentTarget = $null
                $lastKey = $null

                for ($j = 0; $j -lt $keyPath.Count - 1; $j++) {
                    $key = $keyPath[$j]
                    $parentTarget = $target

                    if ($key -is [int] -or $key -match '^\d+$') {
                        $idx = [int]$key
                        if (($target -is [array] -or $target -is [System.Collections.IList]) -and $idx -lt $target.Count) {
                            $target = $target[$idx]
                        }
                        else { $target = $null; break }
                    }
                    else {
                        if ($null -ne $target.$key) { $target = $target.$key }
                        elseif ($target -is [hashtable] -and $target.ContainsKey($key)) { $target = $target[$key] }
                        else { $target = $null; break }
                    }
                }

                if ($null -eq $target) { continue }
                $lastKey = $keyPath[-1]

                # Snapshot before replacing requests
                if ([int]$patch.kind -eq 2 -and $keyPath.Count -eq 1 -and $lastKey -eq 'requests') {
                    if ($session.requests -is [array]) {
                        foreach ($r in $session.requests) {
                            if ($r.requestId) { $requestAccumulator[$r.requestId] = $r }
                        }
                    }
                }

                # Apply patch
                switch ([int]$patch.kind) {
                    1 {
                        if ($lastKey -is [int] -or $lastKey -match '^\d+$') {
                            $idx = [int]$lastKey
                            if (($target -is [array] -or $target -is [System.Collections.IList]) -and $idx -lt $target.Count) {
                                $target[$idx] = $patch.v
                            }
                        }
                        else {
                            if ($target -is [PSCustomObject]) {
                                if ($null -ne $target.$lastKey) { $target.$lastKey = $patch.v }
                                else { $target | Add-Member -NotePropertyName $lastKey -NotePropertyValue $patch.v -Force }
                            }
                            elseif ($target -is [hashtable]) { $target[$lastKey] = $patch.v }
                        }
                        $patchCount++
                    }
                    2 {
                        if ($lastKey -is [int] -or $lastKey -match '^\d+$') {
                            $idx = [int]$lastKey
                            if (($target -is [array] -or $target -is [System.Collections.IList]) -and $idx -lt $target.Count) {
                                $target[$idx] = $patch.v
                            }
                        }
                        else {
                            if ($target -is [PSCustomObject]) { $target.$lastKey = $patch.v }
                            elseif ($target -is [hashtable]) { $target[$lastKey] = $patch.v }
                        }
                        $patchCount++
                    }
                }
            }

            # Final snapshot
            if ($session.requests -is [array]) {
                foreach ($r in $session.requests) {
                    if ($r.requestId) { $requestAccumulator[$r.requestId] = $r }
                }
            }
            if ($requestAccumulator.Count -gt 0) {
                $session.requests = @($requestAccumulator.Values | Sort-Object { if ($_.timestamp) { [long]$_.timestamp } else { 0 } })
            }

            return $session
        }
        else {
            $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
            return ($content | ConvertFrom-Json -Depth 50)
        }
    }
    catch {
        Write-AutosaveLog -Level ERROR -Message "Full read failed for $(Split-Path $FilePath -Leaf): $_"
        return $null
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MARKDOWN CONVERTER — lightweight version for autosave snapshots
# ═══════════════════════════════════════════════════════════════════════════════

function ConvertTo-AutosaveMarkdown {
    <#
    .SYNOPSIS
        Convert a session object to markdown with YAML frontmatter.
        Lighter than V2's full export — optimized for searchability.
    #>
    param(
        [Parameter(Mandatory)]$Session,
        [string]$SessionId,
        [string]$Edition,
        [string]$Workspace,
        [int]$RequestCount,
        [string]$Model
    )

    $sb = [System.Text.StringBuilder]::new(32768)

    # YAML frontmatter for knowledge-base indexing
    $title = $Session.customTitle ?? "Copilot Chat Session"
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $createdDate = if ($Session.creationDate) {
        [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Session.creationDate).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
    else { $now }

    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine("title: `"$($title -replace '"', '\"')`"")
    [void]$sb.AppendLine("source: autosave")
    [void]$sb.AppendLine("category: chat-session")
    [void]$sb.AppendLine("session_id: $SessionId")
    [void]$sb.AppendLine("edition: $Edition")
    [void]$sb.AppendLine("workspace: `"$($Workspace -replace '"', '\"')`"")
    [void]$sb.AppendLine("model: $Model")
    [void]$sb.AppendLine("turns: $RequestCount")
    [void]$sb.AppendLine("created: $createdDate")
    [void]$sb.AppendLine("autosaved: $now")
    [void]$sb.AppendLine("tags: [autosave, copilot, $Edition]")
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine()

    # Header
    [void]$sb.AppendLine("# $title")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Session:** $SessionId | **Edition:** $Edition | **Model:** $Model | **Turns:** $RequestCount")
    [void]$sb.AppendLine("**Workspace:** $Workspace")
    [void]$sb.AppendLine("**Autosaved:** $now")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine()

    # Process requests
    $requests = @()
    if ($Session.requests) { $requests = @($Session.requests) }

    if ($requests.Count -eq 0) {
        [void]$sb.AppendLine('*No messages in this session.*')
        return $sb.ToString()
    }

    for ($i = 0; $i -lt $requests.Count; $i++) {
        $req = $requests[$i]
        $turnNum = $i + 1

        [void]$sb.AppendLine("## Turn $turnNum")
        [void]$sb.AppendLine()

        # User message
        $userText = Get-UserMessage $req
        if ($userText) {
            [void]$sb.AppendLine('### User')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine($userText)
            [void]$sb.AppendLine()
        }

        # Assistant response
        if ($req.response -and $req.response.Count -gt 0) {
            [void]$sb.AppendLine('### Assistant')
            [void]$sb.AppendLine()
            foreach ($part in $req.response) {
                $text = Get-ResponseText $part
                if ($text) {
                    [void]$sb.AppendLine($text)
                }
            }
            [void]$sb.AppendLine()
        }

        # Model metadata
        $metaParts = @()
        if ($req.modelId) { $metaParts += "Model: $($req.modelId -replace '^copilot/', '')" }
        if ($req.result -and $req.result.timings -and $req.result.timings.totalElapsed) {
            $elapsed = [math]::Round($req.result.timings.totalElapsed / 1000, 1)
            $metaParts += "Time: ${elapsed}s"
        }
        if ($metaParts.Count -gt 0) {
            [void]$sb.AppendLine("*$($metaParts -join ' | ')*")
            [void]$sb.AppendLine()
        }

        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine()
    }

    # Sanitize orphan surrogates
    $result = $sb.ToString()
    $result = $result -replace '[\uD800-\uDFFF]', [char]0xFFFD

    return $result
}

function Get-UserMessage {
    param($Request)
    if ($Request.message) {
        if ($Request.message.text -and $Request.message.text -is [string]) { return $Request.message.text }
        if ($Request.message.parts -and $Request.message.parts.Count -gt 0) {
            $parts = foreach ($p in $Request.message.parts) {
                if ($p.text) { $p.text } elseif ($p.value) { $p.value }
            }
            return ($parts -join "`n")
        }
        if ($Request.message.value) { return $Request.message.value }
    }
    return ''
}

function Get-ResponseText {
    param($Part)
    if ($null -eq $Part) { return $null }
    if ($Part -is [string]) { return $Part }

    $kind = $Part.kind ?? ''
    switch ($kind) {
        'markdownContent' {
            if ($Part.content -and $Part.content.value) { return $Part.content.value }
            if ($Part.value) { return $Part.value }
        }
        'textEditGroup' {
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine('<details><summary>File Edits</summary>')
            [void]$sb.AppendLine()
            if ($Part.edits) {
                foreach ($edit in $Part.edits) {
                    $fn = if ($edit.uri) { Split-Path $edit.uri -Leaf } elseif ($edit.resource) { Split-Path $edit.resource -Leaf } else { 'file' }
                    [void]$sb.AppendLine("**$fn**")
                    if ($edit.edits) {
                        foreach ($te in $edit.edits) {
                            $t = if ($te.text) { $te.text } elseif ($te.newText) { $te.newText } else { '' }
                            if ($t) {
                                [void]$sb.AppendLine('```')
                                [void]$sb.AppendLine($t)
                                [void]$sb.AppendLine('```')
                            }
                        }
                    }
                }
            }
            [void]$sb.AppendLine('</details>')
            return $sb.ToString()
        }
        'thinking' {
            if ($Part.content -and $Part.content.value) {
                return "<details><summary>Thinking</summary>`n`n$($Part.content.value)`n`n</details>"
            }
        }
        'inlineReference' {
            if ($Part.uri) { return "[$($Part.name)]($($Part.uri))" }
            if ($Part.name) { return "``$($Part.name)``" }
        }
        'progressTaskSerialized' {
            if ($Part.title) { return "- [x] $($Part.title)" }
        }
        'toolInvocationSerialized' { return $null }
        default {
            if ($Part.value -and $Part.value -is [string]) { return $Part.value }
            if ($Part.content -and $Part.content -is [string]) { return $Part.content }
            if ($Part.content -and $Part.content.value) { return $Part.content.value }
            if ($Part.text) { return $Part.text }
        }
    }
    return $null
}

# ═══════════════════════════════════════════════════════════════════════════════
# TOPIC EXTRACTION — generate safe filename from session content
# ═══════════════════════════════════════════════════════════════════════════════

function Get-SafeTopic {
    param([string]$Title, [string]$Preview, [string]$SessionId)

    $source = if ($Title) { $Title } elseif ($Preview) { $Preview } else { $SessionId }

    $safe = $source -replace '[\\\/:*?"<>|]', '' -replace '\s+', '-' -replace '[^\w-]', '' -replace '-+', '-'
    $safe = $safe.ToLower().Trim('-')

    if ($safe.Length -gt 50) { $safe = $safe.Substring(0, 50).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = $SessionId.Substring(0, 8) }

    return $safe
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN — scan, hash, snapshot changed sessions
# ═══════════════════════════════════════════════════════════════════════════════

$scriptStart = Get-Date

# Lock check
if (Test-LockFile) { exit 0 }
Set-LockFile

try {
    Write-AutosaveLog -Level INFO -Message "Autosave started (PID $PID)"
    Invoke-LogCleanup

    # Load index
    $index = Get-AutosaveIndex
    $today = Get-Date -Format 'yyyy-MM-dd'
    $todayDir = Join-Path $Config.AutosaveBase $today

    # Count today's snapshots
    $todaySnapshots = @($index.snapshots | Where-Object { $_.date -eq $today }).Count

    # Discover all session files
    $sessionFiles = Get-AllSessionFiles
    Write-AutosaveLog -Level INFO -Message "Found $($sessionFiles.Count) session files across all sources"

    $saved = 0
    $skippedHash = 0
    $skippedEmpty = 0
    $errors = 0

    foreach ($sf in $sessionFiles) {
        if ($todaySnapshots + $saved -ge $Config.MaxSnapshotsPerDay) {
            Write-AutosaveLog -Level WARN -Message "Hit daily snapshot limit ($($Config.MaxSnapshotsPerDay)). Stopping."
            break
        }

        # Compute hash
        $hash = Get-FileContentHash -FilePath $sf.Path
        if (-not $hash) {
            $errors++
            continue
        }

        # Check if this session already has a snapshot with same hash (dedup)
        $lastHash = $index.hashCache[$sf.SessionId]
        $hashChanged = ($lastHash -ne $hash)

        if (-not $hashChanged) {
            $skippedHash++
            continue
        }

        # Read metadata to check request count
        $meta = Read-SessionMetadata -FilePath $sf.Path
        if (-not $meta -or $meta.RequestCount -lt $Config.MinSessionRequests) {
            $skippedEmpty++
            continue
        }

        if ($DryRun) {
            $topic = Get-SafeTopic -Title $meta.Title -Preview $meta.Preview -SessionId $sf.SessionId
            Write-AutosaveLog -Level INFO -Message "[DRY RUN] Would save: $($sf.Edition)/$topic ($($meta.RequestCount) turns, $($sf.SizeKB) KB)"
            $saved++
            continue
        }

        # Full read + convert
        try {
            $session = Read-FullSession -FilePath $sf.Path
            if (-not $session) {
                $errors++
                continue
            }

            $markdown = ConvertTo-AutosaveMarkdown `
                -Session $session `
                -SessionId $sf.SessionId `
                -Edition $sf.Edition `
                -Workspace $sf.Workspace `
                -RequestCount $meta.RequestCount `
                -Model $meta.Model

            # Write snapshot
            if (-not (Test-Path $todayDir)) {
                New-Item -ItemType Directory -Path $todayDir -Force | Out-Null
            }

            $topic = Get-SafeTopic -Title $meta.Title -Preview $meta.Preview -SessionId $sf.SessionId
            $ts = Get-Date -Format 'HHmmss'
            $filename = "${today}_${ts}_${topic}.md"
            $outPath = Join-Path $todayDir $filename

            # Atomic write
            $tmp = "$outPath.tmp"
            Set-Content -Path $tmp -Value $markdown -Encoding UTF8
            Move-Item $tmp $outPath -Force

            $fileSizeKB = [math]::Round((Get-Item $outPath).Length / 1KB, 1)

            # Also write a timestamped version for full timeline
            # (hash check means we only write when content actually changes)

            Write-AutosaveLog -Level INFO -Message "Saved: $filename ($($meta.RequestCount) turns, $fileSizeKB KB) [$($sf.Edition)]"

            # Update index
            $index.hashCache[$sf.SessionId] = $hash
            $index.snapshots += @{
                sessionId = $sf.SessionId
                file      = "$today/$filename"
                date      = $sf.Modified.ToString('yyyy-MM-dd')   # real session date, not autosave-run date
                timestamp = $sf.Modified.ToString('o')            # real session date, not autosave-run date
                edition   = $sf.Edition
                workspace = $sf.Workspace
                title     = $meta.Title
                turns     = $meta.RequestCount
                model     = $meta.Model
                hash      = $hash
                sizeKB    = $fileSizeKB
            }

            $saved++
        }
        catch {
            Write-AutosaveLog -Level ERROR -Message "Failed to process $($sf.SessionId): $_"
            $errors++
        }
    }

    # Update and save index
    $index.lastRun = (Get-Date).ToString('o')
    Save-AutosaveIndex $index

    $elapsed = [math]::Round(((Get-Date) - $scriptStart).TotalSeconds, 1)
    Write-AutosaveLog -Level INFO -Message "Autosave complete: $saved saved, $skippedHash unchanged, $skippedEmpty empty, $errors errors (${elapsed}s)"

}
finally {
    Remove-LockFile
}
