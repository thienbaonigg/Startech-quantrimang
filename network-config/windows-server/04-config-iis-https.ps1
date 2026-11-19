<#
.SYNOPSIS
    Cấu hình IIS Web Server + HTTPS + ADCS (Enterprise Root CA) trên Server02
    - IIS Role + Web Management Tools
    - ADCS Enterprise Root CA
    - Chứng chỉ Web Server cho startech.local
    - Binding HTTPS 443, Redirect HTTP -> HTTPS
    - Cấu hình SSL/TLS an toàn (TLS 1.2/1.3)

.NOTES
    Yêu cầu: Server02 đã join domain, Static IP 192.168.10.12
    Chạy với Domain Admin
#>

# ============================================================
# CẤU HÌNH
# ============================================================
$DomainName = "startech.local"
$WebServerName = "web.$DomainName"
$CertSubject = "CN=$WebServerName"
$CertFriendlyName = "STARTECH Web Server Certificate"
$IISSiteName = "STARTECH Web"
$IISPhysicalPath = "C:\inetpub\startech"
$CAName = "STARTECH-ROOT-CA"
$CADistinguishedName = "CN=$CAName,DC=startech,DC=local"

$ErrorActionPreference = "Stop"

Write-Host "=== STARTECH Server02 - Configure IIS + HTTPS + ADCS ===" -ForegroundColor Cyan

# ============================================================
# 1. INSTALL IIS ROLE
# ============================================================
Write-Host "[1/7] Installing IIS Web Server role..." -ForegroundColor Green
Install-WindowsFeature -Name Web-Server, Web-Mgmt-Tools, Web-Mgmt-Console, `
    Web-Common-Http, Web-Http-Logging, Web-Request-Monitor, `
    Web-Http-Redirect, Web-Performance, Web-Stat-Compression, `
    Web-Dyn-Compression, Web-Security, Web-Filtering, `
    Web-Windows-Auth, Web-App-Dev, Web-Net-Ext45, `
    Web-Asp-Net45, Web-ISAPI-Ext, Web-ISAPI-Filter, `
    Web-Includes, Web-WebSockets, Web-AppInit `
    -IncludeManagementTools -ErrorAction Stop

Write-Host "[2/7] Installing AD CS (Enterprise Root CA)..." -ForegroundColor Green
Install-WindowsFeature -Name ADCS-Cert-Authority, ADCS-Web-Enrollment -IncludeManagementTools -ErrorAction Stop

# ============================================================
# 3. CONFIGURE ADCS ENTERPRISE ROOT CA
# ============================================================
Write-Host "[3/7] Configuring Enterprise Root CA..." -ForegroundColor Green

$CAConfig = @"
[Version]
Signature=`"`$CHICAGO`$`"
[PolicyStatementExtension]
Policies=InternalPolicy
[InternalPolicy]
OID=1.3.6.1.4.1.311.2.3.11
URL=`"http://$WebServerName/certrevocation.crl`"
[Certsrv_Server]
RenewalKeyLength=2048
RenewalValidityPeriod=Years
RenewalValidityPeriodUnits=5
CRLPeriod=Weeks
CRLPeriodUnits=1
CRLDeltaPeriod=Days
CRLDeltaPeriodUnits=1
LoadDefaultTemplates=1
AlternateSignatureAlgorithm=1
"@

$CAConfigPath = "C:\Windows\Temp\CAConfig.inf"
$CAConfig | Out-File -FilePath $CAConfigPath -Encoding ASCII -Force

