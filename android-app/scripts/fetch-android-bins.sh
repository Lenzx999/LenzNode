#!/usr/bin/env bash
# ==============================================================================
# LenzNode Android APK — Native Binaries & Secure Runtime Bundle Fetcher
# Downloads verified PRoot (+ libtalloc, libandroid-shmem) from official Termux
# APT repo and static BusyBox from official Alpine Linux v3.20 repo for both
# arm64-v8a (aarch64) and armeabi-v7a (arm/armv7), patches ELF DT_NEEDED/RUNPATH
# for Android jniLibs compatibility, obfuscates panel JS/HTML, and packs the
# runtime bundle into XOR-masked assets/lenznode-bundle.dat.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$ANDROID_APP_DIR/.." && pwd)"

JNILIBS_DIR="$ANDROID_APP_DIR/app/src/main/jniLibs"
ASSETS_DIR="$ANDROID_APP_DIR/app/src/main/assets"
PLAIN_BUNDLE_DIR="$ASSETS_DIR/lenznode-bundle"
ENCRYPTED_BUNDLE_FILE="$ASSETS_DIR/lenznode-bundle.dat"
WORK_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t lenz-bins)"
trap 'rm -rf "$WORK_DIR"' EXIT

TERMUX_REPO="https://packages.termux.dev/apt/termux-main"
ALPINE_REPO="https://dl-cdn.alpinelinux.org/alpine/v3.20/main"

BUNDLE_ONLY=0
if [ "${1:-}" = "--bundle-only" ]; then
  BUNDLE_ONLY=1
fi

log() { printf '[fetch-bins] %s\n' "$*"; }
err() { printf '[fetch-bins][ERROR] %s\n' "$*" >&2; exit 1; }

check_sha256() {
  local file="$1"
  local expected="$2"
  local actual=""
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    log "sha256sum/shasum not found; skipping checksum check for $(basename "$file")"
    return 0
  fi
  if [ "$actual" != "$expected" ]; then
    err "SHA256 mismatch for $(basename "$file"): expected $expected, got $actual"
  fi
}

check_elf_magic() {
  local file="$1"
  [ -s "$file" ] || err "Binary is empty or missing: $file"
  local magic
  magic="$(LC_ALL=C head -c 4 "$file" | od -An -tx1 | tr -d ' \n')"
  [ "$magic" = "7f454c46" ] || err "File is not a valid ELF binary: $file (magic=$magic)"
}

extract_deb() {
  local deb_file="$1"
  local dest_dir="$2"
  mkdir -p "$dest_dir"
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -x "$deb_file" "$dest_dir"
    return 0
  fi
  if command -v ar >/dev/null 2>&1; then
    local data_member
    data_member="$(ar t "$deb_file" | grep '^data\.tar' | head -n 1)"
    [ -n "$data_member" ] || err "No data.tar.* found in $deb_file"
    case "$data_member" in
      *.xz)  ar p "$deb_file" "$data_member" | tar -xJf - -C "$dest_dir" ;;
      *.gz)  ar p "$deb_file" "$data_member" | tar -xzf - -C "$dest_dir" ;;
      *.zst) ar p "$deb_file" "$data_member" | tar --zstd -xf - -C "$dest_dir" ;;
      *)     ar p "$deb_file" "$data_member" | tar -xf - -C "$dest_dir" ;;
    esac
    return 0
  fi
  err "Neither dpkg-deb nor ar is available to extract $deb_file"
}

get_deb_meta() {
  local pkg_index="$1"
  local pkg_name="$2"
  awk -v pkg="$pkg_name" '
    $0 == "Package: " pkg { in_pkg=1; fn=""; sha=""; next }
    in_pkg && /^$/ { if (fn != "") print fn "|" sha; in_pkg=0; exit }
    in_pkg && /^Filename:/ { fn=$2 }
    in_pkg && /^SHA256:/ { sha=$2 }
    END { if (in_pkg && fn != "") print fn "|" sha }
  ' "$pkg_index"
}

