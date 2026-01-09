# Privilege Drift - Main Runner Script
# Convenience script to run full privilege drift analysis

param(
    [switch]$SkipCollection,
    [switch]$SkipComparison,
    [switch]$SkipRiskScore,
    [switch]$SkipReport,
    [switch]$Baseline,
    [switch]$Verbose
)

#Requires -RunAsAdministrator

function Write-Header {
    param([string]$Text)
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

$ErrorActionPreference = "Stop"

Write-Host @"

 ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 ┃                                                                ┃
 ┃                  🔐  PRIVILEGE DRIFT  🔐                      ┃
 ┃                                                                ┃
 ┃              "Permissions should decay, not accumulate"        ┃
 ┃                                                                ┃
 ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

"@ -ForegroundColor Cyan

Write-Host "  Version: 0.1.0-beta" -ForegroundColor Gray
Write-Host "  Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "  System: $env:COMPUTERNAME`n" -ForegroundColor Gray

# Step 1: Collect Snapshot
if (-not $SkipCollection) {
    Write-Header "STEP 1: Collecting System Snapshot"
    try {
        & ".\scripts\collect-snapshot.ps1" -OutputPath ".\snapshots"
        
        # If this is a baseline run, save it as baseline.json
        if ($Baseline) {
            Write-Host "`n📌 Saving as baseline snapshot..." -ForegroundColor Yellow
            Copy-Item ".\snapshots\latest.json" ".\snapshots\baseline.json" -Force
            Write-Host "   ✓ Baseline saved: .\snapshots\baseline.json" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "`n❌ Error during snapshot collection: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "⏭️  Skipping snapshot collection" -ForegroundColor Yellow
}

# Step 2: Compare Snapshots
if (-not $SkipComparison) {
    Write-Header "STEP 2: Comparing with Previous Snapshot"
    try {
        & ".\scripts\compare-snapshots.ps1" -CurrentSnapshot ".\snapshots\latest.json" -OutputPath ".\reports"
    }
    catch {
        Write-Host "`n❌ Error during comparison: $_" -ForegroundColor Red
        Write-Host "   This might be your first run. Try running with -Baseline flag." -ForegroundColor Yellow
        # Don't exit - continue with risk scoring
    }
}
else {
    Write-Host "⏭️  Skipping snapshot comparison" -ForegroundColor Yellow
}

# Step 3: Calculate Risk Score
if (-not $SkipRiskScore) {
    Write-Header "STEP 3: Calculating Risk Score"
    try {
        & ".\scripts\calculate-risk.ps1" -SnapshotPath ".\snapshots\latest.json"
    }
    catch {
        Write-Host "`n❌ Error during risk calculation: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "⏭️  Skipping risk score calculation" -ForegroundColor Yellow
}

# Step 4: Generate Report
if (-not $SkipReport) {
    Write-Header "STEP 4: Generating Report"
    try {
        & ".\scripts\generate-report.ps1" -ComparisonPath ".\reports\comparison-latest.json" -RiskScorePath ".\reports\risk-score-latest.json" -OutputPath ".\reports"
    }
    catch {
        Write-Host "`n❌ Error during report generation: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "⏭️  Skipping report generation" -ForegroundColor Yellow
}

# Final Summary
Write-Host "`n" -NoNewline
Write-Host "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓" -ForegroundColor Green
Write-Host "┃                    ✅ ANALYSIS COMPLETE                       ┃" -ForegroundColor Green
Write-Host "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛" -ForegroundColor Green

Write-Host "`n📁 Generated Files:" -ForegroundColor Cyan
if (Test-Path ".\snapshots\latest.json") {
    Write-Host "   • Snapshot:   .\snapshots\latest.json" -ForegroundColor Gray
}
if (Test-Path ".\reports\comparison-latest.json") {
    Write-Host "   • Comparison: .\reports\comparison-latest.json" -ForegroundColor Gray
}
if (Test-Path ".\reports\risk-score-latest.json") {
    Write-Host "   • Risk Score: .\reports\risk-score-latest.json" -ForegroundColor Gray
}
if (Test-Path ".\reports\drift-report-latest.txt") {
    Write-Host "   • Report:     .\reports\drift-report-latest.txt" -ForegroundColor Gray
}

Write-Host "`n💡 Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Review the report: Get-Content .\reports\drift-report-latest.txt" -ForegroundColor Yellow
Write-Host "   2. Address critical and high-risk changes" -ForegroundColor Yellow
Write-Host "   3. Update whitelist for approved privileges in .\config\whitelist.json" -ForegroundColor Yellow
Write-Host "   4. Schedule daily runs with Task Scheduler" -ForegroundColor Yellow
Write-Host "`n"
