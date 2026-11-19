# Kịch bản kiểm tra dịch vụ mạng (Service Check)

## Mục tiêu
Xác minh từng dịch vụ mạng hoạt động đúng theo thiết kế.

---

## 1. Active Directory Domain Services (AD DS)

### Trên DC1 (Server01)
```powershell
# Kiểm tra domain
Get-ADDomain
Get-ADForest

# Kiểm tra Domain Controller
Get-ADDomainController -Filter * | Select Name, Site, IPv4Address, Enabled, OperatingSystem

# Kiểm tra FSMO
netdom query fsmo

# Kiểm tra OU Structure
Get-ADOrganizationalUnit -Filter * | Select Name, DistinguishedName

# Kiểm tra Security Groups
Get-ADGroup -Filter "Name -like 'GG_*' -or Name -like 'DL_*'" | Select Name, GroupScope, GroupCategory, DistinguishedName

# Kiểm tra User
Get-ADUser -Filter "Enabled -eq '$true'" | Select SamAccountName, Name, Enabled, DistinguishedName
```

### Trên DC2 (Server03)
```powershell
# Tương tự DC1
Get-ADDomainController -Filter *
netdom query fsmo
```

### Kết quả mong đợi
| Kiểm tra | Mong đợi |
|----------|----------|
| Domain/Forest | startech.local / WinThreshold |
| DC1, DC2 | Enabled = True, IPv4Address đúng |
| FSMO | DC1 nắm tất cả 5 roles (Schema, Domain Naming, RID, PDC, Infrastructure) |
| OU | 10+ OU theo cấu trúc: Management, IT, Sales, Accounting, HR, Technical, CustomerService, Servers, Workstations, Printers, NetworkDevices, GuestDevices |
| Groups | 7 Global Groups (GG_*), 5 Domain Local Groups (DL_*) |
| Users | admin (Domain Admin), các user test |

---

## 2. DNS Server

### Trên DC1 & DC2
```powershell
# Kiểm tra Zone
Get-DnsServerZone -Name startech.local
Get-DnsServerZone -Name 10.168.192.in-addr.arpa  # Reverse lookup

# Kiểm tra Resource Records
Get-DnsServerResourceRecord -ZoneName startech.local -RRType A | Format-Table HostName, RecordData -AutoSize
Get-DnsServerResourceRecord -ZoneName startech.local -RRType CNAME | Format-Table HostName, RecordData -AutoSize
Get-DnsServerResourceRecord -ZoneName startech.local -RRType SRV | Format-Table HostName, RecordData -AutoSize

# Kiểm tra Forwarders
Get-DnsServerForwarder

# Kiểm tra Aging/Scavenging
Get-DnsServerZoneAging -Name startech.local
Get-DnsServerScavenging
```

### Bản ghi quan trọng cần có
| Tên | Loại | Giá trị |
|-----|------|---------|
| dc1 | A | 192.168.10.11 |
| dc2 | A | 192.168.110.11 |
| web | A | 192.168.10.12 |
| www | CNAME | web.startech.local |
| server02 | A | 192.168.10.12 |
| _ldap._tcp.dc._msdcs | SRV | Priority 0, Weight 100, Port 389, Target dc1 |
| _kerberos._tcp.dc._msdcs | SRV | Priority 0, Weight 100, Port 88, Target dc1 |
| _gc._tcp | SRV | Global Catalog |

### Kết quả mong đợi
- Zone startech.local: Active, AD-Integrated, Secure Dynamic Update
- Forwarders: 8.8.8.8, 1.1.1.1
- Aging/Scavenging: Enabled, No-Refresh 7d, Refresh 7d

---

## 3. DHCP Server (Server02)

