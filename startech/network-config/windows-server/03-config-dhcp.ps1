<#
.SYNOPSIS
    Cấu hình DHCP Server trên Server02 (File/Web/DHCP/Chatbot)
    Tạo scope cho từng VLAN, authorize trong AD, cấu hình DHCP Relay

.NOTES
    Yêu cầu: Server02 đã join domain startech.local
    Static IP: 192.168.10.12
    DNS: 192.168.10.11 (DC1), 192.168.110.11 (DC2)
#>

# ============================================================
# CẤU HÌNH
# ============================================================
$DomainName = "startech.local"
$DHCPServerIP = "192.168.10.12"
$DNSServers = @("192.168.10.11", "192.168.110.11")

# Scope definitions: @{Name; Subnet; Mask; RangeStart; RangeEnd; Router; Description}
$Scopes = @(
    @{
        Name = "CN1-VLAN20-Sales"
        ScopeId = "192.168.20.0"
        SubnetMask = "255.255.255.0"
        RangeStart = "192.168.20.50"
        RangeEnd = "192.168.20.200"
        Router = "192.168.20.1"  # SVI on L3-SW-CN1
        Description = "Chi nhan 1 - Phong Kinh doanh (VLAN 20)"
        LeaseDuration = "8.00:00:00"
        Exclusions = @("192.168.20.1","192.168.20.2","192.168.20.3","192.168.20.10","192.168.20.11")
    },
    @{
        Name = "CN1-VLAN30-AcctHR"
        ScopeId = "192.168.30.0"
        SubnetMask = "255.255.255.0"
        RangeStart = "192.168.30.50"
        RangeEnd = "192.168.30.200"
        Router = "192.168.30.1"
        Description = "Chi nhanh 1 - Ke toan/Nhan su (VLAN 30)"
        LeaseDuration = "8.00:00:00"
        Exclusions = @("192.168.30.1","192.168.30.2","192.168.30.3")
    },
    @{
        Name = "CN1-VLAN40-Guest"
        ScopeId = "192.168.40.0"
        SubnetMask = "255.255.255.0"
        RangeStart = "192.168.40.50"
        RangeEnd = "192.168.40.200"
        Router = "192.168.40.1"
        Description = "Chi nhanh 1 - Guest WiFi (VLAN 40) - Internet only"
        LeaseDuration = "2.00:00:00"
        Exclusions = @("192.168.40.1","192.168.40.2")
    },
    @{
        Name = "CN2-VLAN120-SalesCS"
        ScopeId = "192.168.120.0"
        SubnetMask = "255.255.255.0"
        RangeStart = "192.168.120.50"
        RangeEnd = "192.168.120.200"
        Router = "192.168.120.1"
        Description = "Chi nhanh 2 - Kinh doanh/CSKH (VLAN 120)"
        LeaseDuration = "8.00:00:00"
        Exclusions = @("192.168.120.1","192.168.120.2","192.168.120.3")
    },
    @{
        Name = "CN2-VLAN140-Guest"
        ScopeId = "192.168.140.0"
        SubnetMask = "255.255.255.0"
        RangeStart = "192.168.140.50"
        RangeEnd = "192.168.140.200"
        Router = "192.168.140.1"
        Description = "Chi nhanh 2 - Guest WiFi (VLAN 140) - Internet only"
        LeaseDuration = "2.00:00:00"
        Exclusions = @("192.168.140.1","192.168.140.2")
    }
)

$ErrorActionPreference = "Stop"

Write-Host "=== STARTECH Server02 - Configure DHCP Server ===" -ForegroundColor Cyan

# ============================================================
# 1. INSTALL DHCP ROLE
# ============================================================
Write-Host "[1/5] Installing DHCP Server role..." -ForegroundColor Green
Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop
Install-WindowsFeature -Name RSAT-DHCP -ErrorAction SilentlyContinue

# ============================================================
# 2. AUTHORIZE IN AD
# ============================================================
Write-Host "[2/5] Authorizing DHCP Server in Active Directory..." -ForegroundColor Green
# Cần chạy với Domain Admin
Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -ErrorAction SilentlyContinue
Write-Host "  Authorized: $env:COMPUTERNAME.$DomainName"

# ============================================================
# 3. CREATE SCOPES
# ============================================================
Write-Host "[3/5] Creating DHCP Scopes..." -ForegroundColor Green

