#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# LenzNode — Unified Launcher & Manager (Native Termux Edition)
# Mengelola: Web Dashboard Panel (Port 8080), SSH Server (Port 2222), & Cloudflare Tunnel
# 100% Native Termux — Ringan, Cepat, Tanpa PRootDistro (Zero Overhead)
# ==============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
GRAY='\033[0;90m'
NC='\033[0m'

# Anti-recursion guard: Mencegah eksekusi ganda jika dipanggil kembali oleh subshell
if [ "$_LENZNODE_RUNNING" = "1" ] && [ -z "$1" ]; then
    exit 0
fi

# Inisialisasi Environment Termux
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
[ -z "$HOME" ] || [ "$HOME" = "/" ] || [ "$HOME" = "/root" ] && [ -d "/data/data/com.termux/files/home" ] && export HOME="/data/data/com.termux/files/home"
export USER="${USER:-$(whoami 2>/dev/null || echo 'termux')}"
export INITIAL_PASSWORD="${INITIAL_PASSWORD:-123456}"
export PATH="/data/data/com.termux/files/usr/bin:$PREFIX/bin:$PREFIX/bin/applets:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
[ -d "$PREFIX/lib" ] && export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Optimasi Memori Ekstrem untuk Semua Perangkat (RAM Minimal & Hemat Baterai)
export NODE_OPTIONS="--max-old-space-size=128 ${NODE_OPTIONS:-}"

DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/panel/server.js" ]; then
    SERVER_DIR="$DIR"
elif [ -d "$HOME/LenzNode" ]; then
    SERVER_DIR="$HOME/LenzNode"
elif [ -d "$HOME/panel" ]; then
    SERVER_DIR="$HOME/panel"
else
    SERVER_DIR="$DIR"
fi

# Auto-register perintah CLI global 'lenz' & 'lenznode' ke PATH sistem
register_cli_symlinks() {
    local target="$SERVER_DIR/start.sh"
    [ -f "$target" ] || return 0
    local bin_dirs=()
    [ -n "$PREFIX" ] && [ -d "$PREFIX/bin" ] && bin_dirs+=("$PREFIX/bin")
    [ -d "/data/data/com.termux/files/usr/bin" ] && bin_dirs+=("/data/data/com.termux/files/usr/bin")
    [ -d "/usr/local/bin" ] && bin_dirs+=("/usr/local/bin")
    for bdir in "${bin_dirs[@]}"; do
        if [ -w "$bdir" ]; then
            [ ! -L "$bdir/lenz" ] || [ "$(readlink "$bdir/lenz" 2>/dev/null)" != "$target" ] && ln -sf "$target" "$bdir/lenz" 2>/dev/null || true
            [ ! -L "$bdir/lenznode" ] || [ "$(readlink "$bdir/lenznode" 2>/dev/null)" != "$target" ] && ln -sf "$target" "$bdir/lenznode" 2>/dev/null || true
        fi
    done
}
register_cli_symlinks

LOG_DIR="$SERVER_DIR/logs"
mkdir -p "$LOG_DIR" "$HOME/workspace"
PANEL_LOG="$LOG_DIR/panel.log"
SSH_LOG="$LOG_DIR/ssh.log"
TUNNEL_LOG="$LOG_DIR/cloudflared.log"
TUNNEL_FILE="$LOG_DIR/tunnel-url.txt"

export PANEL_USER="admin"
export PANEL_PASS="admin123"
export PANEL_PORT="8080"

get_local_ip() {
    local ip=""
    # 1. Android Property check (sangat cepat & native untuk Termux pada koneksi Wi-Fi)
    if command -v getprop >/dev/null 2>&1; then
        local prop_ip=$(getprop dhcp.wlan0.ipaddress 2>/dev/null | tr -d ' \r\n')
        if [ -n "$prop_ip" ] && [ "$prop_ip" != "0.0.0.0" ]; then
            ip="$prop_ip"
        fi
    fi

    # 2. Deteksi via 'ip -4 addr show' pada interface Wi-Fi / Hotspot / LAN / Seluler
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        for iface in wlan0 wlan1 ap0 rndis0 eth0 rmnet_data0; do
            local cand=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1 | tr -d ' \r\n')
            if [ -n "$cand" ] && [ "$cand" != "127.0.0.1" ]; then
                ip="$cand"
                break
            fi
        done
        # Fallback ip route
        if [ -z "$ip" ]; then
            ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n 1 | tr -d ' \r\n')
        fi
    fi

    # 3. Deteksi dinamis via Node.js interface scanner
    if [ -z "$ip" ] && command -v node >/dev/null 2>&1; then
        ip=$(node -e "const os=require('os'),i=os.networkInterfaces();let r='',f='';for(const k in i){for(const x of i[k]){if(x.family==='IPv4'&&!x.internal&&x.address!=='127.0.0.1'){if(k.startsWith('wlan')||k.startsWith('eth')||k.startsWith('ap')||k.startsWith('rndis')){r=x.address;break;}if(!f)f=x.address;}}if(r)break;}console.log(r||f);" 2>/dev/null | tr -d ' \r\n')
    fi

    # 4. Fallback ifconfig multi-interface (wlan0, eth0, ap0, rndis0)
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        for iface in wlan0 wlan1 ap0 rndis0 eth0 rmnet_data0; do
            local cand=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | sed 's/addr://' | tr -d ' \r\n')
            if [ -n "$cand" ] && [ "$cand" != "127.0.0.1" ]; then
                ip="$cand"
                break
            fi
        done
    fi
    [ -z "$ip" ] && ip="127.0.0.1"
    echo "$ip"
}

