# 🚀 Quick Setup Guide - GitHub Copilot Chat Exporter

## For Users Who Just Want It To Work™

### Step 1: Install Python (if needed)

1. Download Python: https://www.python.org/downloads/
2. **IMPORTANT:** Check the box "Add Python to PATH" ✅
3. Install
4. Test in PowerShell:
   ```powershell
   python --version
   ```

### Step 2: Get the Tool

```powershell
# Clone the repo
git clone https://github.com/ZacharyLuz/github-copilot-chat-exporter.git

# Go into the directory
cd github-copilot-chat-exporter
```

### Step 3: Run the Installer

```powershell
# Run this ONE command
.\Install-CopilotChatExporter.ps1
```

The installer will:
- ✅ Check everything you need
- ✅ Create your PowerShell profile (if you don't have one)
- ✅ Set up all the paths automatically
- ✅ Fix any encoding issues
- ✅ Download required components

### Step 4: Reload Your Profile

```powershell
# Just run this
. $PROFILE
```

### Step 5: Use It!

```powershell
# Export your current Copilot chat
Save-GitHubCopilotChat
```

That's it! 🎉

---

## Alternative: Don't Want to Install? Use Standalone Mode

If you don't want to modify your PowerShell profile:

```powershell
# Just run this anytime
.\Save-CopilotChat-Standalone.ps1
```

No installation needed!

---

## Common Questions

### Q: What if I don't have a PowerShell profile?
**A:** The installer creates one for you automatically!

### Q: Will this mess up my existing profile?
**A:** Nope! It adds a clearly marked section you can remove anytime.

### Q: What if something goes wrong?
**A:** Use standalone mode - it works without any installation:
```powershell
.\Save-CopilotChat-Standalone.ps1
```

### Q: Can I uninstall it?
**A:** Yes! Just open your profile and remove the section between the markers:
```powershell
code $PROFILE

# Delete everything between these lines:
# ===== GitHub Copilot Chat Exporter - START =====
# ... stuff here ...
# ===== GitHub Copilot Chat Exporter - END =====
```

### Q: Where are my chats saved?
**A:** In the `sessions` folder, organized by year-month:
```
sessions/
  2026-01/
    2026-01-23_143022_your-topic.md
```

---

## Need Help?

1. Check the main [README.md](README.md) for detailed docs
2. Look at [Issues](https://github.com/ZacharyLuz/github-copilot-chat-exporter/issues)
3. Open a new issue with your error message

---

## Pro Tips

**Tip #1:** Use shortcuts
```powershell
Save-GitHubChat      # Shorter version
Resume-Chat          # Open previous chats
```

**Tip #2:** Custom topics
```powershell
Save-GitHubCopilotChat -Topic "my-awesome-solution"
```

**Tip #3:** Browse old chats
```powershell
Resume-GitHubCopilotChat
# Shows a menu of your recent chats!
```

---

**That's all you need to know! 🚀**
