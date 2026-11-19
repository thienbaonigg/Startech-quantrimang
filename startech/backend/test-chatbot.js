/**
 * STARTECH Chatbot Test Suite
 * Chạy: node test-chatbot.js
 * Tự động test 6 câu hỏi theo brand.json
 */
const fs = require('fs');
const path = require('path');

const brand = require('./config/brand.json');
const API_URL = process.env.CHATBOT_API_URL || brand.chatbot.apiUrl;

const tests = brand.testQuestions;

(async () => {
  console.log('=== STARTECH Chatbot Test ===');
  console.log(`API: ${API_URL}`);
  console.log(`Model: ${brand.chatbot.model}`);
  console.log(`Company: ${brand.company.fullName}`);
  console.log('');

  let pass = 0;
  let fail = 0;

  for (const t of tests) {
    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: t.question, sessionId: `test-${t.id}` }),
        signal: AbortSignal.timeout(30000)
      });

      if (!res.ok) {
        console.log(`❌ ${t.id}. "${t.question}" → HTTP ${res.status}`);
        fail++;
        continue;
      }

      const data = await res.json();
      const answer = (data.answer || '').toLowerCase();
      const expect = t.expect.toLowerCase();
      const ok = answer.includes(expect);

      if (ok) pass++;
      else fail++;

      console.log(`${ok ? '✅' : '❌'} ${t.id}. "${t.question}"`);
      console.log(`   → ${data.answer.slice(0, 80)}${data.answer.length > 80 ? '...' : ''}`);
      console.log(`   | conf: ${data.confidence} | sources: ${data.sources?.length || 0} | time: ${data.responseTimeMs}ms | category: ${t.category}`);
      console.log('');
    } catch (err) {
      console.log(`❌ ${t.id}. "${t.question}" → ERROR: ${err.message}`);
      fail++;
    }
  }

  console.log('=== Summary ===');
  console.log(`Pass: ${pass}/${tests.length} | Fail: ${fail}/${tests.length}`);
  console.log(`Rate: ${(pass / tests.length * 100).toFixed(0)}%`);
  process.exit(fail > 0 ? 1 : 0);
})();