is_port_active() {
    local port="$1"
    # 1. Probe via Node.js net connection (Paling akurat & universal di Android 5-16+ non-root)
    if command -v node >/dev/null 2>&1; then
        node -e "const net=require('net'),s=net.connect(${port},'127.0.0.1',()=>{s.destroy();process.exit(0)});s.on('error',()=>process.exit(1));" >/dev/null 2>&1 && return 0
    fi
    # 2. Probe via curl
    if command -v curl >/dev/null 2>&1; then
        curl -s -m 1 "http://127.0.0.1:${port}/" >/dev/null 2>&1 && return 0
    fi
    # 3. Fallback netstat & ss (khusus device root / Linux standard)
    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -q ":${port}[[:space:]]" && return 0
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -q ":${port}[[:space:]]" && return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# 0. SISTEM AUTO-UPDATE SAAT STARTUP (GitHub Auto-Sync)
# -----------------------------------------------------------------------------
repair_termux_libs() {
    # Periksa apakah curl atau git mengalami linking symbol error di Termux
    local NEED_REPAIR=0
    if command -v curl >/dev/null 2>&1; then
        if ! curl --version >/dev/null 2>&1; then
            NEED_REPAIR=1
        fi
    fi
    if command -v git >/dev/null 2>&1; then
        if ! git --version >/dev/null 2>&1; then
            NEED_REPAIR=1
        fi
    fi

    if [ "$NEED_REPAIR" = "1" ] && [ -d "/data/data/com.termux" ]; then
        echo -e "  ${CYAN}│${NC}  ${YELLOW}ℹ${NC}  update      ${YELLOW}memperbaiki dependensi Termux (curl/ssl)...${NC}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1 || true
        apt-get --fix-broken install -y -o Dpkg::Options::="--force-confnew" >/dev/null 2>&1 || true
        apt-get full-upgrade -y -o Dpkg::Options::="--force-confnew" >/dev/null 2>&1 || pkg upgrade -y >/dev/null 2>&1 || true
        apt-get install --reinstall -y openssl libcurl curl git >/dev/null 2>&1 || true
    fi
}

check_and_apply_update() {
    local IS_MANUAL_TRIGGER=0
    [ "$1" = "manual" ] || [ "$1" = "force" ] && IS_MANUAL_TRIGGER=1

    # Cegah loop jika skrip baru saja di-update dan dieksekusi ulang
    if [ "$_LENZNODE_UPDATED" = "1" ]; then
        local CUR_COMMIT=$(git -C "$SERVER_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest")
        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC}  update      ${GREEN}sistem sudah versi terbaru (${CUR_COMMIT})${NC}"
        return 0
    fi

    repair_termux_libs

    local GIT_DIR="$SERVER_DIR/.git"
    local REPO_URL="https://github.com/Lenzx999/LenzNode.git"
    local CUR_VERSION="2.1.0"
    [ -f "$SERVER_DIR/version.json" ] && CUR_VERSION=$(grep -oE '"version":\s*"[^"]+"' "$SERVER_DIR/version.json" 2>/dev/null | cut -d'"' -f4)

    # Jika folder belum terhubung dengan Git, hubungkan otomatis
    if [ ! -d "$GIT_DIR" ] && command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
        (cd "$SERVER_DIR" && git init -q 2>/dev/null && git remote add origin "$REPO_URL" 2>/dev/null) || true
    fi

    local LOCAL_HASH=""
    if [ -d "$GIT_DIR" ] && command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
        LOCAL_HASH=$(git -C "$SERVER_DIR" rev-parse --short HEAD 2>/dev/null || true)

        # Cek update secara dinamis ke origin/main dengan batas waktu wajar 15 detik
        if git -C "$SERVER_DIR" -c http.lowSpeedLimit=500 -c http.lowSpeedTime=15 fetch origin main --depth=1 >/dev/null 2>&1; then
            local REMOTE_HASH=$(git -C "$SERVER_DIR" rev-parse --short origin/main 2>/dev/null || true)

            # Jika ada perbedaan versi antara repositori lokal dan remote di GitHub
            if [ -n "$REMOTE_HASH" ] && [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
                # Skenario A: Pengguna menjalankan manual './start.sh update' -> Langsung terapkan pembaruan
                if [ "$IS_MANUAL_TRIGGER" = "1" ]; then
                    echo -e "  ${CYAN}│${NC}  ${GREEN}⬆${NC}  update      ${GREEN}mengunduh rilis terbaru (${LOCAL_HASH:-awal} ➜ ${REMOTE_HASH})...${NC}"

                    local AUTH_BACKUP=""
                    [ -f "$SERVER_DIR/panel/auth-config.json" ] && AUTH_BACKUP=$(cat "$SERVER_DIR/panel/auth-config.json" 2>/dev/null)

                    git -C "$SERVER_DIR" reset --hard origin/main >/dev/null 2>&1 || git -C "$SERVER_DIR" pull origin main >/dev/null 2>&1

                    [ -n "$AUTH_BACKUP" ] && echo "$AUTH_BACKUP" > "$SERVER_DIR/panel/auth-config.json" 2>/dev/null || true
                    chmod +x "$SERVER_DIR/"*.sh "$SERVER_DIR/scripts/"*.sh 2>/dev/null || true

                    if [ -d "$HOME" ] && [ -f "$SERVER_DIR/start.sh" ] && [ "$SERVER_DIR" != "$HOME" ]; then
                        cp -f "$SERVER_DIR/start.sh" "$HOME/start.sh" 2>/dev/null && chmod +x "$HOME/start.sh" 2>/dev/null || true
                    fi

                    echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC}  update      ${GREEN}berhasil diperbarui ke versi terbaru (${REMOTE_HASH})!${NC}"

                    if command -v pm2 >/dev/null 2>&1 && pm2 describe lenznode >/dev/null 2>&1; then
                        pm2 restart lenznode >/dev/null 2>&1 || true
                        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC}  service     ${GREEN}layanan PM2 lenznode berhasil dimuat ulang${NC}"
                    fi
                    return 0
                else
                    # Skenario B: Pengguna menjalankan startup normal './start.sh' -> Berikan notifikasi dinamis & saran update
                    echo -e "  ${CYAN}│${NC}  ${YELLOW}⬆${NC}  update      ${YELLOW}${BOLD}TERSEDIA PEMBARUAN!${NC} (${LOCAL_HASH:-lama} ➜ ${GREEN}${REMOTE_HASH}${NC})"
                    echo -e "  ${CYAN}│${NC}  ${YELLOW}ℹ${NC}              Ketik '${BOLD}lenz update${NC}' untuk memperbarui sistem."
                    [ -f "$PANEL_LOG" ] && echo "[$(date '+%H.%M.%S' 2>/dev/null || echo '00:00:00')] [UPDATE] Pembaruan terdeteksi di GitHub (${LOCAL_HASH:-lama} -> ${REMOTE_HASH}). Ketik lenz update untuk memperbarui." >> "$PANEL_LOG" 2>/dev/null || true
                    return 0
                fi
            elif [ -n "$REMOTE_HASH" ]; then
                # Jika hash sama persis, tampilkan versi dan hash aktual (BUKAN teks statis)
                echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC}  update      ${DIM}sistem sudah versi terbaru (v${CUR_VERSION} • ${LOCAL_HASH})${NC}"
                return 0
            fi
        fi
    fi

    # Fallback jika update manual gagal karena kendala jaringan
    if [ "$IS_MANUAL_TRIGGER" = "1" ]; then
        if [ -f "$SERVER_DIR/update.sh" ]; then
            echo -e "  ${CYAN}│${NC}  ${YELLOW}ℹ${NC}  update      ${YELLOW}menjalankan pembaruan cadangan via update.sh...${NC}"
            bash "$SERVER_DIR/update.sh"
            return 0
        fi
        echo -e "  ${CYAN}│${NC}  ${RED}✗${NC}  update      ${RED}gagal memeriksa pembaruan (offline / jaringan sibuk)${NC}"
    else
        echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  update      ${DIM}offline / lewati pengecekan (versi: ${LOCAL_HASH:-v${CUR_VERSION}})${NC}"
    fi
}

