# Kịch bản kiểm tra kết nối (Ping Test)

## Mục tiêu
Xác minh kết nối giữa các VLAN, các chi nhánh, và các dịch vụ quan trọng.

---

## 1. Kiểm tra liên VLAN (Intra-site)

### Trên máy trạm VLAN 20 (Sales CN1) - IP: 192.168.20.x
```powershell
# Ping gateway
ping 192.168.20.1

# Ping Server02 (DHCP, Web, File)
ping 192.168.10.12

# Ping DC1 (DNS, AD)
ping 192.168.10.11

# Ping máy trạm VLAN 30 (Acct/HR)
ping 192.168.30.50

# Ping máy trạm VLAN 40 (Guest) - NÊN THẤT BẠI (Firewall block)
ping 192.168.40.50
```

### Kết quả mong đợi
| Nguồn | Đích | Kết quả |
|-------|------|---------|
| VLAN 20 | Gateway 192.168.20.1 | ✓ Thành công |
| VLAN 20 | Server02 192.168.10.12 | ✓ Thành công |
| VLAN 20 | DC1 192.168.10.11 | ✓ Thành công |
| VLAN 20 | VLAN 30 (192.168.30.x) | ✓ Thành công |
| VLAN 20 | VLAN 40 (192.168.40.x) | ✗ Bị chặn (Firewall) |
| VLAN 40 | Internet (8.8.8.8) | ✓ Thành công |
| VLAN 40 | VLAN 10/20/30 | ✗ Bị chặn |

---

## 2. Kiểm tra liên chi nhánh (Inter-site)

### Từ CN1 ping sang CN2
```powershell
# Ping Router CN2
ping 10.0.0.2

# Ping DC2 (CN2)
ping 192.168.110.11

# Ping máy trạm CN2 (Sales/CS)
ping 192.168.120.50

# Traceroute
tracert 192.168.110.11
```

### Từ CN2 ping sang CN1
```powershell
ping 10.0.0.1
ping 192.168.10.11
ping 192.168.10.12
tracert 192.168.10.11
```

### Kết quả mong đợi
| Nguồn | Đích | Kết quả |
|-------|------|---------|
| CN1 | Router CN2 (10.0.0.2) | ✓ Thành công |
| CN1 | DC2 (192.168.110.11) | ✓ Thành công |
| CN1 | CN2 Workstation (192.168.120.x) | ✓ Thành công |
| CN2 | Router CN1 (10.0.0.1) | ✓ Thành công |
| CN2 | DC1 (192.168.10.11) | ✓ Thành công |
| CN2 | Server02 (192.168.10.12) | ✓ Thành công |

---

## 3. Kiểm tra DNS Resolution

```powershell
# Trên bất kỳ máy nào trong domain
nslookup dc1.startech.local
nslookup dc2.startech.local
nslookup web.startech.local
nslookup www.startech.local
nslookup server02.startech.local

# Reverse lookup
nslookup 192.168.10.11
nslookup 192.168.10.12
nslookup 192.168.110.11
```

### Kết quả mong đợi
- Tất cả tên miền nội bộ resolve đúng IP
- Reverse lookup trả về FQDN đúng

---

## 4. Kiểm tra Internet Access

```powershell
# Từ máy trạm nội bộ (VLAN 20, 30, 120)
ping 8.8.8.8
curl -I https://www.google.com

# Từ Server02 (cho Ollama model pull)
curl -I https://ollama.ai
curl -I https://registry.ollama.ai
```

### Kết quả mong đợi
| Nguồn | Đích | Kết quả |
|-------|------|---------|
| Internal VLANs | Internet | ✓ Thành công |
| Server02 | Ollama registry | ✓ Thành công (chỉ Server02) |
| Guest VLANs | Internet | ✓ Thành công |
| Guest VLANs | Internal | ✗ Bị chặn |

---

## 5. Kiểm tra AD Replication

```powershell
# Trên DC1
repadmin /replsummary
repadmin /showrepl DC1
repadmin /showrepl DC2

# Kiểm tra FSMO
netdom query fsmo

# Kiểm tra SYSVOL
dir \\DC1\SYSVOL
dir \\DC2\SYSVOL
```

### Kết quả mong đợi
- Replication: Success (0 failures)
- FSMO roles: DC1 nắm tất cả (hoặc phân chia đúng)
- SYSVOL share accessible trên cả 2 DC

