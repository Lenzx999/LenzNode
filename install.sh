#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# LenzNode — Master 1-Click Installer (Native Termux Edition)
# 100% Native Termux — Ringan, Cepat, Tanpa PRootDistro (Zero Overhead)
# Mendukung Universal Device (Android 5 s/d 16+, ARM32/ARM64/x86_64)
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Inisialisasi Environment Termux
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
[ -z "$HOME" ] || [ "$HOME" = "/" ] || [ "$HOME" = "/root" ] && [ -d "/data/data/com.termux/files/home" ] && export HOME="/data/data/com.termux/files/home"
export PATH="/data/data/com.termux/files/usr/bin:$PREFIX/bin:$PREFIX/bin/applets:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
[ -d "$PREFIX/lib" ] && export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Optimasi Memori Ekstrem untuk Semua Perangkat (RAM Minimal & Hemat Baterai)
export NODE_OPTIONS="--max-old-space-size=64 --optimize-for-size --expose-gc ${NODE_OPTIONS:-}"

clear
echo -e "${CYAN}=================================================================="
echo "    __     ___            __   __   __      ____                         "
echo "    \ \   / (_)   _____   \ \ / /  / /_    / ___|  ___ _ ____   _____ _ __ "
echo "     \ \ / /| \ \ / / _ \  \ V /  | '_ \   \___ \ / _ \ '__\ \ / / _ \ '__|"
echo "      \ V / | |\ V / (_) |  | |   | (_) |   ___) |  __/ |   \ V /  __/ |   "
echo "       \_/  |_| \_/ \___/   |_|    \___/   |____/ \___|_|    \_/ \___|_|   "
echo "=================================================================="
echo -e " 🚀 Master 1-Click Installer (LenzNode Mini Server & OpenSSH)     "
echo -e "==================================================================${NC}"
echo ""

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -d "$SRC_DIR" ] && BASE_DIR="$SRC_DIR" || BASE_DIR="$HOME/LenzNode"

# -----------------------------------------------------------------------------
# 0. DETEKSI SISTEM & PERANGKAT
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[0/5] Mendeteksi Sistem & Lingkungan Android...${NC}"

ANDROID_VER=$(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
ANDROID_SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo "0")
RAW_ARCH=$(uname -m 2>/dev/null || dpkg --print-architecture 2>/dev/null || echo "arm")

case "$RAW_ARCH" in
    aarch64|arm64*|armv8*)
        SYS_ARCH="arm64"
        CF_ARCH="arm64"
        ;;
    armv7*|armv8l|armeabi*|armhf|arm)
        SYS_ARCH="armhf"
        CF_ARCH="arm"
        ;;
    x86_64|amd64)
        SYS_ARCH="amd64"
        CF_ARCH="amd64"
        ;;
    i*86|x86)
        SYS_ARCH="i386"
        CF_ARCH="386"
        ;;
    *)
        SYS_ARCH="armhf"
        CF_ARCH="arm"
        ;;
esac

echo -e "  • Android Version : ${CYAN}$ANDROID_VER (SDK $ANDROID_SDK)${NC}"
echo -e "  • Arsitektur CPU  : ${CYAN}$RAW_ARCH -> $SYS_ARCH${NC}"
echo -e "  • Mode Server     : ${GREEN}Native Termux (Optimasi Maksimal, Tanpa PRoot)${NC}"

# -----------------------------------------------------------------------------
# 1. SETUP PENYIMPANAN & WAKE LOCK
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/5] Menyiapkan Izin Penyimpanan & Wake-Lock...${NC}"
if [ ! -d "$HOME/storage" ]; then
    termux-setup-storage 2>/dev/null || true
    sleep 2
fi
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null || true
echo -e "${GREEN}✓ Izin penyimpanan & Wake-Lock aktif.${NC}"

# -----------------------------------------------------------------------------
# 2. INSTALASI DEPENDENSI TERMUX HOST
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/5] Memperbarui Paket Termux & Memasang Dependensi Ringan...${NC}"
pkg update -y 2>/dev/null || true
pkg install -y openssh curl wget zip unzip nano git tar xz-utils termux-api jq 2>/dev/null || true

# Pastikan host key OpenSSH telah digenerate
[ ! -f "$PREFIX/etc/ssh/ssh_host_rsa_key" ] && [ ! -f "$PREFIX/etc/ssh/ssh_host_ed25519_key" ] && ssh-keygen -A >/dev/null 2>&1 || true

# Pastikan termux-api terpasang
if ! command -v termux-battery-status >/dev/null 2>&1; then
    pkg install -y termux-api 2>/dev/null || true
fi

# Pastikan Node.js terpasang
if ! command -v node >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/node" ]; then
    echo ">> Memasang Node.js..."
    pkg install -y nodejs || pkg install -y nodejs-lts || true
fi

# PM2 untuk supervisi proses
if ! command -v pm2 >/dev/null 2>&1 || ! pm2 -v >/dev/null 2>&1; then
    echo ">> Memasang PM2..."
    npm install -g pm2 2>/dev/null || npm install -g pm2@5.1.2 --force 2>/dev/null || true
fi

# Cloudflared Tunnel untuk Link Akses Publik Otomatis
if ! command -v cloudflared >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/cloudflared" ]; then
    echo ">> Menyiapkan Cloudflared Tunnel..."
    pkg install -y cloudflared 2>/dev/null || true
    if ! command -v cloudflared >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/cloudflared" ]; then
        mkdir -p "$PREFIX/bin"
        curl -L -o "$PREFIX/bin/cloudflared" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" 2>/dev/null || wget -O "$PREFIX/bin/cloudflared" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" 2>/dev/null || true
        chmod +x "$PREFIX/bin/cloudflared" 2>/dev/null || true
    fi