# -----------------------------------------------------------------------------
# 1. KONTROL SSH SERVER (Port 2222) — NATIVE TERMUX (TANPA PROOT)
# -----------------------------------------------------------------------------
start_ssh() {
    local SSH_PORT=2222
    local SSH_PASS="${LENZ_SSH_PASS:-admin123}"

    mkdir -p "$PREFIX/var/run" "$PREFIX/etc/ssh" 2>/dev/null || true
    chmod 700 "$PREFIX/etc/ssh" 2>/dev/null || true
    rm -f "$PREFIX/var/run/sshd.pid" 2>/dev/null || true

    # Pastikan host key OpenSSH telah digenerate (mencegah error pada instalasi baru)
    for key_type in rsa ed25519; do
        local key_file="$PREFIX/etc/ssh/ssh_host_${key_type}_key"
        if [ ! -s "$key_file" ]; then
            rm -f "$key_file" "${key_file}.pub" 2>/dev/null || true
        fi
    done
    if [ ! -s "$PREFIX/etc/ssh/ssh_host_rsa_key" ] && [ ! -s "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]; then
        ssh-keygen -A >/dev/null 2>&1 || true
    fi
    chmod 600 "$PREFIX/etc/ssh/ssh_host_"*"_key" 2>/dev/null || true
    chmod 644 "$PREFIX/etc/ssh/ssh_host_"*"_key.pub" 2>/dev/null || true

    # Pastikan sshd_config memiliki konfigurasi port 2222 & PasswordAuthentication yes
    local SSHD_CFG="$PREFIX/etc/ssh/sshd_config"
    if [ ! -f "$SSHD_CFG" ] || ! grep -q "^PasswordAuthentication yes" "$SSHD_CFG" 2>/dev/null || ! grep -q "^Port 2222" "$SSHD_CFG" 2>/dev/null; then
        cat << 'EOF' > "$SSHD_CFG"
Port 2222
ListenAddress 0.0.0.0
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
PermitRootLogin yes
PrintMotd yes
Subsystem sftp /data/data/com.termux/files/usr/libexec/sftp-server
EOF
        chmod 600 "$SSHD_CFG" 2>/dev/null || true
    fi

    # Pastikan password SSH Termux bawaan selalu disetel / disinkronkan
    if command -v passwd >/dev/null 2>&1; then
        printf "%s\n%s\n" "$SSH_PASS" "$SSH_PASS" | passwd >/dev/null 2>&1 || true
    fi

    if is_port_active "$SSH_PORT"; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  ssh         ${DIM}port $SSH_PORT${NC}"
        return 0
    fi

    pkill -f "sshd.*$SSH_PORT" 2>/dev/null || true
    sleep 0.3
    sshd -p "$SSH_PORT" 2>/dev/null || true
    sleep 0.4

    if is_port_active "$SSH_PORT"; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  ssh         ${DIM}port $SSH_PORT${NC}"
    else
        sshd 2>/dev/null || true
        sleep 0.4
        if is_port_active "$SSH_PORT"; then
            echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  ssh         ${DIM}port $SSH_PORT${NC}"
        else
            echo -e "  ${CYAN}│${NC}  ${YELLOW}○${NC}  ssh         ${DIM}port $SSH_PORT (periksa log OpenSSH)${NC}"
        fi
    fi
}

stop_ssh() {
    pkill -f "sshd -p 2222" 2>/dev/null || true
    pkill -9 -f "sshd" 2>/dev/null || true
    echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  ssh         ${DIM}stopped${NC}"
}

start_vps() { start_ssh "$@"; }
stop_vps() { stop_ssh "$@"; }

# -----------------------------------------------------------------------------
# 2. KONTROL WEB DASHBOARD PANEL (Port 8080)
# -----------------------------------------------------------------------------
start_panel() {
    if is_port_active "${PANEL_PORT:-8080}"; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  panel       ${DIM}port ${PANEL_PORT:-8080}${NC}"
        return 0
    fi

    local SERVER_JS="$SERVER_DIR/panel/server.js"
    [ ! -f "$SERVER_JS" ] && SERVER_JS="$DIR/panel/server.js"
    [ ! -f "$SERVER_JS" ] && SERVER_JS="$DIR/server.js"

    if [ ! -f "$SERVER_JS" ]; then
        echo -e "  ${CYAN}│${NC}  ${RED}✗${NC}  panel       ${DIM}server.js tidak ditemukan${NC}"
        return 1
    fi

    local ENV_TUNNEL="${LENZ_ENABLE_TUNNEL:-1}"

    if command -v pm2 >/dev/null 2>&1; then
        if pm2 describe lenznode >/dev/null 2>&1; then
            LENZ_ENABLE_TUNNEL="$ENV_TUNNEL" INITIAL_PASSWORD="123456" pm2 restart lenznode --update-env >/dev/null 2>&1
        elif pm2 describe panel >/dev/null 2>&1 && [ ! -d "$HOME/panel" ]; then
            LENZ_ENABLE_TUNNEL="$ENV_TUNNEL" INITIAL_PASSWORD="123456" pm2 restart panel --update-env >/dev/null 2>&1
        else
            LENZ_ENABLE_TUNNEL="$ENV_TUNNEL" INITIAL_PASSWORD="123456" pm2 start "$SERVER_JS" --name "lenznode" --update-env --node-args="--max-old-space-size=128" --max-memory-restart 256M >/dev/null 2>&1
            pm2 save >/dev/null 2>&1 || true
        fi
    else
        pkill -f "node.*/panel/server\.js" 2>/dev/null || true
        pkill -f "node server.js" 2>/dev/null || true
        nohup env LENZ_ENABLE_TUNNEL="$ENV_TUNNEL" INITIAL_PASSWORD="123456" node --max-old-space-size=128 "$SERVER_JS" </dev/null > "$PANEL_LOG" 2>&1 &
        disown $! 2>/dev/null || true
    fi

    # Probe aktif: Pastikan port benar-benar hidup dan merespons (hingga 12 detik)
    local PANEL_OK=0
    for p in $(seq 1 24); do
        if is_port_active "${PANEL_PORT:-8080}"; then
            PANEL_OK=1
            break
        fi
        sleep 0.5
    done

    if [ "$PANEL_OK" = "1" ]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  panel       ${DIM}port ${PANEL_PORT:-8080}${NC}"
        return 0
    else
        echo -e "  ${CYAN}│${NC}  ${RED}✗${NC}  panel       ${RED}gagal merespons di port ${PANEL_PORT:-8080}!${NC}"
        if [ -f "$PANEL_LOG" ]; then
            echo -e "  ${CYAN}│${NC}  ${YELLOW}ℹ${NC}  Log error terakhir:"
            tail -n 5 "$PANEL_LOG" 2>/dev/null | sed "s/^/  ${CYAN}│${NC}     /" || true
        fi
        return 1
    fi
}

stop_panel() {
    if command -v pm2 >/dev/null 2>&1; then
        pm2 stop lenznode >/dev/null 2>&1 || pm2 stop panel >/dev/null 2>&1 || true
    fi
    pkill -f "node.*/panel/server\.js" 2>/dev/null || true
    pkill -f "node server.js" 2>/dev/null || true
    echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  panel       ${DIM}stopped${NC}"
}

# -----------------------------------------------------------------------------
# 3. KONTROL CLOUDFLARE PUBLIC TUNNEL
# -----------------------------------------------------------------------------
ensure_cloudflare_tunnel() {
    local TUNNEL_FILE="$LOG_DIR/tunnel-url.txt"
    local TUNNEL_LOG="$LOG_DIR/cloudflared.log"

    if [ "$LENZ_ENABLE_TUNNEL" = "0" ] || [ "$LENZ_ENABLE_TUNNEL" = "false" ]; then
        stop_tunnel >/dev/null 2>&1 || true
        rm -f "$TUNNEL_FILE" 2>/dev/null || true
        echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  tunnel      ${DIM}dinonaktifkan (mode lokal)${NC}"
        return 0
    fi

    # Bersihkan cache tunnel lama saat start baru agar link tidak statis/kadaluwarsa
    rm -f "$TUNNEL_FILE" 2>/dev/null || true

    local CF_BIN=""
    if command -v cloudflared >/dev/null 2>&1; then
        CF_BIN="cloudflared"
    elif [ -x "$PREFIX/bin/cloudflared" ]; then
        CF_BIN="$PREFIX/bin/cloudflared"
    elif [ -x "/data/data/com.termux/files/usr/bin/cloudflared" ]; then
        CF_BIN="/data/data/com.termux/files/usr/bin/cloudflared"
    fi

    if [ -z "$CF_BIN" ]; then
        echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  tunnel      ${DIM}cloudflared belum terpasang${NC}"
        return 1
    fi

    if ! pgrep -x cloudflared >/dev/null 2>&1; then
        rm -f "$TUNNEL_LOG" 2>/dev/null || true
        nohup env GOGC=20 GOMEMLIMIT=32MiB "$CF_BIN" tunnel --url "http://127.0.0.1:${PANEL_PORT:-8080}" > "$TUNNEL_LOG" 2>&1 &
        disown $! 2>/dev/null || true
    fi

    # Tunggu dan verifikasi handshake tunnel Cloudflare (Health-Check Nyata)
    local URL=""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        if [ -f "$TUNNEL_FILE" ]; then
            URL=$(cat "$TUNNEL_FILE" 2>/dev/null | tr -d ' \r\n')
            [ -n "$URL" ] && [ "$URL" != "https://dashboard.pinggy.io" ] && break
        fi
        if [ -f "$TUNNEL_LOG" ]; then
            URL=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | tail -n 1)
            if [ -n "$URL" ]; then
                echo "$URL" > "$TUNNEL_FILE" 2>/dev/null || true
                break
            fi
        fi
        sleep 0.5
    done

    # Verifikasi HTTP health check jika curl tersedia
    local VERIFIED=0
    if [ -n "$URL" ] && command -v curl >/dev/null 2>&1; then
        for j in 1 2 3; do
            local HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "$URL" 2>/dev/null || true)
            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "401" ]; then
                VERIFIED=1
                break
            fi
            sleep 0.5
        done
    elif [ -n "$URL" ]; then
        VERIFIED=1
    fi

    if [ "$VERIFIED" = "1" ]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  tunnel      ${GREEN}connected (terverifikasi)${NC}"
        return 0
    elif [ -n "$URL" ]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  tunnel      ${DIM}connected${NC}"
        return 0
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}○${NC}  tunnel      ${DIM}menghubungkan ke edge...${NC}"
        return 0
    fi
}

