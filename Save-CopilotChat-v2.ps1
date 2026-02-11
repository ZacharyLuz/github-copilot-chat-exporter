<#
.SYNOPSIS
    GitHub Copilot Chat Exporter v2 — Direct file read with native PowerShell conversion.

.DESCRIPTION
    Reads chat sessions directly from VS Code's on-disk storage (JSONL/JSON),
    converts to markdown using native PowerShell (no Python dependency),
    saves to organized YYYY-MM folders with searchable INDEX files,
    and optionally symlinks into workspace .copilot-chats/ directories.

    Primary method: Direct file read from VS Code globalStorage/workspaceStorage.
    Fallback: SendKeys automation via -UseSendKeys (opt-in only).

.PARAMETER Topic
    Optional custom topic name for the export. If omitted, uses VS Code's
    customTitle or falls back to smart keyword extraction.

.PARAMETER Session
    Export a specific session by its GUID. Skips the session picker.

.PARAMETER List
    Show the last 100 non-empty sessions in pages of 20 for interactive selection.

.PARAMETER All
    Export all non-empty, non-exported sessions in batch mode.

.PARAMETER Catalog
    Build/refresh the INDEX.md and INDEX.json files without exporting new markdown.

.PARAMETER Update
    Check for and install updates from GitHub.

.PARAMETER Check
    Used with -Update. Only check if an update is available, don't install.

.PARAMETER Rollback
    Used with -Update. Restore the previous version from backup.

.PARAMETER UseSendKeys
    Use the legacy SendKeys automation instead of direct file read.

.PARAMETER NoWorkspaceLink
    Skip creating symlinks in workspace .copilot-chats/ directories.

.PARAMETER SkipSecretScan
    Skip the mandatory secret scan. Requires -Force. Logs a warning.

.PARAMETER Force
    Suppress confirmation prompts. Required with -SkipSecretScan.

.PARAMETER LogLevel
    Minimum log level to record. Default: Info.

.PARAMETER NoLog
    Disable file logging (still writes to PowerShell streams).

.EXAMPLE
    Save-CopilotChat-v2.ps1
    # Auto-select latest session, confirm, export.

.EXAMPLE
    Save-CopilotChat-v2.ps1 -List
    # Show last 100 sessions in pages of 20, pick one or many.

.EXAMPLE
    Save-CopilotChat-v2.ps1 -Catalog
    # Rebuild INDEX.md and INDEX.json from all VS Code sessions.

.EXAMPLE
    Save-CopilotChat-v2.ps1 -All
    # Export every non-empty session that hasn't been exported yet.

.NOTES
    Author: Zachary Luz
    Version: 2.0.0
    Date: February 2026
    License: MIT
    Repository: https://github.com/ZacharyLuz/github-copilot-chat-exporter
#>

#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Export')]
param(
    [Parameter(ParameterSetName = 'Export', Position = 0)]
    [ValidateLength(1, 100)]
    [string]$Topic,

    [Parameter(ParameterSetName = 'Export')]
    [guid]$Session,

    [Parameter(ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(ParameterSetName = 'ExportAll')]
    [switch]$All,

    [Parameter(ParameterSetName = 'Catalog')]
    [switch]$Catalog,

    [Parameter(ParameterSetName = 'Update')]
    [switch]$Update,

    [Parameter(ParameterSetName = 'Update')]
    [switch]$Check,

    [Parameter(ParameterSetName = 'Update')]
    [switch]$Rollback,

    [Parameter()]
    [switch]$UseSendKeys,

    [Parameter()]
    [switch]$NoWorkspaceLink,

    [Parameter()]
    [switch]$SkipSecretScan,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateSet('Error', 'Warning', 'Info', 'Debug')]
    [string]$LogLevel = 'Info',

    [Parameter()]
    [switch]$NoLog
)

$ErrorActionPreference = 'Stop'
$script:ExporterVersion = '2.0.0'

# ============================================================================
# CONFIGURATION
# ============================================================================

function Get-ExporterConfig {
    [CmdletBinding()]
    param()

    $configFilePath = Join-Path $env:LOCALAPPDATA 'CopilotChatExporter\config.json'

    # Default configuration — module-ready (no script-scoped leaks)
    $config = @{
        SessionsBasePath   = Join-Path ($env:USERPROFILE) 'OneDrive - Microsoft\Documents\CopilotChatSessions'
        TempPath           = $env:TEMP
        DateFormat         = 'yyyy-MM-dd'
        YearMonthFormat    = 'yyyy-MM'
        TimestampFormat    = 'HHmmss'
        TopicMaxLength     = 50
        TopicWordCount     = 4
        JsonFilePrefix     = 'CHAT-EXPORT'
        MaxSessionsToList  = 100
        PageSize           = 20
        AutoConfirmLatest  = $true
        WorkspaceLinkEnabled = $true
        LogRetentionDays   = 30
        LogLevel           = 'Info'
        # SendKeys fallback settings
        FileWatchTimeout   = 300
        FileWatchInterval  = 2
        KeyDelay_Initial   = 300
        KeyDelay_Command   = 200
        KeyDelay_Execute   = 1500
        KeyDelay_Paste     = 300
        # Update settings
        GitHubRepo         = 'ZacharyLuz/github-copilot-chat-exporter'
        UpdateTimeout      = 30
    }

    # Load user config overrides
    if (Test-Path $configFilePath) {
        try {
            $userConfig = Get-Content $configFilePath -Raw | ConvertFrom-Json
            foreach ($prop in $userConfig.PSObject.Properties) {
                if ($config.ContainsKey($prop.Name)) {
                    $config[$prop.Name] = $prop.Value
                }
            }
            Write-Verbose "Loaded config from: $configFilePath"
        }
        catch {
            Write-Warning "Could not load config file, using defaults: $_"
        }
    }

    return $config
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

    # Level hierarchy for filtering
    $levelMap = @{ 'ERROR' = 0; 'WARN' = 1; 'INFO' = 2; 'DEBUG' = 3 }
    $configLevel = if ($script:ActiveConfig) { $script:ActiveConfig.LogLevel } else { 'Info' }
    $configLevelKey = switch ($configLevel) { 'Error' { 'ERROR' } 'Warning' { 'WARN' } 'Info' { 'INFO' } 'Debug' { 'DEBUG' } default { 'INFO' } }

    if ($levelMap[$Level] -gt $levelMap[$configLevelKey]) { return }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $paddedLevel = $Level.PadRight(5)
    $logLine = "$timestamp [$paddedLevel] $Message"

    if ($ErrorRecord) {
        $logLine += "`n$timestamp [$paddedLevel] Stack: $($ErrorRecord.ScriptStackTrace)"
    }

    # Write to PowerShell streams
    switch ($Level) {
        'ERROR' { Write-Error $Message -ErrorAction Continue }
        'WARN'  { Write-Warning $Message }
        'INFO'  { Write-Verbose $Message }
        'DEBUG' { Write-Debug $Message }
    }

    # Write to log file (unless -NoLog)
    if (-not $script:NoLogFile) {
        try {
            $logsDir = if ($script:ActiveConfig) {
                Join-Path $script:ActiveConfig.SessionsBasePath 'logs'
            } else {
                Join-Path ($env:USERPROFILE) 'OneDrive - Microsoft\Documents\CopilotChatSessions\logs'
            }

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
}

function Invoke-LogMaintenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $logsDir = Join-Path $Config.SessionsBasePath 'logs'
    if (-not (Test-Path $logsDir)) { return }

    $cutoff = (Get-Date).AddDays(-$Config.LogRetentionDays)
    Get-ChildItem -Path $logsDir -Filter 'copilot-exporter-*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Write-ExporterLog -Level DEBUG -Message "Log maintenance: pruned logs older than $($Config.LogRetentionDays) days"
}

# ============================================================================
# SYSTEM PATH RESOLUTION
# ============================================================================

function Resolve-SystemPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $paths = @{
        VSCodeEditions = @()
        StorageLocations = @()
    }

    # Detect VS Code editions
    $editions = @(
        @{ Name = 'Code - Insiders'; AppData = Join-Path $env:APPDATA 'Code - Insiders'; Format = 'jsonl' }
        @{ Name = 'Code';            AppData = Join-Path $env:APPDATA 'Code';            Format = 'json' }
    )

    foreach ($edition in $editions) {
        $userDir = Join-Path $edition.AppData 'User'
        if (Test-Path $userDir) {
            $paths.VSCodeEditions += $edition

            # Global (empty window) sessions
            $globalDir = Join-Path $userDir 'globalStorage\emptyWindowChatSessions'
            if (Test-Path $globalDir) {
                $paths.StorageLocations += @{
                    Path = $globalDir
                    Type = 'global'
                    Edition = $edition.Name
                    Format = $edition.Format
                }
            }

            # Workspace sessions
            $wsRoot = Join-Path $userDir 'workspaceStorage'
            if (Test-Path $wsRoot) {
                $paths.StorageLocations += @{
                    Path = $wsRoot
                    Type = 'workspace'
                    Edition = $edition.Name
                    Format = $edition.Format
                }
            }
        }
    }

    if ($paths.VSCodeEditions.Count -eq 0) {
        Write-ExporterLog -Level ERROR -Message 'No VS Code installation found (checked Code and Code - Insiders)'
        throw 'No VS Code installation found. Install VS Code or VS Code Insiders first.'
    }

    $editionNames = ($paths.VSCodeEditions | ForEach-Object { $_.Name }) -join ', '
    Write-ExporterLog -Level INFO -Message "Detected VS Code edition(s): $editionNames"

    # Validate SessionsBasePath
    $basePath = $Config.SessionsBasePath
    if (-not (Test-Path (Split-Path $basePath -Parent))) {
        # Parent doesn't exist — fall back to SystemDrive
        $fallback = Join-Path $env:SystemDrive 'CopilotChatSessions'
        Write-ExporterLog -Level WARN -Message "SessionsBasePath parent not found, falling back to: $fallback"
        $Config.SessionsBasePath = $fallback
    }

    # Warn about OneDrive (informational — user chose this deliberately)
    if ($Config.SessionsBasePath -match 'OneDrive') {
        Write-ExporterLog -Level INFO -Message 'Sessions will sync via OneDrive. Secret scan is mandatory.'
    }

    return $paths
}