---

## 6. Kiểm tra DHCP

```powershell
# Trên Server02
Get-DhcpServerv4Scope
Get-DhcpServerv4Lease -ScopeId 192.168.20.0
Get-DhcpServerv4Lease -ScopeId 192.168.30.0
Get-DhcpServerv4Lease -ScopeId 192.168.120.0

# Trên máy trạm (sau khi renew)
ipconfig /release
ipconfig /renew
ipconfig /all
```

### Kết quả mong đợi
- Tất cả scope Active
- Máy trạm nhận IP đúng dải, Gateway đúng, DNS đúng (DC1, DC2)

---

## 7. Kiểm tra Website & Chatbot

```powershell
# HTTP -> HTTPS Redirect
curl -I http://web.startech.local
curl -I http://www.startech.local

# HTTPS
curl -I https://web.startech.local
curl -I https://www.startech.local

# Kiểm tra chứng chỉ
openssl s_client -connect web.startech.local:443 -servername web.startech.local < /dev/null

# Chatbot API
curl -X POST http://web.startech.local:8080/api/chat `
  -H "Content-Type: application/json" `
  -d '{"message": "Công ty làm việc giờ nào?", "sessionId": "test-1"}'
```

### Kết quả mong đợi
- HTTP 301/302 redirect sang HTTPS
- HTTPS 200 OK, chứng chỉ hợp lệ (CN=web.startech.local, SAN: www, IP)
- Chatbot trả lời đúng giờ làm việc

---

## 8. Kiểm tra File Share & NTFS

```powershell
# Map drive
net use Z: \\Server02\Data /user:STARTECH\testuser
net use Y: \\Server02\Public

# Kiểm tra quyền
icacls Z:
icacls Y:

# Test ghi/đọc
echo "test" > Z:\test.txt
type Z:\test.txt
del Z:\test.txt

# Test quota (tạo file lớn)
fsutil file createnew Z:\bigfile.tmp 150000000  # ~150MB - nên thất bại nếu quota 100MB
```

### Kết quả mong đợi
- Map drive thành công
- NTFS permissions đúng theo AGDLP
- Quota block khi vượt ngưỡng

---

## 9. Kiểm tra GPO

```powershell
# Trên máy trạm
gpupdate /force
gpresult /h gpreport.html
rsop.msc

# Kiểm tra Firewall
Get-NetFirewallProfile -Name Domain | Select Name, Enabled, DefaultInboundAction
```

### Kết quả mong đợi
- GPO áp dụng thành công
- Firewall Domain Profile: Enabled, Inbound Block

---

## 10. Bảng tổng hợp kết quả cho báo cáo (Chương 5)

| STT | Kịch bản | Kết quả mong đợi | Kết quả thực tế | Đạt/Không đạt |
|-----|----------|------------------|-----------------|---------------|
| 1 | Ping CN1 ↔ CN2 | Thành công | [Điền sau test] | |
| 2 | Internal → Internet | Thành công | | |
| 3 | Guest VLAN → Internal | Bị chặn | | |
| 4 | Guest VLAN → Internet | Thành công | | |
| 5 | HTTPS Website | Thành công, cert valid | | |
| 6 | HTTP → HTTPS Redirect | 301/302 Redirect | | |
| 7 | Non-Server02 → API AI | Bị chặn (Firewall) | | |
| 8 | Server02 → Ollama Registry | Thành công | | |
| 9 | DNS Resolution (Internal) | Thành công | | |
| 10 | AD Replication DC1↔DC2 | Success | | |
| 11 | DHCP Lease (tất cả VLAN) | Đúng IP, Gateway, DNS | | |
| 12 | File Share Access | Theo NTFS/Share permission | | |
| 13 | Quota Enforcement | Block khi vượt limit | | |
| 14 | GPO Applied | Firewall, Screen lock, etc. | | |
| 15 | Chatbot API Response | < 5s, trả lời đúng | | |

---

## Ghi chú
- Chạy test sau khi hoàn tất tất cả cấu hình
- Chụp ảnh màn hình (screenshot) mỗi mục quan trọng
- Ghi lại thời gian test, người test
- Nếu có mục thất bại: ghi rõ nguyên nhân, phương án khắc phục