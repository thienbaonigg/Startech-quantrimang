<#
.SYNOPSIS
    Cấu hình File Server trên Server02: Share, NTFS, Quota (FSRM)
    Áp dụng mô hình AGDLP (Account, Global Group, Domain Local Group, Permission)

.NOTES
    Yêu cầu: Server02 đã join domain, có ổ đĩa dữ liệu riêng (ví dụ D:)
    Chạy với Domain Admin
#>

# ============================================================
# CẤU HÌNH
# ============================================================
$DataDrive = "D:"  # Thay đổi nếu ổ dữ liệu khác
$ShareRoot = "$DataDrive\Shares"
$DomainName = "startech.local"

$Shares = @(
    @{
        Name = "Data"
        Path = "$ShareRoot\Data"
        Description = "Chia se du lieu chung cong ty"
        Groups = @(
            @{Group="GG_Sales"; Rights="Modify"},
            @{Group="GG_Accounting"; Rights="Modify"},
            @{Group="GG_HR"; Rights="Modify"},
            @{Group="GG_IT"; Rights="FullControl"},
            @{Group="GG_Technical"; Rights="Modify"},
            @{Group="GG_Management"; Rights="FullControl"}
        )
        QuotaGB = 100
    },
    @{
        Name = "IT_Software"
        Path = "$ShareRoot\IT_Software"
        Description = "Phan mem, driver, ISO, script IT"
        Groups = @(
            @{Group="GG_IT"; Rights="FullControl"},
            @{Group="GG_Technical"; Rights="Read"}
        )
        QuotaGB = 50
    },
    @{
        Name = "Public"
        Path = "$ShareRoot\Public"
        Description = "Thu muc cong khai (read-only cho nhan vien)"
        Groups = @(
            @{Group="Domain Users"; Rights="Read"},
            @{Group="GG_IT"; Rights="FullControl"}
        )
        QuotaGB = 10
    },
    @{
        Name = "HR_Confidential"
        Path = "$ShareRoot\HR_Confidential"
        Description = "Ho so nhan su - chi HR va Giam doc"
        Groups = @(
            @{Group="GG_HR"; Rights="FullControl"},
            @{Group="GG_Management"; Rights="Read"}
        )
        QuotaGB = 5
    },
    @{
        Name = "Accounting"
        Path = "$ShareRoot\Accounting"
        Description = "Du lieu ke toan - chi Ke toan va Giam doc"
        Groups = @(
            @{Group="GG_Accounting"; Rights="Modify"},
            @{Group="GG_Management"; Rights="Read"}
        )
        QuotaGB = 20
    }
)

$ErrorActionPreference = "Stop"

Write-Host "=== STARTECH Server02 - Configure File Server (Share/NTFS/Quota) ===" -ForegroundColor Cyan

# ============================================================
# 1. INSTALL FILE SERVER ROLES
# ============================================================
Write-Host "[1/5] Installing File Server & FSRM roles..." -ForegroundColor Green
Install-WindowsFeature -Name FS-FileServer, FS-Resource-Manager, RSAT-FSRM-Mgmt -IncludeManagementTools -ErrorAction Stop

# ============================================================
# 2. CREATE DIRECTORY STRUCTURE & NTFS PERMISSIONS
# ============================================================
Write-Host "[2/5] Creating folders and setting NTFS permissions..." -ForegroundColor Green

if (-not (Test-Path $ShareRoot)) {
    New-Item -Path $ShareRoot -ItemType Directory -Force | Out-Null
}

foreach ($Share in $Shares) {
    Write-Host "  Processing: $($Share.Name) -> $($Share.Path)" -ForegroundColor Yellow

    # Tạo thư mục
    if (-not (Test-Path $Share.Path)) {
        New-Item -Path $Share.Path -ItemType Directory -Force | Out-Null
    }

    # Disable inheritance, convert to explicit
    $Acl = Get-Acl -Path $Share.Path
    $Acl.SetAccessRuleProtection($true, $true)  # $true = protect, $true = preserve existing
    Set-Acl -Path $Share.Path -AclObject $Acl

    # Xóa các ACE thừa (chỉ giữ SYSTEM, Administrators, CREATOR OWNER)
    $Acl = Get-Acl -Path $Share.Path
    $RulesToRemove = @()
    foreach ($Rule in $Acl.Access) {
        $Identity = $Rule.IdentityReference.Value
        if ($Identity -notmatch "^(NT AUTHORITY\\SYSTEM|BUILTIN\\Administrators|CREATOR OWNER)$") {
            $RulesToRemove += $Rule
        }
    }
    foreach ($Rule in $RulesToRemove) {
        $Acl.RemoveAccessRule($Rule) | Out-Null
    }

    # Thêm quyền cho từng Group (AGDLP: Domain Local Group -> Permission)
    # Ở đây dùng Global Group trực tiếp cho demo, production nên tạo DLG
    foreach ($G in $Share.Groups) {
        $GroupName = "$DomainName\$($G.Group)"
        $Rights = $G.Rights
        $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $GroupName, $Rights, "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $Acl.AddAccessRule($Rule)
        Write-Host "    NTFS: $GroupName -> $Rights"
    }

    # SYSTEM & Administrators FullControl
    $SysRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $Acl.AddAccessRule($SysRule)

    $AdminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $Acl.AddAccessRule($AdminRule)

    Set-Acl -Path $Share.Path -AclObject $Acl
}

