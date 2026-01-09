# Privilege Drift - Report Generator
# Generates human-readable reports from comparison and risk data

param(
    [string]$ComparisonPath = ".\reports\comparison-latest.json",
    [string]$RiskScorePath = ".\reports\risk-score-latest.json",
    [string]$OutputPath = ".\reports",
    [switch]$HTML
)

$ErrorActionPreference = "Continue"

Write-Host "Privilege Drift - Report Generator" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Load comparison data
$comparison = $null
if (Test-Path $ComparisonPath) {
    Write-Host "[*] Loading comparison data..." -ForegroundColor Yellow
    $comparison = Get-Content $ComparisonPath | ConvertFrom-Json
    Write-Host "    [OK] Loaded comparison" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] No comparison data found. Generating snapshot-only report." -ForegroundColor Yellow
}

# Load risk score
$riskScore = $null
if (Test-Path $RiskScorePath) {
    Write-Host "[*] Loading risk score..." -ForegroundColor Yellow
    $riskScore = Get-Content $RiskScorePath | ConvertFrom-Json
    Write-Host "    [OK] Loaded risk score" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] No risk score found. Run calculate-risk.ps1 first." -ForegroundColor Yellow
}

# Generate report
$reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportContent = @"
======================================================================
                   PRIVILEGE DRIFT REPORT
======================================================================

Generated: $reportDate
Hostname: $env:COMPUTERNAME

"@

# Add risk score section
if ($riskScore) {
    $scoreEmoji = switch -Regex ($riskScore.risk_level) {
        "GOOD" { "[OK]" }
        "REVIEW" { "[!!]" }
        "HIGH RISK" { "[!!]" }
        "CRITICAL" { "[!!]" }
        default { "[??]" }
    }
    
}   

    $reportContent += @"
═══════════════════════════════════════════════════════════════════
                         RISK ASSESSMENT
═══════════════════════════════════════════════════════════════════

Risk Score: $($riskScore.final_score)/100
Risk Level: $scoreEmoji $($riskScore.risk_level)
$($riskScore.description)

"@

    # Add breakdown
    if ($riskScore.breakdown) {
        $reportContent += "SCORE BREAKDOWN:`n"
        $reportContent += "----------------------------------------------------------------------`n"
        
        if ($riskScore.breakdown.admin_users) {
            $reportContent += "  * Admin Users:          $($riskScore.breakdown.admin_users.count) users x $($riskScore.breakdown.admin_users.weight) = $($riskScore.breakdown.admin_users.score) points`n"
        }
        if ($riskScore.breakdown.elevated_services) {
            $reportContent += "  * Elevated Services:    $($riskScore.breakdown.elevated_services.count) services x $($riskScore.breakdown.elevated_services.weight) = $($riskScore.breakdown.elevated_services.score) points`n"
        }
        if ($riskScore.breakdown.startup_items) {
            $reportContent += "  * Admin Startup Items:  $($riskScore.breakdown.startup_items.count) items x $($riskScore.breakdown.startup_items.weight) = $($riskScore.breakdown.startup_items.score) points`n"
        }
        if ($riskScore.breakdown.system_tasks) {
            $reportContent += "  * SYSTEM Tasks:         $($riskScore.breakdown.system_tasks.count) tasks x $($riskScore.breakdown.system_tasks.weight) = $($riskScore.breakdown.system_tasks.score) points`n"
        }
        if ($riskScore.breakdown.unsigned_elevated) {
            $reportContent += "  * Unsigned Elevated:    $($riskScore.breakdown.unsigned_elevated.count) processes x $($riskScore.breakdown.unsigned_elevated.weight) = $($riskScore.breakdown.unsigned_elevated.score) points`n"
        }
        if ($riskScore.breakdown.suspicious_timing) {
            $reportContent += "  * Suspicious Timing:    $($riskScore.breakdown.suspicious_timing.count) tasks x $($riskScore.breakdown.suspicious_timing.weight) = $($riskScore.breakdown.suspicious_timing.score) points`n"
        }
        
        $reportContent += "`n  Base Score: $($riskScore.base_score)`n"
        
        if ($riskScore.multipliers -and $riskScore.multipliers.Count -gt 0) {
            $reportContent += "`n  MULTIPLIERS APPLIED:`n"
            foreach ($mult in $riskScore.multipliers) {
                $reportContent += "    x $($mult.value) - $($mult.reason)`n"
            }
        }
        
        $reportContent += "`n"
    }


