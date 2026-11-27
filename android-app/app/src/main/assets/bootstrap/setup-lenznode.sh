#!/bin/sh
# ==============================================================================
# LenzNode Android APK — Minimal Ubuntu 22.04 PRoot Bootstrap Setup
# Installs ONLY LenzNode's minimal required runtime dependencies so users can
# freely install Python, PHP, Docker/tools, etc. via `apt` in Web/SSH Terminal.
# ==============================================================================
set -e

emit_progress() {
  printf '[PROGRESS:%s] %s\n' "$1" "$2"
}

log_info() {
  printf '[INFO] %s\n' "$1"
}

log_warn() {
  printf '[WARN] %s\n' "$1"
}

log_err() {
  printf '[ERROR] %s\n' "$1" >&2
}

emit_progress 05 "Detecting CPU architecture and runtime binaries..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="${FILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
NATIVE_LIB_DIR="${NATIVE_LIB_DIR:-}"
ROOTFS_DIR="$FILES_DIR/rootfs"
BUNDLE_DIR="$FILES_DIR/lenznode-bundle"
TMP_DIR="$FILES_DIR/tmp"
CACHE_DIR="$FILES_DIR/cache"
SSH_PORT="${SSH_PORT:-2222}"
SSH_PASS="${LENZ_SSH_PASS:-admin123}"

mkdir -p "$TMP_DIR" "$CACHE_DIR"

export PROOT_TMP_DIR="${PROOT_TMP_DIR:-$TMP_DIR}"
if [ -n "$NATIVE_LIB_DIR" ]; then
  export LD_LIBRARY_PATH="$NATIVE_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# Locate proot & busybox
PROOT_BIN=""
if [ -n "$NATIVE_LIB_DIR" ] && [ -x "$NATIVE_LIB_DIR/libproot.so" ]; then
  PROOT_BIN="$NATIVE_LIB_DIR/libproot.so"
elif command -v proot >/dev/null 2>&1; then
  PROOT_BIN="$(command -v proot)"
fi

if [ -z "$PROOT_BIN" ]; then
  log_err "PRoot binary not found (checked NATIVE_LIB_DIR=$NATIVE_LIB_DIR and PATH)"
  exit 1
fi

if [ -z "$PROOT_LOADER" ] && [ -n "$NATIVE_LIB_DIR" ] && [ -x "$NATIVE_LIB_DIR/libproot-loader.so" ]; then
  export PROOT_LOADER="$NATIVE_LIB_DIR/libproot-loader.so"
fi

BUSYBOX_BIN=""
if [ -n "$NATIVE_LIB_DIR" ] && [ -x "$NATIVE_LIB_DIR/libbusybox.so" ]; then
  BB_DIR="$FILES_DIR/bin"
  mkdir -p "$BB_DIR"
  ln -sf "$NATIVE_LIB_DIR/libbusybox.so" "$BB_DIR/busybox" 2>/dev/null || true
  if [ -x "$BB_DIR/busybox" ] && "$BB_DIR/busybox" true >/dev/null 2>&1; then
    BUSYBOX_BIN="$BB_DIR/busybox"
  fi
elif command -v busybox >/dev/null 2>&1 && busybox true >/dev/null 2>&1; then
  BUSYBOX_BIN="$(command -v busybox)"
fi

# Detect CPU ABI -> Ubuntu/Node/Cloudflared arch mapping
RAW_ARCH="${LENZ_ARCH:-$(uname -m)}"
case "$RAW_ARCH" in
  aarch64|arm64|arm64-v8a)
    ARCH="arm64"
    NODE_ARCH="arm64"
    CF_ARCH="arm64"
    ;;
  armv7l|armv8l|armhf|armeabi-v7a|arm*)
    ARCH="armhf"
    NODE_ARCH="armv7l"
    CF_ARCH="arm"
    ;;
  x86_64|amd64)
    ARCH="amd64"
    NODE_ARCH="x64"
    CF_ARCH="amd64"
    ;;
  *)
    log_err "Unsupported CPU architecture: $RAW_ARCH"
    exit 1
    ;;
esac