fetch_termux_proot_for_abi() {
  local android_abi="$1"
  local termux_arch="$2"
  local out_dir="$JNILIBS_DIR/$android_abi"
  local abi_work="$WORK_DIR/termux-$android_abi"
  mkdir -p "$out_dir" "$abi_work/extracted"

  log "Fetching Termux Packages index for $termux_arch ($android_abi)..."
  local pkg_index="$abi_work/Packages"
  curl -fsSL --retry 3 --connect-timeout 20 \
    "$TERMUX_REPO/dists/stable/main/binary-${termux_arch}/Packages" \
    -o "$pkg_index"

  for pkg in proot libtalloc libandroid-shmem; do
    local meta fn sha deb_path
    meta="$(get_deb_meta "$pkg_index" "$pkg")"
    [ -n "$meta" ] || err "Package '$pkg' not found in Termux index ($termux_arch)"
    fn="${meta%%|*}"
    sha="${meta##*|}"
    deb_path="$abi_work/${pkg}.deb"
    log "Downloading $pkg ($termux_arch): $fn"
    curl -fsSL --retry 3 --connect-timeout 20 "$TERMUX_REPO/$fn" -o "$deb_path"
    if [ -n "$sha" ]; then
      check_sha256 "$deb_path" "$sha"
    fi
    extract_deb "$deb_path" "$abi_work/extracted"
  done

  local termux_usr="$abi_work/extracted/data/data/com.termux/files/usr"
  [ -f "$termux_usr/bin/proot" ] || err "proot binary missing in extracted deb ($termux_arch)"
  [ -f "$termux_usr/libexec/proot/loader" ] || err "proot loader missing in extracted deb ($termux_arch)"
  [ -f "$termux_usr/lib/libandroid-shmem.so" ] || err "libandroid-shmem.so missing in extracted deb ($termux_arch)"

  local talloc_real
  talloc_real="$(find "$termux_usr/lib" -maxdepth 1 -type f -name 'libtalloc.so*' | head -n 1)"
  [ -n "$talloc_real" ] || err "libtalloc.so* missing in extracted deb ($termux_arch)"

  cp -f "$termux_usr/bin/proot" "$out_dir/libproot.so"
  cp -f "$termux_usr/libexec/proot/loader" "$out_dir/libproot-loader.so"
  if [ -f "$termux_usr/libexec/proot/loader32" ]; then
    cp -f "$termux_usr/libexec/proot/loader32" "$out_dir/libproot-loader32.so"
    chmod 0755 "$out_dir/libproot-loader32.so"
  fi
  cp -f "$talloc_real" "$out_dir/libtalloc.so"
  cp -f "$termux_usr/lib/libandroid-shmem.so" "$out_dir/libandroid-shmem.so"

  chmod 0755 \
    "$out_dir/libproot.so" \
    "$out_dir/libproot-loader.so" \
    "$out_dir/libtalloc.so" \
    "$out_dir/libandroid-shmem.so"

  # Android PackageManager only extracts lib*.so (not libtalloc.so.2).
  # Rewrite DT_NEEDED and SONAME so libproot.so links directly against libtalloc.so in nativeLibraryDir.
  if command -v patchelf >/dev/null 2>&1; then
    patchelf --replace-needed libtalloc.so.2 libtalloc.so "$out_dir/libproot.so"
    patchelf --set-rpath '$ORIGIN' "$out_dir/libproot.so"
    patchelf --set-soname libtalloc.so "$out_dir/libtalloc.so"
    log "Patched ELF DT_NEEDED & RPATH for $android_abi via patchelf"
  else
    err "patchelf is required to rewrite libtalloc.so.2 -> libtalloc.so for Android jniLibs"
  fi

  check_elf_magic "$out_dir/libproot.so"
  check_elf_magic "$out_dir/libproot-loader.so"
  check_elf_magic "$out_dir/libtalloc.so"
  check_elf_magic "$out_dir/libandroid-shmem.so"
}

