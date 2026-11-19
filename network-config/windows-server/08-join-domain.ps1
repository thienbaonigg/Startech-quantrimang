<#
.SYNOPSIS
    Script join máy trạm (Workstation) vào domain startech.local
    Chạy trên từng máy trạm Windows 10/11 với quyền Administrator

.NOTES
    Yêu cầu:
    - Static IP hoặc DHCP (đã cấu hình DHCP Relay)
    - DNS trỏ về DC1 (192.168.10.11) và DC2 (192.168.110.11)
    - Kết nối mạng đến DC
    - Tài khoản Domain Admin
#>

# ============================================================
# CẤU HÌNH - CHỈNH SỬA TRƯỚC KHI CHẠY
# ============================================================
$DomainName = "startech.local"
$DomainAdminUser = "STARTECH\admin"
$DomainAdminPass = "P@ssw0rd123!"
$DC1_IP = "192.168.10.11"
$DC2_IP = "192.168.110.11"
$TargetOU = "OU=Workstations,DC=startech,DC=local"  # OU đích

# Tự động đặt tên máy theo quy ước: STARTECH-WKS-XXX
$NamePrefix = "STARTECH-WKS"
$AutoRename = $true

$ErrorActionPreference = "Stop"

Write-Host "=== STARTECH - Join Workstation to Domain ===" -ForegroundColor Cyan

# ============================================================
# 1. CHECK PREREQUISITES
# ============================================================
Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Green

# Check Admin rights
$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentUser)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Script must run as Administrator!"
}

# Check network to DC
Write-Host "  Testing connectivity to DC1 ($DC1_IP)..."
if (-not (Test-Connection -ComputerName $DC1_IP -Count 2 -Quiet)) {
    Write-Error "Cannot reach DC1 ($DC1_IP). Check network cable, VLAN, IP config."
}
Write-Host "  DC1 reachable." -ForegroundColor Green

Write-Host "  Testing connectivity to DC2 ($DC2_IP)..."
if (-not (Test-Connection -ComputerName $DC2_IP -Count 2 -Quiet)) {
    Write-Warning "Cannot reach DC2 ($DC2_IP). DC1 is primary."
}

# Check DNS
Write-Host "  Testing DNS resolution..."
try {
    $DnsTest = Resolve-DnsName -Name "dc1.$DomainName" -Server $DC1_IP -ErrorAction Stop
    Write-Host "  DNS OK: dc1.$DomainName -> $($DnsTest.IPAddress)"
} catch {
    Write-Error "DNS resolution failed. Set DNS to $DC1_IP, $DC2_IP"
}

# ============================================================
# 2. CONFIGURE DNS CLIENT
# ============================================================
Write-Host "[2/6] Configuring DNS client..." -ForegroundColor Green
$Interfaces = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notlike "*Bluetooth*" -and $_.Name -notlike "*Wi-Fi*" }
foreach ($If in $Interfaces) {
    Set-DnsClientServerAddress -InterfaceIndex $If.InterfaceIndex -ServerAddresses @($DC1_IP, $DC2_IP) -ErrorAction Stop
    Write-Host "  Set DNS on $($If.Name): $DC1_IP, $DC2_IP"
}

# Flush DNS cache
Clear-DnsClientCache -ErrorAction SilentlyContinue

# ============================================================
# 3. RENAME COMPUTER (Optional)
# ============================================================
if ($AutoRename) {
    Write-Host "[3/6] Renaming computer..." -ForegroundColor Green
    # Tìm số thứ tự tiếp theo
    $Existing = Get-ADComputer -Filter "Name -like '$NamePrefix-*'" -Server $DC1_IP -ErrorAction SilentlyContinue
    $NextNum = 1
    if ($Existing) {
        $Nums = $Existing.Name | ForEach-Object { [int]($_.Split('-')[-1]) } | Sort-Object
        $NextNum = ($Nums[-1] + 1)
    }
    $NewName = "{0}-{1:D3}" -f $NamePrefix, $NextNum

    if ($env:COMPUTERNAME -ne $NewName) {
        Write-Host "  Renaming: $env:COMPUTERNAME -> $NewName"
        Rename-Computer -NewName $NewName -Force -ErrorAction Stop
        $Renamed = $true
    } else {
        Write-Host "  Name already correct: $NewName"
        $Renamed = $false
    }
} else {
    $Renamed = $false
}

# ============================================================
# 4. JOIN DOMAIN
# ============================================================
Write-Host "[4/6] Joining domain $DomainName..." -ForegroundColor Green
$Cred = New-Object System.Management.Automation.PSCredential($DomainAdminUser, (ConvertTo-SecureString $DomainAdminPass -AsPlainText -Force))

$JoinParams = @{
    DomainName = $DomainName
    Credential = $Cred
    Force = $true
    ErrorAction = "Stop"
}
if ($TargetOU) { $JoinParams["OUPath"] = $TargetOU }

Add-Computer @JoinParams

Write-Host "  Joined domain successfully!" -ForegroundColor Green

# ============================================================
# 5. POST-JOIN CONFIGURATION
# ============================================================
Write-Host "[5/6] Post-join configuration..." -ForegroundColor Green

# Enable WinRM for remote management
Write-Host "  Enabling WinRM..."
winrm quickconfig -quiet -force 2>&1 | Out-Null
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force -ErrorAction SilentlyContinue
Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue

# Disable Firewall for Domain Profile (GPO will manage)
Write-Host "  Configuring Firewall (Domain Profile)..."
Set-NetFirewallProfile -Profile Domain -Enabled True -ErrorAction SilentlyContinue

# Set Power Plan to High Performance
Write-Host "  Setting Power Plan..."
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null

# Install RSAT Tools (Windows 10/11 1809+)
Write-Host "  Installing RSAT tools..."
$RSATCapabilities = @(
    "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0",
    "Rsat.DHCP.Tools~~~~0.0.1.0",
    "Rsat.Dns.Tools~~~~0.0.1.0",
    "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0"
)
foreach ($Cap in $RSATCapabilities) {
    Add-WindowsCapability -Online -Name $Cap -ErrorAction SilentlyContinue
}

# ============================================================
# 6. REBOOT
# ============================================================
Write-Host "[6/6] Reboot required to complete domain join." -ForegroundColor Yellow
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Yellow
if ($Renamed) { Write-Host "New Name: $NewName (after reboot)" -ForegroundColor Yellow }
Write-Host "Domain: $DomainName" -ForegroundColor Yellow
Write-Host "OU: $TargetOU" -ForegroundColor Yellow
Write-Host "DNS: $DC1_IP, $DC2_IP" -ForegroundColor Yellow
Write-Host ""
Write-Host "AFTER REBOOT, verify:" -ForegroundColor Cyan
Write-Host "  whoami /fqdn"
Write-Host "  nltest /dsgetdc:$DomainName"
Write-Host "  Get-ADComputer -Identity $env:COMPUTERNAME -Server $DC1_IP"
Write-Host "  gpupdate /force"
Write-Host ""

$Reboot = Read-Host "Reboot now? (Y/N)"
if ($Reboot -eq 'Y' -or $Reboot -eq 'y') {
    Restart-Computer -Force
}