log_info "Detected architecture: raw=$RAW_ARCH -> ubuntu=$ARCH, node=$NODE_ARCH, cloudflared=$CF_ARCH"

download_file() {
  _url="$1"
  _dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 20 --retry 2 -o "$_dest" "$_url" && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$_dest" "$_url" && return 0
  fi
  if [ -n "$BUSYBOX_BIN" ]; then
    "$BUSYBOX_BIN" wget -q -O "$_dest" "$_url" 2>/dev/null && return 0
  fi
  return 1
}

# Helper to execute commands inside PRoot
run_proot() {
  _sd_bind=""
  if [ -d "/sdcard" ] && [ -r "/sdcard" ]; then
    _sd_bind="-b /sdcard"
  fi
  # shellcheck disable=SC2086
  "$PROOT_BIN" \
    --link2symlink \
    -0 \
    -r "$ROOTFS_DIR" \
    -b /dev \
    -b /proc \
    -b /sys \
    -b "$ROOTFS_DIR/tmp:/dev/shm" \
    -b "$FILES_DIR:$FILES_DIR" \
    $_sd_bind \
    -w /root \
    /usr/bin/env -i \
    HOME=/root \
    USER=root \
    TERM=xterm-256color \
    LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$@"
}

# 1. Install minimal Ubuntu 22.04 rootfs if not present
emit_progress 10 "Checking minimal Ubuntu 22.04 rootfs ($ARCH)..."

if [ ! -x "$ROOTFS_DIR/bin/bash" ] || [ ! -f "$ROOTFS_DIR/etc/os-release" ]; then
  ROOTFS_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.5-base-${ARCH}.tar.gz"
  TARBALL=""

  if [ -n "$ROOTFS_TARBALL" ] && [ -s "$ROOTFS_TARBALL" ]; then
    TARBALL="$ROOTFS_TARBALL"
    emit_progress 20 "Using pre-downloaded Ubuntu rootfs archive..."
  elif [ -s "$TMP_DIR/ubuntu-base.tar.gz" ]; then
    TARBALL="$TMP_DIR/ubuntu-base.tar.gz"
    emit_progress 20 "Using cached Ubuntu rootfs archive..."
  elif [ -s "$CACHE_DIR/ubuntu-base-22.04.5-base-${ARCH}.tar.gz" ]; then
    TARBALL="$CACHE_DIR/ubuntu-base-22.04.5-base-${ARCH}.tar.gz"
    emit_progress 20 "Using local Ubuntu rootfs archive..."
  else
    TARBALL="$TMP_DIR/ubuntu-base.tar.gz"
    emit_progress 15 "Downloading Ubuntu 22.04 Base rootfs ($ARCH)..."
    if ! download_file "$ROOTFS_URL" "$TARBALL"; then
      rm -f "$TARBALL" 2>/dev/null || true
      log_err "Failed to download Ubuntu Base rootfs from $ROOTFS_URL"
      exit 1
    fi
  fi

  emit_progress 25 "Extracting minimal Ubuntu rootfs..."
  mkdir -p "$ROOTFS_DIR"

  EXTRACTED=0
  if command -v tar >/dev/null 2>&1; then
    SYS_TAR="$(command -v tar)"
    if "$PROOT_BIN" --link2symlink -0 "$SYS_TAR" -xzf "$TARBALL" -C "$ROOTFS_DIR" --exclude='dev/*' --exclude='./dev/*' 2>&1; then
      EXTRACTED=1
    elif "$SYS_TAR" -xzf "$TARBALL" -C "$ROOTFS_DIR" --exclude='dev/*' --exclude='./dev/*' --no-same-owner 2>&1; then
      EXTRACTED=1
    elif "$SYS_TAR" -xzf "$TARBALL" -C "$ROOTFS_DIR" --exclude='dev/*' --exclude='./dev/*' 2>&1; then
      EXTRACTED=1
    fi
  fi

  if [ "$EXTRACTED" = "0" ] && [ -n "$BUSYBOX_BIN" ]; then
    if "$PROOT_BIN" --link2symlink -0 "$BUSYBOX_BIN" tar -xzf "$TARBALL" -C "$ROOTFS_DIR" --exclude='dev/*' --exclude='./dev/*' 2>&1; then
      EXTRACTED=1
    elif "$PROOT_BIN" --link2symlink -0 "$BUSYBOX_BIN" tar -xzf "$TARBALL" -C "$ROOTFS_DIR" 2>&1; then
      EXTRACTED=1
    elif "$BUSYBOX_BIN" tar -xzf "$TARBALL" -C "$ROOTFS_DIR" --exclude='dev/*' --exclude='./dev/*' 2>&1; then
      EXTRACTED=1
    fi
  fi

  if [ "$EXTRACTED" = "0" ] || [ ! -x "$ROOTFS_DIR/bin/bash" ]; then
    log_err "Failed to extract Ubuntu rootfs tarball ($TARBALL)"
    exit 1
  fi

  # Clean up temporary download to save storage
  if [ "$TARBALL" = "$TMP_DIR/ubuntu-base.tar.gz" ]; then
    rm -f "$TARBALL" 2>/dev/null || true
  fi