# ============================================================================
# JSONL/JSON SESSION READER
# ============================================================================

function Read-CopilotChatSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Write-ExporterLog -Level ERROR -Message "Session file not found: $FilePath"
        return $null
    }

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()

    try {
        if ($extension -eq '.jsonl') {
            # JSONL incremental replay format (VS Code Insiders)
            $lines = [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)
            Write-ExporterLog -Level DEBUG -Message "Reading JSONL: $([System.IO.Path]::GetFileName($FilePath)) ($($lines.Count) lines)"

            if ($lines.Count -eq 0) { return $null }

            # Line 0: kind:0 — full session initialization
            $initEntry = $lines[0] | ConvertFrom-Json -Depth 50
            if ($initEntry.kind -ne 0) {
                Write-ExporterLog -Level WARN -Message "JSONL first line is not kind:0, skipping: $FilePath"
                return $null
            }

            $session = $initEntry.v

            # Replay incremental patches (lines 1+)
            $patchCount = 0
            for ($i = 1; $i -lt $lines.Count; $i++) {
                $line = $lines[$i].Trim()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                try {
                    $patch = $line | ConvertFrom-Json -Depth 50
                }
                catch {
                    Write-ExporterLog -Level DEBUG -Message "Skipping malformed JSONL line $i in $([System.IO.Path]::GetFileName($FilePath))"
                    continue
                }

                if ($null -eq $patch.k) { continue }

                # Navigate to the target location using the key path
                $keyPath = @($patch.k)
                $target = $session
                $parentTarget = $null
                $lastKey = $null

                for ($j = 0; $j -lt $keyPath.Count - 1; $j++) {
                    $key = $keyPath[$j]
                    $parentTarget = $target

                    if ($key -is [int] -or $key -match '^\d+$') {
                        $idx = [int]$key
                        if ($target -is [array] -or $target -is [System.Collections.IList]) {
                            if ($idx -lt $target.Count) {
                                $target = $target[$idx]
                            } else {
                                $target = $null
                                break
                            }
                        } else {
                            $target = $null
                            break
                        }
                    }
                    else {
                        if ($null -ne $target.$key) {
                            $target = $target.$key
                        }
                        elseif ($target -is [hashtable] -and $target.ContainsKey($key)) {
                            $target = $target[$key]
                        }
                        else {
                            $target = $null
                            break
                        }
                    }
                }

                if ($null -eq $target) { continue }

                $lastKey = $keyPath[-1]

                # Apply the patch
                switch ([int]$patch.kind) {
                    1 {
                        # kind:1 — set value at key path
                        if ($lastKey -is [int] -or $lastKey -match '^\d+$') {
                            $idx = [int]$lastKey
                            if ($target -is [array] -or $target -is [System.Collections.IList]) {
                                if ($idx -lt $target.Count) {
                                    $target[$idx] = $patch.v
                                }
                            }
                        }
                        else {
                            if ($target -is [PSCustomObject]) {
                                if ($null -ne $target.$lastKey) {
                                    $target.$lastKey = $patch.v
                                }
                                else {
                                    $target | Add-Member -NotePropertyName $lastKey -NotePropertyValue $patch.v -Force
                                }
                            }
                            elseif ($target -is [hashtable]) {
                                $target[$lastKey] = $patch.v
                            }
                        }
                        $patchCount++
                    }
                    2 {
                        # kind:2 — replace/append array at key path
                        if ($lastKey -is [int] -or $lastKey -match '^\d+$') {
                            $idx = [int]$lastKey
                            if ($target -is [array] -or $target -is [System.Collections.IList]) {
                                if ($idx -lt $target.Count) {
                                    $target[$idx] = $patch.v
                                }
                            }
                        }
                        else {
                            if ($target -is [PSCustomObject]) {
                                $target.$lastKey = $patch.v
                            }
                            elseif ($target -is [hashtable]) {
                                $target[$lastKey] = $patch.v
                            }
                        }
                        $patchCount++
                    }
                }
            }

            Write-ExporterLog -Level DEBUG -Message "JSONL replay: applied $patchCount patches"
            return $session
        }
        else {
            # Plain JSON format (regular VS Code)
            $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
            $session = $content | ConvertFrom-Json -Depth 50
            Write-ExporterLog -Level DEBUG -Message "Read JSON: $([System.IO.Path]::GetFileName($FilePath))"
            return $session
        }
    }
    catch {
        Write-ExporterLog -Level ERROR -Message "Failed to read session $FilePath : $_" -ErrorRecord $_
        return $null
    }
}

# ============================================================================
# SESSION ENUMERATOR
# ============================================================================

function Get-AllChatSessions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SystemPaths,

        [switch]$IncludeEmpty
    )

    $allSessions = @()

    foreach ($location in $SystemPaths.StorageLocations) {
        if ($location.Type -eq 'global') {
            # Global (empty window) sessions — files directly in the directory
            $pattern = if ($location.Format -eq 'jsonl') { '*.jsonl' } else { '*.json' }
            $files = Get-ChildItem -Path $location.Path -Filter $pattern -File -ErrorAction SilentlyContinue

            foreach ($file in $files) {
                $meta = Get-SessionMetadata -FilePath $file.FullName -Format $location.Format -Edition $location.Edition -WorkspacePath '(empty window)'
                if ($null -ne $meta) {
                    if ($IncludeEmpty -or $meta.RequestCount -gt 0) {
                        $allSessions += $meta
                    }
                }
            }
        }
        elseif ($location.Type -eq 'workspace') {
            # Workspace sessions — nested in hash-named subdirectories
            $wsDirs = Get-ChildItem -Path $location.Path -Directory -ErrorAction SilentlyContinue

            foreach ($wsDir in $wsDirs) {
                $chatDir = Join-Path $wsDir.FullName 'chatSessions'
                if (-not (Test-Path $chatDir)) { continue }

                # Resolve workspace path from workspace.json
                $workspacePath = '(unknown workspace)'
                $wsJsonPath = Join-Path $wsDir.FullName 'workspace.json'
                if (Test-Path $wsJsonPath) {
                    try {
                        $wsJson = Get-Content $wsJsonPath -Raw | ConvertFrom-Json
                        if ($wsJson.folder) {
                            $workspacePath = [Uri]::UnescapeDataString(($wsJson.folder -replace '^file:///', '' -replace '/', '\'))
                        }
                        elseif ($wsJson.workspace) {
                            $workspacePath = [Uri]::UnescapeDataString(($wsJson.workspace -replace '^file:///', '' -replace '/', '\'))
                        }
                    }
                    catch {
                        Write-ExporterLog -Level DEBUG -Message "Could not read workspace.json in $($wsDir.Name)"
                    }
                }

                $pattern = if ($location.Format -eq 'jsonl') { '*.jsonl' } else { '*.json' }
                $files = Get-ChildItem -Path $chatDir -Filter $pattern -File -ErrorAction SilentlyContinue

                foreach ($file in $files) {
                    $meta = Get-SessionMetadata -FilePath $file.FullName -Format $location.Format -Edition $location.Edition -WorkspacePath $workspacePath
                    if ($null -ne $meta) {
                        if ($IncludeEmpty -or $meta.RequestCount -gt 0) {
                            $allSessions += $meta
                        }
                    }
                }
            }
        }
    }

    # Sort by creation date descending (newest first)
    $allSessions = $allSessions | Sort-Object -Property CreationDate -Descending

    Write-ExporterLog -Level INFO -Message "Session scan: found $($allSessions.Count) non-empty session(s) across $($SystemPaths.VSCodeEditions.Count) edition(s)"
    return $allSessions
}

function Get-SessionMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Format,

        [Parameter(Mandatory)]
        [string]$Edition,

        [string]$WorkspacePath = '(unknown)'
    )

    try {
        $fileInfo = Get-Item $FilePath

        if ($Format -eq 'jsonl') {
            # Read only the first line (kind:0) for fast metadata extraction
            $firstLine = [System.IO.File]::ReadLines($FilePath, [System.Text.Encoding]::UTF8) |
                Select-Object -First 1

            if ([string]::IsNullOrWhiteSpace($firstLine)) { return $null }

            $init = $firstLine | ConvertFrom-Json -Depth 20
            if ($init.kind -ne 0) { return $null }
            $session = $init.v
        }
        else {
            $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
            $session = $content | ConvertFrom-Json -Depth 20
        }

        $requestCount = 0
        if ($session.requests -is [array]) {
            $requestCount = $session.requests.Count
        }

        $creationDate = [DateTime]::Now
        if ($session.creationDate) {
            $creationDate = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$session.creationDate).LocalDateTime
        }

        $model = 'unknown'
        if ($session.inputState -and $session.inputState.selectedModel -and $session.inputState.selectedModel.identifier) {
            $model = ($session.inputState.selectedModel.identifier -replace '^copilot/', '')
        }
        elseif ($session.requests -and $session.requests.Count -gt 0 -and $session.requests[0].modelId) {
            $model = ($session.requests[0].modelId -replace '^copilot/', '')
        }

        $title = ''
        if ($session.customTitle) {
            $title = $session.customTitle
        }

        $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        if ($session.sessionId) {
            $sessionId = $session.sessionId
        }

        # Get first user message preview (for INDEX.json)
        $preview = ''
        if ($session.requests -and $session.requests.Count -gt 0) {
            $firstReq = $session.requests[0]
            if ($firstReq.message -and $firstReq.message.text) {
                $preview = $firstReq.message.text
                if ($preview.Length -gt 200) {
                    $preview = $preview.Substring(0, 200) + '...'
                }
            }
        }

        return [PSCustomObject]@{
            SessionId    = $sessionId
            Title        = $title
            CreationDate = $creationDate
            Model        = $model
            RequestCount = $requestCount
            Edition      = $Edition
            WorkspacePath = $WorkspacePath
            SourcePath   = $FilePath
            FileSize     = $fileInfo.Length
            Preview      = $preview
        }
    }
    catch {
        Write-ExporterLog -Level DEBUG -Message "Could not read metadata from $([System.IO.Path]::GetFileName($FilePath)): $_"
        return $null
    }
}