stop_tunnel() {
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    pkill -x cloudflared 2>/dev/null || true
    echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  tunnel      ${DIM}stopped${NC}"
}

# -----------------------------------------------------------------------------
# 3.5 DETEKSI & MANAJEMEN MODE ROOT (MAGISK / KERNELSU)
# -----------------------------------------------------------------------------
ROOT_CONFIG_FILE="$SERVER_DIR/panel/root-config.json"

check_real_root() {
    # Verifikasi nyata apakah su benar-benar tersedia dan memberikan UID=0
    if command -v su >/dev/null 2>&1; then
        local test_uid=$(su -c "id -u" 2>/dev/null | tr -d ' \r\n')
        if [ "$test_uid" = "0" ]; then
            return 0
        fi
    fi
    return 1
}

apply_root_iptables() {
    # Pasang iptables port-redirect: Port 80 -> 8080, Port 22 -> 2222
    if [ "$LENZ_ROOT_MODE" = "1" ] && command -v su >/dev/null 2>&1; then
        su -c "iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null; iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080 2>/dev/null; iptables -t nat -D PREROUTING -p tcp --dport 22 -j REDIRECT --to-ports 2222 2>/dev/null; iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-ports 2222 2>/dev/null;" 2>/dev/null || true
    fi
}

detect_and_configure_root() {
    local HAS_ROOT=0
    check_real_root && HAS_ROOT=1

    # Jika argumen eksplisit dipanggil via terminal
    for arg in "$@"; do
        if [ "$arg" = "--root" ]; then
            if [ "$HAS_ROOT" = "1" ]; then
                echo '{"enabled": true}' > "$ROOT_CONFIG_FILE" 2>/dev/null || true
                export LENZ_ROOT_MODE="1"
                apply_root_iptables
                return 0
            else
                echo '{"enabled": false}' > "$ROOT_CONFIG_FILE" 2>/dev/null || true
                export LENZ_ROOT_MODE="0"
                return 0
            fi
        elif [ "$arg" = "--non-root" ]; then
            echo '{"enabled": false}' > "$ROOT_CONFIG_FILE" 2>/dev/null || true
            export LENZ_ROOT_MODE="0"
            return 0
        fi
    done

    # Jika konfigurasi sudah pernah disimpan sebelumnya
    if [ -f "$ROOT_CONFIG_FILE" ]; then
        local saved_val=$(grep -oE '"enabled":\s*(true|false)' "$ROOT_CONFIG_FILE" 2>/dev/null | grep -oE '(true|false)')
        if [ "$saved_val" = "true" ]; then
            if [ "$HAS_ROOT" = "1" ]; then
                export LENZ_ROOT_MODE="1"
                apply_root_iptables
                return 0
            else
                export LENZ_ROOT_MODE="0"
                return 0
            fi
        else
            export LENZ_ROOT_MODE="0"
            return 0
        fi
    fi

    # Jika HP BUKAN ROOT: Jangan tanyakan apa-apa! Langsung non-root aman.
    if [ "$HAS_ROOT" = "0" ]; then
        echo '{"enabled": false}' > "$ROOT_CONFIG_FILE" 2>/dev/null || true
        export LENZ_ROOT_MODE="0"
        return 0
    fi

    # Jika HP TERBUKTI ROOT (Hanya muncul sekali saat pertama kali di perangkat root):
    echo ""
    echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode Root Detection${NC} ${CYAN}────────────────────${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}✓ Terdeteksi akses Superuser (Magisk / KernelSU)!${NC}"
    echo -e "  ${CYAN}│${NC}  Fitur Root: Port standar (80 & 22) tanpa nomor port,"
    echo -e "  ${CYAN}│${NC}  baca sensor baterai mendalam, dan Web Terminal Root (#)."
    echo -e "  ${CYAN}╰─────────────────────────────────────────────${NC}"
    local ROOT_ANS=""
    if [ -t 0 ]; then
        printf "  Aktifkan Mode Root Penuh? [Y/n] (Default Y): "
        read -r ROOT_ANS
    fi
    local LOWER_ROOT=$(echo "$ROOT_ANS" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    case "$LOWER_ROOT" in
        n|no|tidak|0|false)
            echo '{"enabled": false}' > "$ROOT_CONFIG_FILE" 2>/dev/null || true
            export LENZ_ROOT_MODE="0"
            echo -e "  ${CYAN}➜${NC} Memilih: ${CYAN}Mode Non-Root Standar${NC}\n"
            ;;
        *)
            echo '{"enabled": true}' > "$ROOT_CONFIG_FILE" 2>/dev/null || true
            export LENZ_ROOT_MODE="1"
            echo -e "  ${CYAN}➜${NC} Memilih: ${GREEN}Mode Root Penuh (Privileged)${NC}\n"
            apply_root_iptables
            ;;
    esac
}

