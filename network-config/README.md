# STARTECH Network Configuration

Cấu hình mạng cho 2 chi nhánh STARTECH theo mô hình đồ án Quản trị mạng.

## Topology Overview

```
                           INTERNET
                              │
                    ┌─────────┴─────────┐
                    │     Firewall      │  (pfSense / Cisco ASA)
                    └─────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
         ┌────▼────┐     ┌────▼────┐     ┌────▼────┐
         │Router CN1│─────│ WAN Link │─────│Router CN2│  (10.0.0.0/30)
         └────┬────┘     │ 10.0.0.0/30 │     └────┬────┘
              │          └─────────────┘          │
      ┌───────┼───────────────────────────────────┼───────┐
      │       │                                   │       │
┌─────▼──┐ ┌──▼──┐ ┌─────┐                   ┌─────▼──┐ ┌──▼──┐
│ L3 SW1 │ │ L2  │ │ DMZ │                   │ L3 SW2 │ │ L2  │
└────┬───┘ └──┬──┘ └──┬──┘                   └────┬───┘ └──┬──┘
     │        │      │                         │        │
┌────┴──┐ ┌───┴──┐ ┌──┴───┐              ┌─────┴──┐ ┌───┴──┐
│Server01│ │Server02│ │ WiFi │              │Server03│ │ WiFi │
│ DC1/DNS│ │File/Web│ │Guest │              │ DC2/DNS│ │Guest │
└────────┘ └────────┘ └──────┘              └────────┘ └──────┘
```

## IP Address Planning

| VLAN | Tên | Subnet | Gateway | Dải DHCP | Mô tả |
|------|-----|--------|---------|----------|-------|
| 10 | CN1-Server-Mgmt | 192.168.10.0/24 | 192.168.10.1 | Static | Server01, Server02, Mgmt |
| 20 | CN1-Sales | 192.168.20.0/24 | 192.168.20.1 | .50-.200 | Phòng Kinh doanh |
| 30 | CN1-Acct-HR | 192.168.30.0/24 | 192.168.30.1 | .50-.200 | Kế toán, Nhân sự |
| 40 | CN1-Guest-WiFi | 192.168.40.0/24 | 192.168.40.1 | .50-.200 | Khách (chỉ Internet) |
| 110 | CN2-Server-Mgmt | 192.168.110.0/24 | 192.168.110.1 | Static | Server03, Mgmt |
| 120 | CN2-Sales-CS | 192.168.120.0/24 | 192.168.120.1 | .50-.200 | Kinh doanh, CSKH |
| 140 | CN2-Guest-WiFi | 192.168.140.0/24 | 192.168.140.1 | .50-.200 | Khách (chỉ Internet) |
| - | WAN Link | 10.0.0.0/30 | 10.0.0.1/2 | Static | Router CN1 ↔ Router CN2 |

## Server IP Assignment

| Server | Hostname | VLAN | IP | Roles |
|--------|----------|------|-----|-------|
| Server01 | dc1.startech.local | 10 | 192.168.10.11 | AD DC1, DNS, ADCS |
| Server02 | web.startech.local | 10 | 192.168.10.12 | File, Web (IIS), Mail, DHCP, Chatbot |
| Server03 | dc2.startech.local | 110 | 192.168.110.11 | AD DC2, DNS |

## File Structure

```
network-config/
├── README.md                 # This file
├── topology.drawio           # Sơ đồ topology (mở bằng draw.io)
├── topology.png              # Export PNG cho báo cáo
├── router-cn1.cfg            # Config Router Chi nhánh 1
├── router-cn2.cfg            # Config Router Chi nhánh 2
├── l3-sw-cn1.cfg             # Config L3 Switch Chi nhánh 1
├── l3-sw-cn2.cfg             # Config L3 Switch Chi nhánh 2
├── l2-sw-access.cfg          # Template L2 Switch Access
├── firewall-pfsense.rules    # Firewall rules (pfSense format)
├── windows-server/
│   ├── 01-install-ad-dc1.ps1      # Cài AD DS + DNS trên Server01
│   ├── 02-install-ad-dc2.ps1      # Cài AD DC2 trên Server03
│   ├── 03-config-dhcp.ps1         # Cài DHCP trên Server02
│   ├── 04-config-iis-https.ps1    # Cài IIS + HTTPS + ADCS
│   ├── 05-config-file-share.ps1   # Cấu hình File Share, NTFS, Quota
│   ├── 06-config-gpo.ps1          # Group Policy cơ bản
│   ├── 07-config-backup.ps1       # Windows Server Backup
│   └── 08-join-domain.ps1         # Script join domain cho máy trạm
└── verification/
    ├── ping-test.md                 # Kịch bản test kết nối
    ├── service-check.md             # Kiểm tra dịch vụ
    └── chatbot-test.md              # Test chatbot
```

## Hướng dẫn triển khai GNS3