# ============================================================================
# NATIVE POWERSHELL MARKDOWN CONVERTER
# ============================================================================

function ConvertTo-ChatMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$SessionData,

        [string]$ExportDate = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    )

    $sb = [System.Text.StringBuilder]::new(65536)

    # Header
    [void]$sb.AppendLine('# GitHub Copilot Chat Log')
    [void]$sb.AppendLine()

    $requester = if ($SessionData.requesterUsername) { $SessionData.requesterUsername } else { 'User' }
    $responder = if ($SessionData.responderUsername) { $SessionData.responderUsername } else { 'GitHub Copilot' }

    [void]$sb.AppendLine("**Participant:** $requester")
    [void]$sb.AppendLine("**Assistant:** $responder")
    [void]$sb.AppendLine("**Exported:** $ExportDate")
    [void]$sb.AppendLine()

    $requests = @()
    if ($SessionData.requests) {
        $requests = @($SessionData.requests)
    }

    if ($requests.Count -eq 0) {
        [void]$sb.AppendLine('*No messages in this session.*')
        return $sb.ToString()
    }

    # Table of Contents (if >1 request)
    if ($requests.Count -gt 1) {
        [void]$sb.AppendLine('## Table of Contents')
        [void]$sb.AppendLine()
        for ($i = 0; $i -lt $requests.Count; $i++) {
            $reqNum = $i + 1
            $preview = Get-RequestPreview -Request $requests[$i] -MaxLength 80
            [void]$sb.AppendLine("- [Request $reqNum](#request-$reqNum): $preview")
        }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine()
    }

    # Process each request
    for ($i = 0; $i -lt $requests.Count; $i++) {
        $reqNum = $i + 1
        $request = $requests[$i]

        [void]$sb.AppendLine("## Request $reqNum")
        [void]$sb.AppendLine()

        # User message
        $userText = Get-UserMessageText -Request $request
        if ($userText) {
            [void]$sb.AppendLine('### User')
            [void]$sb.AppendLine()
            [void]$sb.AppendLine($userText)
            [void]$sb.AppendLine()
        }

        # References/Variables
        if ($request.variableData -and $request.variableData.variables -and $request.variableData.variables.Count -gt 0) {
            [void]$sb.AppendLine('<details>')
            [void]$sb.AppendLine('<summary>References</summary>')
            [void]$sb.AppendLine()
            foreach ($variable in $request.variableData.variables) {
                $varName = if ($variable.name) { $variable.name } else { 'unnamed' }
                $varValue = if ($variable.value) {
                    $val = $variable.value.ToString()
                    if ($val.Length -gt 200) { $val.Substring(0, 200) + '...' } else { $val }
                } else { '' }
                [void]$sb.AppendLine("- **$varName**: $varValue")
            }
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('</details>')
            [void]$sb.AppendLine()
        }

        # Assistant response
        if ($request.response -and $request.response.Count -gt 0) {
            [void]$sb.AppendLine('### Assistant')
            [void]$sb.AppendLine()

            foreach ($part in $request.response) {
                $partText = Convert-ResponsePart -Part $part
                if ($partText) {
                    [void]$sb.AppendLine($partText)
                }
            }
            [void]$sb.AppendLine()
        }

        # Tool invocations from result metadata
        if ($request.result -and $request.result.metadata) {
            $toolRounds = $request.result.metadata.toolCallRounds
            if ($toolRounds -and $toolRounds.Count -gt 0) {
                foreach ($round in $toolRounds) {
                    if ($round.response -and $round.response.Count -gt 0) {
                        foreach ($toolCall in $round.response) {
                            $toolName = if ($toolCall.name) { $toolCall.name } else { 'tool' }
                            [void]$sb.AppendLine('<details>')
                            [void]$sb.AppendLine("<summary>Tool: $toolName</summary>")
                            [void]$sb.AppendLine()
                            if ($toolCall.parameters) {
                                [void]$sb.AppendLine('**Input:**')
                                $paramJson = $toolCall.parameters | ConvertTo-Json -Depth 5 -Compress
                                [void]$sb.AppendLine('```json')
                                [void]$sb.AppendLine($paramJson)
                                [void]$sb.AppendLine('```')
                            }
                            if ($toolCall.result) {
                                [void]$sb.AppendLine('**Output:**')
                                $resultText = if ($toolCall.result -is [string]) { $toolCall.result } else { $toolCall.result | ConvertTo-Json -Depth 5 }
                                $fence = if ($resultText -match '```') { '````' } else { '```' }
                                [void]$sb.AppendLine($fence)
                                [void]$sb.AppendLine($resultText)
                                [void]$sb.AppendLine($fence)
                            }
                            [void]$sb.AppendLine()
                            [void]$sb.AppendLine('</details>')
                            [void]$sb.AppendLine()
                        }
                    }
                }
            }
        }

        # Error display
        if ($request.result -and $request.result.errorDetails) {
            $errMsg = if ($request.result.errorDetails.message) { $request.result.errorDetails.message } else { 'Unknown error' }
            [void]$sb.AppendLine("> **Error:** $errMsg")
            [void]$sb.AppendLine()
        }

        # Metadata line
        $metaParts = @()
        if ($request.modelId) {
            $metaParts += "Model: $($request.modelId -replace '^copilot/', '')"
        }
        if ($request.result -and $request.result.timings -and $request.result.timings.totalElapsed) {
            $elapsed = [math]::Round($request.result.timings.totalElapsed / 1000, 1)
            $metaParts += "Time: ${elapsed}s"
        }
        if ($metaParts.Count -gt 0) {
            [void]$sb.AppendLine("*$($metaParts -join ' | ')*")
            [void]$sb.AppendLine()
        }

        # Navigation
        $navParts = @()
        if ($requests.Count -gt 1) { $navParts += '[^](#table-of-contents)' }
        if ($i -gt 0) { $navParts += "[< Request $i](#request-$i)" }
        if ($i -lt $requests.Count - 1) { $navParts += "[> Request $($reqNum + 1)](#request-$($reqNum + 1))" }
        if ($navParts.Count -gt 0) {
            [void]$sb.AppendLine($navParts -join ' | ')
            [void]$sb.AppendLine()
        }

        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine()
    }

    # Footer
    [void]$sb.AppendLine("*Exported by [GitHub Copilot Chat Exporter](https://github.com/ZacharyLuz/github-copilot-chat-exporter) v$script:ExporterVersion*")

    # Sanitize surrogates
    $result = $sb.ToString()
    $result = Remove-OrphanSurrogates -Text $result

    return $result
}

function Get-RequestPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Request,

        [int]$MaxLength = 80
    )

    $text = Get-UserMessageText -Request $Request
    if ([string]::IsNullOrWhiteSpace($text)) { return '(empty)' }

    # Take first line only, clean up
    $firstLine = ($text -split "`n")[0].Trim()
    if ($firstLine.Length -gt $MaxLength) {
        $firstLine = $firstLine.Substring(0, $MaxLength - 3) + '...'
    }
    return $firstLine
}

