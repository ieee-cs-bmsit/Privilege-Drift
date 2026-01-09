# Contributing to Privilege Drift

Thank you for your interest in contributing to Privilege Drift! This document provides guidelines for contributing to the project.

## 🎯 Project Vision

Privilege Drift aims to make privilege management:
- **Visible**: Every elevated permission should be tracked
- **Measurable**: Risk should be quantifiable
- **Reversible**: Privileges should be easy to revoke
- **Transparent**: All decisions should be explainable

## 🚀 Getting Started

1. **Fork the repository**
2. **Clone your fork**: `git clone https://github.com/yourusername/privilege-drift.git`
3. **Create a feature branch**: `git checkout -b feature/your-feature-name`
4. **Make your changes**
5. **Test thoroughly** on Windows 10/11
6. **Submit a pull request**

## 📝 Code Guidelines

### PowerShell Scripts
- Use descriptive variable names
- Add comments for complex logic
- Follow PowerShell best practices
- Include error handling
- Test with different privilege levels

### JSON Configuration
- Maintain backward compatibility
- Document new configuration options
- Validate JSON format before committing

### Documentation
- Update README.md for new features
- Keep inline comments up to date
- Add examples for new functionality

## 🧪 Testing

Before submitting:
1. Run on a clean Windows installation
2. Test with baseline creation
3. Verify drift detection with known changes
4. Check risk score accuracy
5. Ensure reports are readable

## 🐛 Bug Reports

When reporting bugs, include:
- Windows version
- PowerShell version
- Steps to reproduce
- Expected vs. actual behavior
- Relevant error messages
- Snapshot/configuration files (sanitized)

## 💡 Feature Requests

We welcome feature requests! Please open an issue with:
- Clear use case description
- Expected behavior
- Why it aligns with project goals
- Willingness to implement (if applicable)

## 🔒 Security Issues

**Do not open public issues for security vulnerabilities.**

Instead:
- Email: security@privilegedrift.org
- Include detailed description
- Provide proof of concept if possible
- Allow time for fix before disclosure

## 📜 Code of Conduct

- Be respectful and professional
- Welcome newcomers
- Focus on constructive feedback
- Assume good intentions

## 🏆 Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Mentioned in release notes
- Credited for significant features

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for helping make systems more secure! 🔐
