#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Script Peluncur Terminal Distro Linux Ubuntu VPS (PRoot) — Lenz Mini Server
# Author / Developer: Lenz
# ==============================================================================

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