function Get-UserMessageText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Request
    )

    if ($Request.message) {
        if ($Request.message.text -and $Request.message.text -is [string]) {
            return $Request.message.text
        }
        if ($Request.message.parts -and $Request.message.parts.Count -gt 0) {
            $parts = foreach ($part in $Request.message.parts) {
                if ($part.text) { $part.text }
                elseif ($part.value) { $part.value }
            }
            return ($parts -join "`n")
        }
        if ($Request.message.value) {
            return $Request.message.value
        }
    }
    return ''
}

function Convert-ResponsePart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Part
    )

    if ($null -eq $Part) { return $null }

    # Simple string response
    if ($Part -is [string]) { return $Part }

    # Object with kind field
    $kind = if ($Part.kind) { $Part.kind } else { '' }

    switch ($kind) {
        'markdownContent' {
            if ($Part.content -and $Part.content.value) {
                return $Part.content.value
            }
            if ($Part.value) { return $Part.value }
            return $null
        }
        'textEditGroup' {
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('<details>')
            [void]$sb.AppendLine('<summary>File Edits</summary>')
            [void]$sb.AppendLine()
            if ($Part.edits) {
                foreach ($edit in $Part.edits) {
                    if ($edit.uri -or $edit.resource) {
                        $fileName = if ($edit.uri) { Split-Path $edit.uri -Leaf } else { Split-Path $edit.resource -Leaf }
                        [void]$sb.AppendLine("**$fileName**")
                    }
                    if ($edit.edits) {
                        foreach ($textEdit in $edit.edits) {
                            if ($textEdit.text -or $textEdit.newText) {
                                $editText = if ($textEdit.text) { $textEdit.text } else { $textEdit.newText }
                                $fence = if ($editText -match '```') { '````' } else { '```' }
                                [void]$sb.AppendLine($fence)
                                [void]$sb.AppendLine($editText)
                                [void]$sb.AppendLine($fence)
                            }
                        }
                    }
                }
            }
            [void]$sb.AppendLine('</details>')
            return $sb.ToString()
        }
        'toolInvocationSerialized' {
            return $null  # Handled via result.metadata.toolCallRounds
        }
        'progressTaskSerialized' {
            if ($Part.title) { return "- [x] $($Part.title)" }
            return $null
        }
        'inlineReference' {
            if ($Part.uri) { return "[$($Part.name)]($($Part.uri))" }
            if ($Part.name) { return "``$($Part.name)``" }
            return $null
        }
        'codeblockUri' {
            if ($Part.uri) {
                $fileName = Split-Path $Part.uri -Leaf
                return "See: ``$fileName``"
            }
            return $null
        }
        'thinking' {
            if ($Part.content -and $Part.content.value) {
                $thinkText = $Part.content.value
                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.AppendLine('<details>')
                [void]$sb.AppendLine('<summary>Thinking</summary>')
                [void]$sb.AppendLine()
                [void]$sb.AppendLine($thinkText)
                [void]$sb.AppendLine()
                [void]$sb.AppendLine('</details>')
                return $sb.ToString()
            }
            return $null
        }
        default {
            # Try to extract text from common patterns
            if ($Part.value -and $Part.value -is [string]) { return $Part.value }
            if ($Part.content -and $Part.content -is [string]) { return $Part.content }
            if ($Part.content -and $Part.content.value) { return $Part.content.value }
            if ($Part.text) { return $Part.text }

            if ($kind -and $kind -ne '') {
                Write-ExporterLog -Level DEBUG -Message "Unknown response part kind: $kind"
            }
            return $null
        }
    }
}

function Remove-OrphanSurrogates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    # In PowerShell/.NET, strings are UTF-16. Replace orphan surrogates with U+FFFD.
    $chars = $Text.ToCharArray()
    $result = [char[]]::new($chars.Length)
    $replaced = 0

    for ($i = 0; $i -lt $chars.Length; $i++) {
        if ([char]::IsHighSurrogate($chars[$i])) {
            if ($i + 1 -lt $chars.Length -and [char]::IsLowSurrogate($chars[$i + 1])) {
                # Valid surrogate pair — keep both
                $result[$i] = $chars[$i]
                $result[$i + 1] = $chars[$i + 1]
                $i++
            }
            else {
                # Orphan high surrogate
                $result[$i] = [char]0xFFFD
                $replaced++
            }
        }
        elseif ([char]::IsLowSurrogate($chars[$i])) {
            # Orphan low surrogate
            $result[$i] = [char]0xFFFD
            $replaced++
        }
        else {
            $result[$i] = $chars[$i]
        }
    }

    if ($replaced -gt 0) {
        Write-ExporterLog -Level WARN -Message "Replaced $replaced orphan surrogate character(s) with U+FFFD"
    }

    return [string]::new($result)
}

# ============================================================================
# SMART TOPIC EXTRACTION (fallback when customTitle is missing)
# ============================================================================

function Get-SmartTopic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ChatData,

        [int]$MaxLength = 50,
        [int]$WordCount = 4
    )

    $stopWords = @(
        'a','an','the','and','or','but','in','on','at','to','for','of','with','by',
        'from','as','is','was','are','were','been','be','have','has','had','do','does',
        'did','will','would','could','should','may','might','must','shall','can',
        'i','me','my','myself','we','our','ours','you','your','yours','he','him','his',
        'she','her','hers','it','its','they','them','their','this','that','these','those',
        'what','which','who','whom','when','where','why','how','all','each','every',
        'both','few','more','most','other','some','such','no','nor','not','only','own',
        'same','so','than','too','very','just','also','now','here','there','then',
        'please','thanks','thank','hello','hi','hey','help','need','want','like','know',
        'think','see','look','make','get','got','going','go','come','take','use','using',
        'used','try','trying','way','thing','something','anything','everything','nothing',
        'sure','okay','ok','yes','maybe','well','really','actually','basically',
        'question','problem','issue','work','working','works','doesnt','dont','cant','wont',
        'im','ive','id','ill','youre','youve','youd','youll','hes','shes','were',
        'theyre','theyve','theyd','theyll','isnt','arent','wasnt','werent','hasnt','havent',
        'hadnt','doesnt','didnt','wont','wouldnt','couldnt','shouldnt','cannot',
        'mustnt','lets','thats','whats','heres','theres','whos','wheres','whens','whys','hows',
        'about','after','before','above','below','between','into','through','during','under',
        'again','further','once','any','being','having','doing','because','until','while'
    )

    $techPatterns = @(
        'azure','aws','gcp','docker','kubernetes','k8s','terraform','ansible',
        'api','rest','graphql','oauth','jwt','auth','authentication','authorization',
        'database','sql','nosql','mongodb','postgres','mysql','redis',
        'git','github','gitlab','cicd','pipeline','deploy','deployment',
        'powershell','bash','script','automation','cli',
        'react','angular','vue','node','express','django','flask',
        'security','encryption','ssl','tls','certificate','credential',
        'performance','optimization','cache','memory',
        'config','configuration','environment'
    )

    $actionVerbs = @(
        'fix','debug','implement','create','add','remove','update','upgrade',
        'refactor','optimize','migrate','deploy','configure','setup','install',
        'build','test','validate','parse','convert','transform','generate',
        'automate','integrate','connect','authenticate','encrypt',
        'troubleshoot','diagnose','analyze','monitor'
    )

    # Collect user messages
    $allText = @()
    if ($ChatData.requests) {
        foreach ($request in @($ChatData.requests)) {
            $msg = Get-UserMessageText -Request $request
            if ($msg) { $allText += $msg }
        }
    }

    $combinedText = $allText -join ' '
    $words = $combinedText -split '\s+' |
        ForEach-Object { ($_ -replace '[^\w\-\.]', '' -replace '^[\-\.]+', '' -replace '[\-\.]+$', '').ToLower() } |
        Where-Object { $_.Length -gt 2 }

    $wordScores = @{}
    foreach ($word in $words) {
        if ($stopWords -contains $word) { continue }
        if (-not $wordScores.ContainsKey($word)) { $wordScores[$word] = 0 }
        $wordScores[$word] += 1
        if ($techPatterns -contains $word) { $wordScores[$word] += 5 }
        if ($actionVerbs -contains $word) { $wordScores[$word] += 3 }
        if ($word -match '\.\w{2,4}$') { $wordScores[$word] += 4 }
    }

    $topWords = $wordScores.GetEnumerator() |
        Sort-Object -Property Value -Descending |
        Select-Object -First ($WordCount * 2) |
        ForEach-Object { $_.Key }

    $selectedWords = @()
    foreach ($word in $topWords) {
        if ($selectedWords.Count -ge $WordCount) { break }
        $isDuplicate = $false
        foreach ($existing in $selectedWords) {
            if ($word -like "$existing*" -or $existing -like "$word*") { $isDuplicate = $true; break }
        }
        if (-not $isDuplicate) { $selectedWords += $word }
    }

    $topic = ($selectedWords -join '-') -replace '-+', '-' -replace '^-|-$', ''
    if ($topic.Length -gt $MaxLength) { $topic = $topic.Substring(0, $MaxLength).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($topic)) { $topic = 'chat-session' }

    return $topic
}

