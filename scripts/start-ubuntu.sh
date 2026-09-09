#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Script Peluncur Terminal Distro Linux Ubuntu VPS (PRoot) — Lenz Mini Server
# Author / Developer: Lenz
# ==============================================================================

# Inisialisasi Environment Termux (Kompatibel Root/su & Non-Root)
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
[ -z "$HOME" ] || [ "$HOME" = "/" ] || [ "$HOME" = "/root" ] && [ -d "/data/data/com.termux/files/home" ] && export HOME="/data/data/com.termux/files/home"
export PATH="/data/data/com.termux/files/usr/bin:$PREFIX/bin:$PREFIX/bin/applets:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
[ -d "$PREFIX/lib" ] && export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

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