```powershell
# Kiểm tra Service
Get-Service dhcpserver

# Kiểm tra Scope
Get-DhcpServerv4Scope | Format-Table ScopeId, Name, State, StartRange, EndRange, LeaseDuration -AutoSize

# Kiểm tra Scope Options
Get-DhcpServerv4Scope | ForEach-Object {
    Get-DhcpServerv4OptionValue -ScopeId $_.ScopeId
} | Format-Table ScopeId, OptionId, Value -AutoSize

# Kiểm tra Lease
Get-DhcpServerv4Lease -ScopeId 192.168.20.0 | Format-Table IPAddress, HostName, ClientId, AddressState -AutoSize
Get-DhcpServerv4Lease -ScopeId 192.168.30.0 | Format-Table IPAddress, HostName, ClientId, AddressState -AutoSize
Get-DhcpServerv4Lease -ScopeId 192.168.120.0 | Format-Table IPAddress, HostName, ClientId, AddressState -AutoSize

# Kiểm tra Exclusions
Get-DhcpServerv4ExclusionRange -ScopeId 192.168.20.0
Get-DhcpServerv4ExclusionRange -ScopeId 192.168.30.0

# Kiểm tra Statistics
Get-DhcpServerv4Statistics
```

### Kết quả mong đợi
| Scope | Subnet | Range | Router | DNS | Lease |
|-------|--------|-------|--------|-----|-------|
| CN1-VLAN20-Sales | 192.168.20.0/24 | .50-.200 | 192.168.20.1 | DC1, DC2 | 8h |
| CN1-VLAN30-AcctHR | 192.168.30.0/24 | .50-.200 | 192.168.30.1 | DC1, DC2 | 8h |
| CN1-VLAN40-Guest | 192.168.40.0/24 | .50-.200 | 192.168.40.1 | DC1, DC2 | 2h |
| CN2-VLAN120-SalesCS | 192.168.120.0/24 | .50-.200 | 192.168.120.1 | DC1, DC2 | 8h |
| CN2-VLAN140-Guest | 192.168.140.0/24 | .50-.200 | 192.168.140.1 | DC1, DC2 | 2h |

- Server authorized trong AD
- Conflict detection: 2 attempts
- Audit log: Enabled

---

## 4. Web Server (IIS) + HTTPS (Server02)

```powershell
# Kiểm tra IIS Service
Get-Service w3svc, was

# Kiểm tra Website
Get-Website | Format-Table Name, State, PhysicalPath, Bindings -AutoSize

# Kiểm tra App Pool
Get-WebAppPoolState -Name "STARTECH-AppPool"

# Kiểm tra SSL Binding
Get-WebBinding -Name "STARTECH Web" -Protocol https | Select-Object bindingInformation, protocol, sslFlags

# Kiểm tra Certificate
Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*web.startech.local*" } | Select Subject, Thumbprint, NotBefore, NotAfter, DnsNameList

# Test HTTPS
Invoke-WebRequest -Uri https://web.startech.local -UseBasicParsing -DisableKeepAlive
Invoke-WebRequest -Uri https://www.startech.local -UseBasicParsing -DisableKeepAlive

# Test HTTP Redirect
$Response = Invoke-WebRequest -Uri http://web.startech.local -MaximumRedirection 0 -ErrorAction Ignore
$Response.StatusCode  # Should be 301/302
$Response.Headers.Location  # Should be https://...

# Test TLS Version
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri https://web.startech.local -UseBasicParsing
```

### Kết quả mong đợi
- Website "STARTECH Web": Started, PhysicalPath = C:\inetpub\startech
- Bindings: HTTP *:80, HTTPS *:443 (HostHeader: web.startech.local)
- Certificate: Valid, CN=web.startech.local, SAN: www.startech.local, startech.local, 192.168.10.12
- HTTP -> HTTPS Redirect: 301/302
- TLS 1.2/1.3 enabled, SSL 2/3, TLS 1.0/1.1 disabled

---

## 5. ADCS (Enterprise Root CA)

```powershell
# Trên Server02 (CA Server)
Get-Service CertSvc

# Kiểm tra CA
certutil -CAInfo
certutil -View -Config "Server02\STARTECH-ROOT-CA" -Restrict "Issued Common Name=web.startech.local"

# Kiểm tra CDP (CRL Distribution Point)
certutil -GetReg CA\CRLPublicationURLs
certutil -GetReg CA\CACertPublicationURLs

# Test CRL Download
Invoke-WebRequest -Uri "http://web.startech.local/certrevocation.crl" -UseBasicParsing
```