# ============================================================================
# SECRET DETECTION (MANDATORY GATE — OneDrive sync requires zero secrets)
# ============================================================================

function Find-PotentialSecrets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $findings = @()

    $placeholderPatterns = @(
        '<[^>]+>', '\$\{[^}]+\}', '\{\{[^}]+\}\}', '\[\[[^\]]+\]\]',
        'your[_-]?\w+', 'example\w*', 'sample\w*', 'placeholder',
        'changeme', 'xxx+', '\*{3,}', 'TBD', 'TODO', 'REPLACE_?ME'
    )

    $secretPatterns = @(
        @{ Name = 'AWS Access Key';   Pattern = 'AKIA[0-9A-Z]{16}'; ValueGroup = 0 }
        @{ Name = 'AWS Secret Key';   Pattern = '(?i)aws[_\-]?secret[_\-]?access[_\-]?key["'':\s=]+([A-Za-z0-9/+=]{40})'; ValueGroup = 1 }
        @{ Name = 'GitHub Token';     Pattern = 'ghp_[A-Za-z0-9]{36}'; ValueGroup = 0 }
        @{ Name = 'GitHub PAT';       Pattern = 'github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}'; ValueGroup = 0 }
        @{ Name = 'Azure Storage Key'; Pattern = '(?i)AccountKey\s*=\s*([A-Za-z0-9+/]{86}==)'; ValueGroup = 1 }
        @{ Name = 'Azure SAS Token';  Pattern = 'sig=[A-Za-z0-9%]{43,}'; ValueGroup = 0 }
        @{ Name = 'JWT Token';        Pattern = 'eyJ[A-Za-z0-9\-_]{10,}\.eyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}'; ValueGroup = 0 }
        @{ Name = 'Private Key';      Pattern = '-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----'; ValueGroup = 0 }
        @{ Name = 'Bearer Token';     Pattern = '(?i)bearer\s+([A-Za-z0-9\-_\.]{40,})'; ValueGroup = 1 }
        @{ Name = 'Hardcoded password'; Pattern = '(?i)(?:password|passwd|pwd)\s*[=:]\s*[''"]([^''"<>\$\{\}]{8,})[''"]'; ValueGroup = 1 }
        @{ Name = 'Hardcoded secret'; Pattern = '(?i)(?:secret|api_?key)\s*[=:]\s*[''"]([^''"<>\$\{\}]{12,})[''"]'; ValueGroup = 1 }
        @{ Name = 'Connection string password'; Pattern = '(?i)(?:Password|Pwd)\s*=\s*([^;<>\$\{\}''"]{8,})(?:;|$)'; ValueGroup = 1 }
    )

    foreach ($pattern in $secretPatterns) {
        $regexMatches = [regex]::Matches($Content, $pattern.Pattern)
        foreach ($match in $regexMatches) {
            $secretValue = if ($pattern.ValueGroup -eq 0) { $match.Value } else { $match.Groups[$pattern.ValueGroup].Value }

            $isPlaceholder = $false
            foreach ($ph in $placeholderPatterns) {
                if ($secretValue -match $ph) { $isPlaceholder = $true; break }
            }
            if ($isPlaceholder) { continue }
            if ($secretValue.Length -lt 8) { continue }
            if (($secretValue.ToCharArray() | Select-Object -Unique).Count -lt 4) { continue }

            $startIdx = [Math]::Max(0, $match.Index - 20)
            $len = [Math]::Min(80, $Content.Length - $startIdx)
            $context = $Content.Substring($startIdx, $len) -replace '[\r\n]+', ' '

            $masked = if ($secretValue.Length -gt 6) {
                $secretValue.Substring(0, 3) + ('*' * [Math]::Min(8, $secretValue.Length - 6)) + $secretValue.Substring($secretValue.Length - 3)
            } else { '***' }

            $findings += [PSCustomObject]@{
                Type = $pattern.Name
                Match = $match.Value
                SecretValue = $secretValue
                Context = ($context -replace [regex]::Escape($secretValue), $masked).Trim()
                Index = $match.Index
            }
        }
    }

    # Deduplicate by secret value
    $seen = @{}
    $unique = foreach ($f in $findings) {
        if (-not $seen.ContainsKey($f.SecretValue)) {
            $seen[$f.SecretValue] = $true
            $f
        }
    }

    return @($unique)
}

function Invoke-SecretRedaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [array]$Findings
    )

    $redacted = $Content
    $secretValues = $Findings | ForEach-Object { $_.SecretValue } | Select-Object -Unique
    foreach ($sv in $secretValues) {
        $redacted = $redacted -replace [regex]::Escape($sv), '[REDACTED]'
    }
    return $redacted
}

function Invoke-SecretGate {
    <#
    .SYNOPSIS
        Mandatory secret scan. Blocks export if secrets found (OneDrive sync protection).
        Only offers Redact or Cancel — no "Proceed with secrets" option.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MarkdownContent,

        [switch]$SkipScan,
        [switch]$ForceSkip
    )

    if ($SkipScan -and $ForceSkip) {
        Write-ExporterLog -Level WARN -Message 'Secret scan SKIPPED by user with -SkipSecretScan -Force. Secrets may sync to OneDrive.'
        Write-Warning 'Secret scan skipped. If this chat contains secrets, they WILL sync to OneDrive.'
        return @{ Action = 'proceed'; Content = $MarkdownContent; SecretsFound = 0 }
    }

    if ($SkipScan -and -not $ForceSkip) {
        Write-Warning '-SkipSecretScan requires -Force because sessions sync to OneDrive. Running scan anyway.'
    }

    $findings = Find-PotentialSecrets -Content $MarkdownContent

    if ($findings.Count -eq 0) {
        Write-ExporterLog -Level INFO -Message 'Secret scan: clean (0 findings)'
        Write-Host '  Security scan: clean' -ForegroundColor Green
        return @{ Action = 'proceed'; Content = $MarkdownContent; SecretsFound = 0 }
    }

    Write-ExporterLog -Level WARN -Message "Secret scan: $($findings.Count) potential secret(s) detected"

    # Display findings
    $grouped = $findings | Group-Object -Property Type
    Write-Host ''
    Write-Host '  WARNING: Potential secrets detected!' -ForegroundColor Red
    Write-Host "  Found $($findings.Count) potential secret(s):" -ForegroundColor Yellow
    Write-Host ''

    foreach ($group in $grouped) {
        Write-Host "    [$($group.Name)] - $($group.Count) occurrence(s)" -ForegroundColor Yellow
        foreach ($finding in $group.Group | Select-Object -First 2) {
            Write-Host "      ...$($finding.Context)..." -ForegroundColor Gray
        }
    }

    Write-Host ''
    Write-Host '  Sessions sync to OneDrive — secrets cannot be exported.' -ForegroundColor Red
    Write-Host '    [R] Redact - replace secrets with [REDACTED] and proceed' -ForegroundColor White
    Write-Host '    [C] Cancel - abort this export' -ForegroundColor White
    Write-Host ''

    do {
        $choice = (Read-Host '  Choice (R/C)').ToUpper()
    } while ($choice -notin @('R', 'C'))

    switch ($choice) {
        'R' {
            Write-ExporterLog -Level INFO -Message "Redacting $($findings.Count) secret(s)"
            $redacted = Invoke-SecretRedaction -Content $MarkdownContent -Findings $findings
            Write-Host "  Redacted $($findings.Count) secret(s)" -ForegroundColor Green
            return @{ Action = 'redact'; Content = $redacted; SecretsFound = $findings.Count }
        }
        'C' {
            Write-ExporterLog -Level INFO -Message 'Export cancelled by user due to secrets'
            return @{ Action = 'cancel'; Content = $null; SecretsFound = $findings.Count }
        }
    }
}

# ============================================================================
# SESSION PICKER
# ============================================================================

