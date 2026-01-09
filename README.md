# Privilege Drift 🔐

> **"Permissions should decay, not accumulate."**

## What is Privilege Drift?

Privilege Drift is an open-source security tool that tracks, monitors, and helps manage elevated permissions on Windows systems. It addresses **privilege creep** — the silent accumulation of elevated permissions that happens when systems grant access but never revoke it.

Think of it as **version control for system privileges** — like git diff, but for admin rights.

## ⚡ Quick Start

```powershell
# Clone or download this repository
cd Privilege-Drift

# Take initial baseline snapshot (requires Administrator)
.\run-analysis.ps1 -Baseline

# Run daily analysis
.\run-analysis.ps1

# View the report
Get-Content .\reports\drift-report-latest.txt
```

## 🎯 The Problem

Systems accumulate privileges over time:
- Apps request admin rights "just once" → never revoked
- Temporary accounts keep admin access → forgotten
- Services run as SYSTEM → never downgraded
- Attack surface grows silently → exploited eventually

**Result:** Your system has increasingly more attack surface over time.

## 💡 The Solution

Privilege Drift:
1. **Snapshots** your system's privilege state daily
2. **Compares** snapshots to detect drift
3. **Alerts** you to new elevated permissions
4. **Scores** your overall privilege risk (0-100)
5. **Reports** human-readable security analysis

## 📋 Features

### Current (v0.1-beta)
- ✅ Daily snapshot collection
- ✅ Privilege drift detection
- ✅ Risk score calculation (0-100)
- ✅ Human-readable reports
- ✅ Whitelist for known-good privileges
- ✅ Tracks: Users, Processes, Services, Tasks, Startup Items

### Planned (v0.2+)
- ⏳ Automated Task Scheduler setup
- ⏳ Desktop notifications
- ⏳ Time-bound permission tracking
- ⏳ HTML reports
- ⏳ GUI for management
- ⏳ Auto-revocation with approval

## 🗂️ Project Structure

```
privilege-drift/
├── snapshots/              # Daily privilege snapshots (JSON)
│   ├── baseline.json       # Initial clean state
│   └── latest.json         # Most recent snapshot
├── scripts/
│   ├── collect-snapshot.ps1    # Gather privilege data
│   ├── compare-snapshots.ps1   # Generate diff
│   ├── calculate-risk.ps1      # Risk scoring
│   └── generate-report.ps1     # Human-readable output
├── config/
│   ├── policies.json           # Decay rules, thresholds
│   └── whitelist.json          # Known-good privileges
├── reports/
│   └── drift-report-latest.txt # Latest analysis report
├── logs/
│   └── audit.log               # Operation logs
└── run-analysis.ps1            # Main entry point
```

## 📊 Sample Output

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                    🔐 PRIVILEGE DRIFT REPORT                     ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Risk Score: 45/100
Risk Level: 🟡 REVIEW
Some privileges need attention

🔴 CRITICAL RISK CHANGES
  • [Admin User] New admin user: backup_admin
  • [Service] New service: DataSync (runs as SYSTEM)
  
🟡 MEDIUM RISK CHANGES
  • [Startup Item] New startup item: QuickLaunch.exe
```

## 🚀 Usage

### Option 1: Full Analysis (Recommended)

```powershell
# Run complete analysis with all steps
.\run-analysis.ps1
```

### Option 2: Individual Scripts

```powershell
# Step 1: Collect snapshot
.\scripts\collect-snapshot.ps1

# Step 2: Compare with previous
.\scripts\compare-snapshots.ps1

# Step 3: Calculate risk score
.\scripts\calculate-risk.ps1

# Step 4: Generate report
.\scripts\generate-report.ps1
```

### Creating a Baseline

On first run or when establishing a clean state:

```powershell
.\run-analysis.ps1 -Baseline
```

This saves the current state as your baseline for future comparisons.

## ⚙️ Configuration

### Risk Thresholds (`config/policies.json`)

```json
{
  "risk_thresholds": {
    "good": 30,
    "review": 60,
    "high_risk": 85,
    "critical": 100
  },
  "scoring_weights": {
    "admin_users": 5,
    "elevated_services": 3,
    "tasks_as_system": 6,
    "unsigned_elevated": 10
  }
}
```

### Whitelist (`config/whitelist.json`)

Add known-good privileges to avoid false positives:

```json
{
  "admin_users": ["Administrator", "SYSTEM"],
  "services": [
    {
      "name": "wuauserv",
      "display_name": "Windows Update",
      "reason": "Required Windows service"
    }
  ]
}
```

## 🔒 Security Considerations

### System Requirements
- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or later
- Administrator privileges (required for snapshot collection)

### Data Privacy
- All data stays **local** — no cloud uploads
- No telemetry or tracking
- Snapshots contain sensitive system information — protect accordingly

### Attack Surface of the Tool
- Snapshots are saved in JSON (consider encrypting)
- Scripts run with admin privileges (verify integrity)
- Configuration files control security policies (protect from tampering)

## 📚 How It Works

1. **Snapshot Collection**: Gathers current state of:
   - Admin users and group memberships
   - Elevated processes and services
   - Scheduled tasks with high privileges
   - Startup items (Registry Run keys + folders)

2. **Drift Detection**: Compares current vs. previous snapshot:
   - Identifies added/removed/modified privileges
   - Checks against whitelist
   - Assesses risk level for each change

3. **Risk Scoring**: Calculates 0-100 score based on:
   - Number of elevated entities
   - Age of privileges
   - Unsigned executables with elevation
   - Suspicious timing (e.g., tasks created at 3 AM)

4. **Reporting**: Generates human-readable report with:
   - Critical/high/medium/low risk changes
   - Risk score interpretation
   - Actionable recommendations

## 🛠️ Automation

### Automate Daily Scans (Task Scheduler)

```powershell
# Create a scheduled task to run daily at 8 AM
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File 'D:\Privilege-Drift\run-analysis.ps1'" `
    -WorkingDirectory "D:\Privilege-Drift"

$trigger = New-ScheduledTaskTrigger -Daily -At 8am

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "PrivilegeDriftDailyCheck" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description "Daily privilege drift analysis"
```

## 🤝 Contributing

Contributions welcome! This is a community-driven security tool.

Areas needing help:
- Linux/macOS support
- GUI development
- SIEM integrations
- Documentation improvements
- Test coverage

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## ⚠️ Disclaimer

This tool is in **early beta (v0.1)**. Use in production environments at your own risk. Always test in a safe environment first.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/privilege-drift/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/privilege-drift/discussions)
- **Security**: For security vulnerabilities, please email security@privilegedrift.org

## 🎯 Threat Model

**Defends against:**
- Malware that silently adds persistence
- Insider threats with lingering elevated access
- Forgotten admin accounts
- Supply chain attacks via installer privileges

**Does not defend against:**
- Kernel-level rootkits
- Physical access attacks
- Zero-day privilege escalation exploits

## 📖 FAQ

**Q: Does this replace antivirus?**  
A: No. This is complementary — it detects privilege creep, not malware directly.

**Q: Will this break my system?**  
A: No. It only monitors by default. All actions require explicit approval.

**Q: How is this different from Windows Defender?**  
A: Defender detects malicious software. Privilege Drift detects malicious *privileges*.

**Q: What's the performance impact?**  
A: Minimal. Snapshot collection takes 10-30 seconds, typically run once daily.

---

**Built with security in mind. Maintained by the community.**

*"Make privilege drift visible, measurable, and reversible."*
