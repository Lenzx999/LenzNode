#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Lenz Mini Server & VPS — Universal 1-Click Installer
# Author / Developer: Lenz
# Mendukung Universal Device (Android 5 s/d 14+, ARM32/ARM64/x86_64) di Termux
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${CYAN}=================================================================="
echo "    __     ___            __   __   __      ____                         "
echo "    \ \   / (_)   _____   \ \ / /  / /_    / ___|  ___ _ ____   _____ _ __ "
echo "     \ \ / /| \ \ / / _ \  \ V /  | '_ \   \___ \ / _ \ '__\ \ / / _ \ '__|"
echo "      \ V / | |\ V / (_) |  | |   | (_) |   ___) |  __/ |   \ V /  __/ |   "
echo "       \_/  |_| \_/ \___/   |_|    \___/   |____/ \___|_|    \_/ \___|_|   "
echo "=================================================================="
echo -e " 🚀 Master 1-Click Installer (Lenz Mini Server & VPS Ubuntu)      "
echo -e "==================================================================${NC}"
echo ""

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$HOME/panel"
UBUNTU_DIR="$HOME/ubuntu-fs"

# -----------------------------------------------------------------------------
# 0. DETEKSI PERANGKAT & REKOMENDASI VERSI TERMUX (UNIVERSAL)
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[0/5] Mendeteksi Perangkat & Lingkungan Sistem...${NC}"

ANDROID_VER=$(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
ANDROID_SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo "0")
RAW_ARCH=$(uname -m 2>/dev/null || dpkg --print-architecture 2>/dev/null || echo "arm")

case "$RAW_ARCH" in
    aarch64|arm64*|armv8*)
        SYS_ARCH="arm64"
        ROOTFS_ARCH="arm64"
        ;;
    armv7*|armv8l|armeabi*|armhf|arm)
        SYS_ARCH="armhf"
        ROOTFS_ARCH="armhf"
        ;;
    x86_64|amd64)
        SYS_ARCH="amd64"
        ROOTFS_ARCH="amd64"
        ;;
    i*86|x86)
        SYS_ARCH="i386"
        ROOTFS_ARCH="i386"
        ;;
    *)
        SYS_ARCH="armhf"
        ROOTFS_ARCH="armhf"
        ;;
esac

echo -e "  • Android Version : ${CYAN}$ANDROID_VER (SDK $ANDROID_SDK)${NC}"
echo -e "  • Arsitektur CPU  : ${CYAN}$RAW_ARCH -> $SYS_ARCH${NC}"

if [ "$ANDROID_SDK" -ne 0 ] && [ "$ANDROID_SDK" -le 23 ]; then
    echo -e "${BLUE}ℹ️ Info: Perangkat terdeteksi Android 5/6 (Legacy). Pastikan menggunakan Termux v0.119.0-beta.3 varian apt-android-5.${NC}"
else
    echo -e "${GREEN}✓ Perangkat mendukung Termux modern.${NC}"
fi

# -----------------------------------------------------------------------------
# 1. SETUP PENYIMPANAN & WAKE LOCK
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/5] Menyiapkan izin penyimpanan & Wake-Lock...${NC}"
if [ ! -d "$HOME/storage" ]; then
    termux-setup-storage 2>/dev/null || true
    sleep 2
fi
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null || true
echo -e "${GREEN}✓ Izin penyimpanan & Wake-Lock aktif.${NC}"

# -----------------------------------------------------------------------------
# 2. INSTALASI DEPENDENSI TERMUX HOST
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/5] Memperbarui paket Termux & Memasang dependensi...${NC}"
pkg update -y 2>/dev/null || true
pkg install -y openssh curl wget zip unzip nano git python ffmpeg libwebp imagemagick proot tar xz-utils 2>/dev/null || true

if ! command -v node >/dev/null 2>&1; then
    pkg install -y nodejs || pkg install -y nodejs-lts || true