function Select-ChatSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Sessions,

        [hashtable]$Config,
        [switch]$ShowList,
        [guid]$SpecificSession
    )

    if ($null -ne $SpecificSession -and $SpecificSession -ne [guid]::Empty) {
        $match = $Sessions | Where-Object { $_.SessionId -eq $SpecificSession.ToString() }
        if ($match) { return @($match) }
        Write-ExporterLog -Level ERROR -Message "Session not found: $SpecificSession"
        throw "Session ID '$SpecificSession' not found in available sessions."
    }

    if ($Sessions.Count -eq 0) {
        throw 'No chat sessions found in VS Code storage.'
    }

    if (-not $ShowList) {
        # Auto-select latest
        $latest = $Sessions[0]
        $dateStr = $latest.CreationDate.ToString('yyyy-MM-dd HH:mm')
        $title = if ($latest.Title) { $latest.Title } else { '(untitled)' }
        $model = $latest.Model

        Write-Host ''
        Write-Host "  Export: `"$title`"" -ForegroundColor Cyan
        Write-Host "  ($dateStr, $model, $($latest.RequestCount) turns, $($latest.WorkspacePath))" -ForegroundColor Gray
        Write-Host ''

        $confirm = Read-Host '  Proceed? [Y/n]'
        if ($confirm -eq '' -or $confirm -match '^[Yy]') {
            return @($latest)
        }
        # Fall through to list view
    }

    # Paginated list view
    $maxSessions = [Math]::Min($Config.MaxSessionsToList, $Sessions.Count)
    $pageSize = $Config.PageSize
    $totalPages = [Math]::Ceiling($maxSessions / $pageSize)
    $currentPage = 0

    while ($true) {
        $startIdx = $currentPage * $pageSize
        $endIdx = [Math]::Min($startIdx + $pageSize, $maxSessions) - 1

        Write-Host ''
        Write-Host "  === Recent Sessions (Page $($currentPage + 1) of $totalPages) ===" -ForegroundColor Cyan
        Write-Host ''
        Write-Host ('  {0,-4} {1,-12} {2,-30} {3,-15} {4}' -f '#', 'Date', 'Topic', 'Model', 'Turns') -ForegroundColor DarkGray
        Write-Host ('  {0}' -f ('-' * 75)) -ForegroundColor DarkGray

        for ($i = $startIdx; $i -le $endIdx; $i++) {
            $s = $Sessions[$i]
            $num = $i + 1
            $date = $s.CreationDate.ToString('yyyy-MM-dd')
            $title = if ($s.Title) { $s.Title } else { '(untitled)' }
            if ($title.Length -gt 28) { $title = $title.Substring(0, 25) + '...' }
            $model = $s.Model
            if ($model.Length -gt 13) { $model = $model.Substring(0, 10) + '...' }

            Write-Host ('  {0,-4} {1,-12} {2,-30} {3,-15} {4}' -f $num, $date, $title, $model, $s.RequestCount)
        }

        Write-Host ''
        $navOptions = @()
        if ($currentPage -lt $totalPages - 1) { $navOptions += '[N]ext' }
        if ($currentPage -gt 0) { $navOptions += '[P]rev' }
        $navOptions += '[#] Select'
        $navOptions += '[A]ll'
        $navOptions += '[Q]uit'
        Write-Host "  $($navOptions -join '  ')" -ForegroundColor DarkGray
        Write-Host ''

        $input = Read-Host '  Select'
        $input = $input.Trim()

        switch -Regex ($input) {
            '^[Nn]$' {
                if ($currentPage -lt $totalPages - 1) { $currentPage++ }
                continue
            }
            '^[Pp]$' {
                if ($currentPage -gt 0) { $currentPage-- }
                continue
            }
            '^[Qq]$' {
                Write-Host '  Cancelled.' -ForegroundColor Yellow
                return @()
            }
            '^[Aa]$' {
                return @($Sessions[0..($maxSessions - 1)])
            }
            '^(\d+)-(\d+)$' {
                $rangeStart = [int]$Matches[1] - 1
                $rangeEnd = [int]$Matches[2] - 1
                $rangeStart = [Math]::Max(0, $rangeStart)
                $rangeEnd = [Math]::Min($maxSessions - 1, $rangeEnd)
                return @($Sessions[$rangeStart..$rangeEnd])
            }
            '^[\d,\s]+$' {
                $indices = $input -split '[,\s]+' | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $maxSessions }
                return @($Sessions[$indices])
            }
        }
    }
}

# ============================================================================
# INDEX MANAGEMENT
# ============================================================================

function Update-ChatIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [PSCustomObject]$SessionMeta,

        [Parameter(Mandatory)]
        [string]$ExportedFilePath
    )

    $basePath = $Config.SessionsBasePath
    $indexMdPath = Join-Path $basePath 'INDEX.md'
    $indexJsonPath = Join-Path $basePath 'INDEX.json'

    # Relative path for the markdown file link
    $relativePath = $ExportedFilePath.Replace($basePath, '').TrimStart('\', '/')

    $title = if ($SessionMeta.Title) { $SessionMeta.Title } else { [System.IO.Path]::GetFileNameWithoutExtension($ExportedFilePath) }
    $dateStr = $SessionMeta.CreationDate.ToString('yyyy-MM-dd')
    $workspace = if ($SessionMeta.WorkspacePath -and $SessionMeta.WorkspacePath -ne '(empty window)') {
        Split-Path $SessionMeta.WorkspacePath -Leaf
    } else { '—' }

    # === INDEX.json ===
    $indexEntries = @()
    if (Test-Path $indexJsonPath) {
        try {
            $indexEntries = @(Get-Content $indexJsonPath -Raw | ConvertFrom-Json)
        }
        catch {
            Write-ExporterLog -Level WARN -Message "Could not parse INDEX.json, rebuilding"
            $indexEntries = @()
        }
    }

    # Check for duplicate
    $existingIdx = -1
    for ($i = 0; $i -lt $indexEntries.Count; $i++) {
        if ($indexEntries[$i].sessionId -eq $SessionMeta.SessionId) {
            $existingIdx = $i
            break
        }
    }

    $newEntry = [PSCustomObject]@{
        sessionId = $SessionMeta.SessionId
        title     = $title
        date      = $dateStr
        model     = $SessionMeta.Model
        workspace = $workspace
        turns     = $SessionMeta.RequestCount
        file      = $relativePath
        exported  = $true
        preview   = $SessionMeta.Preview
    }

    if ($existingIdx -ge 0) {
        $indexEntries[$existingIdx] = $newEntry
    }
    else {
        $indexEntries = @($newEntry) + $indexEntries
    }

    $indexEntries | ConvertTo-Json -Depth 5 | Set-Content -Path $indexJsonPath -Encoding UTF8
    Write-ExporterLog -Level DEBUG -Message "INDEX.json updated ($($indexEntries.Count) entries)"

    # === INDEX.md ===
    $mdSb = [System.Text.StringBuilder]::new()
    [void]$mdSb.AppendLine('# Copilot Chat Sessions Index')
    [void]$mdSb.AppendLine()
    [void]$mdSb.AppendLine("*Auto-generated by [Copilot Chat Exporter](https://github.com/ZacharyLuz/github-copilot-chat-exporter) v$script:ExporterVersion — $(Get-Date -Format 'yyyy-MM-dd HH:mm')*")
    [void]$mdSb.AppendLine()
    [void]$mdSb.AppendLine('| Date | Topic | Model | Workspace | Turns |')
    [void]$mdSb.AppendLine('|------|-------|-------|-----------|-------|')

    foreach ($entry in $indexEntries) {
        $link = "[$($entry.title)]($($entry.file))"
        [void]$mdSb.AppendLine("| $($entry.date) | $link | $($entry.model) | $($entry.workspace) | $($entry.turns) |")
    }

    Set-Content -Path $indexMdPath -Value $mdSb.ToString() -Encoding UTF8
    Write-ExporterLog -Level INFO -Message "Index updated: $($indexEntries.Count) total entries"
}

# ============================================================================
# WORKSPACE SYMLINKS
# ============================================================================

function New-WorkspaceChatLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CentralFilePath,

        [Parameter(Mandatory)]
        [string]$WorkspacePath,

        [switch]$Disabled
    )

    if ($Disabled) { return }
    if ($WorkspacePath -eq '(empty window)' -or $WorkspacePath -eq '(unknown workspace)') { return }

    # Resolve workspace root (handle .code-workspace files and Insiders Workspaces)
    if ($WorkspacePath -match '\.code-workspace$' -or $WorkspacePath -match 'Insiders Workspaces') {
        Write-ExporterLog -Level DEBUG -Message "Skipping workspace link for non-folder workspace: $WorkspacePath"
        return
    }

    if (-not (Test-Path $WorkspacePath -PathType Container)) {
        Write-ExporterLog -Level DEBUG -Message "Workspace path not found, skipping link: $WorkspacePath"
        return
    }

    $chatDir = Join-Path $WorkspacePath '.copilot-chats'
    $linkName = Split-Path $CentralFilePath -Leaf
    $linkPath = Join-Path $chatDir $linkName

    try {
        # Create .copilot-chats directory
        if (-not (Test-Path $chatDir)) {
            New-Item -ItemType Directory -Path $chatDir -Force | Out-Null
        }

        # Create symbolic link
        try {
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $CentralFilePath -Force | Out-Null
            Write-ExporterLog -Level INFO -Message "Symlink created: $linkPath"
        }
        catch {
            # Symlink failed (no developer mode) — create .lnk shortcut instead
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut("$linkPath.lnk")
            $shortcut.TargetPath = $CentralFilePath
            $shortcut.Save()
            Write-ExporterLog -Level INFO -Message "Shortcut created (symlink unavailable): $linkPath.lnk"
        }

        # Auto-add .copilot-chats/ to .gitignore
        $gitignorePath = Join-Path $WorkspacePath '.gitignore'
        if (Test-Path $gitignorePath) {
            $gitignoreContent = Get-Content $gitignorePath -Raw -ErrorAction SilentlyContinue
            if ($gitignoreContent -and $gitignoreContent -notmatch '\.copilot-chats') {
                Add-Content -Path $gitignorePath -Value "`n# Copilot chat session links`n.copilot-chats/" -Encoding UTF8
                Write-ExporterLog -Level INFO -Message "Added .copilot-chats/ to $gitignorePath"
            }
        }
    }
    catch {
        Write-ExporterLog -Level WARN -Message "Could not create workspace link: $_"
    }
}

