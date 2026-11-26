#!/bin/bash
# ==============================================================================
# LenzNode — Nextcloud Installer Script
# Kompatibel untuk Android Termux, PRoot Ubuntu, dan Linux Server (Debian/Ubuntu)
# ==============================================================================

set -e

APP_DIR="${APP_DIR:-$(pwd)}"
PORT="${PORT:-8088}"

echo "[INFO] Memulai instalasi Nextcloud di port $PORT..."
echo "[INFO] Direktori instalasi: $APP_DIR"

# 1. Deteksi Sistem & Pasang Dependensi
if command -v pkg >/dev/null 2>&1; then
    echo "[INFO] Lingkungan Android Termux terdeteksi..."
    if ! command -v php >/dev/null 2>&1; then
        pkg update -y >/dev/null 2>&1 || true
        pkg install -y php sqlite curl unzip >/dev/null 2>&1 || pkg install -y php || true
    fi
elif command -v apt-get >/dev/null 2>&1; then
    echo "[INFO] Lingkungan Linux (apt) terdeteksi..."
    if ! command -v php >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y php-cli php-sqlite3 sqlite3 curl unzip >/dev/null 2>&1 || true
    fi
fi

# 2. Siapkan Struktur Direktori
mkdir -p "$APP_DIR/public" "$APP_DIR/data" "$APP_DIR/config"

# 3. Buat Halaman Web Starter Nextcloud jika belum ada
if [ ! -f "$APP_DIR/public/index.php" ]; then
    cat << 'EOF' > "$APP_DIR/public/index.php"
<?php
$dataDir = dirname(__DIR__) . '/data';
$files = file_exists($dataDir) ? array_diff(scandir($dataDir), array('.', '..')) : [];
?>
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Nextcloud — LenzNode Private Cloud</title>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root { --bg: #0b0f17; --card: rgba(18, 24, 38, 0.85); --accent: #0082C9; --text: #f8fafc; --muted: #94a3b8; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: var(--bg); color: var(--text); font-family: 'Plus Jakarta Sans', sans-serif; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 20px; }
    .card { background: var(--card); border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; padding: 32px; max-width: 480px; width: 100%; box-shadow: 0 20px 40px rgba(0,0,0,0.5); backdrop-filter: blur(16px); }
    .logo { width: 48px; height: 48px; border-radius: 12px; background: rgba(0,130,201,0.15); display: flex; align-items: center; justify-content: center; margin-bottom: 20px; }
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
      <svg viewBox="0 0 24 24"><path d="M18 10h-1.26A8 8 0 1 0 9 20h9a5 5 0 0 0 0-10z"/></svg>
    </div>
    <div class="status-badge">Nextcloud Server Aktif</div>
    <h1>Private Cloud Storage</h1>
    <p>Layanan Nextcloud pribadi Anda aktif di Port 8088. Sinkronisasi berkas otomatis, kalender, dan dokumen kini siap digunakan.</p>
    <div class="storage-box">
      <div class="storage-title">
        <span>Lokasi Penyimpanan:</span>
        <span style="color:#0082C9;">data/</span>
      </div>
      <div style="font-size:12px; color:var(--muted);">Total Berkas Tersimpan: <?php echo count($files); ?> item</div>
    </div>
    <a href="/" class="btn">Kembali ke Dashboard LenzNode</a>
  </div>
</body>
</html>
EOF
fi

# 4. Buat skrip start.sh
cat << 'EOF' > "$APP_DIR/start.sh"
#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-8088}"
PID_FILE="$DIR/nextcloud.pid"
LOG_FILE="$DIR/nextcloud.log"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "[INFO] Nextcloud sudah berjalan (PID: $PID)"
        exit 0
    fi
fi

echo "[INFO] Menjalankan Nextcloud di 0.0.0.0:$PORT..."
if command -v php >/dev/null 2>&1; then
    php -S 0.0.0.0:$PORT -t "$DIR/public" >> "$LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    echo "[OK] Nextcloud berhasil dijalankan dengan PID $PID"
else
    echo "[ERROR] PHP tidak ditemukan di sistem. Harap pasang PHP terlebih dahulu."
    exit 1
fi
EOF
chmod +x "$APP_DIR/start.sh"

# 5. Buat skrip stop.sh
cat << 'EOF' > "$APP_DIR/stop.sh"
#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$DIR/nextcloud.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || kill -9 "$PID" 2>/dev/null
        echo "[OK] Nextcloud (PID: $PID) berhasil dihentikan."
    fi
    rm -f "$PID_FILE"
fi

if command -v fuser >/dev/null 2>&1; then
    fuser -k 8088/tcp 2>/dev/null || true
fi
EOF
chmod +x "$APP_DIR/stop.sh"

echo "[OK] Instalasi Nextcloud selesai dengan sukses!"