fi

# PM2 untuk manajemen proses
if ! command -v pm2 >/dev/null 2>&1 || ! pm2 -v >/dev/null 2>&1; then
    echo ">> Memasang PM2 di Termux..."
    npm install -g pm2 2>/dev/null || npm install -g pm2@5.1.2 --force 2>/dev/null || true
fi

echo -e "${GREEN}✓ Termux siap (Node $(node -v 2>/dev/null || echo '-'), PM2 $(pm2 -v 2>/dev/null || echo '-'))${NC}"

# -----------------------------------------------------------------------------
# 3. PENATAAN STRUKTUR FOLDER SERVER
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/5] Menyiapkan struktur folder server di $BASE_DIR...${NC}"
mkdir -p "$BASE_DIR/logs" "$BASE_DIR/panel" "$BASE_DIR/apps" "$BASE_DIR/scripts"

[ -d "$SRC_DIR/panel" ] && cp -r "$SRC_DIR/panel/"* "$BASE_DIR/panel/" 2>/dev/null || true
[ -d "$SRC_DIR/apps" ] && cp -r "$SRC_DIR/apps/"* "$BASE_DIR/apps/" 2>/dev/null || true
[ -d "$SRC_DIR/scripts" ] && cp -r "$SRC_DIR/scripts/"* "$BASE_DIR/scripts/" 2>/dev/null || true
[ -f "$SRC_DIR/start.sh" ] && cp "$SRC_DIR/start.sh" "$HOME/start.sh" && cp "$SRC_DIR/start.sh" "$BASE_DIR/start.sh" && chmod +x "$HOME/start.sh" "$BASE_DIR/start.sh"

# -----------------------------------------------------------------------------
# 4. INSTALASI DISTRO UBUNTU VPS (PRoot)
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/5] Menyiapkan Distro Ubuntu VPS ($ROOTFS_ARCH Rootfs)...${NC}"

cat << 'EOF' > "$BASE_DIR/scripts/start-ubuntu.sh"
#!/data/data/com.termux/files/usr/bin/bash
UBUNTU_DIR="$HOME/ubuntu-fs"
unset LD_PRELOAD
export PROOT_NO_SECCOMP=1

PROOT_CMD=(
    proot
    --link2symlink
    -0
    -r "$UBUNTU_DIR"
    -b /dev
    -b /dev/pts
    -b /proc
    -b /sys
    -b /sdcard
    -b /data/data/com.termux/files:/data/data/com.termux/files
    -b "$HOME":/root/termux-home
    -w /root
)

ENV_VARS=(
    HOME=/root
    USER=root
    LANG=C.UTF-8
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    TERM="$TERM"
)