# Add changes section
if ($comparison) {
    $totalCritical = if ($comparison.risk_assessment.critical) { $comparison.risk_assessment.critical.Count } else { 0 }
    $totalHigh = if ($comparison.risk_assessment.high) { $comparison.risk_assessment.high.Count } else { 0 }
    $totalMedium = if ($comparison.risk_assessment.medium) { $comparison.risk_assessment.medium.Count } else { 0 }
    $totalLow = if ($comparison.risk_assessment.low) { $comparison.risk_assessment.low.Count } else { 0 }
    
    $reportContent += @"
═══════════════════════════════════════════════════════════════════
                        DETECTED CHANGES
═══════════════════════════════════════════════════════════════════

Comparing: $($comparison.previous_snapshot) → $($comparison.current_snapshot)

Change Summary:
  [C] Critical Changes:  $totalCritical
  [H] High Risk Changes: $totalHigh
  [M] Medium Risk:       $totalMedium
  [L] Low Risk:          $totalLow

"@

    # Critical changes
    if ($totalCritical -gt 0) {
        $reportContent += "[CRITICAL] CRITICAL RISK CHANGES`n"
        $reportContent += "----------------------------------------------------------------------`n"
        foreach ($change in $comparison.risk_assessment.critical) {
            $reportContent += "  * [$($change.category)] $($change.description)`n"
            if ($change.details.path) {
                $reportContent += "    Location: $($change.details.path)`n"
            }
            if ($change.details.command) {
                $reportContent += "    Command: $($change.details.command)`n"
            }
            $reportContent += "`n"
        }
    }
    
    # High risk changes
    if ($totalHigh -gt 0) {
        $reportContent += "[HIGH] HIGH RISK CHANGES`n"
        $reportContent += "----------------------------------------------------------------------`n"
        foreach ($change in $comparison.risk_assessment.high) {
            $reportContent += "  * [$($change.category)] $($change.description)`n"
            if ($change.details.path) {
                $reportContent += "    Location: $($change.details.path)`n"
            }
            if ($change.details.signed -ne $null) {
                $signed = if ($change.details.signed) { "Yes" } else { "No [WARNING]" }
                $reportContent += "    Digitally Signed: $signed`n"
            }
            $reportContent += "`n"
        }
    }
    
    # Medium risk changes
    if ($totalMedium -gt 0) {
        $reportContent += "[MEDIUM] MEDIUM RISK CHANGES`n"
        $reportContent += "----------------------------------------------------------------------`n"
        foreach ($change in $comparison.risk_assessment.medium) {
            $reportContent += "  * [$($change.category)] $($change.description)`n"
            if ($change.details.location) {
                $reportContent += "    Location: $($change.details.location)`n"
            }
            $reportContent += "`n"
        }
    }
    
    # Summary of all changes
    $reportContent += "`nDETAILED CHANGE BREAKDOWN:`n"
    $reportContent += "----------------------------------------------------------------------`n"
    $reportContent += "  Admin Users:        +$($comparison.admin_users.added.Count) / -$($comparison.admin_users.removed.Count)`n"
    $reportContent += "  Elevated Processes: +$($comparison.elevated_processes.added.Count) / -$($comparison.elevated_processes.removed.Count)`n"
    $reportContent += "  Scheduled Tasks:    +$($comparison.scheduled_tasks.added.Count) / -$($comparison.scheduled_tasks.removed.Count)`n"
    $reportContent += "  Services:           +$($comparison.services.added.Count) / -$($comparison.services.removed.Count)`n"
    $reportContent += "  Startup Items:      +$($comparison.startup_items.added.Count) / -$($comparison.startup_items.removed.Count)`n"
    $reportContent += "`n"
}

# Recommendations
if ($riskScore -and $riskScore.final_score -gt 30) {
    $reportContent += @"
═══════════════════════════════════════════════════════════════════
                        RECOMMENDATIONS
═══════════════════════════════════════════════════════════════════

"@

    if ($riskScore.breakdown.unsigned_elevated.count -gt 0) {
        $reportContent += "[WARNING] URGENT: $($riskScore.breakdown.unsigned_elevated.count) unsigned process(es) running with elevated privileges`n"
        $reportContent += "   -> Review and remove unnecessary elevated executables`n"
        $reportContent += "   -> Verify legitimacy of unsigned elevated software`n`n"
    }
    
    if ($riskScore.breakdown.admin_users.count -gt 2) {
        $reportContent += "[*] Review admin accounts: $($riskScore.breakdown.admin_users.count) admin users detected`n"
        $reportContent += "   -> Apply principle of least privilege`n"
        $reportContent += "   -> Remove unnecessary admin accounts`n`n"
    }
    
    if ($riskScore.breakdown.suspicious_timing.count -gt 0) {
        $reportContent += "[TIME] $($riskScore.breakdown.suspicious_timing.count) task(s) created during suspicious hours (12 AM - 5 AM)`n"
        $reportContent += "   -> Investigate these tasks for potential malware`n"
        $reportContent += "   -> Verify their necessity and origin`n`n"
    }
    
    if ($riskScore.final_score -ge 60) {
        $reportContent += "[*] General recommendations:`n"
        $reportContent += "   -> Run a full malware scan`n"
        $reportContent += "   -> Review all elevated privileges manually`n"
        $reportContent += "   -> Consider establishing a new security baseline`n"
        $reportContent += "   -> Schedule regular privilege audits`n`n"
    }
}

# Footer
$reportContent += @"
═══════════════════════════════════════════════════════════════════
                           NEXT STEPS
═══════════════════════════════════════════════════════════════════

1. Review critical and high-risk changes immediately
2. Verify legitimacy of all new elevated privileges
3. Remove or downgrade unnecessary elevated access
4. Update whitelist for approved privileges
5. Re-run analysis to verify improvements

For detailed information, see:
  - Full snapshots: .\snapshots\
  - Comparison data: $ComparisonPath
  - Risk details: $RiskScorePath

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          Built with Privilege Drift v0.1 - Open Source Security
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"@

# Save text report
$textReportFile = Join-Path $OutputPath "drift-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$latestTextFile = Join-Path $OutputPath "drift-report-latest.txt"

Write-Host "`n[*] Saving report..." -ForegroundColor Yellow
try {
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $reportContent | Out-File -FilePath $textReportFile -Encoding UTF8 -Force
    Write-Host "    [OK] Saved text report: $textReportFile" -ForegroundColor Green
    
    $reportContent | Out-File -FilePath $latestTextFile -Encoding UTF8 -Force
    Write-Host "    [OK] Updated: $latestTextFile" -ForegroundColor Green
    
}
catch {
    Write-Host "    [ERROR] Error saving report: $_" -ForegroundColor Red
    exit 1
}

# Display report to console
Write-Host "`n$reportContent" -ForegroundColor White

# Log operation
$logFile = ".\logs\audit.log"
$logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Report generated"
Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue

Write-Host "`n[SUCCESS] Report generation complete!" -ForegroundColor Green
Write-Host "[*] View report: $latestTextFile`n" -ForegroundColor Cyan
