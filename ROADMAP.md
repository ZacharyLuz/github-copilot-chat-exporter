# Roadmap

## v2.0.0 — Direct File Read (Current)

**Status:** In Development (`dev/v2` branch)  
**Target:** February 2026

The complete rewrite. Reads chat sessions directly from VS Code's on-disk storage, converts with native PowerShell, eliminates all external dependencies.

### Features
- [x] Direct JSONL/JSON file reader with incremental replay
- [x] Native PowerShell markdown converter
- [x] Auto-detect VS Code editions (stable + Insiders)
- [x] Smart topic extraction (customTitle → param → keyword extraction)
- [x] Mandatory secret scanning with R/C gate
- [x] Session picker: auto-latest with confirm + paginated list
- [x] YYYY-MM subfolder organization with dual INDEX (md + json)
- [x] Workspace symlinks (`.copilot-chats/`)
- [x] Full catalog crawl mode
- [x] Structured logging with daily rotation
- [x] SendKeys as opt-in fallback
- [x] Config file support (`%LOCALAPPDATA%\CopilotChatExporter\config.json`)

### Migration from v1
- Profile wrapper updated to call v2 script
- Old `sessions/` folder preserved (not migrated automatically)
- Same aliases work: `Save-GitHubChat`, `Save-GHCopilot`, etc.

---

## v2.1.0 — PowerShell Module

**Status:** Planned  
**Target:** Q2 2026

Convert from standalone script to proper PowerShell module with manifest, exported functions, and PSGallery publishing.

### Planned Features
- [ ] Module manifest (`.psd1`) with version, author, exports
- [ ] Separate function files under `Public/` and `Private/`
- [ ] `Install-Module CopilotChatExporter` from PSGallery
- [ ] Tab completion for `-Session` parameter
- [ ] Pester test suite (unit + integration)
- [ ] CI/CD pipeline (GitHub Actions)

---

## v2.2.0 — Installation UX

**Status:** Planned  
**Target:** Q3 2026

Streamline first-run experience and provide guided setup.

### Planned Features
- [ ] `Install-CopilotChatExporter` cmdlet (profile injection)
- [ ] Guided first-run wizard (detect VS Code, choose output folder)
- [ ] Automatic profile backup before modification
- [ ] Winget package submission
- [ ] Scoop bucket entry

---

## v3.0.0 — Cross-Platform

**Status:** Conceptual  
**Target:** TBD

Extend to macOS and Linux where VS Code stores sessions in different paths.

### Planned Features
- [ ] Platform-specific path resolution (`~/Library/Application Support/Code/` on macOS, `~/.config/Code/` on Linux)
- [ ] Remove Windows-specific assumptions (symlinks → junctions, etc.)
- [ ] Test matrix across Windows/macOS/Linux
- [ ] Docker-based testing
