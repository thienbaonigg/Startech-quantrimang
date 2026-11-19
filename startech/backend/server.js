/**
 * STARTECH Backend - Website + Chatbot AI (Ollama + RAG)
 * Chạy trên Server02 (Windows Server / Linux)
 * Port mặc định: 8080 (HTTP) / 8443 (HTTPS khi cấu hình IIS proxy)
 */
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const bodyParser = require('body-parser');
const path = require('path');
const { RAGEngine } = require('./rag/engine');

const app = express();
const PORT = process.env.PORT || 8080;
const HOST = process.env.HOST || '0.0.0.0';

// Middleware bảo mật
app.use(helmet({
  contentSecurityPolicy: false, // tắt CSP để widget chat nhúng được
  crossOriginEmbedderPolicy: false
}));
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
  credentials: true
}));
app.use(bodyParser.json({ limit: '10kb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10kb' }));

// Rate limiting
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 60000,
  max: parseInt(process.env.RATE_LIMIT_MAX) || 20,
  message: { error: 'Quá nhiều yêu cầu, vui lòng thử lại sau 1 phút.' },
  standardHeaders: true,
  legacyHeaders: false
});
app.use('/api/chat', limiter);

// Phục vụ file tĩnh (website frontend)
app.use(express.static(path.join(__dirname, '../frontend')));

// Khởi tạo RAG Engine
const rag = new RAGEngine({
  knowledgeDir: path.join(__dirname, 'rag/knowledge'),
  ollamaBaseUrl: process.env.OLLAMA_BASE_URL || 'http://localhost:11434',
  model: process.env.OLLAMA_MODEL || 'qwen2.5:7b-instruct',
  topK: parseInt(process.env.RAG_TOP_K) || 3,
  similarityThreshold: parseFloat(process.env.SIMILARITY_THRESHOLD) || 0.55,
  timeoutMs: parseInt(process.env.OLLAMA_TIMEOUT_MS) || 30000
});

// Khởi tạo RAG khi start server
async function initRAG() {
  try {
    await rag.initialize();
  } catch (err) {
    console.error('[RAG] Lỗi khởi tạo:', err.message);
  }
}
initRAG();

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', service: 'startech-backend', timestamp: new Date().toISOString() });
});

// Chatbot API endpoint
app.post('/api/chat', async (req, res) => {
  const startTime = Date.now();
  try {
    const { message, sessionId } = req.body;
    if (!message || typeof message !== 'string') {
      return res.status(400).json({ error: 'Thiếu tham số message' });
    }

    // Kiểm tra prompt injection cơ bản
    const suspiciousPatterns = [
      /ignore\s+previous\s+instructions/i,
      /system\s+prompt/i,
      /api\s+key/i,
      /password/i,
      /secret/i,
      /bypass/i,
      /override/i,
      /reveal/i,
      /print\s+your\s+instructions/i
    ];
    if (suspiciousPatterns.some(p => p.test(message))) {
      console.warn('[Chatbot] Phát hiện prompt injection từ IP:', req.ip);
      return res.json({
        answer: 'Xin lỗi, tôi không thể xử lý yêu cầu này. Vui lòng đặt câu hỏi liên quan đến sản phẩm, dịch vụ của STARTECH.',
        sources: [],
        confidence: 0,
        blocked: true
      });
    }

    // Giới hạn độ dài
    if (message.length > 1000) {
      return res.status(400).json({ error: 'Tin nhắn quá dài (tối đa 1000 ký tự)' });
    }

    const result = await rag.answer(message.trim());

    // Ghi log (để sau này phân tích)
    console.log(`[Chatbot] ${req.ip} | ${sessionId || 'anonymous'} | ${message.slice(0,50)} | ${result.confidence.toFixed(2)} | ${Date.now() - startTime}ms`);

    res.json({
      answer: result.answer,
      sources: result.sources,
      confidence: result.confidence,
      responseTimeMs: Date.now() - startTime
    });
  } catch (err) {
    console.error('[Chatbot] Lỗi:', err.message);
    res.status(500).json({
      answer: 'Xin lỗi, hệ thống chatbot đang gặp sự cố. Vui lòng thử lại sau hoặc liên hệ hotline 028.1234.5678.',
      sources: [],
      confidence: 0,
      error: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
  }
});

// API lấy thông tin công ty (dùng cho website)
app.get('/api/company', (req, res) => {
  res.json({
    name: 'Công ty TNHH Công Nghệ và Dịch Vụ TIN HỌC STARTECH',
    branches: [
      { id: 1, name: 'Chi nhánh 1 (Trụ sở)', address: '123 Nguyễn Văn Linh, Quận Tân Bình, TP.HCM', phone: '028.1234.5678' },
      { id: 2, name: 'Chi nhánh 2', address: '45 Lê Lợi, Quận Hải Châu, TP.Đà Nẵng', phone: '0236.1234.5678' }
    ],
    hours: 'Thứ 2 - Thứ 6: 8:00 - 17:30',
    email: 'support@startech.vn',
    website: 'www.startech.vn'
  });
});

// API sản phẩm (dùng cho website)
app.get('/api/products', (req, res) => {
  // Dữ liệu mẫu - thực tế đọc từ file/DB
  res.json([
    { id: 1, name: 'Laptop STARTECH FlexPro 14', price: 18500000, category: 'Laptop' },
    { id: 2, name: 'Laptop STARTECH FlexPro 15', price: 24900000, category: 'Laptop' },
    { id: 3, name: 'Laptop STARTECH Business 14', price: 11200000, category: 'Laptop' },
    { id: 4, name: 'Switch STARTECH S2424', price: 3200000, category: 'Thiết bị mạng' },
    { id: 5, name: 'Router STARTECH R100', price: 2800000, category: 'Thiết bị mạng' },
    { id: 6, name: 'Access Point STARTECH AP-WiFi6', price: 1900000, category: 'Thiết bị mạng' },
    { id: 7, name: 'NAS STARTECH NAS-4', price: 8700000, category: 'Lưu trữ' },
    { id: 8, name: 'SSD 1TB STARTECH', price: 2100000, category: 'Lưu trữ' }
  ]);
});

// Fallback: phục vụ index.html cho SPA
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../frontend/index.html'));
});

// Khởi động server
app.listen(PORT, HOST, () => {
  console.log(`[Server] STARTECH Backend đang chạy tại http://${HOST}:${PORT}`);
  console.log(`[Server] Chatbot API: POST http://${HOST}:${PORT}/api/chat`);
  console.log(`[Server] RAG knowledge: ${path.join(__dirname, 'rag/knowledge')}`);
  console.log(`[Server] Ollama: ${process.env.OLLAMA_BASE_URL || 'http://localhost:11434'} (model: ${process.env.OLLAMA_MODEL || 'qwen2.5:7b-instruct'})`);
});

module.exports = app;