# ============================================================
# 3. CREATE SMB SHARES
# ============================================================
Write-Host "[3/5] Creating SMB Shares..." -ForegroundColor Green

foreach ($Share in $Shares) {
    $ShareName = $Share.Name
    $SharePath = $Share.Path
    $Desc = $Share.Description

    # Xóa share cũ nếu có
    if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
        Remove-SmbShare -Name $ShareName -Force -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Tạo share mới - Share permission: Authenticated Users Change (mở rộng)
    New-SmbShare -Name $ShareName -Path $SharePath -FullAccess "BUILTIN\Administrators" -ChangeAccess "NT AUTHORITY\Authenticated Users" -Description $Desc -ErrorAction Stop
    Write-Host "  Created share: \\$env:COMPUTERNAME\$ShareName (Authenticated Users: Change)"
}

# ============================================================
# 4. CONFIGURE FSRM QUOTA
# ============================================================
Write-Host "[4/5] Configuring FSRM Quotas..." -ForegroundColor Green

# Tạo Quota Template
$TemplateName = "STARTECH_Standard_Quota"
if (-not (Get-FsrmQuotaTemplate -Name $TemplateName -ErrorAction SilentlyContinue)) {
    New-FsrmQuotaTemplate -Name $TemplateName -Description "Standard quota template for STARTECH" -Size 100GB -SoftLimit $false -ErrorAction SilentlyContinue
}

foreach ($Share in $Shares) {
    $QuotaSize = $Share.QuotaGB * 1GB
    $QuotaPath = $Share.Path

    # Xóa quota cũ
    if (Get-FsrmQuota -Path $QuotaPath -ErrorAction SilentlyContinue) {
        Remove-FsrmQuota -Path $QuotaPath -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Tạo quota mới
    New-FsrmQuota -Path $QuotaPath -Description "Quota for $($Share.Name)" -Size $QuotaSize -SoftLimit $false -Threshold @(80, 90, 95) -ErrorAction Stop
    Write-Host "  Quota: $($Share.Name) -> $($Share.QuotaGB) GB (Hard limit)"

    # Cấu hình action khi vượt ngưỡng (Event log + Email)
    $Action = New-FsrmFmjNotificationAction -Type Event -EventType Error -Message "Quota exceeded for $($Share.Name) on $env:COMPUTERNAME"
    Set-FsrmQuota -Path $QuotaPath -ThresholdAction @{80=$Action; 90=$Action; 95=$Action} -ErrorAction SilentlyContinue
}

# ============================================================
# 5. FILE SCREENS (Chặn file nguy hiểm)
# ============================================================
Write-Host "[5/5] Configuring File Screens (Block dangerous extensions)..." -ForegroundColor Green

$ScreenTemplate = "STARTECH_Block_Executables"
$BadExtensions = @("*.exe", "*.bat", "*.cmd", "*.vbs", "*.js", "*.ps1", "*.scr", "*.com", "*.pif", "*.msi", "*.dll", "*.jar")

if (-not (Get-FsrmFileScreenTemplate -Name $ScreenTemplate -ErrorAction SilentlyContinue)) {
    New-FsrmFileScreenTemplate -Name $ScreenTemplate -Description "Block executable files" -IncludeGroup @("Executable Files") -Active $true -ErrorAction Stop
}

# Tạo File Group cho executable (nếu chưa có)
if (-not (Get-FsrmFileGroup -Name "Executable Files" -ErrorAction SilentlyContinue)) {
    New-FsrmFileGroup -Name "Executable Files" -Members $BadExtensions -ErrorAction Stop
}

foreach ($Share in $Shares) {
    $ScreenPath = $Share.Path
    if (-not (Get-FsrmFileScreen -Path $ScreenPath -ErrorAction SilentlyContinue)) {
        New-FsrmFileScreen -Path $ScreenPath -Template $ScreenTemplate -Active $true -ErrorAction Stop
        Write-Host "  File Screen applied: $($Share.Name)"
    }
}

# ============================================================
# VERIFICATION
# ============================================================
Write-Host ""
Write-Host "=== VERIFICATION ===" -ForegroundColor Cyan
Write-Host "Shares:" -ForegroundColor Yellow
Get-SmbShare | Where-Object { $_.Name -notlike "ADMIN$" -and $_.Name -notlike "C$" -and $_.Name -notlike "IPC$" } | Format-Table Name, Path, Description -AutoSize

Write-Host ""
Write-Host "Quotas:" -ForegroundColor Yellow
Get-FsrmQuota | Format-Table Path, Size, Usage, SoftLimit -AutoSize

Write-Host ""
Write-Host "File Screens:" -ForegroundColor Yellow
Get-FsrmFileScreen | Format-Table Path, Active -AutoSize

Write-Host ""
Write-Host "Test from workstation:" -ForegroundColor Cyan
Write-Host "  net use Z: \\\\$env:COMPUTERNAME\\Data /user:STARTECH\username"
Write-Host "  icacls Z:"
Write-Host ""
Write-Host "NEXT: Run 06-config-gpo.ps1" -ForegroundColor Cyan