# -----------------------------------------------------------------------------
# 4. START ALL, STOP ALL, & STATUS
# -----------------------------------------------------------------------------
ask_operational_mode() {
    # Lewati prompt jika sudah ditentukan via argumen atau env var
    if [ -n "$LENZ_ENABLE_TUNNEL" ]; then
        return 0
    fi
    if [ "$1" = "--tunnel" ] || [ "$1" = "-t" ] || [ "$2" = "--tunnel" ]; then
        export LENZ_ENABLE_TUNNEL="1"
        return 0
    fi
    if [ "$1" = "--local" ] || [ "$1" = "-l" ] || [ "$2" = "--local" ]; then
        export LENZ_ENABLE_TUNNEL="0"
        return 0
    fi
    # Jika mode daemon / background, default ke lokal bila tidak di-set
    if [ "$1" = "bg" ] || [ "$1" = "daemon" ] || [ "$1" = "-d" ] || [ "$1" = "--bg" ]; then
        export LENZ_ENABLE_TUNNEL="${LENZ_ENABLE_TUNNEL:-1}"
        return 0
    fi

    # Tampilan Menu Pemilihan Interaktif
    echo ""
    echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode Mode Selection${NC} ${CYAN}────────────────────${NC}"
    echo -e "  ${CYAN}│${NC}  Pilih mode operasional server:"
    echo -e "  ${CYAN}│${NC}  ${BOLD}[1]${NC} Jalankan Lokal Saja ${DIM}(Wi-Fi / LAN, Hemat Kuota & RAM)${NC}"
    echo -e "  ${CYAN}│${NC}  ${BOLD}[2]${NC} Jalankan dengan Public Tunnel ${GREEN}(Cloudflare Online 24/7)${NC}"
    echo -e "  ${CYAN}╰─────────────────────────────────────────────${NC}"
    
    local MODE_CHOICE=""
    if [ -t 0 ]; then
        printf "  Pilihan Anda [1/2 atau y/n] (Default 1): "
        read -r MODE_CHOICE
    fi

    local LOWER_CHOICE=$(echo "$MODE_CHOICE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

    case "$LOWER_CHOICE" in
        2|y|ya|iya|yes|tunnel|t|true|on)
            export LENZ_ENABLE_TUNNEL="1"
            echo -e "  ${CYAN}➜${NC} Memilih mode: ${GREEN}Public Tunnel Cloudflare${NC}\n"
            ;;
        *)
            export LENZ_ENABLE_TUNNEL="0"
            echo -e "  ${CYAN}➜${NC} Memilih mode: ${CYAN}Lokal Saja (Wi-Fi / LAN)${NC}\n"
            ;;
    esac
}