### Kết quả mong đợi
- CA Type: Enterprise Root CA
- CA Name: STARTECH-ROOT-CA
- Validity: 5 years
- Hash: SHA256, Key: 2048-bit RSA
- CDP: HTTP accessible

---

## 6. File Server (Share, NTFS, Quota, File Screen)

```powershell
# Kiểm tra Shares
Get-SmbShare | Where-Object { $_.Name -notlike "ADMIN$" -and $_.Name -notlike "C$" -and $_.Name -notlike "IPC$" } | Format-Table Name, Path, Description -AutoSize

# Kiểm tra NTFS Permissions
Get-ChildItem D:\Shares | ForEach-Object {
    $Path = $_.FullName
    $Acl = Get-Acl $Path
    Write-Host "=== $($_.Name) ===" -ForegroundColor Cyan
    $Acl.Access | Where-Object { $_.AccessControlType -eq "Allow" } | Select IdentityReference, FileSystemRights, InheritanceFlags, PropagationFlags | Format-Table -AutoSize
}

# Kiểm tra Quota
Get-FsrmQuota | Format-Table Path, Size, Usage, SoftLimit -AutoSize

# Kiểm tra File Screen
Get-FsrmFileScreen | Format-Table Path, Active -AutoSize
Get-FsrmFileGroup -Name "Executable Files" | Select Name, Members

# Kiểm tra Quota Template
Get-FsrmQuotaTemplate
```

### Kết quả mong đợi
| Share | Path | NTFS Groups | Quota |
|-------|------|-------------|-------|
| Data | D:\Shares\Data | GG_Sales (M), GG_Accounting (M), GG_HR (M), GG_IT (FC), GG_Technical (M), GG_Management (FC) | 100 GB Hard |
| IT_Software | D:\Shares\IT_Software | GG_IT (FC), GG_Technical (R) | 50 GB Hard |
| Public | D:\Shares\Public | Domain Users (R), GG_IT (FC) | 10 GB Hard |
| HR_Confidential | D:\Shares\HR_Confidential | GG_HR (FC), GG_Management (R) | 5 GB Hard |
| Accounting | D:\Shares\Accounting | GG_Accounting (M), GG_Management (R) | 20 GB Hard |

- Share Permission: Authenticated Users = Change, Administrators = Full
- File Screen: Block *.exe, *.bat, *.ps1, *.msi, *.dll, *.jar, etc.
- Quota: Hard limit, thresholds 80%, 90%, 95% with Event log

---

## 7. Group Policy (GPO)

```powershell
# Trên DC1
Get-GPO -All | Where-Object { $_.DisplayName -like "STARTECH*" } | Format-Table DisplayName, CreationTime, ModificationTime -AutoSize

# Kiểm tra GPO Links
Get-GPInheritance -Target "DC=startech,DC=local" | Select-Object -ExpandProperty GpoLinks | Format-Table DisplayName, Enforced, LinkEnabled, Order -AutoSize
Get-GPInheritance -Target "OU=Workstations,DC=startech,DC=local" | Select-Object -ExpandProperty GpoLinks | Format-Table DisplayName, Enforced, LinkEnabled, Order -AutoSize
Get-GPInheritance -Target "OU=Servers,DC=startech,DC=local" | Select-Object -ExpandProperty GpoLinks | Format-Table DisplayName, Enforced, LinkEnabled, Order -AutoSize

# Trên Workstation (sau gpupdate /force)
gpresult /h gpreport.html
rsop.msc

# Kiểm tra Firewall Policy
Get-NetFirewallProfile -Name Domain | Select Name, Enabled, DefaultInboundAction, DefaultOutboundAction
```