else
  emit_progress 25 "Existing Ubuntu rootfs detected, verifying configuration..."
fi

# 2. Configure DNS, essential directories, PRoot APT fixes & /root/.bashrc
emit_progress 35 "Configuring DNS, PRoot APT sandbox, and shell profile..."

mkdir -p \
  "$ROOTFS_DIR/dev" \
  "$ROOTFS_DIR/proc" \
  "$ROOTFS_DIR/sys" \
  "$ROOTFS_DIR/tmp" \
  "$ROOTFS_DIR/root" \
  "$ROOTFS_DIR/root/workspace" \
  "$ROOTFS_DIR/root/LenzNode" \
  "$ROOTFS_DIR/run/sshd" \
  "$ROOTFS_DIR/etc/apt/apt.conf.d" \
  "$ROOTFS_DIR/usr/sbin"
chmod 1777 "$ROOTFS_DIR/tmp" 2>/dev/null || true

# DNS servers (remove systemd-resolved symlink if present)
rm -f "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null || true
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$ROOTFS_DIR/etc/resolv.conf"

if [ ! -f "$ROOTFS_DIR/etc/hosts" ]; then
  printf '127.0.0.1 localhost\n::1 localhost\n' > "$ROOTFS_DIR/etc/hosts"
fi

# PRoot compatibility fixes for apt-get / dpkg
printf 'APT::Sandbox::User "root";\n' > "$ROOTFS_DIR/etc/apt/apt.conf.d/01-android-proot"
printf '#!/bin/sh\nexit 101\n' > "$ROOTFS_DIR/usr/sbin/policy-rc.d"
chmod 755 "$ROOTFS_DIR/usr/sbin/policy-rc.d" 2>/dev/null || true

# Clean minimal /root/.bashrc
cat > "$ROOTFS_DIR/root/.bashrc" << 'EOF'
# LenzNode Minimal Ubuntu PRoot Shell Profile
export HOME=/root
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export DEBIAN_FRONTEND=noninteractive
export NODE_OPTIONS="--max-old-space-size=128"
export INITIAL_PASSWORD="${INITIAL_PASSWORD:-123456}"
export PS1='\[\e[1;36m\]root@lenznode\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]# '
alias ll='ls -la'
if [ -f /root/LenzNode/panel/server.js ]; then
  alias lenz-dir='cd /root/LenzNode'
fi
mkdir -p "$HOME/workspace" 2>/dev/null || true
if [ "$PWD" = "$HOME" ] && [ -d "$HOME/workspace" ]; then
  cd "$HOME/workspace"
fi
EOF

# 3. Install ONLY LenzNode's minimal required system dependencies
NEED_APT_INSTALL=0
if [ "$FORCE_REINSTALL" = "1" ]; then
  NEED_APT_INSTALL=1
elif ! run_proot /bin/sh -c 'command -v curl >/dev/null 2>&1 && command -v git >/dev/null 2>&1 && [ -x /usr/sbin/sshd ] && command -v pgrep >/dev/null 2>&1 && command -v xz >/dev/null 2>&1'; then
  NEED_APT_INSTALL=1
