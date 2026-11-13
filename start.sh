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
export PATH="/data/data/com.termux/files/usr/bin:$PREFIX/bin:$PREFIX/bin/applets:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
[ -d "$PREFIX/lib" ] && export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Optimasi Memori Ekstrem untuk Semua Perangkat (RAM Minimal & Hemat Baterai)
export NODE_OPTIONS="--max-old-space-size=64 --optimize-for-size --expose-gc ${NODE_OPTIONS:-}"

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

LOG_DIR="$SERVER_DIR/logs"
mkdir -p "$LOG_DIR"
PANEL_LOG="$LOG_DIR/panel.log"
SSH_LOG="$LOG_DIR/ssh.log"
TUNNEL_LOG="$LOG_DIR/cloudflared.log"
TUNNEL_FILE="$LOG_DIR/tunnel-url.txt"

export PANEL_USER="admin"
export PANEL_PASS="admin123"
export PANEL_PORT="8080"

get_local_ip() {
    local ip=""
    # 1. Deteksi dinamis via routing kernel aktif (paling akurat saat online Wi-Fi / Data)
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    fi
    # 2. Deteksi dinamis via Node.js interface scanner
    if [ -z "$ip" ] && command -v node >/dev/null 2>&1; then
        ip=$(node -e "const os=require('os'),i=os.networkInterfaces();let r='',fallback='';for(const k in i){for(const x of i[k]){if(x.family==='IPv4'&&!x.internal){if(k.startsWith('wlan')||k.startsWith('eth')||k.startsWith('ap')||k.startsWith('rndis')){r=x.address;break;}if(!fallback)fallback=x.address;}}if(r)break;}console.log(r||fallback);" 2>/dev/null)
    fi
    # 3. Fallback ifconfig multi-interface (wlan0, eth0, ap0, rndis0)
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        for iface in wlan0 eth0 ap0 rndis0 rmnet_data0; do
            local cand=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | sed 's/addr://')
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
    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -q ":${port}[[:space:]]" && return 0
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -q ":${port}[[:space:]]" && return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -s -m 1 "http://127.0.0.1:${port}/" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# 0. SISTEM AUTO-UPDATE SAAT STARTUP (GitHub Auto-Sync)
# -----------------------------------------------------------------------------
check_and_apply_update() {
    # Cegah loop jika skrip baru saja di-update dan dieksekusi ulang
    if [ "$_LENZNODE_UPDATED" = "1" ]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC}  update      ${GREEN}sistem sudah versi terbaru${NC}"
        return 0
    fi

    local GIT_DIR="$SERVER_DIR/.git"
    local REPO_URL="https://github.com/Lenzx999/LenzNode.git"

    # Jika folder belum terhubung dengan Git, hubungkan otomatis
    if [ ! -d "$GIT_DIR" ] && command -v git >/dev/null 2>&1; then
        (cd "$SERVER_DIR" && git init -q 2>/dev/null && git remote add origin "$REPO_URL" 2>/dev/null) || true
    fi

    if [ -d "$GIT_DIR" ] && command -v git >/dev/null 2>&1; then
        # Cek update dengan batas waktu cepat (3 detik) agar tidak hang jika offline
        if git -C "$SERVER_DIR" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=3 fetch origin main --depth=1 >/dev/null 2>&1; then
            local LOCAL_HASH=$(git -C "$SERVER_DIR" rev-parse HEAD 2>/dev/null)
            local REMOTE_HASH=$(git -C "$SERVER_DIR" rev-parse origin/main 2>/dev/null)
            if [ -n "$LOCAL_HASH" ] && [ -n "$REMOTE_HASH" ] && [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
                echo -e "  ${CYAN}│${NC}  ${GREEN}⬆${NC}  update      ${GREEN}versi baru ditemukan! Memperbarui...${NC}"

                # Amankan kredensial akun agar password tidak ter-reset
                local AUTH_BACKUP=""
                [ -f "$SERVER_DIR/panel/auth-config.json" ] && AUTH_BACKUP=$(cat "$SERVER_DIR/panel/auth-config.json" 2>/dev/null)

                git -C "$SERVER_DIR" reset --hard origin/main >/dev/null 2>&1 || git -C "$SERVER_DIR" pull origin main >/dev/null 2>&1

                [ -n "$AUTH_BACKUP" ] && echo "$AUTH_BACKUP" > "$SERVER_DIR/panel/auth-config.json" 2>/dev/null || true
                chmod +x "$SERVER_DIR/"*.sh "$SERVER_DIR/scripts/"*.sh 2>/dev/null || true

                # Sinkronkan skrip starter di $HOME jika ada
                if [ -d "$HOME" ] && [ -f "$SERVER_DIR/start.sh" ] && [ "$SERVER_DIR" != "$HOME" ]; then
                    cp -f "$SERVER_DIR/start.sh" "$HOME/start.sh" 2>/dev/null && chmod +x "$HOME/start.sh" 2>/dev/null || true
                fi

                echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC}  update      ${GREEN}berhasil diperbarui ke versi terbaru!${NC}"

                # Hapus lock & jalankan skrip terbaru secara mulus
                rm -f "$LOG_DIR/.start.lock" 2>/dev/null || true
                unset _LENZNODE_STARTING
                export _LENZNODE_UPDATED=1
                exec bash "$0" "$@"
            else
                echo -e "  ${CYAN}│${NC}  ${GREEN}✓${NC}  update      ${DIM}sistem sudah versi terbaru${NC}"
            fi
        else
            echo -e "  ${CYAN}│${NC}  ${GRAY}○${NC}  update      ${DIM}offline / lewati pembaruan${NC}"
        fi
    fi
}

