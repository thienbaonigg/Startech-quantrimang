<#
.SYNOPSIS
    Cấu hình Windows Server Backup cho Server01 (DC1), Server02, Server03
    - Backup định kỳ (Daily Full + System State)
    - Backup AD (System State) trên DC
    - Lưu trữ trên ổ đĩa riêng/Network Share
    - Tuân thủ quy tắc 3-2-1 (script chỉ làm phần local)

.NOTES
    Chạy trên từng Server với quyền Administrator
    Yêu cầu: Ổ đĩa backup riêng (ví dụ E:) hoặc Network Share
#>

# ============================================================
# CẤU HÌNH
# ============================================================
$BackupDrive = "E:"  # Thay đổi: ổ đĩa backup chuyên dụng
$BackupShare = "\\Server02\IT_Software\Backups"  # Network share alternative
$RetentionDays = 14
$BackupTime = "02:00"  # 2 AM daily

$ErrorActionPreference = "Stop"

Write-Host "=== STARTECH - Configure Windows Server Backup ===" -ForegroundColor Cyan
Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor Yellow

# ============================================================
# 1. INSTALL WINDOWS SERVER BACKUP FEATURE
# ============================================================
Write-Host "[1/5] Installing Windows Server Backup feature..." -ForegroundColor Green
Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools -ErrorAction Stop
Install-WindowsFeature -Name RSAT-WSB -ErrorAction SilentlyContinue

# ============================================================
# 2. PREPARE BACKUP TARGET
# ============================================================
Write-Host "[2/5] Preparing backup target..." -ForegroundColor Green

$UseLocalDrive = Test-Path $BackupDrive
$UseNetworkShare = $false

if ($UseLocalDrive) {
    Write-Host "  Using local drive: $BackupDrive" -ForegroundColor Yellow
    $BackupTarget = $BackupDrive
} else {
    Write-Host "  Local drive $BackupDrive not found, trying network share..." -ForegroundColor Yellow
    if (Test-Path $BackupShare) {
        $UseNetworkShare = $true
        $BackupTarget = $BackupShare
        Write-Host "  Using network share: $BackupShare"
    } else {
        Write-Error "No backup target available! Add a dedicated backup drive or configure network share."
    }
}

# ============================================================
# 3. CONFIGURE BACKUP SCHEDULE (WBADMIN)
# ============================================================
Write-Host "[3/5] Configuring backup schedule..." -ForegroundColor Green

# Xác định items cần backup
$IsDC = (Get-ADDomainController -Filter "Name -eq '$env:COMPUTERNAME'" -ErrorAction SilentlyContinue) -ne $null

if ($IsDC) {
    Write-Host "  Domain Controller detected - backing up SYSTEM STATE (AD)" -ForegroundColor Cyan
    $BackupItems = "SYSTEMSTATE"
    $IncludeSystemState = $true
} else {
    Write-Host "  Member Server - backing up Critical Volumes + Data" -ForegroundColor Cyan
    $BackupItems = "C:"  # System volume
    # Thêm ổ dữ liệu nếu có
    if (Test-Path "D:") { $BackupItems += ",D:" }
    $IncludeSystemState = $false
}

# Xóa schedule cũ
$ExistingSchedule = wbadmin get schedule 2>&1
if ($ExistingSchedule -notmatch "No scheduled backup") {
    Write-Host "  Removing existing backup schedule..."
    wbadmin delete schedule -quiet 2>&1 | Out-Null
}

# Tạo schedule mới
if ($UseLocalDrive) {
    $ScheduleCmd = "wbadmin enable backup -addtarget:$BackupTarget -schedule:$BackupTime -include:$BackupItems -quiet"
    if ($IncludeSystemState) { $ScheduleCmd += " -systemState" }
    Write-Host "  Running: $ScheduleCmd"
    Invoke-Expression $ScheduleCmd
} else {
    # Network share cần credential
    Write-Host "  Network share backup requires credentials. Configure manually:" -ForegroundColor Yellow
    Write-Host "    wbadmin enable backup -addtarget:$BackupShare -schedule:$BackupTime -include:$BackupItems -user:DOMAIN\user -password:* -quiet"
    if ($IncludeSystemState) { Write-Host "    (add -systemState for DC)" }
}

# ============================================================
# 4. CONFIGURE RETENTION / CLEANUP
# ============================================================
Write-Host "[4/5] Configuring retention policy..." -ForegroundColor Green

# Windows Server Backup tự quản lý retention dựa trên dung lượng
# Ta tạo script cleanup chạy hàng tuần