export_error_log() {
    local REPORT_FILE="$LOG_DIR/LenzNode-Error.log"
    echo "========================================================" > "$REPORT_FILE"
    echo "  LENZNODE CRASH & ERROR REPORT FOR DEVELOPER" >> "$REPORT_FILE"
    echo "  Waktu       : $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'Unknown')" >> "$REPORT_FILE"
    echo "  Android SDK : $(getprop ro.build.version.sdk 2>/dev/null || echo 'Unknown')" >> "$REPORT_FILE"
    echo "  Arsitektur  : $(uname -m 2>/dev/null || echo 'Unknown')" >> "$REPORT_FILE"
    echo "  Node.js     : $(node -v 2>/dev/null || echo 'Not installed')" >> "$REPORT_FILE"
    echo "========================================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "--- [1] PANEL LOG TERAKHIR ---" >> "$REPORT_FILE"
    [ -f "$PANEL_LOG" ] && tail -n 40 "$PANEL_LOG" >> "$REPORT_FILE" 2>/dev/null || echo "Tidak ada panel.log" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "--- [2] CLOUDFLARED TUNNEL LOG ---" >> "$REPORT_FILE"
    [ -f "$TUNNEL_LOG" ] && tail -n 25 "$TUNNEL_LOG" >> "$REPORT_FILE" 2>/dev/null || echo "Tidak ada cloudflared.log" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "--- [3] SSH LOG ---" >> "$REPORT_FILE"
    [ -f "$SSH_LOG" ] && tail -n 15 "$SSH_LOG" >> "$REPORT_FILE" 2>/dev/null || echo "Tidak ada ssh.log" >> "$REPORT_FILE"

    local EXPORTED=""
    for dl in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/storage/downloads"; do
        if [ -d "$dl" ]; then
            cp -f "$REPORT_FILE" "$dl/LenzNode-Error.log" 2>/dev/null && EXPORTED="$dl/LenzNode-Error.log" && break
        fi
    done
    if [ -n "$EXPORTED" ]; then
        echo -e "  ${CYAN}│${NC}  ${YELLOW}📁 Laporan error tersimpan di:${NC} ${GREEN}${EXPORTED}${NC}"
        echo -e "  ${CYAN}│${NC}     ${DIM}(Buka folder Download di HP Anda & kirim file ini ke developer)${NC}"
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}📁 Laporan error tersimpan di:${NC} ${GREEN}${REPORT_FILE}${NC}"
    fi
}

