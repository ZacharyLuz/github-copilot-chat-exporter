# Smoke test: source only the function definitions, test key functions
# Extracts functions without running the main orchestration block

$scriptPath = Join-Path $PSScriptRoot 'Save-CopilotChat-v2.ps1'
$scriptContent = Get-Content $scriptPath -Raw

# Extract and define all functions by parsing the AST
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$tokens, [ref]$errors)

# Define all functions in current scope
$functionDefs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
foreach ($func in $functionDefs) {
    Invoke-Expression $func.Extent.Text
}

# Set script-level vars that functions need
$script:ExporterVersion = '2.0.0'
$script:NoLogFile = $true
$script:ActiveConfig = Get-ExporterConfig

$passed = 0
$failed = 0

function Assert-Test {
    param([string]$Name, [scriptblock]$Test)
    try {
        $result = & $Test
        if ($result) {
            Write-Host "  PASS: $Name" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "  FAIL: $Name" -ForegroundColor Red
            $script:failed++
        }
    } catch {
        Write-Host "  FAIL: $Name - $_" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ""
Write-Host "  Copilot Chat Exporter v2 - Smoke Tests" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""

# --- Test 1: Config loading ---
Assert-Test "Config loads with defaults" {
    $cfg = Get-ExporterConfig
    $cfg.SessionsBasePath -and $cfg.PageSize -eq 20 -and $cfg.MaxSessionsToList -eq 100
}

# --- Test 2: System path resolution ---
Assert-Test "System paths resolve VS Code editions" {
    $cfg = Get-ExporterConfig
    $paths = Resolve-SystemPaths -Config $cfg
    $paths.VSCodeEditions.Count -gt 0 -and $paths.StorageLocations.Count -gt 0
}

# --- Test 3: JSONL session reading (small file) ---
$testFile = Get-ChildItem "$env:APPDATA\Code - Insiders\User\globalStorage\emptyWindowChatSessions\*.jsonl" -ErrorAction SilentlyContinue |
    Sort-Object Length | Select-Object -First 1

if ($testFile) {
    Assert-Test "Read-CopilotChatSession reads JSONL" {
        $session = Read-CopilotChatSession -FilePath $testFile.FullName
        $null -ne $session -and $null -ne $session.requests
    }

    Assert-Test "Get-SessionMetadata extracts metadata" {
        $meta = Get-SessionMetadata -FilePath $testFile.FullName -Format 'jsonl' -Edition 'Code - Insiders'
        $null -ne $meta -and $meta.SessionId -and $meta.CreationDate -is [DateTime]
    }
} else {
    Write-Host "  SKIP: No JSONL test files found" -ForegroundColor Yellow
}

# --- Test 4: Session enumeration ---
Assert-Test "Get-AllChatSessions finds sessions" {
    $cfg = Get-ExporterConfig
    $paths = Resolve-SystemPaths -Config $cfg
    $sessions = Get-AllChatSessions -SystemPaths $paths
    $sessions.Count -gt 0
}

# --- Test 5: Markdown conversion ---
if ($testFile) {
    Assert-Test "ConvertTo-ChatMarkdown produces markdown" {
        $session = Read-CopilotChatSession -FilePath $testFile.FullName
        $md = ConvertTo-ChatMarkdown -SessionData $session
        $md -match '# GitHub Copilot Chat Log' -and $md.Length -gt 100
    }
}

# --- Test 6: Smart topic extraction ---
if ($testFile) {
    Assert-Test "Get-SmartTopic extracts meaningful topic" {
        $session = Read-CopilotChatSession -FilePath $testFile.FullName
        $topic = Get-SmartTopic -ChatData $session
        $topic.Length -gt 0 -and $topic -ne 'chat-session'
    }
}

# --- Test 7: Secret detection ---
Assert-Test "Find-PotentialSecrets detects real secrets" {
    $testContent = 'Here is my key: AKIAIOSFODNN7EXAMPLE and password="SuperSecret123!"'
    $findings = Find-PotentialSecrets -Content $testContent
    $findings.Count -gt 0
}

Assert-Test "Find-PotentialSecrets ignores placeholders" {
    $testContent = 'password="<YOUR_PASSWORD>" and key="${API_KEY}"'
    $findings = Find-PotentialSecrets -Content $testContent
    $findings.Count -eq 0
}

# --- Test 8: Surrogate removal ---
Assert-Test "Remove-OrphanSurrogates handles clean text" {
    $clean = Remove-OrphanSurrogates -Text "Hello World"
    $clean -eq "Hello World"
}

# --- Summary ---
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
$total = $passed + $failed
Write-Host "  Results: $passed/$total passed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
if ($failed -gt 0) { Write-Host "  $failed test(s) FAILED" -ForegroundColor Red }
Write-Host ""