$CleanupScript = @"
# STARTECH Backup Cleanup Script
# Chạy bằng Task Scheduler hàng tuần (Chủ nhật 3 AM)

\$BackupDrive = "$BackupDrive"
\$RetentionDays = $RetentionDays

if (Test-Path \$BackupDrive) {
    \$Cutoff = (Get-Date).AddDays(-\$RetentionDays)
    \$OldBackups = Get-ChildItem -Path "\$BackupDrive\WindowsImageBackup" -Directory -ErrorAction SilentlyContinue | Where-Object { \$_.LastWriteTime -lt \$Cutoff }
    foreach (\$Backup in \$OldBackups) {
        Write-Host "Removing old backup: \$(\$Backup.FullName) [\$(\$Backup.LastWriteTime)]"
        # wbadmin delete backup -keepVersions:1 -quiet  # Giữ 1 version gần nhất
        # Hoặc xóa thủ công thư mục cũ (cẩn thận!)
    }
}
"@

$CleanupPath = "C:\Scripts\Backup-Cleanup.ps1"
if (-not (Test-Path "C:\Scripts")) { New-Item -Path "C:\Scripts" -ItemType Directory -Force | Out-Null }
$CleanupScript | Out-File -FilePath $CleanupPath -Encoding UTF8 -Force

# Tạo Scheduled Task cho cleanup
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $CleanupPath"
$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00"
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "STARTECH Backup Cleanup" -Action $Action -Trigger $Trigger -Settings $Settings -User "SYSTEM" -RunLevel Highest -Force -ErrorAction SilentlyContinue
Write-Host "  Created scheduled task: STARTECH Backup Cleanup (Weekly Sun 03:00)"

# ============================================================
# 5. BARE METAL RECOVERY PREP
# ============================================================
Write-Host "[5/5] Preparing Bare Metal Recovery info..." -ForegroundColor Green

$BMRInfo = @"
STARTECH - Bare Metal Recovery Information
===========================================
Server: $env:COMPUTERNAME
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm")
OS: $([System.Environment]::OSVersion.Version)
Is Domain Controller: $IsDC

Backup Target: $BackupTarget
Backup Schedule: Daily $BackupTime
Items: $BackupItems
$(if ($IncludeSystemState) { "Includes: System State (AD Database, SYSVOL, Registry)" })

Recovery Steps:
1. Boot from Windows Server Installation Media
2. Choose 'Repair your computer' -> Troubleshoot -> System Image Recovery
3. Select 'Use the latest available system image' or 'Select a system image'
4. Locate backup on $BackupTarget
5. Restore and reboot

For DC Recovery (Authoritative/Non-Authoritative):
- Non-Authoritative: Restore System State, let replication sync
- Authoritative: Restore System State, set 'database restored from backup' flag, authoritative restore specific OUs

Important Notes:
- Test restore quarterly in isolated environment
- Document DC FSMO roles before disaster
- Keep ADCS Root CA backup separate (private key!)
- Network share backup requires same credentials for restore

Contact: IT Department - STARTECH
"@

$BMRPath = "C:\Scripts\BMR-Info-$env:COMPUTERNAME.txt"
$BMRInfo | Out-File -FilePath $BMRPath -Encoding UTF8 -Force
Write-Host "  BMR Info saved: $BMRPath"

# ============================================================
# VERIFICATION
# ============================================================
Write-Host ""
Write-Host "=== VERIFICATION ===" -ForegroundColor Cyan
Write-Host "Backup Schedule:" -ForegroundColor Yellow
wbadmin get schedule

Write-Host ""
Write-Host "Backup Status:" -ForegroundColor Yellow
wbadmin get versions -backupTarget:$BackupTarget 2>&1 | Select-Object -First 20

Write-Host ""
Write-Host "Manual backup test:" -ForegroundColor Cyan
Write-Host "  wbadmin start backup -backupTarget:$BackupTarget -include:$BackupItems $(if($IncludeSystemState){'-systemState'}) -quiet"
Write-Host ""
Write-Host "Recovery test (quarterly):" -ForegroundColor Cyan
Write-Host "  1. Isolate test environment (no network)"
Write-Host "  2. Boot Windows Setup -> Repair -> System Image Recovery"
Write-Host "  3. Verify AD comes online (dcdiag /v)"
Write-Host "  4. Verify File Shares, IIS, DHCP"
Write-Host ""
Write-Host "NEXT: Run 08-join-domain.ps1 on workstations" -ForegroundColor Cyan