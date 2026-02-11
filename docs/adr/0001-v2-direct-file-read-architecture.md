# ADR-0001: v2 Direct File Read Architecture

**Status:** Accepted  
**Date:** 2026-02-10  
**Deciders:** @ZacharyLuz  

## Context

Save-CopilotChat v1 relied on a fragile pipeline:
1. **SendKeys automation** to trigger VS Code's export command
2. **Python dependency** (`chat_to_markdown.py`) for JSON-to-Markdown conversion
3. **Clipboard/file watching** to capture the exported JSON

This pipeline had multiple failure modes:
- SendKeys is unreliable (window focus loss, process name mismatches)
- Python dependency creates version/environment friction
- VS Code actively garbage-collects older sessions
- Surrogate encoding crashes in the Python converter
- No programmatic access to session metadata for selection

Meanwhile, VS Code stores all chat sessions as plain files on disk:
- **VS Code Insiders**: JSONL files in `%APPDATA%\Code - Insiders\User\{globalStorage,workspaceStorage}\*\chatSessions\*.jsonl`
- **VS Code (stable)**: JSON files in `%APPDATA%\Code\User\{globalStorage,workspaceStorage}\*\chatSessions\*.json`

## Decision

Rewrite the exporter to read chat sessions directly from VS Code's storage files, using a native PowerShell markdown converter, eliminating both the SendKeys automation and the Python dependency.

### Key Design Choices

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data source | Direct file read | Eliminates SendKeys unreliability |
| Converter | Native PowerShell | Eliminates Python dependency |
| JSONL replay | Incremental patch engine | VS Code Insiders uses kind:0 (init) + kind:1/2 (patches) format |
| Session selection | Auto-latest with confirm, paginated picker | Handles 100+ sessions across multiple VS Code editions |
| Secret scanning | Mandatory gate (R/C only) | Sessions export to OneDrive-synced folder |
| Topic extraction | customTitle > -Topic param > Get-SmartTopic | Cascading fallback with keyword extraction |
| Folder structure | `YYYY-MM/` subfolders + dual INDEX | Scalable organization with search support |
| SendKeys | Opt-in fallback (`-UseSendKeys`) | Preserved for edge cases, not default |

### Architecture

```
VS Code Storage (JSONL/JSON)
    ↓ Resolve-SystemPaths (auto-detect editions)
    ↓ Get-AllChatSessions (enumerate + metadata)
    ↓ Select-ChatSession (auto-latest or picker)
    ↓ Read-CopilotChatSession (JSONL replay or JSON parse)
    ↓ ConvertTo-ChatMarkdown (native PS converter)
    ↓ Invoke-SecretGate (mandatory scan)
    ↓ Export to YYYY-MM/ folder
    ↓ Update-ChatIndex (INDEX.md + INDEX.json)
    ↓ New-WorkspaceChatLink (optional symlinks)
```

### 21 Functions

| Function | Purpose |
|----------|---------|
| `Get-ExporterConfig` | Load config with defaults + user overrides |
| `Write-ExporterLog` | Structured logging with daily rotation |
| `Invoke-LogMaintenance` | Prune old log files |
| `Resolve-SystemPaths` | Auto-detect VS Code editions and storage |
| `Read-CopilotChatSession` | JSONL incremental replay + JSON parsing |
| `Get-AllChatSessions` | Enumerate sessions across all storage |
| `Get-SessionMetadata` | Extract metadata without full replay |
| `ConvertTo-ChatMarkdown` | Native PowerShell markdown converter |
| `Get-RequestPreview` | First 80 chars for TOC |
| `Get-UserMessageText` | Extract user message text |
| `Convert-ResponsePart` | Format response by kind |
| `Remove-OrphanSurrogates` | Replace orphan surrogates with U+FFFD |
| `Get-SmartTopic` | Keyword extraction with stop words |
| `Find-PotentialSecrets` | Regex secret detection |
| `Invoke-SecretRedaction` | Value-only replacement |
| `Invoke-SecretGate` | Mandatory R/C gate |
| `Select-ChatSession` | Auto-latest or paginated picker |
| `Update-ChatIndex` | Maintain INDEX.md + INDEX.json |
| `New-WorkspaceChatLink` | Symlinks in `.copilot-chats/` |
| `Build-ChatCatalog` | Full storage crawl |
| `Export-SingleSession` | Complete single-session pipeline |

## Consequences

### Positive
- **Zero external dependencies** — pure PowerShell, no Python/pip
- **Reliable** — no UI automation, no focus loss, no timing issues
- **Fast** — direct file I/O vs. SendKeys + clipboard + file watching
- **Complete** — access to all sessions (including ones VS Code would garbage-collect)
- **Searchable** — dual-format INDEX enables both human and machine lookup
- **Secure** — mandatory secret scan before any write to OneDrive

### Negative
- **Depends on VS Code's internal storage format** — could change (mitigated: format has been stable since 2024)
- **No real-time streaming** — reads completed sessions only (by design)
- **Profile update required** — wrapper function needs updating (done)

### Risks
- VS Code could change storage paths or format → wrap in try/catch, log warnings, fall back to SendKeys
- Large sessions (>100MB) could be slow → stream-process JSONL lines instead of loading all at once

## Related
- v1 script: `Save-CopilotChat.ps1` (archived to `legacy/`)
- Python converter fix: `copilot-chat-to-markdown` fork v1.0.1
- ROADMAP: v2.1.0 will convert to a proper PowerShell module
