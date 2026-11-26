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
export NODE_OPTIONS="--max-old-space-size=128 ${NODE_OPTIONS:-}"

clear
echo -e "${CYAN}=================================================================="
cat << 'EOF'
  _                    _   _           _      
 | |    ___ _ __  ____| \ | | ___   __| | ___ 
 | |   / _ \ '_ \|_  /|  \| |/ _ \ / _` |/ _ \
 | |__|  __/ | | |/ / | |\  | (_) | (_| |  __/
 |_____\___|_| |_/___||_| \_|\___/ \__,_|\___|
EOF
echo "=================================================================="
echo -e " 🚀 Master 1-Click Installer (LenzNode Mini Server & OpenSSH)     "
echo -e "==================================================================${NC}"
echo ""

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -d "$SRC_DIR" ] && BASE_DIR="$SRC_DIR" || BASE_DIR="$HOME/LenzNode"

# Otomatis tarik pembaruan Git jika folder sudah pernah di-clone sebelumnya
if [ -d "$BASE_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    echo -e "${YELLOW}>> Mengambil pembaruan berkas terbaru dari GitHub...${NC}"
    AUTH_BACKUP=""
    [ -f "$BASE_DIR/panel/auth-config.json" ] && AUTH_BACKUP=$(cat "$BASE_DIR/panel/auth-config.json" 2>/dev/null)
    git -C "$BASE_DIR" fetch origin main --depth=1 2>/dev/null || true
    git -C "$BASE_DIR" reset --hard origin/main 2>/dev/null || git -C "$BASE_DIR" pull origin main 2>/dev/null || true
    [ -n "$AUTH_BACKUP" ] && echo "$AUTH_BACKUP" > "$BASE_DIR/panel/auth-config.json" 2>/dev/null || true
fi

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

# 2.1 Periksa Mirror APT Termux jika belum dikonfigurasi
if [ -d "$PREFIX/etc/apt" ] && [ ! -s "$PREFIX/etc/apt/sources.list" ]; then
    echo "deb https://packages.termux.dev/apt/termux-main stable main" > "$PREFIX/etc/apt/sources.list" 2>/dev/null || true
fi

# 2.2 Sinkronisasi Paket & Perbaikan Dynamic Linker (Mencegah error symbol SSL_set_quic_tls di Android 16)
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a 2>/dev/null || true
apt-get update -y 2>/dev/null || pkg update -y 2>/dev/null || true
apt-get --fix-broken install -y -o Dpkg::Options::="--force-confnew" 2>/dev/null || true
apt-get full-upgrade -y -o Dpkg::Options::="--force-confnew" 2>/dev/null || pkg upgrade -y 2>/dev/null || true

# 2.3 Pasang Paket Utama
pkg install -y openssh psmisc procps curl wget zip unzip nano git tar xz-utils termux-api jq 2>/dev/null || apt-get install -y openssh psmisc procps curl wget zip unzip nano git tar xz-utils termux-api jq 2>/dev/null || true

# 2.4 Verifikasi Kesiapan curl & libcurl (Auto-Reinstall jika terjadi symbol mismatch)
if ! curl --version >/dev/null 2>&1; then
    echo -e ">> Menyesuaikan pustaka libcurl & openssl..."
    apt-get install --reinstall -y openssl libcurl curl 2>/dev/null || pkg install -y openssl libcurl curl 2>/dev/null || true
fi

# 2.5 Pastikan direktori, konfigurasi sshd_config, host key, dan password OpenSSH disetel
mkdir -p "$PREFIX/var/run" "$PREFIX/etc/ssh" 2>/dev/null || true
chmod 700 "$PREFIX/etc/ssh" 2>/dev/null || true
rm -f "$PREFIX/var/run/sshd.pid" 2>/dev/null || true

for key_type in rsa ed25519; do
    key_file="$PREFIX/etc/ssh/ssh_host_${key_type}_key"
    if [ ! -s "$key_file" ]; then
        rm -f "$key_file" "${key_file}.pub" 2>/dev/null || true
    fi
done
if [ ! -s "$PREFIX/etc/ssh/ssh_host_rsa_key" ] && [ ! -s "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]; then
    ssh-keygen -A >/dev/null 2>&1 || true
fi
chmod 600 "$PREFIX/etc/ssh/ssh_host_"*"_key" 2>/dev/null || true
chmod 644 "$PREFIX/etc/ssh/ssh_host_"*"_key.pub" 2>/dev/null || true

cat << 'EOF' > "$PREFIX/etc/ssh/sshd_config"
Port 2222
ListenAddress 0.0.0.0
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
PermitRootLogin yes
PrintMotd yes
Subsystem sftp /data/data/com.termux/files/usr/libexec/sftp-server
EOF
chmod 600 "$PREFIX/etc/ssh/sshd_config" 2>/dev/null || true

if command -v passwd >/dev/null 2>&1; then
    printf "admin123\nadmin123\n" | passwd >/dev/null 2>&1 || true
fi

# Injeksi INITIAL_PASSWORD default untuk 9Router di bashrc
if [ -f "$HOME/.bashrc" ]; then
    if ! grep -q "INITIAL_PASSWORD" "$HOME/.bashrc" 2>/dev/null; then
        echo 'export INITIAL_PASSWORD="123456"' >> "$HOME/.bashrc"
    fi
else
    echo 'export INITIAL_PASSWORD="123456"' > "$HOME/.bashrc"
fi

# 2.6 Pastikan termux-api terpasang (CLI)
if ! command -v termux-battery-status >/dev/null 2>&1; then
    pkg install -y termux-api 2>/dev/null || true
fi

# 2.7 Pastikan Node.js terpasang
if ! command -v node >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/node" ]; then
    echo ">> Memasang Node.js..."
    pkg install -y nodejs || pkg install -y nodejs-lts || apt-get install -y nodejs || apt-get install -y nodejs-lts || true
fi

# 2.8 PM2 untuk supervisi proses
if ! command -v pm2 >/dev/null 2>&1 || ! pm2 -v >/dev/null 2>&1; then
    echo ">> Memasang PM2..."
    npm install -g pm2 2>/dev/null || npm install -g pm2@5.1.2 --force 2>/dev/null || true
fi

# 2.9 Cloudflared Tunnel untuk Link Akses Publik Otomatis
if ! command -v cloudflared >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/cloudflared" ]; then
    echo ">> Menyiapkan Cloudflared Tunnel..."
    pkg install -y tur-repo 2>/dev/null || true
    pkg install -y cloudflared 2>/dev/null || apt-get install -y cloudflared 2>/dev/null || true
    if ! command -v cloudflared >/dev/null 2>&1 && [ ! -x "$PREFIX/bin/cloudflared" ]; then
        mkdir -p "$PREFIX/bin"
        CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
        if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1; then
            curl -sL -o "$PREFIX/bin/cloudflared" "$CF_URL" 2>/dev/null || true
        fi
        if [ ! -s "$PREFIX/bin/cloudflared" ] && command -v wget >/dev/null 2>&1; then
            rm -f "$PREFIX/bin/cloudflared" 2>/dev/null || true
            wget -q -O "$PREFIX/bin/cloudflared" "$CF_URL" 2>/dev/null || true
        fi
        [ -f "$PREFIX/bin/cloudflared" ] && chmod +x "$PREFIX/bin/cloudflared" 2>/dev/null || true
    fi
fi

NODE_VER="$(node -v 2>/dev/null || "$PREFIX/bin/node" -v 2>/dev/null || echo 'Belum terpasang')"
echo -e "${GREEN}✓ Termux siap (Node: $NODE_VER, OpenSSH: 2222)${NC}"

# -----------------------------------------------------------------------------
# 3. PENATAAN STRUKTUR FOLDER SERVER
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/5] Menyiapkan Struktur Folder Server di $BASE_DIR...${NC}"
mkdir -p "$BASE_DIR/logs" "$BASE_DIR/panel" "$BASE_DIR/apps" "$BASE_DIR/scripts"

if [ "$SRC_DIR" != "$BASE_DIR" ]; then
    [ -d "$SRC_DIR/panel" ] && cp -r "$SRC_DIR/panel/"* "$BASE_DIR/panel/" 2>/dev/null || true
    [ -d "$SRC_DIR/apps" ] && cp -r "$SRC_DIR/apps/"* "$BASE_DIR/apps/" 2>/dev/null || true
    [ -d "$SRC_DIR/scripts" ] && cp -r "$SRC_DIR/scripts/"* "$BASE_DIR/scripts/" 2>/dev/null || true
    [ -f "$SRC_DIR/start.sh" ] && cp -f "$SRC_DIR/start.sh" "$BASE_DIR/start.sh" && chmod +x "$BASE_DIR/start.sh"
    [ -f "$SRC_DIR/update.sh" ] && cp -f "$SRC_DIR/update.sh" "$BASE_DIR/update.sh" && chmod +x "$BASE_DIR/update.sh" 2>/dev/null || true
fi
[ -f "$BASE_DIR/start.sh" ] && cp -f "$BASE_DIR/start.sh" "$HOME/start.sh" 2>/dev/null && chmod +x "$HOME/start.sh" || true

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

    ln -sf "$BASE_DIR/start.sh" "$PREFIX_BIN/lenz" 2>/dev/null || true
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
echo -e "${CYAN}Perintah Cepat (dapat diketik dari mana saja):${NC}"
echo -e "  • Cek Status     : ${BOLD}lenz status${NC}"
echo -e "  • Update Sistem  : ${BOLD}lenz update${NC}"
echo -e "  • Restart Server : ${BOLD}lenz restart${NC}"
echo -e "  • Stop Server    : ${BOLD}lenz stop${NC}"
echo -e "  • Live Logs      : ${BOLD}lenz logs${NC}"
echo ""