fi

if [ "$NEED_APT_INSTALL" = "1" ]; then
  emit_progress 45 "Updating apt package index..."
  run_proot /bin/sh -c 'apt-get update -y'

  emit_progress 55 "Installing minimal core packages (ssh, curl, git, ca-certificates)..."
  run_proot /bin/sh -c 'apt-get install -y --no-install-recommends ca-certificates curl git openssh-server procps psmisc xz-utils && apt-get clean && rm -rf /var/lib/apt/lists/*'
else
  emit_progress 60 "Core system dependencies already installed."
fi

# 4. Install Node.js LTS binary (v20.x supports both arm64 and armv7l officially)
NEED_NODE=0
if ! run_proot /bin/sh -c 'command -v node >/dev/null 2>&1'; then
  NEED_NODE=1
else
  NODE_MAJOR="$(run_proot /bin/sh -c 'node -v 2>/dev/null | sed "s/^v//;s/\..*//"')"
  if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 18 ] 2>/dev/null; then
    NEED_NODE=1
  fi
fi

if [ "$NEED_NODE" = "1" ]; then
  emit_progress 70 "Installing Node.js LTS runtime ($NODE_ARCH)..."
  run_proot /bin/sh -c "
    set -e
    NODE_TAR=\"\$(curl -fsSL --connect-timeout 15 https://nodejs.org/dist/latest-v20.x/SHASUMS256.txt 2>/dev/null | grep \"linux-${NODE_ARCH}\\.tar\\.xz\" | head -n 1 | awk '{print \$2}')\"
    if [ -n \"\$NODE_TAR\" ]; then
      NODE_URL=\"https://nodejs.org/dist/latest-v20.x/\$NODE_TAR\"
    else
      NODE_URL=\"https://nodejs.org/dist/v20.18.1/node-v20.18.1-linux-${NODE_ARCH}.tar.xz\"
    fi
    curl -fsSL --connect-timeout 20 --retry 2 \"\$NODE_URL\" -o /tmp/node-lts.tar.xz
    tar -xJf /tmp/node-lts.tar.xz -C /usr/local --strip-components=1 --no-same-owner
    rm -f /tmp/node-lts.tar.xz
    node -v
  "
else
  emit_progress 75 "Node.js LTS already installed."
fi

# 5. Install cloudflared binary
if ! run_proot /bin/sh -c '[ -x /usr/local/bin/cloudflared ] || command -v cloudflared >/dev/null 2>&1'; then
  emit_progress 82 "Installing cloudflared tunnel binary ($CF_ARCH)..."
  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
  if ! run_proot /bin/sh -c "curl -fsSL --connect-timeout 20 --retry 2 '$CF_URL' -o /usr/local/bin/cloudflared && chmod 755 /usr/local/bin/cloudflared"; then
    log_warn "cloudflared download failed (tunnel optional; local server will still run)"
    run_proot /bin/sh -c 'rm -f /usr/local/bin/cloudflared' 2>/dev/null || true
  fi
else
  emit_progress 84 "cloudflared binary already present."
fi

# 6. Configure OpenSSH Server inside PRoot (Port 2222)
emit_progress 88 "Configuring OpenSSH Server (port $SSH_PORT)..."
run_proot /usr/bin/env LENZ_SSH_PASS="$SSH_PASS" /bin/sh -c "
  set -e
  mkdir -p /etc/ssh /run/sshd /var/run/sshd
  chmod 700 /etc/ssh
  if [ ! -s /etc/ssh/ssh_host_rsa_key ] || [ ! -s /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A >/dev/null 2>&1 || true
  fi
  chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
  chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true
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
  chmod 600 /etc/ssh/sshd_config
  printf 'root:%s\n' \"\$LENZ_SSH_PASS\" | chpasswd 2>/dev/null || true
"

# 7. Copy bundled LenzNode server runtime files into /root/LenzNode
emit_progress 93 "Deploying LenzNode server files to /root/LenzNode..."

TARGET_APP_DIR="$ROOTFS_DIR/root/LenzNode"
mkdir -p "$TARGET_APP_DIR/logs" "$TARGET_APP_DIR/panel" "$TARGET_APP_DIR/apps" "$TARGET_APP_DIR/scripts"

SHOULD_COPY_BUNDLE=1
if [ "$FORCE_REINSTALL" != "1" ] && [ -f "$TARGET_APP_DIR/panel/server.js" ] && [ -f "$TARGET_APP_DIR/version.json" ] && [ -f "$BUNDLE_DIR/version.json" ]; then
  SHOULD_COPY_BUNDLE="$(run_proot /bin/sh -c "node -e '
    const fs = require(\"fs\");
    const cmp = (a, b) => {
      const pa = String(a||\"0\").replace(/^v/,\"\").split(\".\").map(n=>parseInt(n,10)||0);
      const pb = String(b||\"0\").replace(/^v/,\"\").split(\".\").map(n=>parseInt(n,10)||0);
      for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        if ((pa[i]||0) > (pb[i]||0)) return 1;
        if ((pa[i]||0) < (pb[i]||0)) return -1;
      }
      return 0;
    };
    try {
      const cur = JSON.parse(fs.readFileSync(\"/root/LenzNode/version.json\", \"utf8\")).version;
      const bnd = JSON.parse(fs.readFileSync(\"$BUNDLE_DIR/version.json\", \"utf8\")).version;
      process.stdout.write(cmp(bnd, cur) > 0 ? \"1\" : \"0\");
    } catch (_) { process.stdout.write(\"1\"); }
  '" 2>/dev/null || echo 1)"
fi

if [ "$SHOULD_COPY_BUNDLE" = "0" ]; then
  emit_progress 95 "Preserving existing/OTA-updated /root/LenzNode runtime..."
elif [ -d "$BUNDLE_DIR" ]; then
  # Preserve user runtime configs if upgrading/re-extracting
  for cfg in auth-config.json vps-config.json sessions.json state.json shares.json root-config.json; do
    if [ -f "$TARGET_APP_DIR/panel/$cfg" ]; then
      cp -f "$TARGET_APP_DIR/panel/$cfg" "$TMP_DIR/.keep-$cfg" 2>/dev/null || true
    fi
  done

  if [ -d "$BUNDLE_DIR/panel" ]; then
    cp -rf "$BUNDLE_DIR/panel/." "$TARGET_APP_DIR/panel/"
  fi
  if [ -d "$BUNDLE_DIR/apps" ]; then
    cp -rf "$BUNDLE_DIR/apps/." "$TARGET_APP_DIR/apps/"
  fi
  if [ -d "$BUNDLE_DIR/scripts" ]; then
    cp -rf "$BUNDLE_DIR/scripts/." "$TARGET_APP_DIR/scripts/"
  fi
  [ -f "$BUNDLE_DIR/version.json" ] && cp -f "$BUNDLE_DIR/version.json" "$TARGET_APP_DIR/version.json"
  [ -f "$BUNDLE_DIR/CHANGELOG.md" ] && cp -f "$BUNDLE_DIR/CHANGELOG.md" "$TARGET_APP_DIR/CHANGELOG.md"

  for cfg in auth-config.json vps-config.json sessions.json state.json shares.json root-config.json; do
    if [ -f "$TMP_DIR/.keep-$cfg" ]; then
      mv -f "$TMP_DIR/.keep-$cfg" "$TARGET_APP_DIR/panel/$cfg" 2>/dev/null || true
    fi
  done

  chmod +x "$TARGET_APP_DIR/scripts/"*.sh "$TARGET_APP_DIR/apps/"*/*.sh 2>/dev/null || true
else
  log_warn "Bundle directory not found at $BUNDLE_DIR"
fi

if [ ! -f "$TARGET_APP_DIR/panel/server.js" ]; then
  log_err "LenzNode panel/server.js missing in $TARGET_APP_DIR/panel"
  exit 1
fi

date '+%Y-%m-%dT%H:%M:%S' > "$ROOTFS_DIR/root/.lenznode-ready" 2>/dev/null || touch "$ROOTFS_DIR/root/.lenznode-ready"

emit_progress 100 "LenzNode Linux environment ready!"
