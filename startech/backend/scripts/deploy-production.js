/**
 * Deploy Production Script
 * Chuyển từ local (localhost:8080) sang production domain
 * Usage: node scripts/deploy-production.js --domain api.startech.vn --port 443
 *
 * Tự động:
 * 1. Thay localhost:8080 → production domain
 * 2. Cấu hình HTTPS (cert from ADCS or Let's Encrypt)
 * 3. Cập nhật CORS origins
 * 4. Cập nhật frontend API_BASE
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const brandPath = path.join(__dirname, '..', 'config', 'brand.json');
const brand = JSON.parse(fs.readFileSync(brandPath, 'utf-8'));

const args = process.argv.slice(2);
const params = {};
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) {
    params[args[i].slice(2)] = args[i + 1];
    i++;
  }
}

const domain = params.domain || brand.chatbot.productionApiUrl.replace('https://', '');
const port = params.port || 443;

console.log('=== Deploy Production ===');
console.log(`Domain: ${domain}`);
console.log(`Port: ${port}`);
console.log('');

// 1. Update .env
const envPath = path.join(__dirname, '..', '.env');
let env = fs.readFileSync(envPath, 'utf-8');

// Update API URL
env = env.replace(/OLLAMA_BASE_URL=.*/g, `OLLAMA_BASE_URL=http://localhost:11434`);
env = env.replace(/HOST=.*/g, `HOST=0.0.0.0`);
env = env.replace(/PORT=.*/g, `PORT=${port}`);
env = env.replace(/NODE_ENV=.*/g, `NODE_ENV=production`);

// Update CORS
const origins = [
  `https://${brand.company.publicDomain}`,
  `https://www.${brand.company.publicDomain}`,
  `https://${brand.company.domain}`,
  `https://api.${brand.company.domain}`,
];
env = env.replace(/ALLOWED_ORIGINS=.*/g, `ALLOWED_ORIGINS=${origins.join(',')}`);

fs.writeFileSync(envPath, env, 'utf-8');
console.log('✅ Updated .env');

// 2. Update frontend API_BASE
const frontendDir = path.join(__dirname, '..', '..', 'frontend');
const htmlFiles = fs.readdirSync(frontendDir).filter(f => f.endsWith('.html'));

for (const file of htmlFiles) {
  const filePath = path.join(frontendDir, file);
  let content = fs.readFileSync(filePath, 'utf-8');

  // Update API_BASE
  const apiBaseScript = `<script>\n    window.CHATBOT_API_BASE = 'https://api.${brand.company.domain}';\n  </script>`;
  content = content.replace(
    /<script>\s*window\.CHATBOT_API_BASE\s*=\s*['"][^'"]*['"];?\s*<\/script>/g,
    apiBaseScript
  );

  // Update company name
  content = content.replace(/STARTECH/g, brand.company.shortName);
  content = content.replace(/startech\.vn/g, brand.company.publicDomain);
  content = content.replace(/startech\.local/g, brand.company.domain);
  content = content.replace(/support@startech\.vn/g, brand.company.email);

  fs.writeFileSync(filePath, content, 'utf-8');
  console.log(`✅ Updated ${file}`);
}

// 3. Update knowledge files
const knowledgeDir = path.join(__dirname, '..', 'rag', 'knowledge');
const knowledgeFiles = fs.readdirSync(knowledgeDir).filter(f => f.endsWith('.md'));

for (const file of knowledgeFiles) {
  const filePath = path.join(knowledgeDir, file);
  let content = fs.readFileSync(filePath, 'utf-8');
  content = content.replace(/STARTECH/g, brand.company.shortName);
  content = content.replace(/startech\.vn/g, brand.company.publicDomain);
  content = content.replace(/startech\.local/g, brand.company.domain);
  content = content.replace(/support@startech\.vn/g, brand.company.email);
  fs.writeFileSync(filePath, content, 'utf-8');
  console.log(`✅ Updated ${file}`);
}

// 4. Summary
console.log('');
console.log('=== Deploy Summary ===');
console.log(`Company: ${brand.company.fullName}`);
console.log(`Domain: ${brand.company.publicDomain}`);
console.log(`API: https://api.${brand.company.domain}`);
console.log(`CORS: ${origins.join(', ')}`);
console.log('');
console.log('Next steps:');
console.log('  1. Install SSL certificate (Let\'s Encrypt or ADCS)');
console.log('  2. Configure reverse proxy (Nginx/IIS)');
console.log('  3. Run: npm start');
console.log('  4. Test: npm test');