start_all() {
    if [ "$_LENZNODE_STARTING" = "1" ]; then
        return 0
    fi
    export _LENZNODE_STARTING=1
    export _LENZNODE_RUNNING=1

    detect_and_configure_root "$@"

    local LOCK_FILE="$LOG_DIR/.start.lock"
    local LAST_START_FILE="$LOG_DIR/.last_start"
    local NOW=$(date +%s 2>/dev/null || echo 0)

    # Concurrency guard
    if [ -f "$LOCK_FILE" ]; then
        local RUNNING_PID=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$RUNNING_PID" ] && kill -0 "$RUNNING_PID" 2>/dev/null && [ "$RUNNING_PID" != "$$" ]; then
            local FILE_MTIME=$(date -r "$LOCK_FILE" +%s 2>/dev/null || echo 0)
            local AGE=$((NOW - FILE_MTIME))
            if [ "$AGE" -le 60 ] && [ "$AGE" -ge 0 ]; then
                echo -e "  ${CYAN}│${NC}  ${YELLOW}ℹ${NC}  LenzNode sedang berjalan oleh PID ${RUNNING_PID}."
                unset _LENZNODE_STARTING
                return 0
            fi
        fi
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi

    # Debounce guard
    if [ "$1" != "force" ] && [ -f "$LAST_START_FILE" ]; then
        local LAST_TIME=$(cat "$LAST_START_FILE" 2>/dev/null || echo 0)
        local DIFF=$((NOW - LAST_TIME))
        if [ "$DIFF" -ge 0 ] && [ "$DIFF" -lt 4 ]; then
            unset _LENZNODE_STARTING
            return 0
        fi
    fi

    echo "$$" > "$LOCK_FILE"
    echo "$NOW" > "$LAST_START_FILE"
    trap 'rm -f "$LOG_DIR/.start.lock" 2>/dev/null || true' EXIT INT TERM

    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null || true

    echo ""
    echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode${NC} ${CYAN}───────────��──────────────────${NC}"

    check_and_apply_update "$@"

    # Bersihkan file URL tunnel lama saat start baru agar link tidak statis
    rm -f "$LOG_DIR/tunnel-url.txt" 2>/dev/null || true

    local PANEL_RES=0
    start_panel || PANEL_RES=1
    start_ssh
    ensure_cloudflare_tunnel

    LOCAL_IP=$(get_local_ip)
    TUNNEL_URL=""
    if [ "$LENZ_ENABLE_TUNNEL" = "1" ]; then
        if [ -f "$TUNNEL_FILE" ]; then
            TUNNEL_URL=$(cat "$TUNNEL_FILE" 2>/dev/null | tr -d ' \r\n')
            [ "$TUNNEL_URL" = "https://dashboard.pinggy.io" ] && TUNNEL_URL=""
        fi
        if [ -z "$TUNNEL_URL" ] && [ -f "$TUNNEL_LOG" ]; then
            TUNNEL_URL=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | tail -n 1)
        fi
    fi

    echo -e "  ${CYAN}│${NC}"
    if [ "$PANEL_RES" = "0" ]; then
        if [ "$LENZ_ROOT_MODE" = "1" ]; then
            echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Local (HP ini):${NC}         http://127.0.0.1:${PANEL_PORT:-8080}/ ${DIM}(atau http://127.0.0.1/)${NC}"
            if [ "$LOCAL_IP" != "127.0.0.1" ]; then
                echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Network (Wi-Fi/LAN):${NC}    ${GREEN}http://${LOCAL_IP}/${NC} ${DIM}(Port 80 Standar & :8080)${NC}"
            else
                echo -e "  ${CYAN}│${NC}  ${YELLOW}➜${NC}  ${BOLD}Network (Wi-Fi/LAN):${NC}    ${YELLOW}Belum terhubung ke Wi-Fi / Hotspot${NC}"
            fi
            echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}SSH Server:${NC}             Port 22 & 2222 ${GREEN}(Root Privileged)${NC}"
        else
            echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Local (HP ini):${NC}         http://127.0.0.1:${PANEL_PORT:-8080}/"
            if [ "$LOCAL_IP" != "127.0.0.1" ]; then
                echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Network (Wi-Fi/LAN):${NC}    http://${LOCAL_IP}:${PANEL_PORT:-8080}/"
            else
                echo -e "  ${CYAN}│${NC}  ${YELLOW}➜${NC}  ${BOLD}Network (Wi-Fi/LAN):${NC}    ${YELLOW}Belum terhubung ke Wi-Fi / Hotspot${NC}"
            fi
            echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}SSH Server:${NC}             Port 2222 ${DIM}(Non-Root Standar)${NC}"
        fi
        if [ "$LENZ_ENABLE_TUNNEL" = "1" ]; then
            if [ -n "$TUNNEL_URL" ]; then
                echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Public (Internet Luar):${NC} ${GREEN}${TUNNEL_URL}${NC}"
            else
                echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Public (Internet Luar):${NC} ${YELLOW}Menghubungkan tunnel... (cek './start.sh status')${NC}"
            fi
        else
            echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Public (Internet Luar):${NC} ${DIM}Dinonaktifkan (Mode Lokal)${NC}"
        fi
        echo -e "  ${CYAN}╰─ Ready ─────────────────────────────────${NC}\n"
    else
        echo -e "  ${CYAN}│${NC}  ${RED}PERHATIAN:${NC} Web dashboard belum aktif."
        echo -e "  ${CYAN}│${NC}  Menyiapkan berkas laporan error untuk developer..."
        export_error_log
        echo -e "  ${CYAN}╰─ Gagal Memulai ─────────────────────────${NC}\n"
    fi

    rm -f "$LOCK_FILE" 2>/dev/null || true
    unset _LENZNODE_STARTING
}

