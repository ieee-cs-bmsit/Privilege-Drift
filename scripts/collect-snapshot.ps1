# Privilege Drift - Snapshot Collection Script
# Collects current system privilege state and saves to JSON

param(
    [string]$OutputPath = ".\snapshots",
    [switch]$Verbose
)

# Requires Administrator privileges
#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
$snapshotId = Get-Date -Format "yyyyMMdd-HHmmss"
$hostname = $env:COMPUTERNAME

Write-Host "[*] Privilege Drift - Snapshot Collection" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "[*] Timestamp: $timestamp"
Write-Host "[*] Hostname: $hostname"
Write-Host ""

# Initialize snapshot object
$snapshot = @{
    timestamp          = $timestamp
    hostname           = $hostname
    snapshot_id        = $snapshotId
    admin_users        = @()
    elevated_processes = @()
    scheduled_tasks    = @()
    services           = @()
    startup_items      = @()
}

# Function to get file hash safely
function Get-SafeFileHash {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            $hash = Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction SilentlyContinue
            return $hash.Hash
        }
    }
    catch {}
    return "N/A"
}

# Function to check if file is signed
# Function to check if file is signed
function Test-FileSigned {
    param(
        [string]$Path,
        [switch]$Detailed  # Optional: return detailed signing info
    )
    
    # Handle empty or null paths
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    
    # Clean path (remove quotes, extract executable from arguments)
    $cleanPath = $Path.Trim('"').Trim()
    
    # Extract just the executable path (before any arguments)
    if ($cleanPath -match '^([A-Za-z]:\\[^/|<>]+\.exe)') {
        $cleanPath = $matches[1]
    }
    elseif ($cleanPath -match '^([A-Za-z]:\\[^/|<>]+\.dll)') {
        $cleanPath = $matches[1]
    }
    else {
        # Try splitting on space for simple "path.exe -args" format
        $cleanPath = $cleanPath.Split(' ')[0]
    }
    
    try {
        # Check if file exists using LiteralPath
        if (-not (Test-Path -LiteralPath $cleanPath -ErrorAction SilentlyContinue)) {
            return $false
        }
        
        # Get authenticode signature
        $sig = Get-AuthenticodeSignature -FilePath $cleanPath -ErrorAction SilentlyContinue
        
        if ($Detailed) {
            # Return detailed information
            return [PSCustomObject]@{
                IsSigned               = ($sig.Status -eq 'Valid')
                Status                 = $sig.Status
                SignerCertificate      = $sig.SignerCertificate.Subject
                TimeStamperCertificate = $sig.TimeStamperCertificate.Subject
                IsOSBinary             = ($sig.IsOSBinary -eq $true)
            }
        }
        else {
            # Return simple boolean
            return ($sig.Status -eq 'Valid')
        }
    }
    catch {
        # Silently handle any errors
        return $false
    }
}

