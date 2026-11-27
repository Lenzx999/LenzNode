#!/bin/sh
# ==============================================================================
# LenzNode Android APK — PRoot Service Launcher (SSHD + LenzNode Panel)
# Starts OpenSSH (port 2222) and Node.js panel/server.js inside Ubuntu PRoot
# and keeps both alive cleanly until stopped by Android Foreground Service.
# ==============================================================================
set -e

if [ -z "$LENZ_IN_PROOT" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  FILES_DIR="${FILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
  NATIVE_LIB_DIR="${NATIVE_LIB_DIR:-}"
  ROOTFS_DIR="$FILES_DIR/rootfs"
  TMP_DIR="$FILES_DIR/tmp"

  mkdir -p "$TMP_DIR"
  export PROOT_TMP_DIR="${PROOT_TMP_DIR:-$TMP_DIR}"
  if [ -n "$NATIVE_LIB_DIR" ]; then
    export LD_LIBRARY_PATH="$NATIVE_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi

  PROOT_BIN=""
  if [ -n "$NATIVE_LIB_DIR" ] && [ -x "$NATIVE_LIB_DIR/libproot.so" ]; then
    PROOT_BIN="$NATIVE_LIB_DIR/libproot.so"
  elif command -v proot >/dev/null 2>&1; then
    PROOT_BIN="$(command -v proot)"
  fi

  if [ -z "$PROOT_BIN" ]; then
    printf '[ERROR] PRoot binary not found (NATIVE_LIB_DIR=%s)\n' "$NATIVE_LIB_DIR" >&2
    exit 1
  fi

  if [ -z "$PROOT_LOADER" ] && [ -n "$NATIVE_LIB_DIR" ] && [ -x "$NATIVE_LIB_DIR/libproot-loader.so" ]; then
    export PROOT_LOADER="$NATIVE_LIB_DIR/libproot-loader.so"
  fi

  # Ensure bootstrap has completed
  if [ ! -x "$ROOTFS_DIR/bin/bash" ] || [ ! -f "$ROOTFS_DIR/root/LenzNode/panel/server.js" ]; then
    if [ -f "$SCRIPT_DIR/setup-lenznode.sh" ]; then
      sh "$SCRIPT_DIR/setup-lenznode.sh"
    else
      printf '[ERROR] Rootfs or LenzNode runtime missing and setup-lenznode.sh not found\n' >&2
      exit 1
    fi
  fi

  # Clean stale proot/node processes before launching a fresh session
  for _pf in "$TMP_DIR/lenz-node.pid" "$TMP_DIR/lenz-proot.pid"; do
    if [ -f "$_pf" ]; then
      _old_pid="$(cat "$_pf" 2>/dev/null || true)"
      if [ -n "$_old_pid" ] && [ "$_old_pid" != "$$" ]; then
        kill -TERM "$_old_pid" 2>/dev/null || true
        sleep 0.2
        kill -KILL "$_old_pid" 2>/dev/null || true
      fi
      rm -f "$_pf" 2>/dev/null || true
    fi
  done

  printf '%s\n' "$$" > "$TMP_DIR/lenz-proot.pid" 2>/dev/null || true

  # Keep DNS valid on each launch
  rm -f "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null || true
  printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$ROOTFS_DIR/etc/resolv.conf"

  SELF_PATH="$SCRIPT_DIR/$(basename "$0")"
  SD_BIND=""
  if [ -d "/sdcard" ] && [ -r "/sdcard" ]; then
    SD_BIND="-b /sdcard"
  fi

  # shellcheck disable=SC2086
  exec "$PROOT_BIN" \
    --link2symlink \
    -0 \
    -r "$ROOTFS_DIR" \
    -b /dev \
    -b /proc \
    -b /sys \
    -b "$ROOTFS_DIR/tmp:/dev/shm" \
    -b "$FILES_DIR:$FILES_DIR" \
    $SD_BIND \
    -w /root/LenzNode/panel \
    /usr/bin/env -i \
    HOME=/root \
    USER=root \
    TERM=xterm-256color \
    LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    FILES_DIR="$FILES_DIR" \
    LENZ_IN_PROOT=1 \
    LENZ_SUPERVISED=1 \
    LENZ_APP_MODE="${LENZ_APP_MODE:-android-apk}" \
    LENZ_BRIDGE_URL="${LENZ_BRIDGE_URL:-http://127.0.0.1:48080}" \
    PANEL_PORT="${PANEL_PORT:-8080}" \
    SSH_PORT="${SSH_PORT:-2222}" \
    LENZ_SSH_PASS="${LENZ_SSH_PASS:-admin123}" \
    LENZ_ENABLE_TUNNEL="${LENZ_ENABLE_TUNNEL:-1}" \
    INITIAL_PASSWORD="${INITIAL_PASSWORD:-123456}" \
    NODE_OPTIONS="--max-old-space-size=128" \
    /bin/bash "$SELF_PATH"
fi

# ------------------------------------------------------------------------------
# Inside PRoot Ubuntu Environment (LENZ_IN_PROOT=1)
# ------------------------------------------------------------------------------
export HOME=/root
export USER=root
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

PANEL_DIR="/root/LenzNode/panel"
LOG_DIR="/root/LenzNode/logs"
TMP_PID_DIR="${FILES_DIR:-/tmp}/tmp"
NODE_PID_FILE="$TMP_PID_DIR/lenz-node.pid"
PROOT_PID_FILE="$TMP_PID_DIR/lenz-proot.pid"
SSH_PORT="${SSH_PORT:-2222}"
PANEL_PORT="${PANEL_PORT:-8080}"

mkdir -p "$LOG_DIR" "$TMP_PID_DIR" /etc/ssh /run/sshd /var/run/sshd
printf '%s\n' "$$" > "$PROOT_PID_FILE" 2>/dev/null || true

configure_and_start_sshd() {
  if [ ! -x /usr/sbin/sshd ]; then
    printf '[WARN] /usr/sbin/sshd not found, skipping SSH server\n'
    return 0
  fi

  chmod 700 /etc/ssh 2>/dev/null || true
  if [ ! -s /etc/ssh/ssh_host_rsa_key ] || [ ! -s /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A >/dev/null 2>&1 || true
  fi
  chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
  chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true

  if [ ! -f /etc/ssh/sshd_config ] || ! grep -q "^Port ${SSH_PORT}$" /etc/ssh/sshd_config 2>/dev/null || ! grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
    cat > /etc/ssh/sshd_config << SSHEOF
Port ${SSH_PORT}
ListenAddress 0.0.0.0
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
PermitRootLogin yes
UsePAM no
PrintMotd yes
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF
    chmod 600 /etc/ssh/sshd_config 2>/dev/null || true
  fi

  # Sync root SSH password from auth-config.json (or default admin123)
  TARGET_PASS="${LENZ_SSH_PASS:-admin123}"
  if [ -f "$PANEL_DIR/auth-config.json" ] && command -v node >/dev/null 2>&1; then
    CFG_PASS="$(node -e "try{const d=JSON.parse(require('fs').readFileSync('$PANEL_DIR/auth-config.json','utf8'));if(d&&d.password)process.stdout.write(String(d.password));}catch(_){}" 2>/dev/null || true)"
    [ -n "$CFG_PASS" ] && TARGET_PASS="$CFG_PASS"
  fi
  printf 'root:%s\n' "$TARGET_PASS" | chpasswd 2>/dev/null || true

  # Check if sshd is already listening
  if command -v node >/dev/null 2>&1; then
    if node -e "const n=require('net'),s=n.connect(${SSH_PORT},'127.0.0.1',()=>{s.destroy();process.exit(0)});s.on('error',()=>process.exit(1));" >/dev/null 2>&1; then
      return 0
    fi
  fi

  rm -f /run/sshd.pid /var/run/sshd.pid 2>/dev/null || true
  pkill -f "sshd.*${SSH_PORT}" 2>/dev/null || true
  /usr/sbin/sshd -p "$SSH_PORT" -E "$LOG_DIR/ssh.log" 2>/dev/null || /usr/sbin/sshd -p "$SSH_PORT" 2>/dev/null || true
}

STOP_REQUESTED=0
NODE_PID=""

cleanup_and_exit() {
  STOP_REQUESTED=1
  if [ -n "$NODE_PID" ] && kill -0 "$NODE_PID" 2>/dev/null; then
    kill -TERM "$NODE_PID" 2>/dev/null || true
    sleep 1
    kill -KILL "$NODE_PID" 2>/dev/null || true
  fi
  rm -f "$NODE_PID_FILE" "$PROOT_PID_FILE" 2>/dev/null || true
  pkill -f "sshd.*${SSH_PORT}" 2>/dev/null || true
  pkill -f "cloudflared.*tunnel" 2>/dev/null || true
  exit 0
}

trap cleanup_and_exit TERM INT QUIT

printf '[PROGRESS:95] Starting OpenSSH Server (port %s)...\n' "$SSH_PORT"
configure_and_start_sshd

printf '[PROGRESS:98] Starting LenzNode Panel (port %s)...\n' "$PANEL_PORT"

cd "$PANEL_DIR" || exit 1

cap_stdout_log() {
  _lfile="$LOG_DIR/panel-stdout.log"
  if [ -f "$_lfile" ]; then
    _sz="$(wc -c < "$_lfile" 2>/dev/null || echo 0)"
    if [ "$_sz" -gt 1048576 ] 2>/dev/null; then
      tail -c 65536 "$_lfile" > "$_lfile.tmp" 2>/dev/null && mv -f "$_lfile.tmp" "$_lfile" 2>/dev/null || true
    fi
  fi
}

while [ "$STOP_REQUESTED" = "0" ]; do
  rm -f "$PANEL_DIR/.restart-requested" 2>/dev/null || true
  cap_stdout_log
  node --max-old-space-size=128 "$PANEL_DIR/server.js" </dev/null >> "$LOG_DIR/panel-stdout.log" 2>&1 &
  NODE_PID=$!
  printf '%s\n' "$NODE_PID" > "$NODE_PID_FILE" 2>/dev/null || true

  set +e
  wait "$NODE_PID"
  EXIT_CODE=$?
  set -e
  NODE_PID=""
  rm -f "$NODE_PID_FILE" 2>/dev/null || true

  if [ "$STOP_REQUESTED" = "1" ]; then
    break
  fi

  if [ "$EXIT_CODE" = "42" ] || [ -f "$PANEL_DIR/.restart-requested" ]; then
    rm -f "$PANEL_DIR/.restart-requested" 2>/dev/null || true
    printf '[INFO] LenzNode panel restart requested, restarting...\n'
    sleep 1
    configure_and_start_sshd
    continue
  fi

  printf '[WARN] LenzNode panel exited with code %s; restarting in 2s...\n' "$EXIT_CODE"
  sleep 2
  configure_and_start_sshd
done
