<#
.SYNOPSIS
    Cấu hình Group Policy (GPO) cơ bản cho domain startech.local
    - Password Policy, Account Lockout (đã làm ở DC1)
    - Windows Firewall Profile (Domain/Private/Public)
    - Software Restriction / AppLocker
    - Drive Mapping via GPP
    - Screen Lock, Power Options
    - Audit Policy

.NOTES
    Chạy trên DC1 (Server01) với Domain Admin
#>

# ============================================================
# CẤU HÌNH
# ============================================================
$DomainName = "startech.local"
$ErrorActionPreference = "Stop"

Import-Module GroupPolicy

Write-Host "=== STARTECH DC1 - Configure Group Policies ===" -ForegroundColor Cyan

# ============================================================
# HELPER FUNCTION
# ============================================================
function New-GPOIfNotExists {
    param([string]$Name, [string]$Comment)
    $GPO = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $GPO) {
        $GPO = New-GPO -Name $Name -Comment $Comment
        Write-Host "  Created GPO: $Name"
    } else {
        Write-Host "  GPO exists: $Name"
    }
    return $GPO
}

function Set-GPRegistryValueSafe {
    param($GPO, $Key, $ValueName, $Type, $Value, [string]$Comment)
    try {
        Set-GPRegistryValue -Name $GPO.DisplayName -Key $Key -ValueName $ValueName -Type $Type -Value $Value -ErrorAction Stop
        Write-Host "    [$($GPO.DisplayName)] $Key\$ValueName = $Value"
    } catch {
        Write-Warning "    Failed to set $Key\$ValueName: $($_.Exception.Message)"
    }
}

# ============================================================
# 1. GPO: STARTECH - Security Baseline (Link to Domain)
# ============================================================
Write-Host "[1/6] Creating Security Baseline GPO..." -ForegroundColor Green
$GPOSecurity = New-GPOIfNotExists -Name "STARTECH - Security Baseline" -Comment "Security settings for all domain computers"

# Windows Firewall - Domain Profile
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile" "EnableFirewall" "DWord" 1
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile" "DisableNotifications" "DWord" 1
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile" "DefaultInboundAction" "DWord" 1  # Block
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile" "DefaultOutboundAction" "DWord" 0 # Allow

# Windows Firewall - Private Profile
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile" "EnableFirewall" "DWord" 1
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile" "DefaultInboundAction" "DWord" 1
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile" "DefaultOutboundAction" "DWord" 0

# Windows Firewall - Public Profile
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile" "EnableFirewall" "DWord" 1
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile" "DefaultInboundAction" "DWord" 1
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile" "DefaultOutboundAction" "DWord" 0

# UAC Settings
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA" "DWord" 1
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "ConsentPromptBehaviorAdmin" "DWord" 5
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "PromptOnSecureDesktop" "DWord" 1

# Disable SMBv1
Set-GPRegistryValueSafe $GPOSecurity "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" "DWord" 0

# Link to Domain
$DomainDN = (Get-ADDomain).DistinguishedName
New-GPLink -Name $GPOSecurity.DisplayName -Target $DomainDN -LinkEnabled Yes -Order 1 -ErrorAction SilentlyContinue
Write-Host "  Linked to Domain root"

# ============================================================
# 2. GPO: STARTECH - Workstation Hardening (Link to Workstations OU)
# ============================================================
Write-Host "[2/6] Creating Workstation Hardening GPO..." -ForegroundColor Green
$GPOWorkstation = New-GPOIfNotExists -Name "STARTECH - Workstation Hardening" -Comment "Hardening for user workstations"

# Screen Saver & Lock
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Control Panel\Desktop" "ScreenSaveActive" "String" "1"
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Control Panel\Desktop" "ScreenSaveTimeOut" "String" "900"  # 15 min
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Control Panel\Desktop" "ScreenSaverIsSecure" "String" "1"
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" "ScreenSaveActive" "String" "1"
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" "ScreenSaveTimeOut" "String" "900"
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" "ScreenSaverIsSecure" "String" "1"

# Power Options - High Performance (plugged), Balanced (battery)
Set-GPRegistryValueSafe $GPOWorkstation "HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings" "ActivePowerScheme" "String" "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

# Disable AutoRun
Set-GPRegistryValueSafe $GPOWorkstation "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" "DWord" 255

# Disable Sticky Keys, Filter Keys, etc. (accessibility shortcuts)
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Control Panel\Accessibility\StickyKeys" "Flags" "String" "506"
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Control Panel\Accessibility\ToggleKeys" "Flags" "String" "506"
Set-GPRegistryValueSafe $GPOWorkstation "HKCU\Control Panel\Accessibility\HighContrast" "Flags" "String" "506"

# Link to Workstations OU
$WorkstationsOU = "OU=Workstations,$DomainDN"
New-GPLink -Name $GPOWorkstation.DisplayName -Target $WorkstationsOU -LinkEnabled Yes -Order 1 -ErrorAction SilentlyContinue
Write-Host "  Linked to Workstations OU"

# ============================================================
# 3. GPO: STARTECH - Server Hardening (Link to Servers OU)
# ============================================================
Write-Host "[3/6] Creating Server Hardening GPO..." -ForegroundColor Green
$GPOServers = New-GPOIfNotExists -Name "STARTECH - Server Hardening" -Comment "Hardening for member servers"

