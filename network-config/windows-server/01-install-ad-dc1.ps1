<#
.SYNOPSIS
    Cài đặt Active Directory Domain Services + DNS trên Server01 (DC1)
    Chạy với quyền Administrator trên Windows Server 2022

.DESCRIPTION
    Script cài đặt Forest mới: startech.local
    - AD DS Role
    - DNS Server Role
    - Promote to Domain Controller (Forest root)
    - Tạo OU structure, Security Groups
    - Cấu hình DNS Forwarder, Aging/Scavenging

.NOTES
    Yêu cầu: Static IP 192.168.10.11, DNS trỏ về chính nó (127.0.0.1)
    Chạy trước 02-install-ad-dc2.ps1 trên Server03
#>

# ============================================================
# CẤU HÌNH - CHỈNH SỬA THEO MÔI TRƯỜNG
# ============================================================
$DomainName = "startech.local"
$NetBIOSName = "STARTECH"
$SafeModePassword = "P@ssw0rd123!"  # DSRM Password
$DomainAdminUser = "admin"
$DomainAdminPass = "P@ssw0rd123!"
$OUList = @(
    "Management", "IT", "Sales", "Accounting", "HR", "Technical", "CustomerService",
    "Servers", "Workstations", "Printers", "NetworkDevices", "GuestDevices"
)
$SecurityGroups = @(
    @{Name="GG_Sales"; Description="Global Group - Sales Dept"; OU="Sales"},
    @{Name="GG_Accounting"; Description="Global Group - Accounting Dept"; OU="Accounting"},
    @{Name="GG_HR"; Description="Global Group - HR Dept"; OU="HR"},
    @{Name="GG_IT"; Description="Global Group - IT Dept"; OU="IT"},
    @{Name="GG_Technical"; Description="Global Group - Technical Dept"; OU="Technical"},
    @{Name="GG_CustomerService"; Description="Global Group - CS Dept"; OU="CustomerService"},
    @{Name="GG_Management"; Description="Global Group - Management"; OU="Management"},
    @{Name="DL_FileServer_RW"; Description="Domain Local - File Server Read/Write"; OU="IT"},
    @{Name="DL_FileServer_RO"; Description="Domain Local - File Server Read Only"; OU="IT"},
    @{Name="DL_WebServer_Admins"; Description="Domain Local - Web Server Admins"; OU="IT"},
    @{Name="DL_DHCP_Admins"; Description="Domain Local - DHCP Admins"; OU="IT"},
    @{Name="DL_Printer_Admins"; Description="Domain Local - Printer Admins"; OU="IT"}
)

$ErrorActionPreference = "Stop"

Write-Host "=== STARTECH DC1 - Install AD DS + DNS ===" -ForegroundColor Cyan
Write-Host "Domain: $DomainName" -ForegroundColor Yellow
Write-Host "NetBIOS: $NetBIOSName" -ForegroundColor Yellow
Write-Host ""

# ============================================================
# 1. SET COMPUTER NAME & STATIC IP (nếu chưa làm)
# ============================================================
Write-Host "[1/8] Setting computer name to DC1..." -ForegroundColor Green
Rename-Computer -NewName "DC1" -Force -ErrorAction SilentlyContinue

Write-Host "[2/8] Installing AD DS and DNS roles..." -ForegroundColor Green
Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools -ErrorAction Stop

Write-Host "[3/8] Installing RSAT tools..." -ForegroundColor Green
Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-DNS-Server -ErrorAction SilentlyContinue

# ============================================================
# 4. PROMOTE TO DOMAIN CONTROLLER (FOREST ROOT)
# ============================================================
Write-Host "[4/8] Promoting to Domain Controller (Forest Root)..." -ForegroundColor Green