fetch_alpine_busybox_for_abi() {
  local android_abi="$1"
  local alpine_arch="$2"
  local out_dir="$JNILIBS_DIR/$android_abi"
  local abi_work="$WORK_DIR/alpine-$android_abi"
  mkdir -p "$out_dir" "$abi_work/extracted"

  log "Fetching Alpine APKINDEX for $alpine_arch ($android_abi)..."
  curl -fsSL --retry 3 --connect-timeout 20 \
    "$ALPINE_REPO/$alpine_arch/APKINDEX.tar.gz" \
    -o "$abi_work/APKINDEX.tar.gz"

  tar -xzf "$abi_work/APKINDEX.tar.gz" -C "$abi_work" APKINDEX
  local bb_ver
  bb_ver="$(awk '
    $0 == "P:busybox-static" { in_pkg=1; next }
    in_pkg && /^$/ { in_pkg=0; exit }
    in_pkg && /^V:/ { print substr($0, 3); exit }
  ' "$abi_work/APKINDEX")"
  [ -n "$bb_ver" ] || err "busybox-static not found in Alpine APKINDEX ($alpine_arch)"

  local apk_url="$ALPINE_REPO/$alpine_arch/busybox-static-${bb_ver}.apk"
  log "Downloading busybox-static ($bb_ver, $alpine_arch)..."
  curl -fsSL --retry 3 --connect-timeout 20 "$apk_url" -o "$abi_work/busybox-static.apk"

  tar -xzf "$abi_work/busybox-static.apk" -C "$abi_work/extracted" bin/busybox.static 2>/dev/null \
    || tar -xzf "$abi_work/busybox-static.apk" -C "$abi_work/extracted"

  [ -f "$abi_work/extracted/bin/busybox.static" ] || err "bin/busybox.static missing in Alpine APK ($alpine_arch)"
  cp -f "$abi_work/extracted/bin/busybox.static" "$out_dir/libbusybox.so"
  chmod 0755 "$out_dir/libbusybox.so"
  check_elf_magic "$out_dir/libbusybox.so"
}

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$p"
  else
    printf '%s' "$p"
  fi
}