stop_all() {
    rm -f "$LOG_DIR/.start.lock" "$LOG_DIR/.last_start" 2>/dev/null || true
    echo ""
    echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode${NC} ${CYAN}──────────────────────────────${NC}"
    stop_panel
    stop_ssh
    stop_tunnel
    echo -e "  ${CYAN}╰─ Stopped ───────────────────────────────${NC}\n"
}

status_all() {
    echo ""
    echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode${NC} ${CYAN}──────────────────────────────${NC}"
    LOCAL_IP=$(get_local_ip)
    is_port_active "${PANEL_PORT:-8080}" && echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  panel       ${DIM}port ${PANEL_PORT:-8080}${NC}" || echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  panel       ${DIM}stopped${NC}"
    is_port_active 2222 && echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  ssh         ${DIM}port 2222${NC}" || echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  ssh         ${DIM}stopped${NC}"
    if pgrep -x cloudflared >/dev/null 2>&1; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  tunnel      ${DIM}connected${NC}"
    else
        echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  tunnel      ${DIM}stopped${NC}"
    fi
    if [ -f "$ROOT_CONFIG_FILE" ] && [ -n "$(grep -oE '"enabled":\s*true' "$ROOT_CONFIG_FILE" 2>/dev/null)" ]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  root        ${DIM}aktif (Port 80/22 & Root Shell)${NC}"
    fi

    TUNNEL_URL=""
    if [ -f "$TUNNEL_FILE" ]; then
        TUNNEL_URL=$(cat "$TUNNEL_FILE" 2>/dev/null | tr -d ' \r\n')
    fi
    if [ -z "$TUNNEL_URL" ] && [ -f "$TUNNEL_LOG" ]; then
        TUNNEL_URL=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | tail -n 1)
    fi

    echo -e "  ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Local (HP ini):${NC}         http://127.0.0.1:${PANEL_PORT:-8080}/"
    if [ "$LOCAL_IP" != "127.0.0.1" ]; then
        echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Network (Wi-Fi/LAN):${NC}    http://${LOCAL_IP}:${PANEL_PORT:-8080}/"
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}➜${NC}  ${BOLD}Network (Wi-Fi/LAN):${NC}    ${YELLOW}Belum terhubung ke Wi-Fi / Hotspot${NC}"
    fi
    if [ -n "$TUNNEL_URL" ]; then
        echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Public (Internet Luar):${NC} ${GREEN}${TUNNEL_URL}${NC}"
    fi
    if is_port_active "${PANEL_PORT:-8080}" || is_port_active 2222; then
        echo -e "  ${CYAN}╰─ Active ────────────────────────────────${NC}\n"
    else
        echo -e "  ${CYAN}╰─ Inactive ──────────────────────────────${NC}\n"
    fi
}

case "$1" in
    --root)
        detect_and_configure_root "--root"
        echo -e "Mode Root berhasil dikonfigurasi. Jalankan ./start.sh untuk memulai server."
        exit 0
        ;;
    --non-root)
        detect_and_configure_root "--non-root"
        echo -e "Mode Non-Root berhasil dikonfigurasi. Jalankan ./start.sh untuk memulai server."
        exit 0
        ;;
    report|error|error-log)
        echo ""
        echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode Error Report${NC} ${CYAN}──────────────────${NC}"
        export_error_log
        echo -e "  ${CYAN}╰───────────────────────────────────────────${NC}\n"
        exit 0
        ;;
    update)
        echo ""
        echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode Update${NC} ${CYAN}───────────────────────${NC}"
        check_and_apply_update "manual"
        echo -e "  ${CYAN}╰───────────────────────────────────────────${NC}\n"
        exit 0
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 1
        start_all "force"
        ;;
    status)
        status_all
        ;;
    panel)
        start_panel
        ;;
    ssh|vps)
        start_ssh
        ;;
    stop-ssh|stop-vps)
        stop_ssh
        ;;
    tunnel)
        ensure_cloudflare_tunnel
        ;;
    stop-tunnel)
        stop_tunnel
        ;;
    router|9router)
        bash "$SERVER_DIR/scripts/start-9router.sh" "$2"
        ;;
    logs)
        tail -f "$PANEL_LOG"
        ;;
    bg|daemon|-d|--bg)
        start_all "bg"
        ;;
    *)
        ask_operational_mode "$@"
        start_all "$@"
        ;;
esac