fi

# Auto-Setup Termux:API Companion APK (Untuk Telemetri Baterai & Daya Android 10-16)
if ! pm list packages 2>/dev/null | grep -q "com.termux.api"; then
    echo -e ">> Menyiapkan Termux:API Companion APK (Baterai Android 10-16)..."
    API_APK="$HOME/termux-api.apk"
    curl -sL "https://github.com/termux/termux-api/releases/download/v0.51.0/termux-api_v0.51.0+github-debug.apk" -o "$API_APK" 2>/dev/null || wget -q "https://github.com/termux/termux-api/releases/download/v0.51.0/termux-api_v0.51.0+github-debug.apk" -O "$API_APK" 2>/dev/null || true
    if [ -f "$API_APK" ]; then
        command -v termux-open >/dev/null 2>&1 && termux-open "$API_APK" 2>/dev/null || true
        echo -e "${GREEN}✓ Installer Termux:API dibuka (silakan klik Pasang/Install di layar HP jika muncul)${NC}"
    fi
fi

NODE_VER="$(node -v 2>/dev/null || "$PREFIX/bin/node" -v 2>/dev/null || echo 'OK')"
echo -e "${GREEN}✓ Termux siap (Node: $NODE_VER, OpenSSH: 2222)${NC}"

# -----------------------------------------------------------------------------
# 3. PENATAAN STRUKTUR FOLDER SERVER
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/5] Menyiapkan Struktur Folder Server di $BASE_DIR...${NC}"
mkdir -p "$BASE_DIR/logs" "$BASE_DIR/panel" "$BASE_DIR/apps" "$BASE_DIR/scripts"

[ -d "$SRC_DIR/panel" ] && cp -r "$SRC_DIR/panel/"* "$BASE_DIR/panel/" 2>/dev/null || true
[ -d "$SRC_DIR/apps" ] && cp -r "$SRC_DIR/apps/"* "$BASE_DIR/apps/" 2>/dev/null || true
[ -d "$SRC_DIR/scripts" ] && cp -r "$SRC_DIR/scripts/"* "$BASE_DIR/scripts/" 2>/dev/null || true
[ -f "$SRC_DIR/start.sh" ] && cp "$SRC_DIR/start.sh" "$HOME/start.sh" && cp "$SRC_DIR/start.sh" "$BASE_DIR/start.sh" && chmod +x "$HOME/start.sh" "$BASE_DIR/start.sh"
[ -f "$SRC_DIR/update.sh" ] && cp "$SRC_DIR/update.sh" "$BASE_DIR/update.sh" && chmod +x "$BASE_DIR/update.sh" 2>/dev/null || true

# -----------------------------------------------------------------------------
# 4. PASANG CLI TOOLS & AUTOSTART BOOT
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/5] Menyiapkan CLI Helpers & Autostart Boot...${NC}"

PREFIX_BIN="/data/data/com.termux/files/usr/bin"
if [ -d "$PREFIX_BIN" ]; then
    cat << 'EOF' > "$PREFIX_BIN/termux-fix"
#!/data/data/com.termux/files/usr/bin/bash
rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock* /data/data/com.termux/files/usr/var/lib/apt/lists/lock 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true
pkg update -y 2>/dev/null || true
EOF
    chmod +x "$PREFIX_BIN/termux-fix"

    cat << 'EOF' > "$PREFIX_BIN/termux-install"
#!/data/data/com.termux/files/usr/bin/bash
rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock* 2>/dev/null || true
pkg install -y "$@"
EOF
    chmod +x "$PREFIX_BIN/termux-install"

    ln -sf "$BASE_DIR/start.sh" "$PREFIX_BIN/lenznode" 2>/dev/null || true
fi

# Konfigurasi Autostart saat HP reboot (Termux:Boot)
BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
cat << 'EOF' > "$BOOT_DIR/start-server.sh"
#!/data/data/com.termux/files/usr/bin/bash
# LenzNode Auto-Boot Guardian
sleep 15
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null || true
if [ -f "$HOME/LenzNode/start.sh" ]; then
    bash "$HOME/LenzNode/start.sh" bg >/dev/null 2>&1 &
elif [ -f "$HOME/start.sh" ]; then
    bash "$HOME/start.sh" bg >/dev/null 2>&1 &
fi
EOF
chmod +x "$BOOT_DIR/start-server.sh" 2>/dev/null || true

echo -e "${GREEN}✓ CLI Tools & Auto-Boot aktif.${NC}"

# -----------------------------------------------------------------------------
# 5. MENJALANKAN SERVER
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[5/5] Mengaktifkan Layanan Server...${NC}"
chmod +x "$BASE_DIR/start.sh"
bash "$BASE_DIR/start.sh"

echo -e "${GREEN}🎉 Instalasi LenzNode Berhasil Selesai!${NC}"
echo -e "${CYAN}Perintah Cepat:${NC}"
echo -e "  • Status Server  : ${BOLD}./start.sh status${NC}"
echo -e "  • Restart Server : ${BOLD}./start.sh restart${NC}"
echo -e "  • Stop Server    : ${BOLD}./start.sh stop${NC}"
echo -e "  • Live Logs      : ${BOLD}./start.sh logs${NC}"
echo ""