pack_encrypted_bundle() {
  local stage_dir="$WORK_DIR/bundle-stage"
  local packer_js="$WORK_DIR/pack-bundle.js"
  log "Preparing protected LenzNode runtime bundle..."

  rm -rf "$stage_dir"
  mkdir -p "$stage_dir/panel" "$stage_dir/apps" "$stage_dir/scripts" "$ASSETS_DIR"

  [ -f "$REPO_ROOT/panel/server.js" ] || err "panel/server.js not found at $REPO_ROOT/panel/server.js"
  cp -a "$REPO_ROOT/panel/." "$stage_dir/panel/"
  # Exclude runtime/instance-specific state files so fresh APK installs initialize cleanly
  rm -f \
    "$stage_dir/panel/sessions.json" \
    "$stage_dir/panel/state.json" \
    "$stage_dir/panel/shares.json" \
    "$stage_dir/panel/root-config.json" \
    "$stage_dir/panel/auth-config.json" \
    "$stage_dir/panel/vps-config.json"
  rm -rf "$stage_dir/panel/logs"

  if [ -d "$REPO_ROOT/apps" ]; then
    cp -a "$REPO_ROOT/apps/." "$stage_dir/apps/"
    rm -f "$stage_dir/apps/.gitkeep"
  fi

  if [ -d "$REPO_ROOT/scripts" ]; then
    cp -a "$REPO_ROOT/scripts/." "$stage_dir/scripts/"
    rm -f "$stage_dir/scripts/.gitkeep" "$stage_dir/scripts/build-release.js"
  fi

  [ -f "$REPO_ROOT/version.json" ] && cp -f "$REPO_ROOT/version.json" "$stage_dir/version.json"
  [ -f "$REPO_ROOT/CHANGELOG.md" ] && cp -f "$REPO_ROOT/CHANGELOG.md" "$stage_dir/CHANGELOG.md"

  # Ensure LF line endings on all bundled shell scripts
  find "$stage_dir" -type f -name '*.sh' -exec sh -c '
    for f do
      tr -d "\r" < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      chmod 0755 "$f"
    done
  ' sh {} +

  command -v node >/dev/null 2>&1 || err "Node.js is required to obfuscate and pack lenznode-bundle.dat"

  cat > "$packer_js" << 'JSEOF'
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');
const vm = require('vm');

const stageDir = process.argv[2];
const outDat = process.argv[3];
const repoRoot = process.argv[4];

function loadObfuscator() {
  const candidates = [
    path.join(repoRoot, 'node_modules', 'javascript-obfuscator'),
    'javascript-obfuscator'
  ];
  for (const c of candidates) {
    try {
      return require(c);
    } catch (_) {}
  }
  return null;
}

const NODE_OBFUSCATOR_OPTIONS = {
  compact: true,
  controlFlowFlattening: false,
  deadCodeInjection: false,
  debugProtection: false,
  disableConsoleOutput: false,
  identifierNamesGenerator: 'hexadecimal',
  log: false,
  numbersToExpressions: false,
  renameGlobals: false,
  rotateStringArray: true,
  selfDefending: false,
  splitStrings: false,
  stringArray: true,
  stringArrayCallsTransform: false,
  stringArrayEncoding: ['base64'],
  stringArrayIndexShift: true,
  stringArrayRotate: true,
  stringArrayShuffle: true,
  stringArrayWrappersCount: 1,
  stringArrayWrappersType: 'variable',
  stringArrayThreshold: 0.8,
  transformObjectKeys: false,
  unicodeEscapeSequence: false,
  target: 'node'
};

const BROWSER_OBFUSCATOR_OPTIONS = {
  compact: true,
  controlFlowFlattening: false,
  deadCodeInjection: false,
  debugProtection: false,
  disableConsoleOutput: false,
  identifierNamesGenerator: 'hexadecimal',
  log: false,
  renameGlobals: false,
  rotateStringArray: true,
  selfDefending: false,
  stringArray: true,
  stringArrayEncoding: ['base64'],
  stringArrayThreshold: 0.75,
  target: 'browser'
};

const obfuscator = loadObfuscator();

const serverJsPath = path.join(stageDir, 'panel', 'server.js');
let serverCode = fs.readFileSync(serverJsPath, 'utf8');
const alreadyObfuscated = /_0x[0-9a-f]{4,}/i.test(serverCode) && serverCode.split('\n').length < 30;

if (!alreadyObfuscated) {
  if (!obfuscator) {
    console.warn('[fetch-bins] WARN: javascript-obfuscator not installed; packing un-obfuscated JS');
  } else {
    console.log('[fetch-bins] Obfuscating panel/server.js...');
    const signatureLock =
      "\n/* LenzNode Core Server Engine - (C) 2026 Lenz. All Rights Reserved. */\n" +
      "if (!process.env.LENZ_BYPASS_AUTH_SIGN) {\n" +
      "  const _s = 'LenzNode';\n" +
      "  const _a = 'Created by Lenz';\n" +
      "  if (!_s || !_a) { process.exit(1); }\n" +
      "}\n";
    const obf = obfuscator.obfuscate(signatureLock + '\n' + serverCode, NODE_OBFUSCATOR_OPTIONS);
    serverCode = obf.getObfuscatedCode();
    new vm.Script(serverCode);
    fs.writeFileSync(serverJsPath, serverCode, 'utf8');
  }
} else {
  console.log('[fetch-bins] panel/server.js already obfuscated; skipping double obfuscation.');
}

function minifyHtmlAndCss(html) {
  const parts = html.split(/(<script\b[^>]*>[\s\S]*?<\/script>|<style\b[^>]*>[\s\S]*?<\/style>|<pre\b[^>]*>[\s\S]*?<\/pre>|<textarea\b[^>]*>[\s\S]*?<\/textarea>)/gi);
  return parts.map(part => {
    if (!part) return '';
    if (/^<script\b/i.test(part)) {
      const m = part.match(/^<script\b(?![^>]*\bsrc\b)([^>]*)>([\s\S]*?)<\/script>$/i);
      if (m && m[2] && m[2].trim().length >= 300) {
        const body = m[2];
        const bodyAlreadyObf = /_0x[0-9a-f]{4,}/i.test(body) && body.split('\n').length < 20;
        if (!bodyAlreadyObf && obfuscator) {
          const obf = obfuscator.obfuscate(body, BROWSER_OBFUSCATOR_OPTIONS);
          return `<script${m[1]}>\n${obf.getObfuscatedCode()}\n</script>`;
        }
      }
      return part;
    }
    if (/^<style\b/i.test(part)) {
      const m = part.match(/^<style\b([^>]*)>([\s\S]*?)<\/style>$/i);
      if (!m) return part;
      const css = m[2]
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .split('\n')
        .map(line => line.trim())
        .filter(Boolean)
        .join('\n');
      return `<style${m[1]}>${css}</style>`;
    }
    if (/^<(pre|textarea)\b/i.test(part)) {
      return part;
    }
    return part
      .replace(/<!--[\s\S]*?-->/g, '')
      .split('\n')
      .map(line => line.trim())
      .filter(Boolean)
      .join('\n');
  }).join('\n');
}

for (const page of ['index.html', 'login.html']) {
  const htmlPath = path.join(stageDir, 'panel', 'public', page);
  if (!fs.existsSync(htmlPath)) continue;
  console.log(`[fetch-bins] Securing & minifying panel/public/${page}...`);
  const original = fs.readFileSync(htmlPath, 'utf8');
  const secured = minifyHtmlAndCss(original);
  fs.writeFileSync(htmlPath, secured, 'utf8');
}

// CRC32 table for standard PKZIP archive compatible with Java ZipInputStream
const crcTable = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) {
    c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
  }
  crcTable[n] = c >>> 0;
}
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function collectFiles(dir, prefix = '') {
  const items = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(dir, entry.name);
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      items.push(...collectFiles(full, rel));
    } else if (entry.isFile()) {
      items.push({ rel, full });
    }
  }
  return items;
}

