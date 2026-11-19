/**
 * Change Brand Script
 * Usage: node scripts/change-brand.js --name STARTUP --domain startup.vn
 *
 * Thay đổi toàn bộ branding: tên công ty, domain, API URL, test questions
 * Không cần sửa code - chỉ cần config brand.json
 */
const fs = require('fs');
const path = require('path');

const brandPath = path.join(__dirname, '..', 'config', 'brand.json');
const brand = JSON.parse(fs.readFileSync(brandPath, 'utf-8'));

// Parse args
const args = process.argv.slice(2);
const params = {};
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) {
    const key = args[i].slice(2);
    const value = args[i + 1];
    params[key] = value;
    i++;
  }
}

// Apply changes
if (params.name) {
  brand.company.shortName = params.name.toUpperCase();
  brand.company.fullName = `Công ty TNHH Công Nghệ và Dịch Vụ ${params.name.toUpperCase()}`;
  brand.company.name = params.name.toUpperCase();
  brand.company.email = `support@${params.domain || params.name.toLowerCase()}.vn`;
  brand.company.salesEmail = `sales@${params.domain || params.name.toLowerCase()}.vn`;
  brand.company.publicDomain = `www.${params.domain || params.name.toLowerCase()}.vn`;
  brand.company.domain = params.domain || params.name.toLowerCase();
  brand.chatbot.widgetTitle = `Hỗ trợ ${params.name.toUpperCase()}`;
  brand.chatbot.productionApiUrl = `https://api.${params.domain || params.name.toLowerCase()}.vn`;
  brand.chatbot.welcomeMessage = `Xin chào! Tôi là trợ lý ảo của ${params.name.toUpperCase()}. Tôi có thể giúp bạn hỏi giá sản phẩm, chính sách bảo hành, giờ làm việc...`;
  brand.chatbot.disclaimer = `Chatbot AI chạy nội bộ, dữ liệu không rời khỏi mạng doanh nghiệp ${params.name.toUpperCase()}.`;
}

if (params.phone) brand.company.phone = params.phone;
if (params.address1) brand.company.address1 = params.address1;
if (params.address2) brand.company.address2 = params.address2;

// Save
fs.writeFileSync(brandPath, JSON.stringify(brand, null, 2), 'utf-8');
console.log(`✅ Brand changed to: ${brand.company.fullName}`);
console.log(`   Domain: ${brand.company.publicDomain}`);
console.log(`   API: ${brand.chatbot.productionApiUrl}`);
console.log(`   Test questions: ${brand.testQuestions.length} questions`);
console.log('');
console.log('Next steps:');
console.log('  1. Update knowledge files in backend/rag/knowledge/');
console.log('  2. Restart backend: npm run dev');
console.log('  3. Run tests: npm test');