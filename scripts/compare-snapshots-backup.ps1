# Privilege Drift - Snapshot Comparison Script
# Compares two snapshots and detects privilege drift

param(
    [string]$CurrentSnapshot = ".\snapshots\latest.json",
    [string]$PreviousSnapshot = "",
    [string]$OutputPath = ".\reports",
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

Write-Host "🔐 Privilege Drift - Snapshot Comparison" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# Load whitelist configuration
$whitelistPath = ".\config\whitelist.json"
$whitelist = @{}
if (Test-Path $whitelistPath) {
    $whitelist = Get-Content $whitelistPath | ConvertFrom-Json
}

# Load current snapshot
if (-not (Test-Path $CurrentSnapshot)) {
    Write-Host "❌ Current snapshot not found: $CurrentSnapshot" -ForegroundColor Red
    exit 1
}

Write-Host "📂 Loading current snapshot..." -ForegroundColor Yellow
$current = Get-Content $CurrentSnapshot | ConvertFrom-Json
Write-Host "   ✓ Loaded: $($current.snapshot_id)" -ForegroundColor Green

# Find previous snapshot
if (-not $PreviousSnapshot) {
    # Get the second most recent snapshot
    $snapshots = Get-ChildItem -Path ".\snapshots\*.json" | 
    Where-Object { $_.Name -ne "latest.json" -and $_.Name -ne "baseline.json" } | 
    Sort-Object LastWriteTime -Descending
    
    if ($snapshots.Count -ge 2) {
        $PreviousSnapshot = $snapshots[1].FullName
    }
    elseif ($snapshots.Count -eq 1) {
        $PreviousSnapshot = $snapshots[0].FullName
    }
    else {
        Write-Host "⚠️  No previous snapshot found. This will be treated as the baseline." -ForegroundColor Yellow
        $previous = @{
            admin_users        = @()
            elevated_processes = @()
            scheduled_tasks    = @()
            services           = @()
            startup_items      = @()
        }
    }
}

if ($PreviousSnapshot -and (Test-Path $PreviousSnapshot)) {
    Write-Host "📂 Loading previous snapshot..." -ForegroundColor Yellow
    $previous = Get-Content $PreviousSnapshot | ConvertFrom-Json
    Write-Host "   ✓ Loaded: $($previous.snapshot_id)" -ForegroundColor Green
}
else {
    # If we still don't have a previous snapshot, use empty baseline
    if (-not $previous) {
        $previous = @{
            admin_users        = @()
            elevated_processes = @()
            scheduled_tasks    = @()
            services           = @()
            startup_items      = @()
        }
    }
}

Write-Host "`n🔍 Analyzing changes...`n" -ForegroundColor Yellow

# Initialize changes tracking
$changes = @{
    timestamp          = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    current_snapshot   = $current.snapshot_id
    previous_snapshot  = if ($previous.snapshot_id) { $previous.snapshot_id } else { "baseline" }
    admin_users        = @{
        added    = @()
        removed  = @()
        modified = @()
    }
    elevated_processes = @{
        added   = @()
        removed = @()
    }
    scheduled_tasks    = @{
        added    = @()
        removed  = @()
        modified = @()
    }
    services           = @{
        added    = @()
        removed  = @()
        modified = @()
    }
    startup_items      = @{
        added   = @()
        removed = @()
    }
    risk_assessment    = @{
        critical = @()
        high     = @()
        medium   = @()
        low      = @()
    }
}

# Helper function to check if item is whitelisted
function Test-Whitelisted {
    param($Category, $Item)
    
    if (-not $whitelist.$Category) { return $false }
    
    switch ($Category) {
        "admin_users" {
            return $whitelist.admin_users -contains $Item.username
        }
        "services" {
            $whitelistedService = $whitelist.services | Where-Object { $_.name -eq $Item.name }
            return $null -ne $whitelistedService
        }
        "scheduled_tasks" {
            foreach ($wlTask in $whitelist.scheduled_tasks) {
                if ($Item.path -like "$($wlTask.path)*") {
                    return $true
                }
            }
            return $false
        }
        "processes" {
            $whitelistedProc = $whitelist.processes | Where-Object { 
                $_.name -eq $Item.name -or $_.path -eq $Item.path 
            }
            return $null -ne $whitelistedProc
        }
    }
    return $false
}

# Helper function to assess risk level
function Get-RiskLevel {
    param($Category, $Change, $ChangeType)
    
    # Critical: New admin user, new SYSTEM service
    if ($Category -eq "admin_users" -and $ChangeType -eq "added") {
        if (-not (Test-Whitelisted -Category "admin_users" -Item $Change)) {
            return "critical"
        }
    }
    
    if ($Category -eq "services" -and $ChangeType -eq "added") {
        if ($Change.run_as -match "SYSTEM|LocalSystem" -and -not $Change.signed) {
            return "critical"
        }
    }
    
    if ($Category -eq "scheduled_tasks" -and $ChangeType -eq "added") {
        if ($Change.run_as -match "SYSTEM") {
            return "high"
        }
    }
    
    # High: Unsigned elevated executable
    if ($Category -eq "elevated_processes" -and $ChangeType -eq "added") {
        if (-not $Change.signed) {
            return "high"
        }
    }
    
    # Medium: Startup item added
    if ($Category -eq "startup_items" -and $ChangeType -eq "added") {
        return "medium"
    }
    
    # Default to low
    return "low"
}

# Compare Admin Users
Write-Host "👥 Comparing admin users..." -ForegroundColor Cyan
$prevUsernames = $previous.admin_users | ForEach-Object { $_.username }
$currUsernames = $current.admin_users | ForEach-Object { $_.username }

foreach ($user in $current.admin_users) {
    if ($user.username -notin $prevUsernames) {
        $changes.admin_users.added += $user
        $risk = Get-RiskLevel -Category "admin_users" -Change $user -ChangeType "added"
        $changes.risk_assessment.$risk += @{
            category    = "Admin User"
            change      = "Added"
            details     = $user
            description = "New admin user: $($user.username)"
        }
    }
}

foreach ($user in $previous.admin_users) {
    if ($user.username -notin $currUsernames) {
        $changes.admin_users.removed += $user
    }
}

Write-Host "   ✓ Found $($changes.admin_users.added.Count) new, $($changes.admin_users.removed.Count) removed" -ForegroundColor Green

# Compare Elevated Processes
Write-Host "⚡ Comparing elevated processes..." -ForegroundColor Cyan
$prevProcPaths = $previous.elevated_processes | ForEach-Object { $_.path }
$currProcPaths = $current.elevated_processes | ForEach-Object { $_.path }

foreach ($proc in $current.elevated_processes) {
    if ($proc.path -notin $prevProcPaths) {
        if (-not (Test-Whitelisted -Category "processes" -Item $proc)) {
            $changes.elevated_processes.added += $proc
            $risk = Get-RiskLevel -Category "elevated_processes" -Change $proc -ChangeType "added"
            $changes.risk_assessment.$risk += @{
                category    = "Elevated Process"
                change      = "Added"
                details     = $proc
                description = "New elevated process: $($proc.name) at $($proc.path)"
            }
        }
    }
}

foreach ($proc in $previous.elevated_processes) {
    if ($proc.path -notin $currProcPaths) {
        $changes.elevated_processes.removed += $proc
    }
}

Write-Host "   ✓ Found $($changes.elevated_processes.added.Count) new, $($changes.elevated_processes.removed.Count) removed" -ForegroundColor Green

# Compare Scheduled Tasks
Write-Host "📅 Comparing scheduled tasks..." -ForegroundColor Cyan
$prevTaskNames = $previous.scheduled_tasks | ForEach-Object { $_.path + $_.name }
$currTaskNames = $current.scheduled_tasks | ForEach-Object { $_.path + $_.name }

foreach ($task in $current.scheduled_tasks) {
    $taskKey = $task.path + $task.name
    if ($taskKey -notin $prevTaskNames) {
        if (-not (Test-Whitelisted -Category "scheduled_tasks" -Item $task)) {
            $changes.scheduled_tasks.added += $task
            $risk = Get-RiskLevel -Category "scheduled_tasks" -Change $task -ChangeType "added"
            
            # Check for suspicious timing
            $isSuspicious = $false
            if ($task.created -ne "N/A") {
                try {
                    $createdTime = [DateTime]::Parse($task.created)
                    $hour = $createdTime.Hour
                    if ($hour -ge 0 -and $hour -le 5) {
                        $isSuspicious = $true
                        $risk = "high"
                    }
                }
                catch {}
            }
            
            $desc = "New scheduled task: $($task.name) (runs as $($task.run_as))"
            if ($isSuspicious) {
                $desc += " ⚠️ Created during suspicious hours"
            }
            
            $changes.risk_assessment.$risk += @{
                category    = "Scheduled Task"
                change      = "Added"
                details     = $task
                description = $desc
            }
        }
    }
}

foreach ($task in $previous.scheduled_tasks) {
    $taskKey = $task.path + $task.name
    if ($taskKey -notin $currTaskNames) {
        $changes.scheduled_tasks.removed += $task
    }
}

Write-Host "   ✓ Found $($changes.scheduled_tasks.added.Count) new, $($changes.scheduled_tasks.removed.Count) removed" -ForegroundColor Green

# Compare Services
Write-Host "⚙️  Comparing services..." -ForegroundColor Cyan
$prevSvcNames = $previous.services | ForEach-Object { $_.name }
$currSvcNames = $current.services | ForEach-Object { $_.name }

foreach ($svc in $current.services) {
    if ($svc.name -notin $prevSvcNames) {
        if (-not (Test-Whitelisted -Category "services" -Item $svc)) {
            $changes.services.added += $svc
            $risk = Get-RiskLevel -Category "services" -Change $svc -ChangeType "added"
            $changes.risk_assessment.$risk += @{
                category    = "Service"
                change      = "Added"
                details     = $svc
                description = "New service: $($svc.display_name) (runs as $($svc.run_as))"
            }
        }
    }
}

foreach ($svc in $previous.services) {
    if ($svc.name -notin $currSvcNames) {
        $changes.services.removed += $svc
    }
}

Write-Host "   ✓ Found $($changes.services.added.Count) new, $($changes.services.removed.Count) removed" -ForegroundColor Green

# Compare Startup Items
Write-Host "🚀 Comparing startup items..." -ForegroundColor Cyan
$prevStartupCmds = $previous.startup_items | ForEach-Object { $_.command }
$currStartupCmds = $current.startup_items | ForEach-Object { $_.command }

foreach ($item in $current.startup_items) {
    if ($item.command -notin $prevStartupCmds) {
        $changes.startup_items.added += $item
        $risk = Get-RiskLevel -Category "startup_items" -Change $item -ChangeType "added"
        $changes.risk_assessment.$risk += @{
            category    = "Startup Item"
            change      = "Added"
            details     = $item
            description = "New startup item: $($item.name)"
        }
    }
}

foreach ($item in $previous.startup_items) {
    if ($item.command -notin $currStartupCmds) {
        $changes.startup_items.removed += $item
    }
}

Write-Host "   ✓ Found $($changes.startup_items.added.Count) new, $($changes.startup_items.removed.Count) removed" -ForegroundColor Green

# Save comparison results
$outputFile = Join-Path $OutputPath "comparison-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
Write-Host "`n💾 Saving comparison results..." -ForegroundColor Yellow

try {
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $changes | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8 -Force
    Write-Host "   ✓ Saved to: $outputFile" -ForegroundColor Green
    
    # Also save as latest
    $latestFile = Join-Path $OutputPath "comparison-latest.json"
    $changes | ConvertTo-Json -Depth 10 | Out-File -FilePath $latestFile -Encoding UTF8 -Force
    
}
catch {
    Write-Host "   ✗ Error saving comparison: $_" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host "`n📊 Change Summary:" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "   🔴 Critical: $($changes.risk_assessment.critical.Count)" -ForegroundColor Red
Write-Host "   🟠 High:     $($changes.risk_assessment.high.Count)" -ForegroundColor Yellow
Write-Host "   🟡 Medium:   $($changes.risk_assessment.medium.Count)" -ForegroundColor Yellow
Write-Host "   🟢 Low:      $($changes.risk_assessment.low.Count)" -ForegroundColor Green
Write-Host "`nComparison complete!" -ForegroundColor Green

# Return the comparison object for use by other scripts
return $changes