function buildZip(rootDir) {
  const files = collectFiles(rootDir);
  const localParts = [];
  const centralParts = [];
  let offset = 0;

  for (const item of files) {
    const raw = fs.readFileSync(item.full);
    const deflated = zlib.deflateRawSync(raw, { level: 9 });
    const useDeflate = deflated.length < raw.length;
    const payload = useDeflate ? deflated : raw;
    const method = useDeflate ? 8 : 0;
    const crc = crc32(raw);
    const nameBuf = Buffer.from(item.rel, 'utf8');

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6); // UTF-8 filename, no data descriptor
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(0, 10);
    local.writeUInt16LE(0x5421, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(payload.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt16LE(0, 12);
    central.writeUInt16LE(0x5421, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(payload.length, 20);
    central.writeUInt32LE(raw.length, 24);
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(0, 38);
    central.writeUInt32LE(offset, 42);

    localParts.push(local, nameBuf, payload);
    centralParts.push(central, nameBuf);
    offset += local.length + nameBuf.length + payload.length;
  }

  const centralBuf = Buffer.concat(centralParts);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(files.length, 8);
  eocd.writeUInt16LE(files.length, 10);
  eocd.writeUInt32LE(centralBuf.length, 12);
  eocd.writeUInt32LE(offset, 16);
  eocd.writeUInt16LE(0, 20);

  return { zipBuf: Buffer.concat([...localParts, centralBuf, eocd]), count: files.length };
}

const { zipBuf, count } = buildZip(stageDir);
const key = crypto.createHash('sha256').update('com.lenznode.app:LenzNode-APK-Bundle-v1', 'utf8').digest();
const masked = Buffer.allocUnsafe(zipBuf.length);
for (let i = 0; i < zipBuf.length; i++) {
  masked[i] = zipBuf[i] ^ key[i & 31];
}

fs.writeFileSync(outDat, masked);
console.log(`[fetch-bins] Packed ${count} files -> ${outDat} (${masked.length} bytes, XOR-protected)`);
JSEOF

  node "$(to_native_path "$packer_js")" \
    "$(to_native_path "$stage_dir")" \
    "$(to_native_path "$ENCRYPTED_BUNDLE_FILE")" \
    "$(to_native_path "$REPO_ROOT")"

  [ -s "$ENCRYPTED_BUNDLE_FILE" ] || err "Failed to generate $ENCRYPTED_BUNDLE_FILE"

  # Remove any legacy plain directory so APK assets never expose unencrypted bundle files
  rm -rf "$PLAIN_BUNDLE_DIR"
}

if [ "$BUNDLE_ONLY" = "0" ]; then
  fetch_termux_proot_for_abi "arm64-v8a" "aarch64"
  fetch_alpine_busybox_for_abi "arm64-v8a" "aarch64"

  fetch_termux_proot_for_abi "armeabi-v7a" "arm"
  fetch_alpine_busybox_for_abi "armeabi-v7a" "armv7"
fi

pack_encrypted_bundle

if [ "$BUNDLE_ONLY" = "0" ]; then
  log "Verification summary:"
  for abi in arm64-v8a armeabi-v7a; do
    for bin in libproot.so libproot-loader.so libtalloc.so libandroid-shmem.so libbusybox.so; do
      target="$JNILIBS_DIR/$abi/$bin"
      [ -s "$target" ] || err "Missing required binary: $target"
      size="$(wc -c < "$target" | tr -d ' ')"
      printf '  %-12s %-22s %s bytes\n' "$abi" "$bin" "$size"
    done
  done
fi

log "Done."