# -----------------------------------------------------------------------------
# 1. KONTROL SSH SERVER (Port 2222) — NATIVE TERMUX (TANPA PROOT)
# -----------------------------------------------------------------------------
start_ssh() {
    if is_port_active 2222; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  ssh         ${DIM}port 2222${NC}"
        return 0
    fi

    # Pastikan host key OpenSSH telah digenerate (mencegah error pada instalasi baru)
    if [ ! -f "$PREFIX/etc/ssh/ssh_host_rsa_key" ] && [ ! -f "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]; then
        ssh-keygen -A >/dev/null 2>&1 || true
    fi

    pkill -f "sshd -p 2222" 2>/dev/null || true
    sshd -p 2222 2>/dev/null || true
    sleep 0.5

    if is_port_active 2222; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  ssh         ${DIM}port 2222${NC}"
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}○${NC}  ssh         ${DIM}port 2222 (menjalankan ulang)${NC}"
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
        if pm2 describe panel >/dev/null 2>&1; then
            LENZ_ENABLE_TUNNEL="$ENV_TUNNEL" pm2 restart panel --update-env >/dev/null 2>&1
        else
            LENZ_ENABLE_TUNNEL="$ENV_TUNNEL" pm2 start "$SERVER_JS" --name "panel" --node-args="--max-old-space-size=128 --optimize-for-size --expose-gc" --max-memory-restart 120M >/dev/null 2>&1
            pm2 save >/dev/null 2>&1 || true
        fi
    else
        pkill -f "node.*/panel/server\.js" 2>/dev/null || true
        pkill -f "node server.js" 2>/dev/null || true
        nohup env LENZ_ENABLE_TUNNEL="$ENV_TUNNEL" node --max-old-space-size=128 --optimize-for-size --expose-gc "$SERVER_JS" > "$PANEL_LOG" 2>&1 &
        disown $! 2>/dev/null || true
    fi

    # Probe aktif: Pastikan port 8080 benar-benar hidup dan merespons
    local PANEL_OK=0
    for p in 1 2 3 4 5 6; do
        if is_port_active "${PANEL_PORT:-8080}"; then
            PANEL_OK=1
            break
        fi
        sleep 0.5
    done

    if [ "$PANEL_OK" = "1" ]; then
        echo -e "  ${CYAN}│${NC}  ${GREEN}●${NC}  panel       ${DIM}port ${PANEL_PORT:-8080}${NC}"
    else
        echo -e "  ${CYAN}│${NC}  ${YELLOW}○${NC}  panel       ${YELLOW}memulai (port ${PANEL_PORT:-8080})...${NC}"
    fi
}