$SecureDSPass = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
$SecureAdminPass = ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBIOSName `
    -SafeModeAdministratorPassword $SecureDSPass `
    -DomainMode WinThreshold `
    -ForestMode WinThreshold `
    -InstallDns:$true `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -NoDnsOnNetwork:$false `
    -Force:$true `
    -ErrorAction Stop

Write-Host "Waiting for reboot..." -ForegroundColor Yellow
# Script sẽ reboot ở đây - phần dưới chạy sau reboot

# ============================================================
# SAU KHI REBOOT - CHẠY PHẦN NÀY (copy vào PowerShell mới)
# ============================================================

<# POST-REBOOT SECTION - COPY VÀ CHẠY SAU KHI REBOOT #>

Write-Host "[POST-REBOOT] Configuring DNS Forwarders & Aging..." -ForegroundColor Green

# DNS Forwarders (Google, Cloudflare)
Set-DnsServerForwarder -IPAddress @("8.8.8.8","1.1.1.1") -PassThru -ErrorAction SilentlyContinue

# DNS Aging/Scavenging (7 ngày no-refresh, 7 ngày refresh)
Set-DnsServerZoneAging -Name $DomainName -AgingEnabled $true -NoRefreshInterval 7.00:00:00 -RefreshInterval 7.00:00:00 -PassThru -ErrorAction SilentlyContinue
Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 1.00:00:00 -PassThru -ErrorAction SilentlyContinue

Write-Host "[POST-REBOOT] Creating OU Structure..." -ForegroundColor Green

# Tạo OU
$BaseDN = (Get-ADDomain).DistinguishedName
foreach ($OU in $OUList) {
    $OUPath = "OU=$OU,$BaseDN"
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$OU'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $OU -Path $BaseDN -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
        Write-Host "  Created OU: $OU"
    } else {
        Write-Host "  OU exists: $OU"
    }
}

# Tạo Sub-OU dưới Servers
$ServersOU = "OU=Servers,$BaseDN"
$SubServerOUs = @("DomainControllers","FileWeb","Database","Application")
foreach ($SubOU in $SubServerOUs) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$SubOU'" -SearchBase $ServersOU -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $SubOU -Path $ServersOU -ProtectedFromAccidentalDeletion $true
        Write-Host "  Created Sub-OU: $SubOU"
    }
}

Write-Host "[POST-REBOOT] Creating Security Groups (AGDLP model)..." -ForegroundColor Green

# Tạo Groups
foreach ($G in $SecurityGroups) {
    $TargetOU = "OU=$($G.OU),$BaseDN"
    if (-not (Get-ADGroup -Filter "Name -eq '$($G.Name)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $G.Name -SamAccountName $G.Name -GroupCategory Security -GroupScope Global -Path $TargetOU -Description $G.Description -ErrorAction Stop
        Write-Host "  Created Group: $($G.Name) in $($G.OU)"
    } else {
        Write-Host "  Group exists: $($G.Name)"
    }
}

# Domain Local groups - đổi scope
$DLGroups = @("DL_FileServer_RW","DL_FileServer_RO","DL_WebServer_Admins","DL_DHCP_Admins","DL_Printer_Admins")
foreach ($DLG in $DLGroups) {
    $grp = Get-ADGroup -Identity $DLG -ErrorAction SilentlyContinue
    if ($grp -and $grp.GroupScope -ne "DomainLocal") {
        Set-ADGroup -Identity $DLG -GroupScope DomainLocal -ErrorAction SilentlyContinue
        Write-Host "  Updated $DLG to DomainLocal scope"
    }
}

Write-Host "[POST-REBOOT] Creating Domain Admin account..." -ForegroundColor Green

# Tạo tài khoản admin domain
if (-not (Get-ADUser -Filter "SamAccountName -eq '$DomainAdminUser'" -ErrorAction SilentlyContinue)) {
    New-ADUser -SamAccountName $DomainAdminUser -UserPrincipalName "$DomainAdminUser@$DomainName" `
        -Name "Domain Administrator" -GivenName "Domain" -Surname "Administrator" `
        -Enabled $true -AccountPassword $SecureAdminPass -PasswordNeverExpires $true `
        -Path "OU=Management,$BaseDN" -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members $DomainAdminUser -ErrorAction Stop
    Write-Host "  Created domain admin: $DomainAdminUser"
} else {
    Write-Host "  Domain admin exists: $DomainAdminUser"
}

# Thêm Domain Controllers vào OU DomainControllers
$DC1 = Get-ADComputer -Identity "DC1" -ErrorAction SilentlyContinue
if ($DC1 -and $DC1.DistinguishedName -notlike "*OU=DomainControllers*") {
    Move-ADObject -Identity $DC1.DistinguishedName -TargetPath "OU=DomainControllers,OU=Servers,$BaseDN"
    Write-Host "  Moved DC1 to DomainControllers OU"
}

Write-Host "[POST-REBOOT] Configuring Default Domain Policy..." -ForegroundColor Green

# Password Policy (GPO Default Domain Policy)
Set-ADDefaultDomainPasswordPolicy -Identity $DomainName -ComplexityEnabled $true -MinPasswordLength 12 -MaxPasswordAge 90.00:00:00 -MinPasswordAge 1.00:00:00 -PasswordHistoryCount 24 -ReversibleEncryptionEnabled $false -ErrorAction Stop

# Account Lockout Policy
Set-ADAccountLockoutPolicy -Identity $DomainName -LockoutDuration 30 -LockoutThreshold 5 -LockoutObservationWindow 30 -ErrorAction Stop

# Kerberos Policy
Set-ADDomain -Identity $DomainName -KerberosEncryptionType AES256,AES128,RC4 -ErrorAction SilentlyContinue

Write-Host "[POST-REBOOT] Enabling AD Recycle Bin..." -ForegroundColor Green
Enable-ADOptionalFeature -Identity "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target $DomainName -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== DC1 SETUP COMPLETE ===" -ForegroundColor Cyan
Write-Host "Domain: $DomainName" -ForegroundColor Yellow
Write-Host "Admin: $DomainAdminUser / $DomainAdminPass" -ForegroundColor Yellow
Write-Host "DSRM Password: $SafeModePassword" -ForegroundColor Yellow
Write-Host ""
Write-Host "NEXT: Run 02-install-ad-dc2.ps1 on Server03" -ForegroundColor Cyan
Write-Host "THEN: Run 08-join-domain.ps1 on workstations" -ForegroundColor Cyan

# ============================================================
# VERIFICATION COMMANDS (chạy thủ công)
# ============================================================
<#
# Verify AD
Get-ADDomain
Get-ADForest
Get-ADDomainController -Filter *

# Verify DNS
Get-DnsServerZone -Name startech.local
Get-DnsServerResourceRecord -ZoneName startech.local -RRType A

# Verify Replication (sau khi có DC2)
repadmin /replsummary
repadmin /showrepl DC1

# Verify FSMO
netdom query fsmo
#>