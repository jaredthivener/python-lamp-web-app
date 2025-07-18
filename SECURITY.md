# Security Configuration for Python Lamp Web App

## GitHub Native Security Tools (Recommended)

This project leverages GitHub's built-in security features for comprehensive protection:

### 🛡️ **GitHub CodeQL** - Advanced Static Analysis
- **Purpose**: Industry-leading semantic code analysis
- **Coverage**: Security vulnerabilities, code quality issues, CWE mapping
- **Config**: `.github/workflows/security-native.yml`
- **Languages**: Python, JavaScript
- **Queries**: `security-extended`, `security-and-quality`
- **Results**: Available in GitHub Security tab

### 🤖 **GitHub Dependabot** - Automatic Dependency Management
- **Purpose**: Automated vulnerability scanning and dependency updates
- **Config**: `.github/dependabot.yml`
- **Features**:
  - Weekly dependency updates
  - Security vulnerability alerts
  - Grouped updates by dependency type
  - Auto-rebase and conflict resolution
- **Alerts**: GitHub Security Advisory Database

### 🔍 **GitHub Dependency Review** - PR Security Scanning
- **Purpose**: Scans pull requests for vulnerable dependencies
- **Triggers**: Automatically on every PR
- **Threshold**: Fails on moderate+ severity vulnerabilities
- **License checking**: Ensures approved licenses only

### 🕵️ **GitHub Secret Scanning** - Credential Protection
- **Purpose**: Detects accidentally committed secrets
- **Coverage**: API keys, tokens, passwords, certificates
- **Action**: Automatic alerts and optional blocking

## Quick Start

### GitHub Native (Recommended)
```bash
# Enable in your repository settings:
# 1. Go to Settings > Security and analysis
# 2. Enable "Dependency graph"
# 3. Enable "Dependabot alerts" 
# 4. Enable "Dependabot security updates"
# 5. Enable "Code scanning" (CodeQL)
# 6. Enable "Secret scanning"
```

## CI/CD Integration

### GitHub Actions Workflows
- **Security Analysis**: `.github/workflows/security-native.yml`
  - CodeQL analysis (Python + JavaScript) 
  - Dependency review on PRs
- **Dependabot**: `.github/dependabot.yml`
  - Weekly dependency updates
  - Grouped by dependency type
  - Automatic rebase and conflict resolution

### Security Dashboard
Access your security overview at:
`https://github.com/jaredthivener/python-lamp-web-app/security`

## Advantages of GitHub Native Tools

✅ **Zero configuration** - Works out of the box  
✅ **Industry-leading accuracy** - Lower false positive rates  
✅ **Integrated workflow** - Results appear in PRs and Security tab  
✅ **Free for public repos** - No additional costs  
✅ **Continuous monitoring** - Always-on scanning  
✅ **Community-driven** - Constantly updated rules   

## Security Best Practices Applied

✅ **Input validation** with Pydantic models  
✅ **Type hints** for better code safety  
✅ **No hardcoded secrets** (use environment variables)  
✅ **Dependency pinning** with exact versions  
✅ **Regular vulnerability scanning**  
✅ **Minimal Docker images** (Alpine Linux)  
✅ **Non-root user** in Docker containers  
✅ **HTTPS enforcement** (production recommendation)  

## Additional Recommendations

1. **Environment Variables**: Use `.env` files for sensitive config
2. **Rate Limiting**: Consider adding rate limiting for production
3. **CORS**: Configure CORS properly for your frontend
4. **Logging**: Avoid logging sensitive information
5. **Updates**: Regular dependency updates with security patches

## Report Review

After running scans, review reports in this order:
1. **Critical/High** severity issues first
2. **Medium** severity issues
3. **Low/Info** issues for code quality

Remember: Some findings may be false positives - review carefully!

## Local Development Tools (Optional)

### � **Pre-commit Hooks** - Development Quality Gates
For teams wanting additional local enforcement before commits reach GitHub's security tools.

**Quick Setup:**
```bash
# Add to development dependencies
uv pip install pre-commit

# Minimal configuration focusing on code quality
pre-commit install
```

**Simple Configuration** (`.pre-commit-config.yaml`):
```yaml
repos:
  - repo: https://github.com/psf/black
    rev: 23.12.1
    hooks:
      - id: black
        language_version: python3.12
  
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
```

**Why Optional?** GitHub's security tools provide comprehensive coverage:
- **CodeQL** handles advanced security analysis
- **Secret Scanning** catches credentials automatically  
- **Dependabot** manages vulnerability detection
- **Dependency Review** blocks problematic dependencies in PRs

**When to Use:** Consider pre-commit hooks if your team wants immediate feedback during development, but GitHub's native tools remain the primary security layer.