stop_panel() {
    if command -v pm2 >/dev/null 2>&1; then
        pm2 stop panel >/dev/null 2>&1 || true
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
            [ -n "$URL" ] && break
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
        printf "  Pilihan Anda [1/2] (Default 1): "
        read -r MODE_CHOICE
    fi

    case "$MODE_CHOICE" in
        2)
            export LENZ_ENABLE_TUNNEL="1"
            echo -e "  ${CYAN}➜${NC} Memilih mode: ${GREEN}Public Tunnel Cloudflare${NC}\n"
            ;;
        *)
            export LENZ_ENABLE_TUNNEL="0"
            echo -e "  ${CYAN}➜${NC} Memilih mode: ${CYAN}Lokal Saja (Wi-Fi / LAN)${NC}\n"
            ;;
    esac
}

start_all() {
    if [ "$_LENZNODE_STARTING" = "1" ]; then
        return 0
    fi
    export _LENZNODE_STARTING=1
    export _LENZNODE_RUNNING=1

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
    echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode${NC} ${CYAN}──────────────────────────────${NC}"

    check_and_apply_update "$@"

    # Bersihkan file URL tunnel lama saat start baru agar link tidak statis
    rm -f "$LOG_DIR/tunnel-url.txt" 2>/dev/null || true

    start_panel
    start_ssh
    ensure_cloudflare_tunnel

    LOCAL_IP=$(get_local_ip)
    TUNNEL_URL=""
    if [ "$LENZ_ENABLE_TUNNEL" = "1" ]; then
        if [ -f "$TUNNEL_FILE" ]; then
            TUNNEL_URL=$(cat "$TUNNEL_FILE" 2>/dev/null | tr -d ' \r\n')
        fi
        if [ -z "$TUNNEL_URL" ] && [ -f "$TUNNEL_LOG" ]; then
            TUNNEL_URL=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | tail -n 1)
        fi
    fi

    echo -e "  ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Local:${NC}    http://127.0.0.1:${PANEL_PORT:-8080}/"
    echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Network:${NC}  http://${LOCAL_IP}:${PANEL_PORT:-8080}/"
    if [ "$LENZ_ENABLE_TUNNEL" = "1" ]; then
        if [ -n "$TUNNEL_URL" ]; then
            echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Public:${NC}   ${GREEN}${TUNNEL_URL}${NC}"
        else
            echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Public:${NC}   ${YELLOW}Menghubungkan tunnel... (cek './start.sh status')${NC}"
        fi
    else
        echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Public:${NC}   ${DIM}Dinonaktifkan (Mode Lokal)${NC}"
    fi
    echo -e "  ${CYAN}╰─ Ready ─────────────────────────────────${NC}\n"

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

    TUNNEL_URL=""
    if [ -f "$TUNNEL_FILE" ]; then
        TUNNEL_URL=$(cat "$TUNNEL_FILE" 2>/dev/null | tr -d ' \r\n')
    fi
    if [ -z "$TUNNEL_URL" ] && [ -f "$TUNNEL_LOG" ]; then
        TUNNEL_URL=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | tail -n 1)
    fi

    echo -e "  ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Local:${NC}    http://127.0.0.1:${PANEL_PORT:-8080}/"
    echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Network:${NC}  http://${LOCAL_IP}:${PANEL_PORT:-8080}/"
    if [ -n "$TUNNEL_URL" ]; then
        echo -e "  ${CYAN}│${NC}  ${CYAN}➜${NC}  ${BOLD}Public:${NC}   ${GREEN}${TUNNEL_URL}${NC}"
    fi
    if is_port_active "${PANEL_PORT:-8080}" || is_port_active 2222; then
        echo -e "  ${CYAN}╰─ Active ────────────────────────────────${NC}\n"
    else
        echo -e "  ${CYAN}╰─ Inactive ──────────────────────────────${NC}\n"
    fi
}

case "$1" in
    update)
        echo ""
        echo -e "  ${CYAN}╭─${NC} ${BOLD}LenzNode Update${NC} ${CYAN}───────────────────────${NC}"
        check_and_apply_update "force"
        echo -e "  ${CYAN}╰───────────────────────────────────────────${NC}\n"
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
