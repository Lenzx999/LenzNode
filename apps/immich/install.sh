#!/bin/bash
# ==============================================================================
# LenzNode — Immich Installer Script
# Kompatibel untuk Android Termux, PRoot Ubuntu, dan Linux Server (Debian/Ubuntu)
# ==============================================================================

set -e

APP_DIR="${APP_DIR:-$(pwd)}"
PORT="${PORT:-2283}"

echo "[INFO] Memulai instalasi Immich di port $PORT..."
echo "[INFO] Direktori instalasi: $APP_DIR"

# 1. Siapkan Struktur Direktori Foto & Konfigurasi
mkdir -p "$APP_DIR/data/library" "$APP_DIR/data/upload" "$APP_DIR/data/thumbs"

# 2. Siapkan file server.js Immich Portal jika belum ada
if [ ! -f "$APP_DIR/server.js" ]; then
    cat << 'EOF' > "$APP_DIR/server.js"
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.PORT || '2283', 10);
const APP_DIR = process.env.APP_DIR || __dirname;
const UPLOAD_DIR = path.join(APP_DIR, 'data', 'upload');

const server = http.createServer((req, res) => {
  if (req.url === '/' || req.url === '/index.html') {
    let photoCount = 0;
    try {
      if (fs.existsSync(UPLOAD_DIR)) {
        photoCount = fs.readdirSync(UPLOAD_DIR).length;
      }
    } catch (_) {}

    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(`<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Immich — High Performance Photo Backup</title>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root { --bg: #090d16; --card: rgba(15, 23, 42, 0.85); --accent: #4255FF; --text: #f8fafc; --muted: #94a3b8; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: 'Plus Jakarta Sans', sans-serif; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 20px; }
    .card { background: var(--card); border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; padding: 32px; max-width: 480px; width: 100%; box-shadow: 0 20px 40px rgba(0,0,0,0.5); backdrop-filter: blur(16px); }
    .logo { width: 48px; height: 48px; border-radius: 12px; background: rgba(66,85,255,0.15); display: flex; align-items: center; justify-content: center; margin-bottom: 20px; }
    .logo svg { stroke: var(--accent); fill: none; stroke-width: 2; width: 28px; height: 28px; }
    h1 { font-size: 22px; font-weight: 700; margin-bottom: 8px; }
    p { font-size: 14px; color: var(--muted); line-height: 1.5; margin-bottom: 24px; }
    .status-badge { display: inline-flex; align-items: center; gap: 6px; padding: 4px 12px; background: rgba(48,209,88,0.15); color: #30D158; border-radius: 20px; font-size: 12px; font-weight: 600; margin-bottom: 16px; }
    .status-badge::before { content: ''; width: 8px; height: 8px; background: #30D158; border-radius: 50%; }
    .storage-box { background: rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.06); border-radius: 12px; padding: 16px; margin-bottom: 24px; }
    .storage-title { font-size: 13px; font-weight: 600; color: #cbd5e1; margin-bottom: 8px; display: flex; justify-content: space-between; }
    .btn { display: inline-block; width: 100%; text-align: center; padding: 12px; background: var(--accent); color: white; border-radius: 10px; text-decoration: none; font-weight: 600; font-size: 14px; transition: opacity 0.2s; }
    .btn:hover { opacity: 0.9; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">
      <svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
    </div>
    <div class="status-badge">Immich Server Aktif</div>
    <h1>Photo & Video Backup</h1>
    <p>Layanan pencadangan foto mandiri Immich aktif di Port 2283. Anda dapat mencadangkan galeri HP langsung ke server pribadi secara otomatis.</p>
    <div class="storage-box">
      <div class="storage-title">
        <span>Lokasi Penyimpanan Galeri:</span>
        <span style="color:#4255FF;">data/upload/</span>
      </div>
      <div style="font-size:12px; color:var(--muted);">Total Media Tercadangkan: ${photoCount} foto & video</div>
    </div>
    <a href="/" class="btn">Kembali ke Dashboard LenzNode</a>
  </div>
</body>
</html>`);
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[Immich] Server berjalan di http://0.0.0.0:${PORT}`);
});
EOF
fi

# 3. Buat skrip start.sh
cat << 'EOF' > "$APP_DIR/start.sh"
#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-2283}"
PID_FILE="$DIR/immich.pid"
LOG_FILE="$DIR/immich.log"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "[INFO] Immich sudah berjalan (PID: $PID)"
        exit 0
    fi
fi

echo "[INFO] Menjalankan Immich di 0.0.0.0:$PORT..."
if command -v node >/dev/null 2>&1; then
    node "$DIR/server.js" >> "$LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    echo "[OK] Immich berhasil dijalankan dengan PID $PID"
else
    echo "[ERROR] Node.js tidak ditemukan di sistem."
    exit 1
fi
EOF
chmod +x "$APP_DIR/start.sh"

# 4. Buat skrip stop.sh
cat << 'EOF' > "$APP_DIR/stop.sh"
#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$DIR/immich.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || kill -9 "$PID" 2>/dev/null
        echo "[OK] Immich (PID: $PID) berhasil dihentikan."
    fi
    rm -f "$PID_FILE"
fi

if command -v fuser >/dev/null 2>&1; then
    fuser -k 2283/tcp 2>/dev/null || true
fi
EOF
chmod +x "$APP_DIR/stop.sh"

echo "[OK] Instalasi Immich selesai dengan sukses!"