# ============================================================================
# CATALOG BUILDER
# ============================================================================

function Build-ChatCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Sessions,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $basePath = $Config.SessionsBasePath
    if (-not (Test-Path $basePath)) {
        New-Item -ItemType Directory -Path $basePath -Force | Out-Null
    }

    $indexJsonPath = Join-Path $basePath 'INDEX.json'
    $indexMdPath = Join-Path $basePath 'INDEX.md'

    # Load existing index to preserve export status
    $existingIndex = @{}
    if (Test-Path $indexJsonPath) {
        try {
            $existing = Get-Content $indexJsonPath -Raw | ConvertFrom-Json
            foreach ($e in $existing) {
                if ($e.sessionId) { $existingIndex[$e.sessionId] = $e }
            }
        }
        catch { }
    }

    # Build entries for all sessions
    $entries = foreach ($s in $Sessions) {
        $title = if ($s.Title) { $s.Title } else { '(untitled)' }
        $dateStr = $s.CreationDate.ToString('yyyy-MM-dd')
        $workspace = if ($s.WorkspacePath -and $s.WorkspacePath -ne '(empty window)') {
            Split-Path $s.WorkspacePath -Leaf
        } else { '—' }

        $isExported = $false
        $exportedFile = ''
        if ($existingIndex.ContainsKey($s.SessionId)) {
            $isExported = [bool]$existingIndex[$s.SessionId].exported
            $exportedFile = $existingIndex[$s.SessionId].file
        }

        [PSCustomObject]@{
            sessionId = $s.SessionId
            title     = $title
            date      = $dateStr
            model     = $s.Model
            workspace = $workspace
            turns     = $s.RequestCount
            file      = $exportedFile
            exported  = $isExported
            preview   = $s.Preview
        }
    }

    # Write INDEX.json
    @($entries) | ConvertTo-Json -Depth 5 | Set-Content -Path $indexJsonPath -Encoding UTF8

    # Write INDEX.md
    $mdSb = [System.Text.StringBuilder]::new()
    [void]$mdSb.AppendLine('# Copilot Chat Sessions Index')
    [void]$mdSb.AppendLine()
    [void]$mdSb.AppendLine("*Auto-generated by [Copilot Chat Exporter](https://github.com/ZacharyLuz/github-copilot-chat-exporter) v$script:ExporterVersion — $(Get-Date -Format 'yyyy-MM-dd HH:mm')*")
    [void]$mdSb.AppendLine()

    $exportedCount = ($entries | Where-Object { $_.exported }).Count
    $totalCount = $entries.Count
    [void]$mdSb.AppendLine("**Total:** $totalCount sessions | **Exported:** $exportedCount | **Pending:** $($totalCount - $exportedCount)")
    [void]$mdSb.AppendLine()

    [void]$mdSb.AppendLine('| Date | Topic | Model | Workspace | Turns | Exported |')
    [void]$mdSb.AppendLine('|------|-------|-------|-----------|-------|----------|')

    foreach ($entry in $entries) {
        $titleDisplay = if ($entry.exported -and $entry.file) { "[$($entry.title)]($($entry.file))" } else { $entry.title }
        $exportStatus = if ($entry.exported) { 'yes' } else { '—' }
        [void]$mdSb.AppendLine("| $($entry.date) | $titleDisplay | $($entry.model) | $($entry.workspace) | $($entry.turns) | $exportStatus |")
    }

    Set-Content -Path $indexMdPath -Value $mdSb.ToString() -Encoding UTF8

    Write-ExporterLog -Level INFO -Message "Catalog built: $totalCount sessions ($exportedCount exported)"
    Write-Host ''
    Write-Host "  Catalog built: $totalCount sessions ($exportedCount previously exported)" -ForegroundColor Green
    Write-Host "  INDEX.md:   $indexMdPath" -ForegroundColor Gray
    Write-Host "  INDEX.json: $indexJsonPath" -ForegroundColor Gray
}

# ============================================================================
# EXPORT ORCHESTRATOR
# ============================================================================

