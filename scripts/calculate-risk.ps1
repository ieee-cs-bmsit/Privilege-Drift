# Privilege Drift - Risk Score Calculator
# Calculates risk score based on current privilege state

param(
    [string]$SnapshotPath = ".\snapshots\latest.json",
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

Write-Host "🔐 Privilege Drift - Risk Score Calculator" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# Load configuration
$policiesPath = ".\config\policies.json"
if (-not (Test-Path $policiesPath)) {
    Write-Host "❌ Policies file not found: $policiesPath" -ForegroundColor Red
    exit 1
}

$policies = Get-Content $policiesPath | ConvertFrom-Json

# Load snapshot
if (-not (Test-Path $SnapshotPath)) {
    Write-Host "❌ Snapshot not found: $SnapshotPath" -ForegroundColor Red
    exit 1
}

Write-Host "📂 Loading snapshot..." -ForegroundColor Yellow
$snapshot = Get-Content $SnapshotPath | ConvertFrom-Json
Write-Host "   ✓ Loaded: $($snapshot.snapshot_id)`n" -ForegroundColor Green

# Initialize score
$baseScore = 0
$multiplier = 1.0
$details = @{
    timestamp   = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    snapshot_id = $snapshot.snapshot_id
    base_score  = 0
    multipliers = @()
    final_score = 0
    risk_level  = ""
    breakdown   = @{}
}

# Count elevated entities (excluding whitelisted ones)
Write-Host "📊 Calculating base score..." -ForegroundColor Yellow

# Admin users (exclude built-in Administrator, SYSTEM, etc.)
$adminUsers = $snapshot.admin_users | Where-Object { 
    $_.username -notmatch "Administrator|SYSTEM|LOCAL SERVICE|NETWORK SERVICE" 
}
$adminUserScore = $adminUsers.Count * $policies.scoring_weights.admin_users
$baseScore += $adminUserScore
$details.breakdown.admin_users = @{
    count  = $adminUsers.Count
    weight = $policies.scoring_weights.admin_users
    score  = $adminUserScore
}
Write-Host "   • Admin users: $($adminUsers.Count) × $($policies.scoring_weights.admin_users) = $adminUserScore points" -ForegroundColor Gray

# Elevated services (running as SYSTEM/LocalSystem)
$elevatedServices = $snapshot.services | Where-Object { 
    $_.run_as -match "LocalSystem|^SYSTEM$" 
}
$elevatedServiceScore = $elevatedServices.Count * $policies.scoring_weights.elevated_services
$baseScore += $elevatedServiceScore
$details.breakdown.elevated_services = @{
    count  = $elevatedServices.Count
    weight = $policies.scoring_weights.elevated_services
    score  = $elevatedServiceScore
}
Write-Host "   • Elevated services: $($elevatedServices.Count) × $($policies.scoring_weights.elevated_services) = $elevatedServiceScore points" -ForegroundColor Gray

# Startup items with admin privileges
$adminStartupItems = $snapshot.startup_items | Where-Object { 
    $_.privilege -match "System|Admin" 
}
$startupItemScore = $adminStartupItems.Count * $policies.scoring_weights.startup_items_as_admin
$baseScore += $startupItemScore
$details.breakdown.startup_items = @{
    count  = $adminStartupItems.Count
    weight = $policies.scoring_weights.startup_items_as_admin
    score  = $startupItemScore
}
Write-Host "   • Admin startup items: $($adminStartupItems.Count) × $($policies.scoring_weights.startup_items_as_admin) = $startupItemScore points" -ForegroundColor Gray

# Scheduled tasks as SYSTEM
$systemTasks = $snapshot.scheduled_tasks | Where-Object { 
    $_.run_as -match "^SYSTEM$|LocalSystem" 
}
$systemTaskScore = $systemTasks.Count * $policies.scoring_weights.tasks_as_system
$baseScore += $systemTaskScore
$details.breakdown.system_tasks = @{
    count  = $systemTasks.Count
    weight = $policies.scoring_weights.tasks_as_system
    score  = $systemTaskScore
}
Write-Host "   • SYSTEM tasks: $($systemTasks.Count) × $($policies.scoring_weights.tasks_as_system) = $systemTaskScore points" -ForegroundColor Gray

# Unsigned elevated executables
$unsignedElevated = $snapshot.elevated_processes | Where-Object { -not $_.signed }
$unsignedScore = $unsignedElevated.Count * $policies.scoring_weights.unsigned_elevated
$baseScore += $unsignedScore
$details.breakdown.unsigned_elevated = @{
    count  = $unsignedElevated.Count
    weight = $policies.scoring_weights.unsigned_elevated
    score  = $unsignedScore
}
Write-Host "   • Unsigned elevated processes: $($unsignedElevated.Count) × $($policies.scoring_weights.unsigned_elevated) = $unsignedScore points" -ForegroundColor Gray

# Suspicious timing (tasks created between midnight and 5 AM)
$suspiciousTasks = 0
$suspiciousHourStart = $policies.suspicious_hours.start
$suspiciousHourEnd = $policies.suspicious_hours.end

foreach ($task in $snapshot.scheduled_tasks) {
    if ($task.created -ne "N/A") {
        try {
            $createdTime = [DateTime]::Parse($task.created)
            $hour = $createdTime.Hour
            if ($hour -ge $suspiciousHourStart -and $hour -le $suspiciousHourEnd) {
                $suspiciousTasks++
            }
        }
        catch {}
    }
}

$suspiciousTimingScore = $suspiciousTasks * $policies.scoring_weights.suspicious_timing
$baseScore += $suspiciousTimingScore
$details.breakdown.suspicious_timing = @{
    count  = $suspiciousTasks
    weight = $policies.scoring_weights.suspicious_timing
    score  = $suspiciousTimingScore
}
Write-Host "   • Suspicious timing tasks: $suspiciousTasks × $($policies.scoring_weights.suspicious_timing) = $suspiciousTimingScore points" -ForegroundColor Gray

Write-Host "`n   Base Score: $baseScore" -ForegroundColor Cyan

# Apply multipliers
Write-Host "`n📈 Applying multipliers..." -ForegroundColor Yellow

# Long-lived privileges (older than configured threshold)
$thresholdDays = $policies.multipliers.long_lived_privileges_days

# Check how long ago the first snapshot was taken
$snapshots = Get-ChildItem -Path ".\snapshots\*.json" | 
Where-Object { $_.Name -ne "latest.json" } | 
Sort-Object LastWriteTime

if ($snapshots.Count -gt 0) {
    $oldestSnapshot = $snapshots[0]
    $daysSinceFirst = (Get-Date) - $oldestSnapshot.LastWriteTime
    
    if ($daysSinceFirst.TotalDays -ge $thresholdDays) {
        $longLivedMultiplier = $policies.multipliers.long_lived_multiplier
        $multiplier *= $longLivedMultiplier
        $details.multipliers += @{
            type   = "long_lived_privileges"
            value  = $longLivedMultiplier
            reason = "Privileges tracked for $([math]::Round($daysSinceFirst.TotalDays)) days (threshold: $thresholdDays days)"
        }
        Write-Host "   • Long-lived privileges: ×$longLivedMultiplier" -ForegroundColor Yellow
    }
}

# Unsigned executable multiplier (if any unsigned elevated processes exist)
if ($unsignedElevated.Count -gt 0) {
    $unsignedMultiplier = $policies.multipliers.unsigned_executable_multiplier
    $multiplier *= $unsignedMultiplier
    $details.multipliers += @{
        type   = "unsigned_executables"
        value  = $unsignedMultiplier
        reason = "$($unsignedElevated.Count) unsigned elevated executable(s)"
    }
    Write-Host "   • Unsigned executables: ×$unsignedMultiplier" -ForegroundColor Yellow
}

# Calculate final score
$details.base_score = $baseScore
$finalScore = [math]::Min([int]($baseScore * $multiplier), 100)
$details.final_score = $finalScore

# Interpret score
function Get-RiskInterpretation {
    param([int]$Score)
    
    if ($Score -le $policies.risk_thresholds.good) {
        return @{
            level       = "GOOD"
            color       = "Green"
            emoji       = "🟢"
            description = "Normal privilege baseline"
        }
    }
    elseif ($Score -le $policies.risk_thresholds.review) {
        return @{
            level       = "REVIEW"
            color       = "Yellow"
            emoji       = "🟡"
            description = "Some privileges need attention"
        }
    }
    elseif ($Score -le $policies.risk_thresholds.high_risk) {
        return @{
            level       = "HIGH RISK"
            color       = "Red"
            emoji       = "🔴"
            description = "Immediate review recommended"
        }
    }
    else {
        return @{
            level       = "CRITICAL"
            color       = "Red"
            emoji       = "🔴"
            description = "Serious privilege drift detected"
        }
    }
}

$interpretation = Get-RiskInterpretation -Score $finalScore
$details.risk_level = $interpretation.level
$details.description = $interpretation.description

# Display results
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 RISK SCORE RESULTS" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Score: $finalScore/100" -ForegroundColor $interpretation.color
Write-Host "   Level: $($interpretation.emoji) $($interpretation.level)" -ForegroundColor $interpretation.color
Write-Host "   $($interpretation.description)" -ForegroundColor Gray
Write-Host ""

# Show visual gauge
$barLength = 40
$filledLength = [int](($finalScore / 100) * $barLength)
$emptyLength = $barLength - $filledLength
$bar = "█" * $filledLength + "░" * $emptyLength

$gaugeColor = switch -Regex ($interpretation.level) {
    "GOOD" { "Green" }
    "REVIEW" { "Yellow" }
    default { "Red" }
}

Write-Host "   [$bar] $finalScore%" -ForegroundColor $gaugeColor
Write-Host ""

# Recommendations
if ($finalScore -gt $policies.risk_thresholds.good) {
    Write-Host "💡 RECOMMENDATIONS:" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    
    if ($adminUsers.Count -gt 2) {
        Write-Host "   • Review $($adminUsers.Count) admin users - consider reducing elevated accounts" -ForegroundColor Yellow
    }
    
    if ($unsignedElevated.Count -gt 0) {
        Write-Host "   • $($unsignedElevated.Count) unsigned processes running elevated - HIGH RISK" -ForegroundColor Red
    }
    
    if ($suspiciousTasks -gt 0) {
        Write-Host "   • $suspiciousTasks task(s) created during suspicious hours (12 AM - 5 AM)" -ForegroundColor Red
    }
    
    if ($systemTasks.Count -gt 10) {
        Write-Host "   • $($systemTasks.Count) tasks running as SYSTEM - review necessity" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Save risk score
$outputFile = ".\reports\risk-score-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
Write-Host "💾 Saving risk score..." -ForegroundColor Yellow

try {
    if (-not (Test-Path ".\reports")) {
        New-Item -ItemType Directory -Path ".\reports" -Force | Out-Null
    }
    
    $details | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8 -Force
    Write-Host "   ✓ Saved to: $outputFile" -ForegroundColor Green
    
    # Also save as latest
    $latestFile = ".\reports\risk-score-latest.json"
    $details | ConvertTo-Json -Depth 10 | Out-File -FilePath $latestFile -Encoding UTF8 -Force
}
catch {
    Write-Host "   X Error saving risk score: $_" -ForegroundColor Red
}

Write-Host "`nRisk calculation complete!" -ForegroundColor Green

# Return the score details
return $details
