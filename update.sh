#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Lenz Mini Server — Universal Auto Update Script
# Author / Developer: Lenz
# Bekerja untuk instalasi Git Clone maupun download ZIP manual
# ==============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}       LENZ MINI SERVER — AUTO UPDATE SYSTEM          ${NC}"
echo -e "${CYAN}======================================================${NC}"

REPO_URL="https://github.com/Lenzx999/LenzNode.git"
ZIP_URL="https://github.com/Lenzx999/LenzNode/archive/refs/heads/main.zip"

export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
[ -z "$HOME" ] || [ "$HOME" = "/" ] || [ "$HOME" = "/root" ] && [ -d "/data/data/com.termux/files/home" ] && export HOME="/data/data/com.termux/files/home"
export PATH="/data/data/com.termux/files/usr/bin:$PREFIX/bin:$PATH"

if [ -f "./panel/server.js" ]; then
    SERVER_DIR="$(pwd)"
elif [ -d "$HOME/panel" ]; then
    SERVER_DIR="$HOME/panel"
elif [ -d "$HOME/LenzNode" ]; then
    SERVER_DIR="$HOME/LenzNode"
else
    SERVER_DIR="$HOME/panel"
    mkdir -p "$SERVER_DIR"
fi

cd "$SERVER_DIR" || exit 1

# Simpan backup password / kredensial jika ada
BACKUP_AUTH=""
if [ -f "$SERVER_DIR/panel/auth-config.json" ]; then
    BACKUP_AUTH=$(cat "$SERVER_DIR/panel/auth-config.json" 2>/dev/null)
fi

echo -e "\n${BLUE}[1/3] Memeriksa status repositori & mengambil pembaruan...${NC}"

UPDATED=false

# Metode 1: Jika sudah ada folder .git
if [ -d "$SERVER_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    echo -e "${CYAN}>> Mengupdate melalui Git repository...${NC}"
    git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL" 2>/dev/null || true
    git fetch --all --prune 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || git pull origin main 2>/dev/null || git pull 2>/dev/null || true
    UPDATED=true
fi

# Metode 2: Jika belum ada .git tapi paket git terpasang (ubah instalasi ZIP ke Git otomatis)
if [ "$UPDATED" = false ] && command -v git >/dev/null 2>&1; then
    echo -e "${CYAN}>> Menginisialisasi koneksi Git repository...${NC}"
    git init -q 2>/dev/null || true
    git remote add origin "$REPO_URL" 2>/dev/null || git remote set-url origin "$REPO_URL" 2>/dev/null || true
    git fetch --depth=1 origin main 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || true
    UPDATED=true
fi

# Metode 3: Jika tidak ada Git (Download ZIP langsung dari GitHub via curl/wget)
if [ "$UPDATED" = false ]; then
    echo -e "${YELLOW}>> Git tidak ditemukan. Mengunduh paket update langsung via ZIP...${NC}"
    TEMP_ZIP="$HOME/lenz_update_temp.zip"
    rm -f "$TEMP_ZIP" 2>/dev/null || true

    if command -v curl >/dev/null 2>&1; then
        curl -sL "$ZIP_URL" -o "$TEMP_ZIP"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$ZIP_URL" -O "$TEMP_ZIP"
    fi

    if [ -f "$TEMP_ZIP" ] && [ -s "$TEMP_ZIP" ]; then
        if command -v unzip >/dev/null 2>&1; then
            unzip -q -o "$TEMP_ZIP" -d "$HOME" 2>/dev/null || true
            if [ -d "$HOME/LenzNode-main" ]; then
                cp -rf "$HOME/LenzNode-main/"* "$SERVER_DIR/" 2>/dev/null || true
                cp -rf "$HOME/LenzNode-main/."* "$SERVER_DIR/" 2>/dev/null || true
                rm -rf "$HOME/LenzNode-main" "$TEMP_ZIP" 2>/dev/null || true
                UPDATED=true
            fi
        else
            pkg install unzip -y 2>/dev/null || true
            unzip -q -o "$TEMP_ZIP" -d "$HOME" 2>/dev/null || true
            if [ -d "$HOME/LenzNode-main" ]; then
                cp -rf "$HOME/LenzNode-main/"* "$SERVER_DIR/" 2>/dev/null || true
                cp -rf "$HOME/LenzNode-main/."* "$SERVER_DIR/" 2>/dev/null || true
                rm -rf "$HOME/LenzNode-main" "$TEMP_ZIP" 2>/dev/null || true
                UPDATED=true
            fi
        fi
    fi
fi

# Kembalikan file kredensial auth jika tadi ada
if [ -n "$BACKUP_AUTH" ]; then
    mkdir -p "$SERVER_DIR/panel"
    echo "$BACKUP_AUTH" > "$SERVER_DIR/panel/auth-config.json"
fi

if [ "$UPDATED" = true ]; then
    echo -e "${GREEN}✓ Berkas panel berhasil diperbarui ke versi terbaru!${NC}"
else
    echo -e "${RED}✗ Gagal memperbarui berkas. Pastikan perangkat terhubung ke internet.${NC}"
fi

echo -e "\n${BLUE}[2/3] Memperbarui hak akses file skrip...${NC}"
chmod +x "$SERVER_DIR/"*.sh "$SERVER_DIR/scripts/"*.sh 2>/dev/null || true
echo -e "${GREEN}✓ Hak akses skrip diperbarui.${NC}"

echo -e "\n${BLUE}[3/3] Memulai ulang panel server...${NC}"
if command -v pm2 >/dev/null 2>&1 && pm2 describe lenz-panel >/dev/null 2>&1; then
    pm2 restart lenz-panel
    echo -e "${GREEN}✓ Layanan PM2 lenz-panel berhasil dimuat ulang!${NC}"
else
    pkill -f "node.*panel/server.js" 2>/dev/null || true
    sleep 1
    if [ -f "$SERVER_DIR/start.sh" ]; then
        bash "$SERVER_DIR/start.sh" --bg
    else
        nohup node "$SERVER_DIR/panel/server.js" > "$SERVER_DIR/logs/panel.log" 2>&1 &
    fi
    echo -e "${GREEN}✓ Server panel berhasil dimulai ulang!${NC}"
fi

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}  ✓ UPDATE SELESAI! Lenz Mini Server siap digunakan.  ${NC}"
echo -e "${GREEN}======================================================${NC}\n"