if [ $# -eq 0 ]; then
    exec "${PROOT_CMD[@]}" /usr/bin/env -i "${ENV_VARS[@]}" /bin/bash --login
else
    exec "${PROOT_CMD[@]}" /usr/bin/env -i "${ENV_VARS[@]}" "$@"
fi
EOF
chmod +x "$BASE_DIR/scripts/start-ubuntu.sh"
cp "$BASE_DIR/scripts/start-ubuntu.sh" "$HOME/start-ubuntu.sh" 2>/dev/null || true

PREFIX_BIN="/data/data/com.termux/files/usr/bin"
[ -d "$PREFIX_BIN" ] && ln -sf "$BASE_DIR/scripts/start-ubuntu.sh" "$PREFIX_BIN/ubuntu" 2>/dev/null || true

if [ ! -d "$UBUNTU_DIR" ] || [ ! -f "$UBUNTU_DIR/bin/bash" ]; then
    echo ">> Mengunduh Rootfs Ubuntu $ROOTFS_ARCH..."
    mkdir -p "$UBUNTU_DIR" "$HOME/.cache"
    TAR_FILE="$HOME/.cache/ubuntu-rootfs.tar.xz"
    ROOTFS_URL="https://raw.githubusercontent.com/EXALAB/AnLinux-Resources/master/Rootfs/Ubuntu/${ROOTFS_ARCH}/ubuntu-rootfs-${ROOTFS_ARCH}.tar.xz"
    curl -L -o "$TAR_FILE" "$ROOTFS_URL" 2>/dev/null || wget -O "$TAR_FILE" "$ROOTFS_URL"
    cd "$UBUNTU_DIR"
    tar -xJf "$TAR_FILE" 2>/dev/null || tar -xzf "$TAR_FILE" 2>/dev/null || true
    rm -f "$TAR_FILE"
fi

# Konfigurasi OpenSSH & Policy di Ubuntu
mkdir -p "$UBUNTU_DIR/usr/sbin" "$UBUNTU_DIR/etc" "$UBUNTU_DIR/usr/local/bin"
echo -e '#!/bin/sh\nexit 101' > "$UBUNTU_DIR/usr/sbin/policy-rc.d"
chmod +x "$UBUNTU_DIR/usr/sbin/policy-rc.d"
echo -e 'nameserver 8.8.8.8\nnameserver 1.1.1.1' > "$UBUNTU_DIR/etc/resolv.conf"

mkdir -p "$UBUNTU_DIR/etc/ssh"
cat << 'EOF' > "$UBUNTU_DIR/etc/ssh/sshd_config"
Port 2222
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
UsePAM no
StrictModes no
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# Setup paket dasar di dalam Ubuntu VPS
bash "$BASE_DIR/scripts/start-ubuntu.sh" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    dpkg --configure -a 2>/dev/null || true
    apt-get install -f -y 2>/dev/null || true
    apt-get update -y 2>/dev/null || true
    apt-get install -y openssh-server sudo curl wget git nano xz-utils python3 python3-pip ffmpeg webp imagemagick build-essential 2>/dev/null || true

    # Siapkan bridge shell untuk user Lenz
    cat << 'SHELL_EOF' > /usr/local/bin/termux-shell
#!/bin/bash
export HOME=\"/data/data/com.termux/files/home\"
export PREFIX=\"/data/data/com.termux/files/usr\"
export PATH=\"/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:\$PATH\"
export LD_LIBRARY_PATH=\"/data/data/com.termux/files/usr/lib\"
export TERM=\"\${TERM:-xterm-256color}\"
cd \"\$HOME\" 2>/dev/null || cd /
if [ -x \"/data/data/com.termux/files/usr/bin/bash\" ]; then
    exec /data/data/com.termux/files/usr/bin/bash --login \"\$@\"
else
    exec /bin/bash \"\$@\"
fi
SHELL_EOF
    chmod +x /usr/local/bin/termux-shell

    echo 'root:ubuntu123' | chpasswd 2>/dev/null || true
    id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash -d /root/termux-home ubuntu 2>/dev/null || true
    echo 'ubuntu:ubuntu123' | chpasswd 2>/dev/null || true
    usermod -aG sudo ubuntu 2>/dev/null || true

    id -u Lenz >/dev/null 2>&1 || useradd -m -s /usr/local/bin/termux-shell -d /data/data/com.termux/files/home Lenz 2>/dev/null || true
    usermod -s /usr/local/bin/termux-shell -d /data/data/com.termux/files/home Lenz 2>/dev/null || true
    echo 'Lenz:ubuntu123' | chpasswd 2>/dev/null || true
    usermod -aG sudo Lenz 2>/dev/null || true

    mkdir -p /run/sshd /var/run/sshd
    chmod 0755 /run/sshd /var/run/sshd 2>/dev/null || true
    ssh-keygen -A 2>/dev/null || true
" 2>/dev/null || true

# Helper tools & CLI shortcuts di Termux & Ubuntu
if [ -d "$PREFIX_BIN" ]; then
    # Lenz Mini Server Global Commands
    cat << 'EOF' > "$PREFIX_BIN/lenz-server"
#!/data/data/com.termux/files/usr/bin/bash
# Lenz Mini Server — Author: Lenz
bash "$HOME/start.sh"
EOF
    chmod +x "$PREFIX_BIN/lenz-server"

    cat << 'EOF' > "$PREFIX_BIN/lenz-vps"
#!/data/data/com.termux/files/usr/bin/bash
# Lenz Mini Server — Author: Lenz
bash "$HOME/start-ubuntu.sh"
EOF
    chmod +x "$PREFIX_BIN/lenz-vps"

    cat << 'EOF' > "$PREFIX_BIN/lenz-stop"
#!/data/data/com.termux/files/usr/bin/bash
# Lenz Mini Server — Author: Lenz
bash "$HOME/start.sh" --stop
EOF
    chmod +x "$PREFIX_BIN/lenz-stop"

    cat << 'EOF' > "$PREFIX_BIN/lenz-status"
#!/data/data/com.termux/files/usr/bin/bash
# Lenz Mini Server — Author: Lenz
bash "$HOME/start.sh" --status
EOF
    chmod +x "$PREFIX_BIN/lenz-status"

    cat << 'EOF' > "$PREFIX_BIN/termux-fix"
#!/data/data/com.termux/files/usr/bin/bash
# Lenz Mini Server — Author: Lenz
rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock* /data/data/com.termux/files/usr/var/lib/apt/lists/lock 2>/dev/null || true
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true
pkg update -y 2>/dev/null || true
echo "✓ Paket Termux siap!"
EOF
    chmod +x "$PREFIX_BIN/termux-fix"

    cat << 'EOF' > "$PREFIX_BIN/termux-install"
#!/data/data/com.termux/files/usr/bin/bash
# Lenz Mini Server — Author: Lenz
rm -f /data/data/com.termux/files/usr/var/lib/dpkg/lock* 2>/dev/null || true
pkg install -y "$@"
EOF
    chmod +x "$PREFIX_BIN/termux-install"
fi

cat << 'EOF' > "$UBUNTU_DIR/usr/local/bin/vps-fix"
#!/bin/bash
# Lenz Mini Server — Author: Lenz
rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
if [ -d /var/lib/dpkg/info ]; then
    for f in /var/lib/dpkg/info/*.postinst; do
        [ -f "$f" ] && sed -i '1s|^|exit 0\n|' "$f" 2>/dev/null || true
    done
fi
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true
apt-get update -y 2>/dev/null || true
echo "✓ Sistem paket Ubuntu VPS siap!"
EOF
chmod +x "$UBUNTU_DIR/usr/local/bin/vps-fix"

cat << 'EOF' > "$UBUNTU_DIR/usr/local/bin/vps-install"
#!/bin/bash
# Lenz Mini Server — Author: Lenz
if [ $# -eq 0 ]; then
    echo "Penggunaan: vps-install <nama-paket>"
    exit 1
fi
rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends "$@" || true
echo "✓ Instalasi selesai!"
EOF
chmod +x "$UBUNTU_DIR/usr/local/bin/vps-install"

# -----------------------------------------------------------------------------
# 5. AUTOSTART BOOT & JALANKAN SERVER
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[5/5] Menyiapkan autostart Termux:Boot & Menjalankan Server...${NC}"

BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
cat << 'EOF' > "$BOOT_DIR/start-server.sh"
#!/data/data/com.termux/files/usr/bin/bash
sleep 15
termux-wake-lock 2>/dev/null || true
bash "$HOME/start.sh" >/dev/null 2>&1 &
EOF
chmod +x "$BOOT_DIR/start-server.sh"

echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN} ✅ INSTALASI BERHASIL SELESAI!                                   ${NC}"
echo -e "${GREEN}==================================================================${NC}"
echo ""

# Jalankan server
exec bash "$HOME/start.sh"
