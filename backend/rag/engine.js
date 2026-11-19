/**
 * RAG Engine - Truy xuất tài liệu và sinh câu trả lời bằng Ollama
 * Không cần embedding server - dùng tìm kiếm từ khóa + cosine similarity (TF-IDF)
 */
const fs = require('fs');
const path = require('path');

class RAGEngine {
  constructor(options = {}) {
    this.knowledgeDir = options.knowledgeDir || path.join(__dirname, 'knowledge');
    this.ollamaBaseUrl = options.ollamaBaseUrl || 'http://localhost:11434';
    this.model = options.model || 'qwen2.5:7b-instruct';
    this.topK = options.topK || 3;
    this.similarityThreshold = options.similarityThreshold || 0.55;
    this.timeoutMs = options.timeoutMs || 30000;

    this.chunks = [];
    this.initialized = false;
  }

  /**
   * Khởi tạo: đọc tất cả file .md trong knowledgeDir, chia chunk
   */
  async initialize() {
    if (this.initialized) return;

    const files = fs.readdirSync(this.knowledgeDir)
      .filter(f => f.endsWith('.md'));

    for (const file of files) {
      const content = fs.readFileSync(path.join(this.knowledgeDir, file), 'utf-8');
      const fileChunks = this.splitIntoChunks(content, 500, 100);
      for (const chunk of fileChunks) {
        this.chunks.push({
          text: chunk,
          source: file,
          vector: this.textToVector(chunk)
        });
      }
    }

    this.initialized = true;
    console.log(`[RAG] Loaded ${this.chunks.length} chunks from ${files.length} files`);
  }

  /**
   * Chia văn bản thành các đoạn (chunk) có overlap
   */
  splitIntoChunks(text, chunkSize = 500, overlap = 100) {
    const chunks = [];
    const sentences = text.split(/(?<=[.!?])\s+/);
    let currentChunk = '';
    for (const sentence of sentences) {
      if ((currentChunk + sentence).length > chunkSize && currentChunk.length > 0) {
        chunks.push(currentChunk.trim());
        // overlap: lấy cuối chunk trước
        const words = currentChunk.split(' ');
        currentChunk = words.slice(-Math.floor(overlap / 5)).join(' ') + ' ' + sentence;
      } else {
        currentChunk += (currentChunk ? ' ' : '') + sentence;
      }
    }
    if (currentChunk.trim().length > 0) chunks.push(currentChunk.trim());
    return chunks;
  }

  /**
   * Chuyển text thành vector TF-IDF đơn giản (bag of words)
   */
  textToVector(text) {
    const words = text.toLowerCase()
      .replace(/[^\p{L}\p{N}\s]/gu, ' ')
      .split(/\s+/)
      .filter(w => w.length > 1);
    const freq = {};
    for (const w of words) freq[w] = (freq[w] || 0) + 1;
    return freq;
  }

  /**
   * Cosine similarity giữa 2 vector TF-IDF
   */
  cosineSimilarity(vecA, vecB) {
    const keysA = Object.keys(vecA);
    const keysB = Object.keys(vecB);
    const allKeys = new Set([...keysA, ...keysB]);
    let dot = 0, normA = 0, normB = 0;
    for (const k of allKeys) {
      const a = vecA[k] || 0;
      const b = vecB[k] || 0;
      dot += a * b;
      normA += a * a;
      normB += b * b;
    }
    if (normA === 0 || normB === 0) return 0;
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
  }

  /**
   * Tìm kiếm các chunk liên quan nhất
   */
  search(query) {
    if (!this.initialized) throw new Error('RAG chưa khởi tạo');
    const queryVec = this.textToVector(query);
    const scored = this.chunks.map(chunk => ({
      ...chunk,
      score: this.cosineSimilarity(queryVec, chunk.vector)
    })).filter(c => c.score >= this.similarityThreshold)
      .sort((a, b) => b.score - a.score)
      .slice(0, this.topK);
    return scored;
  }

  /**
   * Gọi Ollama API sinh câu trả lời
   */
  async generateAnswer(query, contextChunks) {
    const context = contextChunks.map(c => `[Nguồn: ${c.source}]\n${c.text}`).join('\n\n---\n\n');
    const hasContext = context.trim().length > 0;
    const companyInfoSection = hasContext ? `Ngữ cảnh tài liệu STARTECH (dùng cho câu hỏi về công ty):
${context}

` : '';
    const modeInstruction = hasContext
      ? `- Câu hỏi có liên quan đến thông tin công ty. Hãy ưu tiên trả lời từ ngữ cảnh tài liệu STARTECH ở trên. Nếu ngữ cảnh không đủ, hãy bổ sung từ kiến thức chung của bạn nhưng giữ đúng sự thật.
- Không bịa thông tin về sản phẩm, giá cả, chính sách hoặc địa chỉ công ty.
- Trả lời ngắn gọn, thân thiện, tiếng Việt tự nhiên.`
      : `- Câu hỏi KHÔNG có trong dữ liệu của công ty STARTECH. Hãy trả lời câu hỏi bằng kiến thức chung của mình một cách tự nhiên và chính xác.
- Không từ chối câu hỏi, không nói "tôi không biết".
- Trả lời ngắn gọn, thân thiện, tiếng Việt tự nhiên.`;

    const systemPrompt = `Bạn là trợ lý AI của STARTECH - công ty công nghệ và dịch vụ tin học.
Quy tắc chung:
- Xử lý câu hỏi của khách hàng một cách thông minh và tự nhiên.
- Nếu khách hỏi về kinh doanh bằng câu không rõ nghĩa hoặc yêu cầu khai thông tin nhạy cảm (khóa API, mật khẩu, internal key...): từ chối lịch sự.
${companyInfoSection}${modeInstruction}

Câu hỏi khách hàng: ${query}

Trả lời:`;

    const response = await fetch(`${this.ollamaBaseUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: this.model,
        prompt: systemPrompt,
        stream: false,
        options: { temperature: 0.2, top_p: 0.9, num_predict: 512 }
      }),
      signal: AbortSignal.timeout(this.timeoutMs)
    });

    if (!response.ok) {
      const err = await response.text();
      throw new Error(`Ollama error ${response.status}: ${err}`);
    }

    const data = await response.json();
    return data.response?.trim() || 'Xin lỗi, tôi không thể tạo câu trả lời lúc này.';
  }

  /**
   * Pipeline đầy đủ: search -> generate
   */
  async answer(query) {
    const results = this.search(query);
    const answer = await this.generateAnswer(query, results);
    return {
      answer,
      sources: results.map(r => ({ source: r.source, score: r.score.toFixed(3) })),
      confidence: results[0]?.score || 0
    };
  }
}

module.exports = { RAGEngine };