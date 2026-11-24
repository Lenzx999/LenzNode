#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# LenzNode — Pengelola Layanan 9Router AI Gateway (Port 20128)
# ==============================================================================

DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROUTER_DIR="$DIR/apps/9router"
LOG_DIR="$DIR/logs"
mkdir -p "$LOG_DIR"
ROUTER_LOG="$LOG_DIR/9router.log"
PID_FILE="$ROUTER_DIR/9router.pid"
PORT=20128

get_local_ip() {
    local ip=""
    if command -v node >/dev/null 2>&1; then
        ip=$(node -e "const os=require('os'),i=os.networkInterfaces();let r='';for(const k in i){for(const x of i[k]){if(x.family==='IPv4'&&!x.internal){r=x.address;break;}}if(r)break;}console.log(r);" 2>/dev/null)
    fi
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    fi
    [ -z "$ip" ] && ip="127.0.0.1"
    echo "$ip"
}

is_port_active() {
    local p="$1"
    if command -v node >/dev/null 2>&1; then
        node -e "const net=require('net'),s=net.connect(${p},'127.0.0.1',()=>{s.destroy();process.exit(0)});s.on('error',()=>process.exit(1));s.on('timeout',()=>process.exit(1));s.setTimeout(1000);" >/dev/null 2>&1 && return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -s -m 1 "http://127.0.0.1:${p}/" >/dev/null 2>&1 && return 0
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -q ":${p}[[:space:]]" && return 0
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -q ":${p}[[:space:]]" && return 0
    fi
    return 1
}

is_running() {
    is_port_active "$PORT" && return 0
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

start_router() {
    if is_running; then
        echo ">> 9Router sudah aktif berjalan di port $PORT."
        echo ">> Kunjungi: http://$(get_local_ip):$PORT"
        return 0
    fi

    local CLI="$ROUTER_DIR/node_modules/9router/cli.js"
    if [ ! -f "$CLI" ]; then
        if command -v 9router >/dev/null 2>&1; then
            CLI="$(command -v 9router)"
        else
            echo ">> Error: 9Router belum terpasang. Pasang melalui Web Panel LenzNode atau jalankan: cd '$ROUTER_DIR' && npm install 9router"
            return 1
        fi
    fi

    echo ">> Memulai layanan 9Router di port $PORT..."
    mkdir -p "$ROUTER_DIR"
    
    export INITIAL_PASSWORD="${INITIAL_PASSWORD:-123456}"
    export PORT=$PORT
    export HOSTNAME="0.0.0.0"
    export NO_BROWSER="true"
    NODE_OPTIONS="--max-old-space-size=128" INITIAL_PASSWORD="$INITIAL_PASSWORD" PORT=$PORT HOSTNAME="0.0.0.0" NO_BROWSER=true nohup node "$CLI" --port $PORT -H 0.0.0.0 --skip-update --no-browser >> "$ROUTER_LOG" 2>&1 &
    local BG_PID=$!
    echo "$BG_PID" > "$PID_FILE"

    for i in {1..30}; do
        sleep 0.5
        if is_running; then
            echo ">> 9Router BERHASIL AKTIF (PID: $BG_PID)!"
            echo ">> URL Akses: http://$(get_local_ip):$PORT"
            return 0
        fi
    done

    echo ">> 9Router gagal merespons di port $PORT (PID: $BG_PID). Memeriksa log..."
    tail -n 15 "$ROUTER_LOG" 2>/dev/null || true
    return 1
}

stop_router() {
    echo ">> Menghentikan layanan 9Router..."
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$PID" ] && kill -9 "$PID" 2>/dev/null || true
        rm -f "$PID_FILE" 2>/dev/null || true
    fi

    # Bersihkan PID dari ~/.9router/launcher.pid jika ada
    local LAUNCHER_PID="$HOME/.9router/launcher.pid"
    [ ! -f "$LAUNCHER_PID" ] && [ -d "/data/data/com.termux/files/home/.9router" ] && LAUNCHER_PID="/data/data/com.termux/files/home/.9router/launcher.pid"
    if [ -f "$LAUNCHER_PID" ]; then
        local S_PID=$(grep -o '"serverPid":[0-9]*' "$LAUNCHER_PID" 2>/dev/null | cut -d: -f2)
        local C_PID=$(grep -o '"cliPid":[0-9]*' "$LAUNCHER_PID" 2>/dev/null | cut -d: -f2)
        [ -n "$S_PID" ] && kill -9 "$S_PID" 2>/dev/null || true
        [ -n "$C_PID" ] && kill -9 "$C_PID" 2>/dev/null || true
        rm -f "$LAUNCHER_PID" 2>/dev/null || true
    fi

    pkill -9 -f "custom-server.js" 2>/dev/null || true
    pkill -9 -f "9router" 2>/dev/null || true
    if command -v fuser >/dev/null 2>&1; then
        fuser -k -9 $PORT/tcp 2>/dev/null || true
    fi
    if command -v lsof >/dev/null 2>&1; then
        lsof -ti :$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
    fi

    for i in {1..15}; do
        sleep 0.2
        if ! is_running; then
            break
        fi
    done
    if is_running; then
        echo ">> Peringatan: 9Router masih berjalan di port $PORT."
        return 1
    else
        echo ">> 9Router berhasil dihentikan."
        return 0
    fi
}

delete_router() {
    echo ">> Menghapus 9Router dari server..."
    stop_router
    if [ -d "$ROUTER_DIR" ]; then
        rm -rf "$ROUTER_DIR"
    fi
    mkdir -p "$DIR/apps"
    touch "$DIR/apps/.gitkeep"
    echo ">> Berkas instalasi 9Router berhasil dihapus."
}

status_router() {
    if is_running; then
        echo ">> 9Router: AKTIF (Online)"
        echo ">> Port: $PORT"
        echo ">> URL Akses: http://$(get_local_ip):$PORT"
    else
        echo ">> 9Router: BERHENTI (Offline)"
    fi
}

case "$1" in
    start)
        start_router
        ;;
    stop)
        stop_router
        ;;
    restart)
        stop_router
        sleep 1
        start_router
        ;;
    delete|hapus)
        delete_router
        ;;
    status)
        status_router
        ;;
    *)
        echo "Penggunaan: $0 {start|stop|restart|status|delete}"
        exit 1
        ;;
esac

