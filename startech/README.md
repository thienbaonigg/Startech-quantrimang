# STARTECH - Website doanh nghiệp + Chatbot AI (Ollama + RAG)

Hệ thống demo hoàn chỉnh cho đồ án **Quản trị mạng**: Website doanh nghiệp + Chatbot AI chạy mô hình cục bộ (Ollama) + RAG (Retrieval-Augmented Generation).

## Cấu trúc thư mục

```
startech/
├── backend/                 # Node.js/Express backend
│   ├── server.js           # Entry point
│   ├── package.json
│   ├── .env                # Cấu hình môi trường
│   └── rag/
│       ├── engine.js       # RAG engine (TF-IDF + cosine similarity)
│       └── knowledge/      # Kho tri thức doanh nghiệp (.md)
│           ├── company_info.md
│           ├── products_pricing.md
│           └── policies_faq.md
├── frontend/               # Website tĩnh (HTML/CSS/JS)
│   ├── index.html          # Trang chủ
│   ├── products.html       # Sản phẩm
│   ├── services.html       # Dịch vụ
│   ├── about.html          # Giới thiệu
│   ├── contact.html        # Liên hệ
│   ├── styles.css          # CSS chung
│   ├── app.js              # JS chung
│   ├── chat-widget.js      # Widget chatbot
│   ├── products.js         # JS trang sản phẩm
│   └── contact.js          # JS trang liên hệ
└── network-config/         # Config mạng GNS3 (xem file riêng)
```

## Yêu cầu hệ thống

- **Node.js** >= 18
- **Ollama** (cài đặt và chạy model)
- **RAM** >= 8GB (khuyến nghị 16GB cho model 7B)
- **OS**: Windows/Linux/macOS

## Cài đặt và chạy

### 1. Cài đặt Ollama và tải model

```bash
# Windows: tải từ https://ollama.ai/download
# Linux/macOS:
curl -fsSL https://ollama.ai/install.sh | sh

# Khởi động Ollama service
ollama serve

# Tải model (chọn 1 trong 2):
# - qwen2.5:7b-instruct (tốt tiếng Việt, ~4.7GB)
ollama pull qwen2.5:7b-instruct

# Hoặc llama3.1:8b (~4.9GB)
# ollama pull llama3.1:8b
```

### 2. Cài đặt backend

```bash
cd startech/backend
npm install

# Copy .env và chỉnh sửa nếu cần
cp .env .env.local
```

### 3. Chạy backend

```bash
# Development (auto-reload)
npm run dev

# Production
npm start
```

Backend chạy tại: `http://localhost:8080`
- API chatbot: `POST http://localhost:8080/api/chat`
- Health check: `GET http://localhost:8080/api/health`
- API sản phẩm: `GET http://localhost:8080/api/products`
- API công ty: `GET http://localhost:8080/api/company`

### 4. Phục vụ frontend

```bash
cd startech/frontend

# Option 1: Python (có sẵn)
python3 -m http.server 3000

# Option 2: Node.js serve
npx serve -p 3000

# Option 3: VS Code Live Server extension
```

Truy cập: `http://localhost:3000`

### 5. Test chatbot

```bash
curl -X POST http://localhost:8080/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Công ty làm việc giờ nào?", "sessionId": "test-1"}'
```

## Tùy chỉnh kho tri thức (RAG)

Chỉnh sửa file trong `backend/rag/knowledge/`:
- `company_info.md`: Thông tin công ty, chi nhánh, giờ làm việc
- `products_pricing.md`: Sản phẩm, giá, ưu đãi
- `policies_faq.md`: Chính sách bảo hành, đổi trả, FAQ

Sau khi sửa: **khởi động lại backend** (`npm run dev`) để RAG nạp lại dữ liệu.

## Triển khai lên Windows Server (IIS)

1. Cài Node.js trên Windows Server
2. Copy thư mục `startech/backend` lên server (ví dụ: `C:\inetpub\startech-backend`)
3. Chạy `npm install --production`
4. Tạo file `web.config` cho IIS (reverse proxy):
```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="Proxy to Node.js" stopProcessing="true">
          <match url="(.*)" />
          <action type="Rewrite" url="http://localhost:8080/{R:1}" />
        </rule>
      </rules>
    </rewrite>
    <iisnode node_env="production" />
  </system.webServer>
</configuration>
```
5. Cấu hình IIS Site trỏ đến thư mục, bật Application Request Routing (ARR)
6. Cấu hình HTTPS binding với chứng chỉ từ ADCS

## Mạng & Hạ tầng (theo đồ án)

Xem thư mục `network-config/` cho:
- Sơ đồ topology 2 chi nhánh (draw.io / PNG)
- Config IOS Router/Switch (VLAN, trunk, SVI, routing, DHCP relay)
- Firewall ACL rules
- Windows Server PowerShell script (AD, DNS, DHCP, IIS, ADCS)

## Bảo mật chatbot

- API key Ollama **không bao giờ** ở frontend (chạy local)
- Rate limiting: 20 req/phút/IP
- Prompt injection detection
- Input sanitization (XSS protection)
- CORS chỉ cho phép domain nội bộ
- Log đầy đủ để audit

## Cấu trúc API Chatbot

**Request:**
```json
POST /api/chat
{
  "message": "Câu hỏi khách hàng",
  "sessionId": "optional-session-id"
}
```

**Response:**
```json
{
  "answer": "Câu trả lời từ AI",
  "sources": [{"source": "products_pricing.md", "score": "0.823"}],
  "confidence": 0.823,
  "responseTimeMs": 1245
}
```

## Tùy chỉnh model

Sửa file `.env`:
```env
OLLAMA_MODEL=qwen2.5:7b-instruct
# hoặc llama3.1:8b, gemma2:9b, v.v.
```

## License

Dự án demo cho đồ án Quản trị mạng - Trường ĐH Ngoại ngữ Tin học TP.HCM.