### Kết quả mong đợi
| GPO | Linked To | Order | Key Settings |
|-----|-----------|-------|--------------|
| STARTECH - Security Baseline | Domain | 1 | Firewall Domain/Private/Public Enabled, Inbound Block, UAC Enabled, SMBv1 Disabled |
| STARTECH - Workstation Hardening | Workstations OU | 1 | Screen Saver 15min + Lock, Power High Perf, AutoRun Disabled |
| STARTECH - Server Hardening | Servers OU | 1 | Unnecessary Services Disabled, IPv6 Disabled, Event Log 128MB |
| STARTECH - Drive Mappings | Domain (User) | 2 | GPP Drive Maps Z:, Y:, X: |
| STARTECH - Audit Policy | Domain | 3 | Advanced Audit: Logon, Object Access, Process Creation, etc. |

---

## 8. Windows Server Backup

```powershell
# Trên từng Server
wbadmin get schedule
wbadmin get versions -backupTarget:E:  # hoặc network share
wbadmin get status

# Kiểm tra Scheduled Task
Get-ScheduledTask -TaskName "STARTECH Backup Cleanup"
```

### Kết quả mong đợi
- Schedule: Daily 02:00
- DC: Backup System State + Critical Volumes
- Member Server: Backup Critical Volumes + Data (D:)
- Retention: 14 days (cleanup script weekly)
- Bare Metal Recovery info documented

---

## 9. Network Devices (Router, Switch, Firewall)

### Router (show commands)
```
show ip interface brief
show ip route
show ip ospf neighbor
show vlan brief
show interfaces trunk
show spanning-tree summary
```

### L3 Switch
```
show ip interface brief
show vlan brief
show ip route
show standby brief  # nếu HSRP
show ip dhcp snooping binding
```

### Firewall (pfSense)
```
# Kiểm tra Rules
# Firewall > Rules > LAN, WAN, DMZ
# Kiểm tra NAT Port Forward
# Firewall > NAT > Port Forward
# Kiểm tra Aliases
# Firewall > Aliases
# Kiểm tra Logs
# Status > System Logs > Firewall
```

### Kết quả mong đợi
- OSPF: Full adjacency giữa Router-L3SW, Router-Router
- VLAN: Tất cả VLAN up, trunk allowed đúng
- STP: Rapid-PVST, L3SW root cho VLAN tại site
- DHCP Relay: ip helper-address 192.168.10.12 trên tất cả SVI (trừ VLAN 10/110)
- Firewall: Rules theo thiết kế, NAT port forward 80/443 -> Server02

---

## 10. Bảng tổng hợp cho báo cáo (Chương 5 - mục 4)

| Dịch vụ | Server/Thiết bị | Trạng thái | Chi tiết kiểm tra | Screenshot |
|---------|-----------------|------------|-------------------|------------|
| AD DS | DC1, DC2 | [Điền] | Domain, FSMO, OU, Groups, Users, Replication | [File] |
| DNS | DC1, DC2 | [Điền] | Zone, Records, Forwarders, Aging | [File] |
| DHCP | Server02 | [Điền] | Scopes, Options, Leases, Exclusions | [File] |
| Web/HTTPS | Server02 | [Điền] | IIS Site, Binding, Cert, Redirect | [File] |
| ADCS | Server02 | [Điền] | CA Info, Cert, CRL | [File] |
| File Server | Server02 | [Điền] | Shares, NTFS, Quota, File Screen | [File] |
| GPO | DC1 | [Điền] | GPO List, Links, RSOP | [File] |
| Backup | DC1, DC2, Srv02 | [Điền] | Schedule, Versions, Cleanup | [File] |
| Network | Router, SW, FW | [Điền] | Routing, VLAN, Firewall Rules | [File] |

---

## Ghi chú
- Chạy từng script kiểm tra, chụp màn hình kết quả
- Lưu output ra file text: `command > check_dns.txt 2>&1`
- Nếu dịch vụ FAIL: ghi rõ nguyên nhân, khắc phục, test lại
- Ký tên người kiểm tra, ngày giờ