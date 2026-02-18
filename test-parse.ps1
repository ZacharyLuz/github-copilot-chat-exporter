$e = $null
$t = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Save-CopilotChat-v2.ps1'),
    [ref]$t,
    [ref]$e
) | Out-Null
Write-Output "Parse errors: $($e.Count)"
foreach ($err in $e) {
    Write-Output "  $($err.Message) at line $($err.Extent.StartLineNumber)"
}
if ($e.Count -eq 0) { Write-Output "SYNTAX OK" }