Install-AdcsCertificationAuthority `
    -CAType EnterpriseRootCA `
    -CACommonName $CAName `
    -CADistinguishedNameSuffix "DC=startech,DC=local" `
    -KeyLength 2048 `
    -HashAlgorithmName SHA256 `
    -ValidityPeriod Years `
    -ValidityPeriodUnits 5 `
    -DatabaseDirectory "C:\Windows\System32\CertLog" `
    -LogDirectory "C:\Windows\System32\CertLog" `
    -Force `
    -ErrorAction Stop

Install-AdcsWebEnrollment -Force -ErrorAction Stop

Write-Host "  ADCS configured. Root CA: $CAName"

# ============================================================
# 4. REQUEST WEB SERVER CERTIFICATE
# ============================================================
Write-Host "[4/7] Requesting Web Server Certificate..." -ForegroundColor Green

# Tạo template request
$CertReq = @"
[Version]
Signature=`"`$CHICAGO`$`"
[NewRequest]
Subject = "$CertSubject"
FriendlyName = "$CertFriendlyName"
KeyLength = 2048
KeyAlgorithm = RSA
HashAlgorithm = SHA256
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
MachineKeySet = TRUE
Exportable = FALSE
UserProtected = FALSE
UseExistingKeySet = FALSE
RequestType = CMC
[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.1 ; Server Authentication
OID=1.3.6.1.5.5.7.3.2 ; Client Authentication
[Extensions]
2.5.29.17 = `{text}`
_continue_ = "dns=$WebServerName&dns=www.$DomainName&dns=$DomainName&ipaddress=192.168.10.12&ipaddress=192.168.110.11"
"@

$CertReqPath = "C:\Windows\Temp\WebServerCert.req"
$CertReq | Out-File -FilePath $CertReqPath -Encoding ASCII -Force

# Submit request to CA
$CertReqBlob = Get-Content -Path $CertReqPath -Raw
$CertResponse = certreq -submit -attrib "CertificateTemplate:WebServer" $CertReqPath "C:\Windows\Temp\WebServerCert.cer" 2>&1

if ($LASTEXITCODE -ne 0) {
    # Thử template mặc định nếu WebServer không có
    Write-Host "  WebServer template not found, trying default..." -ForegroundColor Yellow
    $CertResponse = certreq -submit $CertReqPath "C:\Windows\Temp\WebServerCert.cer" 2>&1
}

# Accept certificate
certreq -accept "C:\Windows\Temp\WebServerCert.cer" 2>&1 | Out-Null

# Verify certificate in Local Machine\My store
$Cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$WebServerName*" } | Select-Object -First 1
if (-not $Cert) {
    Write-Error "Certificate not found in Local Machine store!"
}
Write-Host "  Certificate installed. Thumbprint: $($Cert.Thumbprint)"

# ============================================================
# 5. CREATE IIS SITE & BINDING HTTPS
# ============================================================
Write-Host "[5/7] Creating IIS Site and HTTPS Binding..." -ForegroundColor Green

# Tạo thư mục website
if (-not (Test-Path $IISPhysicalPath)) {
    New-Item -Path $IISPhysicalPath -ItemType Directory -Force | Out-Null
}

# Copy frontend files (giả định đã copy sẵn hoặc deploy từ CI/CD)
# New-Item -Path "$IISPhysicalPath\index.html" -ItemType File -Value "<h1>STARTECH - Under Construction</h1>" -Force | Out-Null

# Xóa Default Web Site
Remove-Website -Name "Default Web Site" -ErrorAction SilentlyContinue

# Tạo Application Pool
$AppPoolName = "STARTECH-AppPool"
if (-not (Get-WebAppPoolState -Name $AppPoolName -ErrorAction SilentlyContinue)) {
    New-WebAppPool -Name $AppPoolName -Force -ErrorAction Stop
    Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "managedRuntimeVersion" -Value "v4.0"
    Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "enable32BitAppOnWin64" -Value $false
    Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.identityType" -Value "ApplicationPoolIdentity"
}

# Tạo Website
New-Website -Name $IISSiteName -Port 80 -PhysicalPath $IISPhysicalPath -ApplicationPool $AppPoolName -Force -ErrorAction Stop

# Binding HTTPS 443
$CertHash = $Cert.Thumbprint
New-WebBinding -Name $IISSiteName -IP "*" -Port 443 -Protocol https -HostHeader $WebServerName -SslFlags 1 -ErrorAction Stop

# Set SSL Certificate cho binding
$Binding = Get-WebBinding -Name $IISSiteName -Protocol https
$Binding.AddSslCertificate($CertHash, "My") | Out-Null

Write-Host "  IIS Site created: $IISSiteName"
Write-Host "  HTTP:  Port 80"
Write-Host "  HTTPS: Port 443 (Cert: $CertHash)"

# ============================================================
# 6. CONFIGURE HTTP -> HTTPS REDIRECT
# ============================================================
Write-Host "[6/7] Configuring HTTP to HTTPS Redirect..." -ForegroundColor Green

# Enable URL Rewrite (cần cài module URL Rewrite 2.1 trước)
# Download: https://www.iis.net/downloads/microsoft/url-rewrite
# Hoặc dùng web.config approach

$WebConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="Redirect HTTP to HTTPS" stopProcessing="true">
                    <match url="(.*)" />
                    <conditions>
                        <add input="{HTTPS}" pattern="^OFF$" />
                    </conditions>
                    <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
                </rule>
            </rules>
        </rewrite>
        <staticContent>
            <remove fileExtension=".woff" />
            <remove fileExtension=".woff2" />
            <mimeMap fileExtension=".woff" mimeType="font/woff" />
            <mimeMap fileExtension=".woff2" mimeType="font/woff2" />
        </staticContent>
        <httpProtocol>
            <customHeaders>
                <add name="X-Content-Type-Options" value="nosniff" />
                <add name="X-Frame-Options" value="DENY" />
                <add name="X-XSS-Protection" value="1; mode=block" />
                <add name="Referrer-Policy" value="strict-origin-when-cross-origin" />
            </customHeaders>
        </httpProtocol>
    </system.webServer>
</configuration>
"@

$WebConfigPath = Join-Path $IISPhysicalPath "web.config"
$WebConfig | Out-File -FilePath $WebConfigPath -Encoding UTF8 -Force

Write-Host "  URL Rewrite rule added (requires URL Rewrite Module installed)"

# ============================================================
# 7. SSL/TLS HARDENING
# ============================================================
Write-Host "[7/7] Applying SSL/TLS Hardening (Registry)..." -ForegroundColor Green

# Disable SSL 2.0, 3.0, TLS 1.0, 1.1 - Enable TLS 1.2, 1.3
$TLSRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"

# SSL 2.0
New-Item -Path "$TLSRegPath\SSL 2.0\Server" -Force | Out-Null
New-ItemProperty -Path "$TLSRegPath\SSL 2.0\Server" -Name "Enabled" -Value 0 -PropertyType DWord -Force | Out-Null

# SSL 3.0
New-Item -Path "$TLSRegPath\SSL 3.0\Server" -Force | Out-Null
New-ItemProperty -Path "$TLSRegPath\SSL 3.0\Server" -Name "Enabled" -Value 0 -PropertyType DWord -Force | Out-Null

# TLS 1.0
New-Item -Path "$TLSRegPath\TLS 1.0\Server" -Force | Out-Null
New-ItemProperty -Path "$TLSRegPath\TLS 1.0\Server" -Name "Enabled" -Value 0 -PropertyType DWord -Force | Out-Null

# TLS 1.1
New-Item -Path "$TLSRegPath\TLS 1.1\Server" -Force | Out-Null
New-ItemProperty -Path "$TLSRegPath\TLS 1.1\Server" -Name "Enabled" -Value 0 -PropertyType DWord -Force | Out-Null

# TLS 1.2
New-Item -Path "$TLSRegPath\TLS 1.2\Server" -Force | Out-Null
New-ItemProperty -Path "$TLSRegPath\TLS 1.2\Server" -Name "Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "$TLSRegPath\TLS 1.2\Server" -Name "DisabledByDefault" -Value 0 -PropertyType DWord -Force | Out-Null

# TLS 1.3 (Windows Server 2022+ auto enabled)
New-Item -Path "$TLSRegPath\TLS 1.3\Server" -Force | Out-Null
New-ItemProperty -Path "$TLSRegPath\TLS 1.3\Server" -Name "Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "$TLSRegPath\TLS 1.3\Server" -Name "DisabledByDefault" -Value 0 -PropertyType DWord -Force | Out-Null

# Cipher Suite Order (PFS preferred)
$CipherOrder = @(
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384",
    "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256",
    "TLS_DHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_DHE_RSA_WITH_AES_128_GCM_SHA256"
) -join ","

New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002" -Name "Functions" -Value $CipherOrder -PropertyType String -Force | Out-Null

Write-Host "  TLS 1.2/1.3 enabled, SSL 2/3, TLS 1.0/1.1 disabled"

# ============================================================
# VERIFICATION
# ============================================================
Write-Host ""
Write-Host "=== VERIFICATION ===" -ForegroundColor Cyan
Write-Host "Website: https://$WebServerName" -ForegroundColor Yellow
Write-Host "Certificate: $CertHash" -ForegroundColor Yellow
Write-Host ""
Write-Host "Test commands:" -ForegroundColor Cyan
Write-Host "  curl -I https://$WebServerName"
Write-Host "  openssl s_client -connect $WebServerName:443 -servername $WebServerName"
Write-Host "  Test-Connection $WebServerName"
Write-Host ""
Write-Host "IMPORTANT:" -ForegroundColor Red
Write-Host "  1. Install URL Rewrite Module 2.1 for HTTP->HTTPS redirect"
Write-Host "  2. Add DNS A record: www.startech.local -> 192.168.10.12"
Write-Host "  3. Deploy frontend files to $IISPhysicalPath"
Write-Host "  4. Configure Firewall NAT: WAN:443 -> 192.168.10.12:443"
Write-Host ""
Write-Host "NEXT: Run 05-config-file-share.ps1" -ForegroundColor Cyan