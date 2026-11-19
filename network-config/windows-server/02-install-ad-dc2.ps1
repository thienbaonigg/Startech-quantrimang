<#
.SYNOPSIS
    Cài đặt Additional Domain Controller (DC2) trên Server03
    Chạy SAU KHI Server01 (DC1) đã sẵn sàng và replicate DNS

.NOTES
    Yêu cầu: Static IP 192.168.110.11, DNS trỏ về DC1 (192.168.10.11)
    Server03 join domain startech.local trước khi promote
#>

# ============================================================
# CẤU HÌNH
# ============================================================
$DomainName = "startech.local"
$NetBIOSName = "STARTECH"
$SafeModePassword = "P@ssw0rd123!"
$DC1_IP = "192.168.10.11"
$DC2_IP = "192.168.110.11"
$DomainAdminUser = "STARTECH\admin"
$DomainAdminPass = "P@ssw0rd123!"

$ErrorActionPreference = "Stop"

Write-Host "=== STARTECH DC2 - Install Additional Domain Controller ===" -ForegroundColor Cyan

# ============================================================
# 1. SET COMPUTER NAME & STATIC IP
# ============================================================
Write-Host "[1/6] Setting computer name to DC2..." -ForegroundColor Green
Rename-Computer -NewName "DC2" -Force -ErrorAction SilentlyContinue

Write-Host "[2/6] Configuring DNS client to point to DC1..." -ForegroundColor Green
Set-DnsClientServerAddress -InterfaceAlias "Ethernet*" -ServerAddresses @($DC1_IP, "127.0.0.1") -ErrorAction Stop

# Test kết nối DC1
Write-Host "  Testing connectivity to DC1 ($DC1_IP)..."
Test-Connection -ComputerName $DC1_IP -Count 2 -Quiet | Out-Null
if (-not $?) { Write-Error "Cannot reach DC1. Check network." }

# ============================================================
# 3. JOIN DOMAIN
# ============================================================
Write-Host "[3/6] Joining domain $DomainName..." -ForegroundColor Green
$Cred = New-Object System.Management.Automation.PSCredential($DomainAdminUser, (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))
Add-Computer -DomainName $DomainName -Credential $Cred -Force -ErrorAction Stop
Write-Host "  Joined domain. Reboot required."

# ============================================================
# SAU REBOOT - CHẠY TIẾP
# ============================================================

<# POST-REBOOT SECTION #>

Write-Host "[POST-REBOOT] Installing AD DS and DNS roles..." -ForegroundColor Green
Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools -ErrorAction Stop
Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-DNS-Server -ErrorAction SilentlyContinue

Write-Host "[POST-REBOOT] Promoting to Additional Domain Controller..." -ForegroundColor Green

$SecureDSPass = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

Install-ADDSDomainController `
    -DomainName $DomainName `
    -Credential $Cred `
    -SafeModeAdministratorPassword $SecureDSPass `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -NoGlobalCatalog:$false `
    -SiteName "Default-First-Site-Name" `
    -Force:$true `
    -ErrorAction Stop

Write-Host "Waiting for reboot..." -ForegroundColor Yellow

<# POST-REBOOT 2 #>

Write-Host "[POST-REBOOT 2] Configuring DNS on DC2..." -ForegroundColor Green

# DNS Forwarders
Set-DnsServerForwarder -IPAddress @("8.8.8.8","1.1.1.1") -PassThru -ErrorAction SilentlyContinue

# DNS Aging/Scavenging
Set-DnsServerZoneAging -Name $DomainName -AgingEnabled $true -NoRefreshInterval 7.00:00:00 -RefreshInterval 7.00:00:00 -PassThru -ErrorAction SilentlyContinue
Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 1.00:00:00 -PassThru -ErrorAction SilentlyContinue

# Conditional Forwarder cho _msdcs (nếu cần)
# Add-DnsServerConditionalForwarderZone -Name "_msdcs.$DomainName" -MasterServers @($DC1_IP) -ErrorAction SilentlyContinue

Write-Host "[POST-REBOOT 2] Moving DC2 to DomainControllers OU..." -ForegroundColor Green
$BaseDN = (Get-ADDomain).DistinguishedName
$DC2 = Get-ADComputer -Identity "DC2" -ErrorAction SilentlyContinue
if ($DC2 -and $DC2.DistinguishedName -notlike "*OU=DomainControllers*") {
    Move-ADObject -Identity $DC2.DistinguishedName -TargetPath "OU=DomainControllers,OU=Servers,$BaseDN"
    Write-Host "  Moved DC2 to DomainControllers OU"
}

Write-Host "[POST-REBOOT 2] Verifying Replication..." -ForegroundColor Green

# Force replication
repadmin /syncall /AdeP
Start-Sleep -Seconds 10

# Check replication status
$ReplStatus = repadmin /showrepl DC2 /errorsonly
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Replication: SUCCESS" -ForegroundColor Green
} else {
    Write-Warning "  Replication may have issues. Check: repadmin /showrepl DC2"
}

# Verify SYSVOL share
if (Test-Path "\\DC2\SYSVOL") {
    Write-Host "  SYSVOL share: ACCESSIBLE" -ForegroundColor Green
} else {
    Write-Warning "  SYSVOL share not ready yet. Run: dfsrdiag pollad"
}

Write-Host ""
Write-Host "=== DC2 SETUP COMPLETE ===" -ForegroundColor Cyan
Write-Host "Domain: $DomainName" -ForegroundColor Yellow
Write-Host "DC1: $DC1_IP | DC2: $DC2_IP" -ForegroundColor Yellow
Write-Host ""
Write-Host "VERIFICATION:" -ForegroundColor Cyan
Write-Host "  repadmin /replsummary"
Write-Host "  repadmin /showrepl DC1"
Write-Host "  repadmin /showrepl DC2"
Write-Host "  dcdiag /v"
Write-Host "  Get-ADDomainController -Filter * | Select Name, Site, IPv4Address, Enabled"
Write-Host ""
Write-Host "NEXT: Run 03-config-dhcp.ps1 on Server02" -ForegroundColor Cyan