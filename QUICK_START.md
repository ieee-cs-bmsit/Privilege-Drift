# 🚀 Privilege Drift - Quick Start Guide

## Prerequisites

- **Windows 10/11** or **Windows Server 2016+**
- **PowerShell 5.1** or later
- **Administrator privileges** (required for all operations)

## Installation

1. **Download or clone** this repository to your preferred location:
   ```
   git clone https://github.com/ieee-cs-bmsit/privilege-drift.git
   cd privilege-drift
   ```

2. **Verify folder structure**:
   ```
   privilege-drift/
   ├── scripts/          ✓ PowerShell scripts
   ├── config/           ✓ Configuration files
   ├── snapshots/        ✓ Empty (will store snapshots)
   ├── reports/          ✓ Empty (will store reports)
   └── logs/             ✓ Empty (will store logs)
   ```

## First Run: Creating a Baseline

### Option 1: Using the Batch File (Recommended)

**Double-click** `run-as-admin.bat` and when prompted:
- Choose **Yes** to grant Administrator privileges
- The baseline snapshot will be created automatically

### Option 2: Using PowerShell Directly

1. **Right-click** on PowerShell and select **"Run as Administrator"**

2. Navigate to the Privilege Drift directory:
   ```powershell
   cd D:\Privilege-Drift  # Adjust path as needed
   ```

3. Run the baseline analysis:
   ```powershell
   .\run-analysis.ps1 -Baseline
   ```

### What Happens During Baseline?

The tool will:
1. ✅ Collect current privilege state (30-60 seconds)
2. ✅ Save as baseline snapshot
3. ✅ Calculate initial risk score
4. ✅ Generate first report

## Daily Usage

After creating the baseline, run daily to detect privilege drift:

```powershell
# Option 1: Double-click run-as-admin.bat

# Option 2: PowerShell (as Administrator)
.\run-analysis.ps1
```

## Viewing Results

### Quick View (Text Report)
```powershell
Get-Content .\reports\drift-report-latest.txt
```

### Detailed View (JSON Data)
```powershell
# View latest snapshot
Get-Content .\snapshots\latest.json | ConvertFrom-Json | Format-List

# View risk score details
Get-Content .\reports\risk-score-latest.json | ConvertFrom-Json | Format-List

# View detected changes
Get-Content .\reports\comparison-latest.json | ConvertFrom-Json | Format-List
```

## Understanding the Risk Score

| Score   | Level      | Meaning                              | Action Required              |
|---------|------------|--------------------------------------|------------------------------|
| 0-30    | 🟢 GOOD    | Normal privilege baseline            | No immediate action          |
| 31-60   | 🟡 REVIEW  | Some privileges need attention       | Review within 1 week         |
| 61-85   | 🟠 HIGH    | Immediate review recommended         | Review within 24 hours       |
| 86-100  | 🔴 CRITICAL| Serious privilege drift detected     | **Review immediately**       |

## Common Tasks

### 1. Review Latest Report
```powershell
notepad .\reports\drift-report-latest.txt
```

### 2. Add Known-Good Privilege to Whitelist
Edit `config\whitelist.json` to add trusted services/users:
```json
{
  "services": [
    {
      "name": "YourServiceName",
      "display_name": "Your Service Display Name",
      "reason": "Company approved software"
    }
  ]
}
```

### 3. Adjust Risk Thresholds
Edit `config\policies.json` to customize scoring:
```json
{
  "risk_thresholds": {
    "good": 30,
    "review": 60,
    "high_risk": 85
  }
}
```

### 4. Reset Baseline (After Cleanup)
After removing unwanted privileges, create a new baseline:
```powershell
.\run-analysis.ps1 -Baseline
```

## Automating Daily Scans

### Create Scheduled Task (Run Once)

```powershell
# Run this in PowerShell as Administrator
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File 'D:\Privilege-Drift\run-analysis.ps1'" `
    -WorkingDirectory "D:\Privilege-Drift"

$trigger = New-ScheduledTaskTrigger -Daily -At 8am

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "PrivilegeDriftDailyCheck" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description "Daily privilege drift security analysis"
```

## Troubleshooting

### Issue: "Script requires elevation"
**Solution**: Run PowerShell as Administrator or use `run-as-admin.bat`

### Issue: "Execution Policy" error
**Solution**: Run with bypass flag:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\run-analysis.ps1
```

### Issue: No previous snapshot found
**Solution**: This is normal on first run. Use `-Baseline` flag:
```powershell
.\run-analysis.ps1 -Baseline
```

### Issue: High risk score immediately
**Solution**: Review the report. Your system might have legitimate elevated privileges. Add them to `config\whitelist.json` if they're trusted.

## Next Steps

1. ✅ Create baseline snapshot
2. ✅ Review initial report
3. ✅ Add trusted privileges to whitelist
4. ✅ Set up daily scheduled task
5. ✅ Monitor weekly for drift trends

## Support

- **Questions**: ieee_cs@bmsit.in
- **Documentation**: See README.md
- **Contributing**: See CONTRIBUTING.md

---

**Remember**: Privilege Drift is a monitoring tool. It detects changes but requires human judgment for remediation decisions.