function Export-SingleSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$SessionMeta,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [string]$TopicOverride,
        [switch]$SkipSecretScan,
        [switch]$ForceSkip,
        [switch]$NoWorkspaceLink
    )

    $title = if ($SessionMeta.Title) { $SessionMeta.Title } else { '(untitled)' }
    Write-ExporterLog -Level INFO -Message "Exporting: `"$title`" ($($SessionMeta.RequestCount) turns)"

    # Step 1: Read full session
    Write-Host "  Reading session..." -ForegroundColor Gray -NoNewline
    $sessionData = Read-CopilotChatSession -FilePath $SessionMeta.SourcePath
    if ($null -eq $sessionData) {
        Write-Host ' FAILED' -ForegroundColor Red
        Write-ExporterLog -Level ERROR -Message "Could not read session: $($SessionMeta.SourcePath)"
        return $null
    }
    Write-Host ' OK' -ForegroundColor Green

    # Step 2: Resolve topic
    if ($TopicOverride) {
        $topicSlug = $TopicOverride -replace '[\\\/:*?"<>|]', '-' -replace '\s+', '-' -replace '-+', '-'
        $topicSlug = $topicSlug.ToLower().Trim('-')
    }
    elseif ($SessionMeta.Title) {
        $topicSlug = $SessionMeta.Title -replace '[\\\/:*?"<>|]', '-' -replace '\s+', '-' -replace '-+', '-'
        $topicSlug = $topicSlug.ToLower().Trim('-')
        if ($topicSlug.Length -gt $Config.TopicMaxLength) {
            $topicSlug = $topicSlug.Substring(0, $Config.TopicMaxLength).TrimEnd('-')
        }
    }
    else {
        $topicSlug = Get-SmartTopic -ChatData $sessionData -MaxLength $Config.TopicMaxLength -WordCount $Config.TopicWordCount
    }
    Write-ExporterLog -Level INFO -Message "Topic: $topicSlug"

    # Step 3: Convert to markdown
    Write-Host "  Converting to markdown..." -ForegroundColor Gray -NoNewline
    $markdown = ConvertTo-ChatMarkdown -SessionData $sessionData
    Write-Host ' OK' -ForegroundColor Green

    # Step 4: Secret gate (mandatory)
    $gateResult = Invoke-SecretGate -MarkdownContent $markdown -SkipScan:$SkipSecretScan -ForceSkip:$ForceSkip
    if ($gateResult.Action -eq 'cancel') {
        Write-Host '  Export cancelled.' -ForegroundColor Yellow
        return $null
    }
    $markdown = $gateResult.Content

    # Step 5: Save file
    $yearMonth = $SessionMeta.CreationDate.ToString($Config.YearMonthFormat)
    $dateStr = $SessionMeta.CreationDate.ToString($Config.DateFormat)
    $timestamp = $SessionMeta.CreationDate.ToString($Config.TimestampFormat)
    $sessionsDir = Join-Path $Config.SessionsBasePath $yearMonth

    if (-not (Test-Path $sessionsDir)) {
        New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null
    }

    $fileName = "${dateStr}_${timestamp}_${topicSlug}.md"
    $outputPath = Join-Path $sessionsDir $fileName

    # Handle duplicate filenames
    $counter = 1
    while (Test-Path $outputPath) {
        $fileName = "${dateStr}_${timestamp}_${topicSlug}_${counter}.md"
        $outputPath = Join-Path $sessionsDir $fileName
        $counter++
    }

    Set-Content -Path $outputPath -Value $markdown -Encoding UTF8
    $fileSize = [math]::Round((Get-Item $outputPath).Length / 1KB, 1)
    Write-ExporterLog -Level INFO -Message "Saved: $outputPath ($fileSize KB)"
    Write-Host "  Saved: $fileName ($fileSize KB)" -ForegroundColor Green

    # Step 6: Update index
    Update-ChatIndex -Config $Config -SessionMeta $SessionMeta -ExportedFilePath $outputPath

    # Step 7: Workspace symlink
    if (-not $NoWorkspaceLink -and $Config.WorkspaceLinkEnabled) {
        New-WorkspaceChatLink -CentralFilePath $outputPath -WorkspacePath $SessionMeta.WorkspacePath -Disabled:$NoWorkspaceLink
    }

    return $outputPath
}

# ============================================================================
# SENDKEYS FALLBACK (opt-in via -UseSendKeys)
# ============================================================================

function Invoke-SendKeysExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Write-ExporterLog -Level INFO -Message 'Using SendKeys fallback for export'
    Write-Host '  Using SendKeys automation (legacy mode)...' -ForegroundColor Yellow

    # Prepare temp file path
    $date = Get-Date -Format $Config.DateFormat
    $timestamp = Get-Date -Format $Config.TimestampFormat
    $jsonFilename = "$($Config.JsonFilePrefix)-${date}_${timestamp}.json"
    $jsonFullPath = Join-Path $Config.TempPath $jsonFilename
    $jsonFullPath | Set-Clipboard

    # Find VS Code process (handle both editions)
    $vscode = Get-Process -Name 'Code - Insiders' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $vscode) {
        $vscode = Get-Process -Name 'Code' -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if (-not $vscode) {
        throw 'VS Code is not running. Start VS Code first, or use direct read mode (remove -UseSendKeys).'
    }

    # Focus VS Code and send keys
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

    $null = [WinAPI]::SetForegroundWindow($vscode.MainWindowHandle)
    Start-Sleep -Milliseconds 500

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait('{F1}')
    Start-Sleep -Milliseconds $Config.KeyDelay_Initial
    [System.Windows.Forms.SendKeys]::SendWait('Chat: Export Chat')
    Start-Sleep -Milliseconds $Config.KeyDelay_Command
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds $Config.KeyDelay_Execute
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds $Config.KeyDelay_Paste
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')

    Write-Host '  Waiting for export file...' -ForegroundColor Gray

    # File watcher with timeout
    $elapsed = 0
    while (-not (Test-Path $jsonFullPath) -and $elapsed -lt $Config.FileWatchTimeout) {
        Start-Sleep -Seconds $Config.FileWatchInterval
        $elapsed += $Config.FileWatchInterval
    }

    if (-not (Test-Path $jsonFullPath)) {
        Write-ExporterLog -Level ERROR -Message "SendKeys export timed out after $($Config.FileWatchTimeout)s"
        throw @"
Timeout waiting for export file ($($Config.FileWatchTimeout) seconds)

Expected file: $jsonFullPath

This usually means:
  - VS Code export dialog was cancelled or closed
  - A different VS Code window was focused
  - The export saved to an unexpected location

Suggestion: Use 'save-githubchat' without -UseSendKeys (default).
The direct read method doesn't require VS Code interaction.

Log: $(Join-Path $Config.SessionsBasePath 'logs')
"@
    }

    # Read the exported JSON and convert
    $jsonContent = Get-Content $jsonFullPath -Raw -Encoding UTF8
    $sessionData = $jsonContent | ConvertFrom-Json -Depth 50

    # Clean up temp file
    Remove-Item -Path $jsonFullPath -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $Config.TempPath -Filter 'CHAT-EXPORT-*.json' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    return $sessionData
}

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================

# Set script-level state
$script:NoLogFile = $NoLog.IsPresent
$script:ActiveConfig = Get-ExporterConfig

# Override log level from parameter if specified
if ($PSBoundParameters.ContainsKey('LogLevel')) {
    $script:ActiveConfig.LogLevel = $LogLevel
}

Write-ExporterLog -Level INFO -Message "Copilot Chat Exporter v$script:ExporterVersion starting"
Write-Host ''
Write-Host '  Copilot Chat Exporter v2.0.0' -ForegroundColor Cyan
Write-Host '  =============================' -ForegroundColor Cyan
Write-Host ''

# Log maintenance (prune old logs)
Invoke-LogMaintenance -Config $script:ActiveConfig

# Resolve system paths
$systemPaths = Resolve-SystemPaths -Config $script:ActiveConfig

# --- Route based on parameter set ---

if ($Update) {
    Write-Host '  Update functionality will be available in a future release.' -ForegroundColor Yellow
    Write-ExporterLog -Level INFO -Message 'Update requested but not yet implemented'
    exit 0
}

if ($Catalog) {
    Write-Host '  Building catalog from all VS Code sessions...' -ForegroundColor Cyan
    $allSessions = Get-AllChatSessions -SystemPaths $systemPaths -IncludeEmpty:$false
    Build-ChatCatalog -Sessions $allSessions -Config $script:ActiveConfig
    exit 0
}

if ($UseSendKeys) {
    # Legacy SendKeys path
    try {
        $sessionData = Invoke-SendKeysExport -Config $script:ActiveConfig
        $markdown = ConvertTo-ChatMarkdown -SessionData $sessionData

        $gateResult = Invoke-SecretGate -MarkdownContent $markdown -SkipScan:$SkipSecretScan -ForceSkip:$Force
        if ($gateResult.Action -eq 'cancel') { exit 0 }

        $topicSlug = if ($Topic) {
            ($Topic -replace '[\\\/:*?"<>|]', '-' -replace '\s+', '-' -replace '-+', '-').ToLower().Trim('-')
        }
        elseif ($sessionData.customTitle) {
            ($sessionData.customTitle -replace '[\\\/:*?"<>|]', '-' -replace '\s+', '-' -replace '-+', '-').ToLower().Trim('-')
        }
        else {
            Get-SmartTopic -ChatData $sessionData -MaxLength $script:ActiveConfig.TopicMaxLength -WordCount $script:ActiveConfig.TopicWordCount
        }

        $yearMonth = Get-Date -Format $script:ActiveConfig.YearMonthFormat
        $dateStr = Get-Date -Format $script:ActiveConfig.DateFormat
        $ts = Get-Date -Format $script:ActiveConfig.TimestampFormat
        $dir = Join-Path $script:ActiveConfig.SessionsBasePath $yearMonth
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $fileName = "${dateStr}_${ts}_${topicSlug}.md"
        $outputPath = Join-Path $dir $fileName
        Set-Content -Path $outputPath -Value $gateResult.Content -Encoding UTF8

        Write-Host "  Saved: $outputPath" -ForegroundColor Green
        $open = Read-Host '  Open in VS Code? [Y/n]'
        if ($open -eq '' -or $open -match '^[Yy]') { code $outputPath }
    }
    catch {
        Write-ExporterLog -Level ERROR -Message "SendKeys export failed: $_" -ErrorRecord $_
        Write-Host "  Export failed: $_" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# --- Primary path: Direct file read ---

# Enumerate all sessions
$allSessions = Get-AllChatSessions -SystemPaths $systemPaths

if ($allSessions.Count -eq 0) {
    Write-Host '  No chat sessions found in VS Code storage.' -ForegroundColor Yellow
    Write-ExporterLog -Level WARN -Message 'No sessions found'
    exit 0
}

Write-Host "  Found $($allSessions.Count) session(s)" -ForegroundColor Gray

# Select session(s)
if ($All) {
    $selectedSessions = $allSessions
    Write-Host "  Batch mode: exporting all $($selectedSessions.Count) sessions" -ForegroundColor Cyan
}
else {
    $selectParams = @{
        Sessions = $allSessions
        Config   = $script:ActiveConfig
    }
    if ($List) { $selectParams.ShowList = $true }
    if ($Session -ne [guid]::Empty -and $PSBoundParameters.ContainsKey('Session')) {
        $selectParams.SpecificSession = $Session
    }

    $selectedSessions = Select-ChatSession @selectParams

    if ($selectedSessions.Count -eq 0) {
        Write-Host '  No sessions selected.' -ForegroundColor Yellow
        exit 0
    }
}

# Export selected sessions
$exported = @()
$failed = 0
$totalToExport = $selectedSessions.Count

for ($i = 0; $i -lt $totalToExport; $i++) {
    $meta = $selectedSessions[$i]

    if ($totalToExport -gt 1) {
        Write-Host ''
        Write-Host "  [$($i + 1)/$totalToExport] $($meta.Title ?? '(untitled)')" -ForegroundColor Cyan
    }

    $result = Export-SingleSession -SessionMeta $meta -Config $script:ActiveConfig `
        -TopicOverride:$(if ($totalToExport -eq 1) { $Topic } else { $null }) `
        -SkipSecretScan:$SkipSecretScan -ForceSkip:$Force -NoWorkspaceLink:$NoWorkspaceLink

    if ($result) {
        $exported += $result
    }
    else {
        $failed++
    }
}

# Summary
Write-Host ''
if ($exported.Count -gt 0) {
    Write-Host "  Export complete: $($exported.Count) session(s) saved" -ForegroundColor Green

    if ($exported.Count -eq 1) {
        Write-Host "  Location: $($exported[0])" -ForegroundColor Gray
        $open = Read-Host '  Open in VS Code? [Y/n]'
        if ($open -eq '' -or $open -match '^[Yy]') { code $exported[0] }
    }
    else {
        Write-Host "  Location: $($script:ActiveConfig.SessionsBasePath)" -ForegroundColor Gray
        Write-Host "  Index: $(Join-Path $script:ActiveConfig.SessionsBasePath 'INDEX.md')" -ForegroundColor Gray
    }
}

if ($failed -gt 0) {
    Write-Host "  Failed: $failed session(s) — check logs" -ForegroundColor Yellow
    Write-Host "  Logs: $(Join-Path $script:ActiveConfig.SessionsBasePath 'logs')" -ForegroundColor Gray
}

Write-ExporterLog -Level INFO -Message "Session complete: $($exported.Count) exported, $failed failed"