# 1. Collect Admin Users
Write-Host "[+] Collecting admin users..." -ForegroundColor Yellow
try {
    $adminGroup = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
    foreach ($member in $adminGroup) {
        $lastLogin = "N/A"
        if ($member.ObjectClass -eq "User") {
            try {
                $user = Get-LocalUser -Name $member.Name.Split('\')[-1] -ErrorAction SilentlyContinue
                if ($user.LastLogon) {
                    $lastLogin = $user.LastLogon.ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
            catch {}
        }
        
        $snapshot.admin_users += @{
            username     = $member.Name
            sid          = $member.SID.Value
            object_class = $member.ObjectClass
            last_login   = $lastLogin
        }
    }
    Write-Host "    [OK] Found $($snapshot.admin_users.Count) admin users" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Error collecting admin users: $_" -ForegroundColor Red
}

# 2. Collect Elevated Processes (running with high privileges)
Write-Host "[+] Collecting elevated processes..." -ForegroundColor Yellow
try {
    $processes = Get-Process | Where-Object { $_.Path } | Select-Object -Unique Name, Path
    $elevatedProcesses = @()
    
    foreach ($proc in $processes) {
        if ($proc.Path -and (Test-Path $proc.Path)) {
            # Check if running as admin/system (simplified check)
            $isElevated = $false
            try {
                $procInstances = Get-Process -Name $proc.Name -ErrorAction SilentlyContinue
                foreach ($instance in $procInstances) {
                    # Very basic elevation check - in production, use Windows API
                    if ($instance.SessionId -eq 0) {
                        $isElevated = $true
                        break
                    }
                }
            }
            catch {}
            
            if ($isElevated) {
                $hash = Get-SafeFileHash -Path $proc.Path
                $signed = Test-FileSigned -Path $proc.Path
                
                $elevatedProcesses += @{
                    name            = $proc.Name
                    path            = $proc.Path
                    privilege_level = "Elevated"
                    hash            = "sha256:$hash"
                    signed          = $signed
                    first_seen      = $timestamp
                }
            }
        }
    }
    
    $snapshot.elevated_processes = $elevatedProcesses
    Write-Host "    [OK] Found $($elevatedProcesses.Count) elevated processes" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Error collecting processes: $_" -ForegroundColor Red
}

# 3. Collect Scheduled Tasks with elevated privileges
Write-Host "[+] Collecting scheduled tasks..." -ForegroundColor Yellow
try {
    $tasks = Get-ScheduledTask | Where-Object { 
        $_.Principal.UserId -match "SYSTEM|Administrators" -or 
        $_.Principal.RunLevel -eq "Highest" 
    }
    
    foreach ($task in $tasks) {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
        
        $created = "N/A"
        if ($taskInfo.LastRunTime) {
            $created = $taskInfo.LastRunTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        
        $action = ""
        if ($task.Actions.Count -gt 0) {
            $action = $task.Actions[0].Execute + " " + $task.Actions[0].Arguments
        }
        
        $trigger = "N/A"
        if ($task.Triggers.Count -gt 0) {
            $trigger = $task.Triggers[0].ToString()
        }
        
        $snapshot.scheduled_tasks += @{
            name      = $task.TaskName
            path      = $task.TaskPath
            run_as    = $task.Principal.UserId
            run_level = $task.Principal.RunLevel
            command   = $action
            created   = $created
            trigger   = $trigger
            enabled   = $task.State -eq "Ready"
        }
    }
    Write-Host "    [OK] Found $($snapshot.scheduled_tasks.Count) elevated tasks" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Error collecting scheduled tasks: $_" -ForegroundColor Red
}

# 4. Collect Services running with high privileges
Write-Host "[+] Collecting services..." -ForegroundColor Yellow
try {
    $services = Get-CimInstance Win32_Service | Where-Object { 
        $_.StartName -match "LocalSystem|SYSTEM|LocalService|NetworkService" 
    }
    
    foreach ($svc in $services) {
        $signed = Test-FileSigned -Path $svc.PathName.Trim('"').Split(' ')[0]
        
        $snapshot.services += @{
            name         = $svc.Name
            display_name = $svc.DisplayName
            run_as       = $svc.StartName
            binary_path  = $svc.PathName
            startup_type = $svc.StartMode
            state        = $svc.State
            signed       = $signed
        }
    }
    Write-Host "    [OK] Found $($snapshot.services.Count) elevated services" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Error collecting services: $_" -ForegroundColor Red
}

# 5. Collect Startup Items
Write-Host "[+] Collecting startup items..." -ForegroundColor Yellow
try {
    # Registry Run keys
    $runKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    
    foreach ($key in $runKeys) {
        if (Test-Path $key) {
            $items = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            $items.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                $snapshot.startup_items += @{
                    location  = $key
                    name      = $_.Name
                    command   = $_.Value
                    privilege = if ($key -match "HKLM") { "System" } else { "User" }
                }
            }
        }
    }
    
    # Startup folder
    $startupFolders = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    )
    
    foreach ($folder in $startupFolders) {
        if (Test-Path $folder) {
            Get-ChildItem -Path $folder -File | ForEach-Object {
                $snapshot.startup_items += @{
                    location  = $folder
                    name      = $_.Name
                    command   = $_.FullName
                    privilege = if ($folder -match "ProgramData") { "System" } else { "User" }
                }
            }
        }
    }
    
    Write-Host "    [OK] Found $($snapshot.startup_items.Count) startup items" -ForegroundColor Green
}
catch {
    Write-Host "    [ERROR] Error collecting startup items: $_" -ForegroundColor Red
}

# Save snapshot to file
$outputFile = Join-Path $OutputPath "$($snapshotId).json"
$latestFile = Join-Path $OutputPath "latest.json"

Write-Host ""
Write-Host "[*] Saving snapshot..." -ForegroundColor Yellow
try {
    # Ensure directory exists
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Convert to JSON with nice formatting
    $jsonContent = $snapshot | ConvertTo-Json -Depth 10
    
    # Save to timestamped file
    $jsonContent | Out-File -FilePath $outputFile -Encoding UTF8 -Force
    Write-Host "    [OK] Saved to: $outputFile" -ForegroundColor Green
    
    # Also save as latest for easy access
    $jsonContent | Out-File -FilePath $latestFile -Encoding UTF8 -Force
    Write-Host "    [OK] Updated: $latestFile" -ForegroundColor Green
    
    # Log operation
    $logFile = ".\logs\audit.log"
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Snapshot created: $snapshotId"
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    
}
catch {
    Write-Host "    [ERROR] Error saving snapshot: $_" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host ""
Write-Host "[*] Snapshot Summary:" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "    Admin Users:        $($snapshot.admin_users.Count)"
Write-Host "    Elevated Processes: $($snapshot.elevated_processes.Count)"
Write-Host "    Scheduled Tasks:    $($snapshot.scheduled_tasks.Count)"
Write-Host "    Services:           $($snapshot.services.Count)"
Write-Host "    Startup Items:      $($snapshot.startup_items.Count)"
Write-Host ""
Write-Host "[SUCCESS] Snapshot collection complete!" -ForegroundColor Green
