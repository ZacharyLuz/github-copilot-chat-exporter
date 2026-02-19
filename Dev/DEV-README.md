# Dev Folder

This folder contains **development files** - templates, drafts, and test exports.

## ⚠️ Important Notes

### Placeholder Paths Are Intentional

The `.ps1` files in this folder contain **placeholder paths** like:
```powershell
$env:USERPROFILE\path\to\copilot-chat-exporter
```

**This is intentional.** These files are:
- Templates for reference
- Drafts being developed
- Historical versions

**Do NOT use these files directly.** Use the files in the root directory instead, which are configured by the installer.

### Chat Export Files

The `.md` files in this folder are test exports used during development. They demonstrate the export format and may contain example bugs or issues being investigated.

## File Purposes

| File                  | Purpose                             |
| --------------------- | ----------------------------------- |
| `*.ps1`               | Development versions / templates    |
| `*.md` (docs)         | Draft documentation                 |
| `*.md` (dated)        | Test chat exports                   |
| `chat_to_markdown.py` | Local copy of converter for testing |
