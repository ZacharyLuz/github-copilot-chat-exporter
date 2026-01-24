# Contributing to GitHub Copilot Chat Exporter

Thank you for your interest in contributing! 🎉

## Ways to Contribute

- 🐛 Report bugs and issues
- 💡 Suggest new features
- 📝 Improve documentation
- 🔧 Submit pull requests

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork**:
   ```powershell
   git clone https://github.com/ZacharyLuz/github-copilot-chat-exporter.git
   cd github-copilot-chat-exporter
   ```
3. **Create a branch** for your changes:
   ```powershell
   git checkout -b feature/your-feature-name
   ```

## Development Setup

### Requirements
- PowerShell 7+
- Python 3.6+
- VS Code with GitHub Copilot

### Testing Your Changes

1. Edit the scripts directly in the repository folder
2. Update your profile to point to your local copy:
   ```powershell
   # In your $PROFILE
   . "C:\path\to\your\github-copilot-chat-exporter\profile-functions.ps1"
   ```
3. Test thoroughly in VS Code terminal
4. Try both success and failure scenarios

## Coding Guidelines

### PowerShell

- Use **descriptive variable names** (`$sessionsPath` not `$sp`)
- Add **parameter validation** where appropriate
- Include **error handling** with try/catch
- Use **Write-Host with colors** for user feedback:
  - 🟢 Green for success
  - 🔴 Red for errors
  - 🟡 Yellow for warnings
  - ⚪ Gray for info
- **Comment complex logic**
- Follow **PowerShell naming conventions** (PascalCase for functions)

### Python

- Follow **PEP 8** style guidelines
- Use **type hints** where possible
- Add **docstrings** to functions
- Handle **exceptions gracefully**
- Test with different JSON formats from VS Code

### Documentation

- Update README.md if adding features
- Add examples for new functionality
- Keep explanations clear and concise
- Use emojis sparingly for visual clarity

## Pull Request Process

1. **Update documentation** if needed
2. **Test your changes** thoroughly
3. **Commit with clear messages**:
   ```
   feat: Add support for custom output formats
   fix: Handle malformed JSON exports
   docs: Update installation instructions
   ```
4. **Push to your fork**:
   ```powershell
   git push origin feature/your-feature-name
   ```
5. **Open a Pull Request** on GitHub
6. **Describe your changes** clearly in the PR description

## Reporting Issues

When reporting bugs, please include:

- **PowerShell version**: `$PSVersionTable.PSVersion`
- **Python version**: `python --version`
- **VS Code version**: Help → About
- **Steps to reproduce** the issue
- **Expected vs actual behavior**
- **Error messages** (full text)
- **Screenshots** if helpful

## Feature Requests

When suggesting features:

- **Describe the use case** clearly
- **Explain the benefit** to users
- **Consider backwards compatibility**
- **Suggest implementation** if you have ideas

## Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on the code, not the person
- Help others learn and grow

## Questions?

- Open an **issue** for questions
- Check existing **issues** and **PRs** first
- Be patient - this is a community project

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for making this project better!** 🙏