### 1. Chuẩn bị GNS3
- Cài GNS3 >= 2.2
- Tải appliance: Cisco IOSv (router), Cisco IOSvL2 (switch), pfSense (firewall)
- Tạo project mới: `STARTECH-Network`

### 2. Thêm thiết bị
| Thiết bị | Template | Số lượng | Ghi chú |
|----------|----------|----------|---------|
| Router CN1 | Cisco IOSv | 1 | Rename: R-CN1 |
| Router CN2 | Cisco IOSv | 1 | Rename: R-CN2 |
| L3 SW CN1 | Cisco IOSvL2 | 1 | Rename: L3-SW-CN1 |
| L3 SW CN2 | Cisco IOSvL2 | 1 | Rename: L3-SW-CN2 |
| L2 Access CN1 | Cisco IOSvL2 | 2 | Rename: L2-SW-CN1-1, L2-SW-CN1-2 |
| L2 Access CN2 | Cisco IOSvL2 | 2 | Rename: L2-SW-CN2-1, L2-SW-CN2-2 |
| Firewall | pfSense | 1 | Rename: FW-MAIN |
| Cloud (Internet) | Cloud | 1 | Kết nối VMnet/NAT |

### 3. Kết nối (Links)
```
R-CN1 g0/0 ──── FW-MAIN WAN
R-CN1 g0/1 ──── L3-SW-CN1 g1/1 (Trunk)
R-CN1 g0/2 ──── R-CN2 g0/2 (WAN Link 10.0.0.0/30)

R-CN2 g0/0 ──── FW-MAIN WAN (hoặc dùng chung FW)
R-CN2 g0/1 ──── L3-SW-CN2 g1/1 (Trunk)

L3-SW-CN1 g1/2 ──── L2-SW-CN1-1 g1/1 (Trunk)
L3-SW-CN1 g1/3 ──── L2-SW-CN1-2 g1/1 (Trunk)
L3-SW-CN1 g1/4 ──── Server01 (VMware VMnet)
L3-SW-CN1 g1/5 ──── Server02 (VMware VMnet)
L3-SW-CN1 g1/6 ──── WiFi-AP-CN1 (hoặc Cloud)

L3-SW-CN2 g1/2 ──── L2-SW-CN2-1 g1/1 (Trunk)
L3-SW-CN2 g1/3 ──── L2-SW-CN2-2 g1/1 (Trunk)
L3-SW-CN2 g1/4 ──── Server03 (VMware VMnet)
L3-SW-CN2 g1/5 ──── WiFi-AP-CN2 (hoặc Cloud)

FW-MAIN LAN ──── L3-SW-CN1 g1/1 (hoặc qua switch riêng DMZ)
FW-MAIN DMZ ──── Server02 (Web) - optional
```

### 4. Nạp config
Mở console từng thiết bị, copy-paste config từ file `.cfg` tương ứng.

### 5. Tích hợp VM Windows Server
- Tạo 3 VM Windows Server 2022 trong VMware Workstation/Pro
- Cấu hình 3 network adapter: VMnet1 (VLAN 10/110), VMnet2 (VLAN 20/120), VMnet3 (VLAN 30/140)
- Trong GNS3: Add QEMU VM hoặc dùng Cloud node trỏ đến VMnet

## Kiểm tra nhanh

```bash
# Trên Router CN1
show ip route
show ip interface brief
ping 192.168.110.11   # DC2
ping 10.0.0.2         # Router CN2

# Trên L3 Switch
show vlan brief
show ip interface brief
show standby brief    # nếu cấu hình HSRP

# Trên Server (PowerShell)
Test-Connection dc2.startech.local
Resolve-DnsName www.startech.local
Get-DhcpServerv4Scope
```

## Lưu ý quan trọng

1. **VTP Domain**: `STARTECH` - mode transparent trên L3 switch, client trên L2
2. **STP Root**: L3-SW-CN1 là root cho VLAN 10,20,30,40; L3-SW-CN2 root cho 110,120,140
3. **HSRP/VRRP**: Cấu hình gateway ảo cho từng VLAN nếu cần HA
4. **DHCP Relay**: `ip helper-address 192.168.10.12` trên tất cả SVI
5. **Firewall**: Chỉ cho phép Server02 (192.168.10.12) ra Internet cổng 443 đến Ollama model registry (nếu pull model lần đầu)

## Screenshot cho báo cáo

Chụp ảnh màn hình sau khi chạy thành công:
1. `show vlan brief` trên L3 switch
2. `show ip route` trên Router
3. Firewall rules bảng
4. AD Users & Computers với OU structure
5. IIS binding HTTPS với chứng chỉ ADCS
6. Chatbot widget trên website
7. Kết quả test chatbot (câu hỏi + trả lời)

---
*File config này dành cho môi trường demo/mô phỏng. Triển khai production cần review bảo mật kỹ hơn.*