# Disable unnecessary services via registry (Services key)
$ServicesToDisable = @(
    "Fax", "WerSvc", "WSearch", "DiagTrack", "dmwappushservice",
    "RetailDemo", "XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc"
)
foreach ($Svc in $ServicesToDisable) {
    Set-GPRegistryValueSafe $GPOServers "HKLM\SYSTEM\CurrentControlSet\Services\$Svc" "Start" "DWord" 4  # Disabled
}

# Disable IPv6 (if not used)
Set-GPRegistryValueSafe $GPOServers "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" "DWord" 0xFF

# Event Log - Increase size
Set-GPRegistryValueSafe $GPOServers "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security" "MaxSize" "DWord" 131072  # 128 MB
Set-GPRegistryValueSafe $GPOServers "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\System" "MaxSize" "DWord" 131072
Set-GPRegistryValueSafe $GPOServers "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application" "MaxSize" "DWord" 131072

# Link to Servers OU
$ServersOU = "OU=Servers,$DomainDN"
New-GPLink -Name $GPOServers.DisplayName -Target $ServersOU -LinkEnabled Yes -Order 1 -ErrorAction SilentlyContinue
Write-Host "  Linked to Servers OU"

# ============================================================
# 4. GPO: STARTECH - Drive Mapping (GPP) - User Configuration
# ============================================================
Write-Host "[4/6] Creating Drive Mapping GPO (GPP)..." -ForegroundColor Green
$GPODriveMap = New-GPOIfNotExists -Name "STARTECH - Drive Mappings" -Comment "Map network drives via Group Policy Preferences"

# GPP Drive Maps cần dùng PowerShell COM hoặc XML - ở đây demo registry approach
# Thực tế dùng: Import-Module GroupPolicyPreferences; New-GPPDriveMap...

Write-Host "  Note: Drive Mapping via GPP requires manual GPMC or PowerShell GPP module"
Write-Host "  Example drives to map:"
Write-Host "    Z: -> \\Server02\Data (Authenticated Users)"
Write-Host "    Y: -> \\Server02\IT_Software (GG_IT, GG_Technical)"
Write-Host "    X: -> \\Server02\Public (Domain Users)"

# Link to Domain (User config applies to users)
New-GPLink -Name $GPODriveMap.DisplayName -Target $DomainDN -LinkEnabled Yes -Order 2 -ErrorAction SilentlyContinue

# ============================================================
# 5. GPO: STARTECH - Audit Policy (Advanced Audit)
# ============================================================
Write-Host "[5/6] Configuring Advanced Audit Policy..." -ForegroundColor Green
$GPOAudit = New-GPOIfNotExists -Name "STARTECH - Audit Policy" -Comment "Advanced audit policy for security monitoring"

# Audit Policy subcategories (Windows 2008+)
# Sử dụng auditpol.exe /set /subcategory:...
$AuditCommands = @(
    'auditpol /set /subcategory:"Logon" /success:enable /failure:enable',
    'auditpol /set /subcategory:"Logoff" /success:enable /failure:enable',
    'auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable',
    'auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable',
    'auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable',
    'auditpol /set /subcategory:"Computer Account Management" /success:enable /failure:enable',
    'auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable',
    'auditpol /set /subcategory:"Object Access" /success:enable /failure:enable',
    'auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable',
    'auditpol /set /subcategory:"Process Termination" /success:enable /failure:enable',
    'auditpol /set /subcategory:"System" /success:enable /failure:enable'
)

Write-Host "  Run these commands on each DC/server to apply audit policy:"
foreach ($Cmd in $AuditCommands) {
    Write-Host "    $Cmd"
}

# Link to Domain
New-GPLink -Name $GPOAudit.DisplayName -Target $DomainDN -LinkEnabled Yes -Order 3 -ErrorAction SilentlyContinue

# ============================================================
# 6. GPO: STARTECH - Chrome/Edge Enterprise Policy (Optional)
# ============================================================
Write-Host "[6/6] Browser Policies (Chrome/Edge) - Optional..." -ForegroundColor Yellow
Write-Host "  Download ADMX templates from Google/Microsoft"
Write-Host "  Copy to SYSVOL\Policies\PolicyDefinitions"
Write-Host "  Configure: Homepage, Block extensions, Safe Browsing, etc."

# ============================================================
# VERIFICATION
# ============================================================
Write-Host ""
Write-Host "=== VERIFICATION ===" -ForegroundColor Cyan
Get-GPO -All | Where-Object { $_.DisplayName -like "STARTECH*" } | Format-Table DisplayName, CreationTime, ModificationTime, @{Name="Linked";Expression={$_.GpoLinks.Count -gt 0}} -AutoSize

Write-Host ""
Write-Host "Check GPO Links:" -ForegroundColor Cyan
Get-GPInheritance -Target $DomainDN | Select-Object -ExpandProperty GpoLinks | Format-Table DisplayName, Enforced, LinkEnabled, Order -AutoSize

Write-Host ""
Write-Host "Test on workstation:" -ForegroundColor Cyan
Write-Host "  gpupdate /force"
Write-Host "  gpresult /h gpreport.html"
Write-Host "  rsop.msc"
Write-Host ""
Write-Host "NEXT: Run 07-config-backup.ps1" -ForegroundColor Cyan