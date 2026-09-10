#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Lenz Mini Server — Auto Update Script
# Author / Developer: Lenz
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

DIR="$(cd "$(dirname "$0")" && pwd)"
[ -d "$HOME/panel" ] && SERVER_DIR="$HOME/panel" || SERVER_DIR="$DIR"

cd "$SERVER_DIR" || exit 1

echo -e "\n${BLUE}[1/3] Mengambil pembaruan terbaru dari GitHub...${NC}"
if command -v git >/dev/null 2>&1; then
    git fetch --all --prune
    git reset --hard origin/main 2>/dev/null || git pull origin main || git pull
    echo -e "${GREEN}✓ Source code berhasil diperbarui ke versi terbaru!${NC}"
else
    echo -e "${RED}✗ Git tidak ditemukan di Termux. Silakan jalankan: pkg install git -y${NC}"
    exit 1
fi

echo -e "\n${BLUE}[2/3] Memperbarui hak akses file skrip...${NC}"
chmod +x *.sh scripts/*.sh 2>/dev/null || true
echo -e "${GREEN}✓ Hak akses skrip diperbarui.${NC}"

echo -e "\n${BLUE}[3/3] Memulai ulang panel server...${NC}"
if command -v pm2 >/dev/null 2>&1 && pm2 describe lenz-panel >/dev/null 2>&1; then
    pm2 restart lenz-panel
    echo -e "${GREEN}✓ Layanan PM2 lenz-panel berhasil dimuat ulang!${NC}"
else
    pkill -f "node.*panel/server.js" 2>/dev/null || true
    sleep 1
    nohup node "$SERVER_DIR/panel/server.js" > "$SERVER_DIR/logs/panel.log" 2>&1 &
    echo -e "${GREEN}✓ Server panel berhasil dimulai ulang di background!${NC}"
fi

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}  ✓ UPDATE SELESAI! Lenz Mini Server siap digunakan.  ${NC}"
echo -e "${GREEN}======================================================${NC}\n"
