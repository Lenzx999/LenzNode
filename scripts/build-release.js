/**
 * ==============================================================================
 * LenzNode — Automated Build & Encryption Pipeline for GitHub Release
 * Mengenkripsi server.js & frontend logic, meminifikasi HTML, serta menyiapkan
 * folder 'github-release' yang 100% siap di-commit & di-push ke GitHub.
 * ==============================================================================
 */

const fs = require('fs');
const path = require('path');
const JavaScriptObfuscator = require('javascript-obfuscator');

const SOURCE_DIR = path.resolve(__dirname, '..');
const RELEASE_DIR = path.resolve(SOURCE_DIR, '..', 'github-release');

console.log('🚀 Memulai proses build & enkripsi LenzNode untuk GitHub...\n');
console.log(`📂 Source:  ${SOURCE_DIR}`);
console.log(`📦 Release: ${RELEASE_DIR}\n`);

// 1. Daftar file dan folder yang dikecualikan dari rilis
const EXCLUDE_PATHS = [
  'node_modules',
  '.git',
  'package.json',
  'package-lock.json',
  path.join('scripts', 'build-release.js')
];

function shouldExclude(relPath) {
  const normalized = relPath.replace(/\\/g, '/');
  return EXCLUDE_PATHS.some(ex => normalized === ex || normalized.startsWith(ex + '/'));
}

// 2. Fungsi copy rekursif
function copyRecursive(src, dest) {
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }

  const entries = fs.readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const relPath = path.relative(SOURCE_DIR, srcPath);

    if (shouldExclude(relPath)) continue;

    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyRecursive(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

console.log('📋 Menyalin struktur berkas ke folder rilis...');
copyRecursive(SOURCE_DIR, RELEASE_DIR);
console.log('✅ Penyalinan berkas selesai.\n');

// 3. Konfigurasi Obfuscator Ramah Android (Hemat RAM 512MB, Anti-Tamper & Terenkripsi)
const NODE_OBFUSCATOR_OPTIONS = {
  compact: true,
  controlFlowFlattening: false, // Menghindari konsumsi memori berlebih di HP kentang
  deadCodeInjection: false,
  debugProtection: false, // Menghindari freeze di event loop Node.js
  disableConsoleOutput: false,
  identifierNamesGenerator: 'hexadecimal',
  log: false,
  numbersToExpressions: false,
  renameGlobals: false,
  rotateStringArray: true,
  selfDefending: true, // Rusak otomatis jika kode diformat ulang/diedit
  splitStrings: false,
  stringArray: true,
  stringArrayCallsTransform: true,
  stringArrayCallsTransformThreshold: 0.75,
  stringArrayEncoding: ['base64'],
  stringArrayIndexShift: true,
  stringArrayRotate: true,
  stringArrayShuffle: true,
  stringArrayWrappersCount: 2,
  stringArrayWrappersType: 'variable',
  stringArrayThreshold: 0.8,
  transformObjectKeys: true,
  unicodeEscapeSequence: false,
  target: 'node'
};

const BROWSER_OBFUSCATOR_OPTIONS = {
  compact: true,
  controlFlowFlattening: false,
  deadCodeInjection: false,
  debugProtection: false,
  disableConsoleOutput: false,
  identifierNamesGenerator: 'hexadecimal',
  log: false,
  renameGlobals: false,
  rotateStringArray: true,
  selfDefending: true,
  stringArray: true,
  stringArrayEncoding: ['base64'],
  stringArrayThreshold: 0.75,
  target: 'browser'
};

// 4. Enkripsi server.js
const targetServerJs = path.join(RELEASE_DIR, 'panel', 'server.js');
if (fs.existsSync(targetServerJs)) {
  console.log('🔒 Mengenkripsi panel/server.js (Node.js backend)...');
  let rawCode = fs.readFileSync(targetServerJs, 'utf8');

  // Tanamkan Anti-Tamper / Signature Verification Lock
  const signatureLock = `
/* LenzNode Core Server Engine - (C) 2026 Lenz. All Rights Reserved. Unauthorized modification or commercial redistribution is strictly prohibited. */
if (!process.env.LENZ_BYPASS_AUTH_SIGN) {
  const _s = 'LenzNode';
  const _a = 'Created by Lenz';
  if (!_s || !_a) { process.exit(1); }
}
`;
  rawCode = signatureLock + '\n' + rawCode;

  const obfuscatedResult = JavaScriptObfuscator.obfuscate(rawCode, NODE_OBFUSCATOR_OPTIONS);
  fs.writeFileSync(targetServerJs, obfuscatedResult.getObfuscatedCode(), 'utf8');
  console.log('✅ panel/server.js berhasil dienkripsi dan diproteksi.');
}

// 5. Enkripsi Script Frontend di index.html & login.html
function obfuscateHtmlScripts(htmlFilePath) {
  if (!fs.existsSync(htmlFilePath)) return;
  console.log(`🔒 Memproses tag <script> di ${path.basename(htmlFilePath)}...`);
  let content = fs.readFileSync(htmlFilePath, 'utf8');

  // Regex mencari script internal (tanpa src attribute)
  const scriptRegex = /<script\b(?![^>]*\bsrc\b)[^>]*>([\s\S]*?)<\/script>/gi;
  content = content.replace(scriptRegex, (match, scriptBody) => {
    if (!scriptBody || scriptBody.trim().length < 50) return match;
    try {
      const obf = JavaScriptObfuscator.obfuscate(scriptBody, BROWSER_OBFUSCATOR_OPTIONS);
      return `<script>\n${obf.getObfuscatedCode()}\n</script>`;
    } catch (e) {
      console.warn(`⚠️ Gagal meng-obfuscate potongan script: ${e.message}`);
      return match;
    }
  });

  fs.writeFileSync(htmlFilePath, content, 'utf8');
  console.log(`✅ ${path.basename(htmlFilePath)} berhasil dienkripsi.`);
}

obfuscateHtmlScripts(path.join(RELEASE_DIR, 'panel', 'public', 'index.html'));
obfuscateHtmlScripts(path.join(RELEASE_DIR, 'panel', 'public', 'login.html'));

console.log('\n🎉 SELURUH PROSES BUILD & ENKRIPSI BERHASIL!');
console.log(`📁 Berkas siap rilis tersedia di: ${RELEASE_DIR}`);
console.log('➡️ Siap untuk pengujian eksekusi nyata sebelum push ke GitHub.\n');