foreach ($Scope in $Scopes) {
    Write-Host "  Creating scope: $($Scope.Name) ($($Scope.ScopeId))" -ForegroundColor Yellow

    # Tạo scope
    Add-DhcpServerv4Scope `
        -Name $Scope.Name `
        -StartRange $Scope.RangeStart `
        -EndRange $Scope.RangeEnd `
        -SubnetMask $Scope.SubnetMask `
        -State Active `
        -LeaseDuration $Scope.LeaseDuration `
        -Description $Scope.Description `
        -ErrorAction Stop

    # Set Scope Options
    Set-DhcpServerv4OptionValue `
        -ScopeId $Scope.ScopeId `
        -Router $Scope.Router `
        -DnsServer $DNSServers `
        -DnsDomain $DomainName `
        -ErrorAction Stop

    # Exclusions (static IP reserved for printers, APs, etc.)
    foreach ($Excl in $Scope.Exclusions) {
        Add-DhcpServerv4ExclusionRange -ScopeId $Scope.ScopeId -StartRange $Excl -EndRange $Excl -ErrorAction SilentlyContinue
    }

    # Activate scope
    Set-DhcpServerv4Scope -ScopeId $Scope.ScopeId -State Active -ErrorAction Stop

    Write-Host "    Done: $($Scope.Name)"
}

# ============================================================
# 4. GLOBAL OPTIONS & SETTINGS
# ============================================================
Write-Host "[4/5] Configuring global DHCP options..." -ForegroundColor Green

# DNS Servers (global)
Set-DhcpServerv4OptionValue -DnsServer $DNSServers -DnsDomain $DomainName -ErrorAction Stop

# Enable DHCP Name Protection (đăng ký DNS an toàn)
Set-DhcpServerv4DnsSetting -ComputerName $env:COMPUTERNAME -EnableDynamicDns $true -DynamicDnsUpdatePolicy "Always" -DeleteDnsRROnLeaseExpiry $true -ErrorAction SilentlyContinue

# Conflict Detection (ping check before offer)
Set-DhcpServerv4ConflictDetection -ComputerName $env:COMPUTERNAME -DetectionAttempts 2 -ErrorAction SilentlyContinue

# Audit Log
Set-DhcpServerv4AuditLog -ComputerName $env:COMPUTERNAME -Enable $true -Path "C:\Windows\System32\dhcp" -MaxMB 70 -DiskCheckInterval 50 -ErrorAction SilentlyContinue

# ============================================================
# 5. DHCP FAILOVER (Optional - nếu có Server03 làm DHCP backup)
# ============================================================
Write-Host "[5/5] DHCP Failover configuration (optional - skip if single DHCP)..." -ForegroundColor Yellow
Write-Host "  To configure failover with another server:"
Write-Host "  Add-DhcpServerv4Failover -Name 'STARTECH-DHCP-Failover' -PartnerServer DC2.startech.local -Mode LoadBalance -LoadBalancePercent 50 -ScopeId 192.168.20.0,192.168.30.0,192.168.40.0,192.168.120.0,192.168.140.0"

# ============================================================
# VERIFICATION
# ============================================================
Write-Host ""
Write-Host "=== VERIFICATION ===" -ForegroundColor Cyan
Get-DhcpServerv4Scope | Format-Table ScopeId, Name, State, StartRange, EndRange, LeaseDuration -AutoSize
Write-Host ""
Get-DhcpServerv4Scope | ForEach-Object {
    Get-DhcpServerv4OptionValue -ScopeId $_.ScopeId | Select-Object ScopeId, OptionId, Value
} | Format-Table -AutoSize

Write-Host ""
Write-Host "DHCP SERVICE STATUS:" -ForegroundColor Cyan
Get-Service dhcpserver | Format-Table -AutoSize

Write-Host ""
Write-Host "NEXT: Configure DHCP Relay (ip helper-address) on L3 Switches:" -ForegroundColor Cyan
Write-Host "  interface Vlan20"
Write-Host "   ip helper-address 192.168.10.12"
Write-Host "  ... (repeat for all VLAN SVIs except VLAN 10)"
Write-Host ""
Write-Host "THEN: Run 04-config-iis-https.ps1" -ForegroundColor Cyan