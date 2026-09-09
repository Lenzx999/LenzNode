/**
 * Lenz Mini Server — Web Dashboard & Server Manager di Termux (Universal Edition)
 * Author / Developer: Lenz
 *
 * Ditulis menggunakan modul bawaan Node.js murni (zero external npm dependencies):
 * http, https, fs, path, os, child_process, crypto, net.
 * Sangat hemat memori RAM dan 100% kompatibel di Android 5 s/d 14+ (ARM32/ARM64/x86_64).
 */

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn, exec, execSync } = require('child_process');
const crypto = require('crypto');
const net = require('net');

// ------------------------------------------------------------------
// KONFIGURASI & VARIABEL LINGKUNGAN
// ------------------------------------------------------------------
const BASE_DIR = path.resolve(__dirname, '..');
const LOG_DIR = path.join(BASE_DIR, 'logs');
const STATE_FILE = path.join(__dirname, 'state.json');
const AUTH_CONFIG_FILE = path.join(__dirname, 'auth-config.json');

const PANEL_PORT = parseInt(process.env.PANEL_PORT || '8080', 10);

let authConfig = {
  username: process.env.PANEL_USER || 'admin',
  password: process.env.PANEL_PASS || 'admin123',
};

function loadAuthConfig() {
  try {
    if (fs.existsSync(AUTH_CONFIG_FILE)) {
      const raw = fs.readFileSync(AUTH_CONFIG_FILE, 'utf8');
      const data = JSON.parse(raw);
      if (data.username && typeof data.username === 'string') authConfig.username = data.username.trim();
      if (data.password && typeof data.password === 'string') authConfig.password = data.password.trim();
    } else {
      saveAuthConfig(authConfig.username, authConfig.password);
    }
  } catch (e) {
    console.error('Gagal membaca auth-config.json:', e.message);
  }
}

function saveAuthConfig(newUsername, newPassword) {
  try {
    if (newUsername) authConfig.username = newUsername.trim();
    if (newPassword) authConfig.password = newPassword.trim();
    fs.writeFileSync(AUTH_CONFIG_FILE, JSON.stringify(authConfig, null, 2), 'utf8');
  } catch (e) {
    console.error('Gagal menyimpan auth-config.json:', e.message);
  }
}

loadAuthConfig();

if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

// ------------------------------------------------------------------
// SESI & AUTENTIKASI PERSISTEN
// ------------------------------------------------------------------
const SESSIONS_FILE = path.join(__dirname, 'sessions.json');
const activeSessions = new Map();
const failedAttempts = new Map();
const activeTerminalJobs = new Map();

function loadSessions() {
  try {
    if (fs.existsSync(SESSIONS_FILE)) {
      const raw = fs.readFileSync(SESSIONS_FILE, 'utf8');
      const data = JSON.parse(raw);
      const now = Date.now();
      activeSessions.clear();
      for (const token in data) {
        const session = data[token];
        if (session && session.expiresAt && session.expiresAt > now) {
          activeSessions.set(token, session);
        }
      }
    }
  } catch (e) {
    console.error('Gagal membaca sessions.json:', e.message);
  }
}

function saveSessions() {
  try {
    const obj = {};
    const now = Date.now();
    for (const [token, session] of activeSessions.entries()) {
      if (session.expiresAt > now) {
        obj[token] = session;
      }
    }
    fs.writeFileSync(SESSIONS_FILE, JSON.stringify(obj, null, 2), 'utf8');
  } catch (e) {
    console.error('Gagal menyimpan sessions.json:', e.message);
  }
}

function isSessionValid(token) {
  if (!token) return false;
  const session = activeSessions.get(token);
  if (!session) return false;
  if (session.expiresAt <= Date.now()) {
    activeSessions.delete(token);
    saveSessions();
    return false;
  }
  return true;
}

function createSession(token, user = 'admin', ip = '127.0.0.1') {
  const session = {
    user,
    ip,
    createdAt: Date.now(),
    expiresAt: Date.now() + 30 * 24 * 3600 * 1000, // 30 Hari aktif
  };
  activeSessions.set(token, session);
  saveSessions();
  return session;
}

function deleteSession(token) {
  if (token && activeSessions.has(token)) {
    activeSessions.delete(token);
    saveSessions();
  }
}

loadSessions();

function getClientIP(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) return forwarded.split(',')[0].trim();
  return (req.socket && req.socket.remoteAddress) || '127.0.0.1';
}

function parseCookies(req) {
  const list = {};
  const rc = req.headers.cookie;
  if (!rc) return list;
  rc.split(';').forEach((cookie) => {
    const parts = cookie.split('=');
    list[parts.shift().trim()] = decodeURI(parts.join('='));
  });
  return list;
}

function checkAuth(req) {
  const cookies = parseCookies(req);
  if (cookies.session_token && isSessionValid(cookies.session_token)) {
    return true;
  }

  const authHeader = req.headers['authorization'] || '';
  if (authHeader.startsWith('Bearer ')) {
    const token = authHeader.substring(7).trim();
    if (isSessionValid(token)) return true;
  }

  if (authHeader.startsWith('Basic ')) {
    const encoded = authHeader.substring(6).trim();
    const decoded = Buffer.from(encoded, 'base64').toString('utf8');
    const idx = decoded.indexOf(':');
    const user = decoded.slice(0, idx);
    const pass = decoded.slice(idx + 1);
    if (user === authConfig.username && pass === authConfig.password) return true;
  }

  return false;
}

function isPortListening(port, host = '127.0.0.1') {
  return new Promise((resolve) => {
    const sock = new net.Socket();
    sock.setTimeout(1200);
    sock.on('connect', () => { sock.destroy(); resolve(true); });
    sock.on('error', () => { sock.destroy(); resolve(false); });
    sock.on('timeout', () => { sock.destroy(); resolve(false); });
    sock.connect(port, host);
  });
}

function checkAndRotateLogs() {
  try {
    if (!fs.existsSync(LOG_DIR)) return;
    const files = fs.readdirSync(LOG_DIR);
    for (let i = 0; i < files.length; i++) {
      const f = files[i];
      if (!f.endsWith('.log')) continue;
      const fPath = path.join(LOG_DIR, f);
      const stat = fs.statSync(fPath);
      if (stat.size > 2 * 1024 * 1024) {
        const buffer = Buffer.alloc(64 * 1024);
        const fd = fs.openSync(fPath, 'r');
        const pos = Math.max(0, stat.size - buffer.length);
        const bytesRead = fs.readSync(fd, buffer, 0, buffer.length, pos);
        fs.closeSync(fd);
        const tailText = buffer.slice(0, bytesRead).toString('utf8');
        const lines = tailText.split('\n');
        lines.shift();
        const trimmed = lines.join('\n');
        fs.writeFileSync(fPath, `[${new Date().toISOString()}] (Log otomatis dipangkas, batas 2MB)\n` + trimmed);
      }
    }
  } catch (e) {}
}

checkAndRotateLogs();
setInterval(checkAndRotateLogs, 5 * 60 * 1000);

// ------------------------------------------------------------------
// MONITORING SISTEM (RAM, DISK, CPU, SUHU, BATERAI, NETWORK)
// ------------------------------------------------------------------
function getLocalIPs() {
  const ips = [];
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        ips.push({ iface: name, address: iface.address });
      }
    }
  }
  return ips;
}

function getThermalInfo() {
  let cpuTemp = null;
  let batteryTemp = null;
  let cores = [null, null, null, null];

  try {
    if (fs.existsSync('/sys/class/thermal')) {
      const tzDirs = fs.readdirSync('/sys/class/thermal').filter(f => f.startsWith('thermal_zone'));
      let cpuTemps = [];
      let tsensMap = {};
      let explicitCoreMap = {};

      for (let i = 0; i < tzDirs.length; i++) {
        const d = tzDirs[i];
        try {
          const typeFile = `/sys/class/thermal/${d}/type`;
          const tempFile = `/sys/class/thermal/${d}/temp`;
          if (!fs.existsSync(typeFile) || !fs.existsSync(tempFile)) continue;
          const type = fs.readFileSync(typeFile, 'utf8').trim().toLowerCase();
          const raw = parseInt(fs.readFileSync(tempFile, 'utf8').trim(), 10);
          if (isNaN(raw)) continue;
          const deg = raw > 1000 ? Math.round(raw / 1000) : raw;

          if (deg > 0 && deg < 120) {
            const tsensMatch = type.match(/^tsens_tz_sensor([0-9]+)$/);
            if (tsensMatch) {
              const sNum = parseInt(tsensMatch[1], 10);
              tsensMap[sNum] = deg;
            }

            const coreMatch = type.match(/cpu[_-]?([0-9]+)|core[_-]?([0-9]+)/);
            if (coreMatch) {
              const cIdx = parseInt(coreMatch[1] || coreMatch[2], 10);
              explicitCoreMap[cIdx] = deg;
            }

            if (type.startsWith('tsens_tz') || type.includes('cpu')) {
              cpuTemps.push(deg);
            }
          }

          if (type === 'battery' && batteryTemp === null) {
            const bVal = raw > 1000 ? (raw / 1000) : (raw > 100 ? raw / 10 : raw);
            batteryTemp = bVal.toFixed(1);
          }
        } catch {}
      }

      if (Object.keys(explicitCoreMap).length >= 4) {
        cores = [explicitCoreMap[0], explicitCoreMap[1], explicitCoreMap[2], explicitCoreMap[3]];
      } else if (tsensMap[1] !== undefined && tsensMap[2] !== undefined && tsensMap[3] !== undefined && tsensMap[4] !== undefined) {
        cores = [tsensMap[1], tsensMap[2], tsensMap[3], tsensMap[4]];
      } else if (tsensMap[0] !== undefined && tsensMap[1] !== undefined && tsensMap[2] !== undefined && tsensMap[3] !== undefined) {
        cores = [tsensMap[0], tsensMap[1], tsensMap[2], tsensMap[3]];
      }

      if (cpuTemps.length > 0) {
        cpuTemp = Math.max(...cpuTemps);
      }
    }
  } catch {}

  if (batteryTemp === null) {
    try {
      const bTempPath = '/sys/class/power_supply/battery/temp';
      if (fs.existsSync(bTempPath)) {
        const raw = parseInt(fs.readFileSync(bTempPath, 'utf8').trim(), 10);
        if (!isNaN(raw)) {
          batteryTemp = (raw > 100 ? (raw / 10) : raw).toFixed(1);
        }
      }
    } catch {}
  }

  if (cpuTemp === null && os.platform() === 'win32') {
    cpuTemp = 42;
    batteryTemp = '33.0';
    cores = [41, 43, 42, 40];
  } else {
    for (let c = 0; c < 4; c++) {
      if (cores[c] === null && cpuTemp !== null) {
        cores[c] = cpuTemp;
      }
    }
  }

  let status = 'Optimal';
  if (cpuTemp !== null) {
    if (cpuTemp >= 75) status = 'Panas';
    else if (cpuTemp >= 60) status = 'Hangat';
    else status = 'Optimal';
  }

  return {
    cpu: cpuTemp !== null ? `${cpuTemp}°C` : null,
    cpuTemp: cpuTemp,
    cores: cores,
    battery: batteryTemp !== null ? `${batteryTemp}°C` : null,
    batteryTemp: batteryTemp ? parseFloat(batteryTemp) : null,
    status: status
  };
}

function getBatteryInfo() {
  if (os.platform() === 'win32') {
    return { percentage: 100, status: 'AC Powered', temperature: null };
  }

  let percentage = null;
  let status = 'Unknown';
  let temperature = null;

  // 1. Scan seluruh node power_supply di Linux / Android (/sys/class/power_supply/*)
  try {
    const psDir = '/sys/class/power_supply';
    if (fs.existsSync(psDir)) {
      const candidates = ['battery', 'bms', 'main', 'sec-fuelgauge', 'qcom-battery', 'smb-battery', 'max170xx_battery'];
      const dirs = fs.readdirSync(psDir);
      
      const sortedDirs = dirs.slice().sort((a, b) => {
        const aPri = candidates.indexOf(a) !== -1 ? candidates.indexOf(a) : 999;
        const bPri = candidates.indexOf(b) !== -1 ? candidates.indexOf(b) : 999;
        return aPri - bPri;
      });

      for (let i = 0; i < sortedDirs.length; i++) {
        const d = sortedDirs[i];
        const capFile = path.join(psDir, d, 'capacity');
        if (fs.existsSync(capFile)) {
          const rawCap = parseInt(fs.readFileSync(capFile, 'utf8').trim(), 10);
          if (!isNaN(rawCap) && rawCap >= 0 && rawCap <= 100) {
            percentage = rawCap;

            const stFile = path.join(psDir, d, 'status');
            if (fs.existsSync(stFile)) {
              status = fs.readFileSync(stFile, 'utf8').trim();
            }

            const tempFile = path.join(psDir, d, 'temp');
            if (fs.existsSync(tempFile)) {
              const rawT = parseInt(fs.readFileSync(tempFile, 'utf8').trim(), 10);
              if (!isNaN(rawT)) {
                temperature = (rawT > 100 ? (rawT / 10) : rawT).toFixed(1);
              }
            }
            break;
          }
        }
      }
    }
  } catch {}

  // 2. Fallback ke dumpsys battery & cmd battery (Android Framework API bawaan)
  if (percentage === null) {
    try {
      const out = execSync('dumpsys battery 2>/dev/null || cmd battery get level 2>/dev/null', { timeout: 1200, stdio: ['ignore', 'pipe', 'ignore'] }).toString();
      if (out) {
        const levelMatch = out.match(/level:\s*([0-9]+)/i);
        if (levelMatch) {
          percentage = parseInt(levelMatch[1], 10);
        } else if (/^[0-9]+$/.test(out.trim())) {
          percentage = parseInt(out.trim(), 10);
        }

        const statusMatch = out.match(/status:\s*([0-9]+)/i);
        if (statusMatch) {
          const stCode = parseInt(statusMatch[1], 10);
          if (stCode === 2) status = 'Charging';
          else if (stCode === 3) status = 'Discharging';
          else if (stCode === 5) status = 'Full';
          else status = 'In Use';
        }

        const tempMatch = out.match(/temperature:\s*([0-9]+)/i);
        if (tempMatch) {
          const rawT = parseInt(tempMatch[1], 10);
          temperature = (rawT > 100 ? (rawT / 10) : rawT).toFixed(1);
        }
      }
    } catch {}
  }

  // 3. Fallback ke termux-battery-status (jika paket Termux:API terpasang)
  if (percentage === null) {
    try {
      const out = execSync('termux-battery-status 2>/dev/null', { timeout: 1000, stdio: ['ignore', 'pipe', 'ignore'] }).toString();
      const data = JSON.parse(out);
      if (data && data.percentage !== undefined) {
        percentage = data.percentage;
        status = data.status || status;
        if (data.temperature) {
          temperature = (data.temperature / 10).toFixed(1);
        }
      }
    } catch {}
  }

  return {
    percentage: percentage !== null ? percentage : null,
    status: percentage !== null ? status : 'Tidak terbaca',
    temperature: temperature !== null ? temperature : null,
  };
}

function parseHumanSize(str) {
  if (!str) return 0;
  const unit = str.slice(-1).toUpperCase();
  const val = parseFloat(str.slice(0, -1));
  if (isNaN(val)) return parseInt(str, 10) || 0;
  if (unit === 'K') return Math.round(val * 1024);
  if (unit === 'M') return Math.round(val * 1024 * 1024);
  if (unit === 'G') return Math.round(val * 1024 * 1024 * 1024);
  if (unit === 'T') return Math.round(val * 1024 * 1024 * 1024 * 1024);
  return Math.round(parseFloat(str)) || 0;
}

function parseDiskLine(line) {
  const parts = line.trim().split(/\s+/);
  if (parts.length < 4) return null;
  const mount = parts[parts.length - 1].startsWith('/') ? parts[parts.length - 1] : parts[0];
  const isHuman = /[KMGT]$/i.test(parts[1]) || /[KMGT]$/i.test(parts[2]) || /[KMGT]$/i.test(parts[3]);
  let totalBytes = 0;
  let usedBytes = 0;
  let freeBytes = 0;

  if (isHuman) {
    totalBytes = parseHumanSize(parts[1]);
    usedBytes = parseHumanSize(parts[2]);
    freeBytes = parseHumanSize(parts[3]);
  } else {
    const col1 = parseInt(parts[1], 10);
    const col2 = parseInt(parts[2], 10);
    const col3 = parseInt(parts[3], 10);
    if (!isNaN(col1) && !isNaN(col2) && !isNaN(col3)) {
      totalBytes = col1 * 1024;
      usedBytes = col2 * 1024;
      freeBytes = col3 * 1024;
    }
  }

  if (totalBytes > 0) {
    const usagePercent = Math.min(100, Math.max(0, Math.round((usedBytes / totalBytes) * 100)));
    return { mount, totalBytes, usedBytes, freeBytes, usagePercent };
  }
  return null;
}

function getDiskInfo() {
  const disks = [];
  try {
    if (os.platform() === 'win32') {
      const out = execSync('wmic logicaldisk get caption,freespace,size 2>nul', { timeout: 2000 }).toString().trim();
      const lines = out.split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('Caption'));
      for (const line of lines) {
        const parts = line.split(/\s+/);
        if (parts.length >= 3) {
          const total = parseInt(parts[2], 10);
          const free = parseInt(parts[1], 10);
          const used = total - free;
          disks.push({
            mount: parts[0],
            totalBytes: total,
            freeBytes: free,
            usedBytes: used,
            usagePercent: total ? Math.round((used / total) * 100) : 0,
          });
        }
      }
      return disks;
    }

    const candidateCommands = [
      'df -k /data',
      'df -k',
      'df /data',
      'df',
      `df "${process.env.HOME || '.'}"`,
    ];

    let dfOutput = '';
    for (let i = 0; i < candidateCommands.length; i++) {
      try {
        dfOutput = execSync(`${candidateCommands[i]} 2>/dev/null`, { timeout: 1500 }).toString().trim();
        if (dfOutput) break;
      } catch {}
    }

    if (dfOutput) {
      const lines = dfOutput.split('\n');
      for (let i = 1; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line) continue;
        const parsed = parseDiskLine(line);
        if (parsed) {
          const m = parsed.mount;
          if (m.includes('/data') || m.includes('storage') || m.includes('sdcard') || m === '/' || disks.length === 0) {
            if (!disks.some((d) => d.mount === parsed.mount)) {
              disks.push(parsed);
            }
          }
        }
      }
    }
  } catch {}

  return disks;
}

let prevCpuSample = null;
function getCpuUsagePercent() {
  try {
    if (fs.existsSync('/proc/stat')) {
      const stat = fs.readFileSync('/proc/stat', 'utf8');
      const firstLine = stat.split('\n')[0];
      const parts = firstLine.trim().split(/\s+/).slice(1).map(Number);
      if (parts.length >= 4) {
        const idle = (parts[3] || 0) + (parts[4] || 0);
        const total = parts.reduce((acc, val) => acc + val, 0);
        if (!prevCpuSample) {
          prevCpuSample = { idle, total };
          return 0;
        }
        const idleDiff = idle - prevCpuSample.idle;
        const totalDiff = total - prevCpuSample.total;
        prevCpuSample = { idle, total };
        if (totalDiff <= 0) return 0;
        const pct = Math.round((1 - (idleDiff / totalDiff)) * 100);
        return Math.max(0, Math.min(100, pct));
      }
    } else if (os.cpus && os.cpus().length) {
      const cpus = os.cpus();
      let idle = 0, total = 0;
      for (const cpu of cpus) {
        for (const type in cpu.times) total += cpu.times[type];
        idle += cpu.times.idle;
      }
      if (!prevCpuSample) {
        prevCpuSample = { idle, total };
        return 0;
      }
      const idleDiff = idle - prevCpuSample.idle;
      const totalDiff = total - prevCpuSample.total;
      prevCpuSample = { idle, total };
      if (totalDiff <= 0) return 0;
      return Math.max(0, Math.min(100, Math.round((1 - (idleDiff / totalDiff)) * 100)));
    }
  } catch (e) {}
  return 0;
}

function getSystemStats() {
  let totalMem = os.totalmem();
  let freeMem = os.freemem();

  if (os.platform() !== 'win32') {
    try {
      const meminfo = fs.readFileSync('/proc/meminfo', 'utf8');
      let memAvail = null;
      let memTot = null;
      const lines = meminfo.split('\n');
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.startsWith('MemTotal:')) {
          const val = parseInt(line.replace(/\D/g, ''), 10);
          if (!isNaN(val)) memTot = val * 1024;
        } else if (line.startsWith('MemAvailable:')) {
          const val = parseInt(line.replace(/\D/g, ''), 10);
          if (!isNaN(val)) memAvail = val * 1024;
        }
      }
      if (memTot) totalMem = memTot;
      if (memAvail !== null) freeMem = memAvail;
    } catch (e) {}
  }

  const usedMem = Math.max(0, totalMem - freeMem);
  const cpuPercent = getCpuUsagePercent();

  return {
    hostname: os.hostname(),
    platform: os.platform(),
    arch: os.arch(),
    uptimeSeconds: Math.floor(os.uptime()),
    panelUptimeSeconds: Math.floor(process.uptime()),
    nodeVersion: process.version,
    memory: {
      totalBytes: totalMem,
      usedBytes: usedMem,
      freeBytes: freeMem,
      usagePercent: Math.round((usedMem / totalMem) * 100),
    },
    cpu: {
      model: `${os.cpus().length || 4} Cores (${os.arch()})`,
      cores: os.cpus().length || 4,
      loadavg: os.loadavg(),
      usagePercent: cpuPercent,
    },
    battery: getBatteryInfo(),
    thermal: getThermalInfo(),
    disks: getDiskInfo(),
    network: {
      localIPs: getLocalIPs(),
      publicUrl: currentPublicUrl,
      tunnelStatus: tunnelProcess ? (currentPublicUrl ? 'connected' : 'connecting') : 'disabled',
    },
    services: [],
    vps: Object.assign({}, vpsConfig, {
      running: lastVpsRunningState,
    }),
  };
}

// ------------------------------------------------------------------
// KONFIGURASI VPS UBUNTU (SSH Port 2222)
// ------------------------------------------------------------------
let vpsConfig = {
  enabled: true,
  distro: 'ubuntu',
  username: 'root',
  password: 'ubuntu123',
  port: 2222,
  publicHost: null,
  publicPort: null,
  publicCommand: null,
};

function loadVpsConfig() {
  const cfgPath = path.join(__dirname, 'vps-config.json');
  if (fs.existsSync(cfgPath)) {
    try {
      const data = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
      vpsConfig = Object.assign(vpsConfig, data);
    } catch (e) {
      console.error('Gagal membaca vps-config.json:', e.message);
    }
  }
}

function saveVpsConfig(updates) {
  try {
    vpsConfig = Object.assign(vpsConfig, updates);
    const cfgPath = path.join(__dirname, 'vps-config.json');
    const current = fs.existsSync(cfgPath) ? JSON.parse(fs.readFileSync(cfgPath, 'utf8')) : {};
    const merged = Object.assign(current, updates);
    fs.writeFileSync(cfgPath, JSON.stringify(merged, null, 2), 'utf8');
  } catch (e) {}
}
loadVpsConfig();

let lastVpsRunningState = false;

async function checkVpsListeningAsync() {
  lastVpsRunningState = await isPortListening(vpsConfig.port || 2222);
  return lastVpsRunningState;
}
setInterval(checkVpsListeningAsync, 8000);
checkVpsListeningAsync();

function startVpsService() {
  const startScript = path.join(BASE_DIR, 'start.sh');
  try {
    const child = spawn('bash', [startScript, 'vps'], {
      detached: true,
      stdio: 'ignore',
      env: process.env,
    });
    child.unref();
    setTimeout(() => {
      checkVpsListeningAsync().then((running) => {
        if (running) startVpsTunnel();
      });
    }, 2000);
    return { ok: true, message: 'Service SSH VPS sedang dijalankan.' };
  } catch (e) {
    return { ok: false, message: 'Gagal menjalankan VPS: ' + e.message };
  }
}

function stopVpsService() {
  try {
    if (vpsTunnelProcess) {
      try { vpsTunnelProcess.kill('SIGKILL'); } catch (e) {}
      vpsTunnelProcess = null;
    }
    clearTimeout(vpsTunnelRetryTimer);
    saveVpsConfig({ publicHost: null, publicPort: null, publicCommand: null });

    if (os.platform() !== 'win32') {
      execSync('pkill -9 -f "tcp@free.pinggy.io" 2>/dev/null || true');
      execSync('pkill -9 -f "sshd -p 2222" 2>/dev/null || pkill -9 -f "/usr/sbin/sshd" 2>/dev/null || true');
    }
    lastVpsRunningState = false;
    return { ok: true, message: 'Service SSH VPS berhasil dihentikan.' };
  } catch (e) {
    return { ok: false, message: 'Gagal menghentikan VPS: ' + e.message };
  }
}

function restartVpsService() {
  stopVpsService();
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve(startVpsService());
    }, 1500);
  });
}

function controlScreen(action) {
  try {
    const sysEnv = Object.assign({}, process.env, {
      PATH: '/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin:' + (process.env.PATH || '')
    });

    if (action === 'off') {
      if (os.platform() !== 'win32') {
        const offCmds = [
          'su -c "input keyevent 26"',
          'termux-brightness 0',
          'settings put global stay_on_while_plugged_in 0',
          'settings put system screen_off_timeout 5000',
          'input keyevent 26'
        ];
        exec(offCmds.join(' 2>/dev/null; ') + ' 2>/dev/null', { timeout: 3000, env: sysEnv });
      }
      return { ok: true, message: 'Layar HP dinonaktifkan (mode hemat daya).' };
    } else {
      if (os.platform() !== 'win32') {
        const onCmds = [
          'su -c "input keyevent 224 || input keyevent 26"',
          'termux-brightness 180',
          'settings put global stay_on_while_plugged_in 3',
          'settings put system screen_off_timeout 600000',
          'input keyevent 224 || input keyevent 26',
          'am start -n com.termux/.app.TermuxActivity || am start -a android.intent.action.MAIN -c android.intent.category.HOME'
        ];
        exec(onCmds.join(' 2>/dev/null; ') + ' 2>/dev/null', { timeout: 3000, env: sysEnv });
      }
      return { ok: true, message: 'Layar HP diaktifkan kembali.' };
    }
  } catch (e) {
    return { ok: false, message: 'Gagal mengontrol layar: ' + e.message };
  }
}

function rebootDevice() {
  setTimeout(() => {
    try {
      if (os.platform() !== 'win32') {
        exec('su -c reboot 2>/dev/null || reboot 2>/dev/null');
      }
    } catch (e) {}
  }, 1000);
  return { ok: true, message: 'Perintah reboot telah dikirim ke perangkat.' };
}

function setupVpsCliHelpers() {
  const home = process.env.HOME || (os.platform() === 'win32' ? os.homedir() : '/data/data/com.termux/files/home');
  const binDir = path.join(home, 'ubuntu-fs', 'usr', 'local', 'bin');
  if (fs.existsSync(binDir)) {
    try {
      const statusScript = `#!/bin/bash
echo "=========================================="
echo "      Lenz Mini Server - Live Status      "
echo "=========================================="
curl -s -u "${authConfig.username}:${authConfig.password}" http://127.0.0.1:${PANEL_PORT}/api/system/stats | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    mem = d.get("memory", {})
    cpu = d.get("cpu", {})
    bat = d.get("battery", {})
    therm = d.get("thermal", {})
    net = d.get("network", {})
    print(f"Uptime: {d.get(\\"uptimeSeconds\\", 0)//3600}h {(d.get(\\"uptimeSeconds\\", 0)%3600)//60}m")
    print(f"RAM:    {mem.get(\\"usedBytes\\", 0)//(1024*1024)}MB / {mem.get(\\"totalBytes\\", 0)//(1024*1024)}MB ({mem.get(\\"usagePercent\\", 0)}%)")
    print(f"CPU:    {cpu.get(\\"usagePercent\\", 0)}%")
    print(f"Suhu:   {therm.get(\\"cpu\\", \\"-\\\")} (SoC) | {therm.get(\\"battery\\", \\"-\\\")} (Baterai) [{therm.get(\\"status\\", \\"-\\")}]")
    print(f"Power:  {bat.get(\\"percentage\\", \\"-\\")}% ({bat.get(\\"status\\", \\"-\\")})")
    print(f"Web:    {net.get(\\"publicUrl\\") or \\"Connecting...\\"}")
except Exception as e:
    print("Gagal parse stats:", e)
' 2>/dev/null || curl -s -u "${authConfig.username}:${authConfig.password}" http://127.0.0.1:${PANEL_PORT}/api/system/stats
echo "=========================================="
`;
      fs.writeFileSync(path.join(binDir, 'panel-status'), statusScript, { mode: 0o755 });

      const restartScript = `#!/bin/bash
echo ">> Mengirim sinyal restart ke Server Panel..."
curl -s -X POST -u "${authConfig.username}:${authConfig.password}" http://127.0.0.1:${PANEL_PORT}/api/restart-panel
echo ""
echo ">> Panel sedang dimulai ulang di latar belakang."
`;
      fs.writeFileSync(path.join(binDir, 'panel-restart'), restartScript, { mode: 0o755 });

      const vpsFixScript = `#!/bin/bash
echo ">> [VPS Fix] Membersihkan lock file dan memperbaiki konfigurasi paket..."
rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
echo -e '#!/bin/sh\\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
if [ -d /var/lib/dpkg/info ]; then
  for f in /var/lib/dpkg/info/*.postinst; do
    [ -f "$f" ] && sed -i '1s|^|exit 0\\n|' "$f" 2>/dev/null || true
  done
fi
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true
apt-get update -y 2>/dev/null || true
echo "✓ Sistem paket Ubuntu VPS siap!"
`;
      fs.writeFileSync(path.join(binDir, 'vps-fix'), vpsFixScript, { mode: 0o755 });

      const vpsInstallScript = `#!/bin/bash
if [ $# -eq 0 ]; then
  echo "Penggunaan: vps-install <nama-paket>"
  exit 1
fi
rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends "$@" || true
echo "✓ Instalasi selesai!"
`;
      fs.writeFileSync(path.join(binDir, 'vps-install'), vpsInstallScript, { mode: 0o755 });
    } catch (e) {}
  }
}

// ------------------------------------------------------------------
// TUNNEL PUBLIK OTOMATIS (Web Port 8080 & VPS SSH Port 2222)
// ------------------------------------------------------------------
let currentPublicUrl = null;
let tunnelProcess = null;
let tunnelRetryTimer = null;
let tunnelFailCount = 0;

let vpsTunnelProcess = null;
let vpsTunnelRetryTimer = null;
let vpsFailCount = 0;

function findCloudflaredBin() {
  const prefix = process.env.PREFIX || '/data/data/com.termux/files/usr';
  const termuxHome = process.env.HOME || '/data/data/com.termux/files/home';

  const candidates = [
    path.join(prefix, 'bin', 'cloudflared'),
    '/data/data/com.termux/files/usr/bin/cloudflared',
    path.join(termuxHome, 'ubuntu-fs', 'usr', 'local', 'bin', 'cloudflared'),
    path.join(termuxHome, 'ubuntu-fs', 'usr', 'bin', 'cloudflared'),
    '/usr/local/bin/cloudflared',
    '/usr/bin/cloudflared',
  ];

  for (let i = 0; i < candidates.length; i++) {
    if (fs.existsSync(candidates[i])) return candidates[i];
  }

  try {
    const which = execSync('command -v cloudflared 2>/dev/null', { timeout: 1000 }).toString().trim();
    if (which) return which;
  } catch (e) {}

  return null;
}

function startPublicTunnel() {
  if (tunnelProcess) return;

  const cfBin = findCloudflaredBin();

  if (!cfBin) {
    startFallbackSshTunnel();
    return;
  }

  try {
    tunnelProcess = spawn(cfBin, ['tunnel', '--url', `http://127.0.0.1:${PANEL_PORT}`], {
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let stdoutBuffer = '';
    const checkUrl = (data) => {
      stdoutBuffer += data.toString();
      if (stdoutBuffer.length > 3000) stdoutBuffer = stdoutBuffer.slice(-1500);
      const match = stdoutBuffer.match(/https:\/\/(?!api\.)[a-zA-Z0-9-]+\.trycloudflare\.com/);
      if (match && match[0] !== currentPublicUrl) {
        currentPublicUrl = match[0];
        tunnelFailCount = 0;
        console.log(`🌐 Web Tunnel Aktif: ${currentPublicUrl}`);
      }
    };

    tunnelProcess.stdout.on('data', checkUrl);
    tunnelProcess.stderr.on('data', checkUrl);

    let errorHandled = false;
    tunnelProcess.on('close', () => {
      if (errorHandled) return;
      tunnelProcess = null;
      currentPublicUrl = null;
      tunnelFailCount++;
      const delay = Math.min(60000, 8000 * tunnelFailCount);
      clearTimeout(tunnelRetryTimer);
      tunnelRetryTimer = setTimeout(startPublicTunnel, delay);
    });

    tunnelProcess.on('error', () => {
      errorHandled = true;
      tunnelProcess = null;
      clearTimeout(tunnelRetryTimer);
      startFallbackSshTunnel();
    });
  } catch (e) {
    startFallbackSshTunnel();
  }
}

function startFallbackSshTunnel() {
  if (tunnelProcess) return;

  const sshCmd = 'ssh';
  const sshArgs = [
    '-p', '443',
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'ServerAliveInterval=30',
    '-o', 'ServerAliveCountMax=3',
    `-R0:127.0.0.1:${PANEL_PORT}`,
    'free.pinggy.io',
  ];

  try {
    tunnelProcess = spawn(sshCmd, sshArgs, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stdoutBuffer = '';
    const checkUrl = (data) => {
      stdoutBuffer += data.toString();
      if (stdoutBuffer.length > 3000) stdoutBuffer = stdoutBuffer.slice(-1500);
      const match = stdoutBuffer.match(/https:\/\/(?:[a-zA-Z0-9-._]+\.pinggy\.(?:link|online|io)|[a-zA-Z0-9-._]+\.free\.pinggy\.link|[a-zA-Z0-9-._]+\.a\.pinggy\.link|(?!api\.)[a-zA-Z0-9-]+\.trycloudflare\.com)/);
      if (match && match[0] !== currentPublicUrl) {
        currentPublicUrl = match[0];
        tunnelFailCount = 0;
        console.log(`🌐 Web Tunnel Aktif (Fallback Pinggy): ${currentPublicUrl}`);
      }
    };

    tunnelProcess.stdout.on('data', checkUrl);
    tunnelProcess.stderr.on('data', checkUrl);

    tunnelProcess.on('close', () => {
      tunnelProcess = null;
      currentPublicUrl = null;
      tunnelFailCount++;
      const delay = Math.min(60000, 10000 * tunnelFailCount);
      clearTimeout(tunnelRetryTimer);
      tunnelRetryTimer = setTimeout(startPublicTunnel, delay);
    });

    tunnelProcess.on('error', () => {
      tunnelProcess = null;
      clearTimeout(tunnelRetryTimer);
      tunnelRetryTimer = setTimeout(startPublicTunnel, 15000);
    });
  } catch (e) {}
}

async function startVpsTunnel() {
  if (vpsTunnelProcess) return;

  loadVpsConfig();
  const vpsPort = vpsConfig.port || 2222;

  const isListening = await isPortListening(vpsPort);
  if (!isListening) {
    clearTimeout(vpsTunnelRetryTimer);
    vpsTunnelRetryTimer = setTimeout(startVpsTunnel, 45000);
    return;
  }

  if (os.platform() !== 'win32') {
    try {
      execSync('pkill -f "tcp@free.pinggy.io" 2>/dev/null || true');
    } catch (e) {}
  }

  const sshCmd = 'ssh';
  const sshArgs = [
    '-p', '443',
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=/dev/null',
    '-o', 'ServerAliveInterval=30',
    '-o', 'ServerAliveCountMax=3',
    `-R0:127.0.0.1:${vpsPort}`,
    'tcp@free.pinggy.io',
  ];

  try {
    vpsTunnelProcess = spawn(sshCmd, sshArgs, { stdio: ['ignore', 'pipe', 'pipe'] });

    let vpsBuffer = '';
    const checkVps = (data) => {
      vpsBuffer += data.toString();
      if (vpsBuffer.length > 2048) vpsBuffer = vpsBuffer.slice(-1024);
      const tcpMatch = vpsBuffer.match(/(?:tcp:\/\/|ssh\s+-p\s+)([a-zA-Z0-9-._]+)(?::|\s+)([0-9]+)/i) || vpsBuffer.match(/([a-zA-Z0-9-._]+\.pinggy\.(?:link|online)):([0-9]+)/i);
      if (tcpMatch) {
        const host = tcpMatch[1];
        const port = tcpMatch[2];
        const cmd = `ssh ${vpsConfig.username}@${host} -p ${port}`;
        if (vpsConfig.publicPort !== port || vpsConfig.publicHost !== host || vpsConfig.publicCommand !== cmd) {
          vpsConfig.publicHost = host;
          vpsConfig.publicPort = port;
          vpsConfig.publicCommand = cmd;
          vpsFailCount = 0;
          console.log(`🖥 VPS SSH Publik Aktif: ${vpsConfig.publicCommand}`);
          saveVpsConfig({
            publicHost: host,
            publicPort: port,
            publicCommand: cmd,
          });
        }
      }
    };

    vpsTunnelProcess.stdout.on('data', checkVps);
    vpsTunnelProcess.stderr.on('data', checkVps);

    vpsTunnelProcess.on('close', () => {
      vpsTunnelProcess = null;
      saveVpsConfig({ publicHost: null, publicPort: null, publicCommand: null });
      vpsFailCount++;
      const delay = Math.min(60000, 12000 * vpsFailCount);
      clearTimeout(vpsTunnelRetryTimer);
      vpsTunnelRetryTimer = setTimeout(startVpsTunnel, delay);
    });

    vpsTunnelProcess.on('error', () => {
      vpsTunnelProcess = null;
      clearTimeout(vpsTunnelRetryTimer);
      vpsTunnelRetryTimer = setTimeout(startVpsTunnel, 20000);
    });
  } catch (e) {}
}

// ------------------------------------------------------------------
// FILE MANAGER HANDLER (Streaming Multipart Upload, Zip, List)
// ------------------------------------------------------------------
const DEFAULT_ROOT_DIR = BASE_DIR;

function resolveSafePath(userPath) {
  return userPath ? path.resolve(userPath) : DEFAULT_ROOT_DIR;
}

function listDirectory(dirPath) {
  const safePath = resolveSafePath(dirPath);
  if (!fs.existsSync(safePath)) {
    throw new Error('Direktori tidak ditemukan: ' + safePath);
  }

  const stat = fs.statSync(safePath);
  if (!stat.isDirectory()) {
    throw new Error('Path bukan direktori: ' + safePath);
  }

  const entries = fs.readdirSync(safePath, { withFileTypes: true });
  const items = [];

  for (const entry of entries) {
    const fullPath = path.join(safePath, entry.name);
    try {
      const itemStat = fs.statSync(fullPath);
      items.push({
        name: entry.name,
        path: fullPath.replace(/\\/g, '/'),
        isDir: entry.isDirectory(),
        sizeBytes: entry.isDirectory() ? null : itemStat.size,
        modifiedAt: itemStat.mtime.toISOString(),
      });
    } catch {}
  }

  items.sort((a, b) => {
    if (a.isDir && !b.isDir) return -1;
    if (!a.isDir && b.isDir) return 1;
    return a.name.localeCompare(b.name);
  });

  return {
    currentPath: safePath.replace(/\\/g, '/'),
    parentPath: path.dirname(safePath).replace(/\\/g, '/'),
    homeDir: (process.env.HOME || BASE_DIR).replace(/\\/g, '/'),
    serverDir: BASE_DIR.replace(/\\/g, '/'),
    items,
  };
}

function handleStreamingUpload(req, targetDir, callback) {
  const contentType = req.headers['content-type'] || '';
  const boundaryMatch = contentType.match(/boundary=(?:"([^"]+)"|([^;]+))/i);
  if (!boundaryMatch) {
    return callback(new Error('Boundary multipart tidak ditemukan'));
  }

  const boundary = boundaryMatch[1] || boundaryMatch[2];
  const boundaryBuffer = Buffer.from('--' + boundary);

  let state = 'WAIT_BOUNDARY';
  let buffer = Buffer.alloc(0);
  let currentFileStream = null;
  let uploadedFiles = [];
  const streamPromises = [];

  req.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);

    let running = true;
    while (running) {
      if (state === 'WAIT_BOUNDARY') {
        const bIdx = buffer.indexOf(boundaryBuffer);
        if (bIdx === -1) {
          running = false;
          break;
        }
        buffer = buffer.slice(bIdx + boundaryBuffer.length);
        state = 'WAIT_HEADER';
      } else if (state === 'WAIT_HEADER') {
        if (buffer.length >= 2 && buffer[0] === 45 && buffer[1] === 45) {
          running = false;
          break;
        }

        const headerEndIdx = buffer.indexOf(Buffer.from('\r\n\r\n'));
        if (headerEndIdx === -1) {
          running = false;
          break;
        }

        const headerStr = buffer.slice(0, headerEndIdx).toString('utf8');
        buffer = buffer.slice(headerEndIdx + 4);

        const filenameMatch = headerStr.match(/filename="([^"]+)"/i);
        if (filenameMatch) {
          const rawRel = filenameMatch[1].replace(/\\/g, '/');
          const cleanRel = path.normalize(rawRel).replace(/^(\.\.[\/\\])+/, '').replace(/^[\/\\]+/, '');
          const destPath = path.resolve(targetDir, cleanRel);

          if (!destPath.startsWith(path.resolve(targetDir))) {
            throw new Error('Akses direktori tidak sah');
          }

          const destDir = path.dirname(destPath);
          if (!fs.existsSync(destDir)) {
            fs.mkdirSync(destDir, { recursive: true });
          }

          const ws = fs.createWriteStream(destPath);
          streamPromises.push(new Promise((resolve, reject) => {
            ws.on('finish', resolve);
            ws.on('error', reject);
          }));
          currentFileStream = ws;
          uploadedFiles.push(cleanRel);
          state = 'READ_FILE_DATA';
        } else {
          state = 'READ_FIELD_DATA';
        }
      } else if (state === 'READ_FILE_DATA') {
        const nextBIdx = buffer.indexOf(boundaryBuffer);
        if (nextBIdx === -1) {
          if (buffer.length > boundaryBuffer.length + 4) {
            const flushLen = buffer.length - (boundaryBuffer.length + 4);
            const chunkToWrite = buffer.slice(0, flushLen);
            currentFileStream.write(chunkToWrite);
            buffer = buffer.slice(flushLen);
          }
          running = false;
        } else {
          let fileDataEnd = nextBIdx;
          if (fileDataEnd >= 2 && buffer[fileDataEnd - 2] === 13 && buffer[fileDataEnd - 1] === 10) {
            fileDataEnd -= 2;
          }
          const finalChunk = buffer.slice(0, fileDataEnd);
          currentFileStream.end(finalChunk);
          currentFileStream = null;

          buffer = buffer.slice(nextBIdx + boundaryBuffer.length);
          state = 'WAIT_HEADER';
        }
      } else if (state === 'READ_FIELD_DATA') {
        const nextBIdx = buffer.indexOf(boundaryBuffer);
        if (nextBIdx === -1) {
          buffer = Buffer.alloc(0);
          running = false;
        } else {
          buffer = buffer.slice(nextBIdx + boundaryBuffer.length);
          state = 'WAIT_HEADER';
        }
      }
    }
  });

  req.on('end', () => {
    if (currentFileStream) currentFileStream.end();
    Promise.all(streamPromises)
      .then(() => callback(null, uploadedFiles))
      .catch(callback);
  });

  req.on('error', (err) => {
    if (currentFileStream) currentFileStream.end();
    callback(err);
  });
}

function sendJSON(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-cache',
  });
  res.end(body);
}

function parseJSONBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(new Error('Format JSON tidak valid'));
      }
    });
    req.on('error', reject);
  });
}

function getPm2Status() {
  let isInstalled = false;
  try {
    execSync('pm2 -v', { timeout: 2000, stdio: 'ignore' });
    isInstalled = true;
  } catch (e) {}

  if (!isInstalled) {
    return {
      installed: false,
      running: false,
      available: false,
      processes: [],
      message: 'PM2 tidak terpasang di sistem.',
    };
  }

  try {
    const out = execSync('pm2 jlist 2>/dev/null', { timeout: 3000 }).toString();
    const list = JSON.parse(out);
    if (Array.isArray(list)) {
      return {
        installed: true,
        running: true,
        available: true,
        processes: list.map((p) => {
          const env = p.pm2_env || {};
          const monit = p.monit || {};
          return {
            pm_id: p.pm_id,
            name: p.name || 'app',
            pid: p.pid || '-',
            status: env.status || 'unknown',
            uptimeMs: env.pm_uptime ? Date.now() - env.pm_uptime : 0,
            restarts: env.restart_time || 0,
            memory: monit.memory || 0,
            memoryBytes: monit.memory || 0,
            cpu: monit.cpu || 0,
            cpuPercent: monit.cpu || 0,
          };
        }),
      };
    }
  } catch (e) {}
  return {
    installed: true,
    running: false,
    available: true,
    processes: [],
    message: 'PM2 terpasang, namun belum ada proses yang berjalan.',
  };
}

const activeSockets = new Set();

function getPm2Logs(name, lines = 100) {
  try {
    const target = name ? String(name).replace(/[^a-zA-Z0-9_.-]/g, '') : '';
    const cmd = target ? `pm2 logs "${target}" --lines ${lines} --nostream 2>&1` : `pm2 logs --lines ${lines} --nostream 2>&1`;
    const out = execSync(cmd, { timeout: 3500 }).toString();
    return out || '(log PM2 kosong)';
  } catch (e) {
    return 'Gagal memuat log PM2 (periksa apakah PM2 terpasang dan proses sedang berjalan).';
  }
}

function getWebsiteLogs(lines = 150) {
  checkAndRotateLogs();
  const candidates = [
    path.join(LOG_DIR, 'panel.log'),
    path.join(LOG_DIR, 'vps.log'),
  ];
  let logs = '';
  for (let i = 0; i < candidates.length; i++) {
    const fPath = candidates[i];
    if (fs.existsSync(fPath)) {
      try {
        const content = fs.readFileSync(fPath, 'utf8');
        if (content.trim()) {
          const arr = content.split('\n');
          logs += `=== [ ${path.basename(fPath)} ] ===\n` + arr.slice(Math.max(0, arr.length - lines)).join('\n') + '\n\n';
        }
      } catch (e) {}
    }
  }
  return logs.trim() || '(belum ada log server)';
}

function restartPanel() {
  if (tunnelProcess) {
    try { tunnelProcess.kill('SIGKILL'); } catch (e) {}
  }
  if (vpsTunnelProcess) {
    try { vpsTunnelProcess.kill('SIGKILL'); } catch (e) {}
  }

  setTimeout(() => {
    for (const sock of activeSockets) {
      try { sock.destroy(); } catch (e) {}
    }
    try { server.close(); } catch (e) {}
    process.exit(0);
  }, 300);
}

// ------------------------------------------------------------------
// ROUTER & HTTP SERVER
// ------------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
  const pathname = parsedUrl.pathname;
  const clientIP = getClientIP(req);

  // Public Endpoints
  if (req.method === 'GET' && pathname === '/api/auth/status') {
    const isAuth = checkAuth(req);
    sendJSON(res, 200, { authenticated: isAuth });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/auth/login') {
    const attempt = failedAttempts.get(clientIP) || { count: 0, lockedUntil: 0 };
    if (attempt.lockedUntil > Date.now()) {
      const waitSec = Math.ceil((attempt.lockedUntil - Date.now()) / 1000);
      sendJSON(res, 429, { ok: false, message: `Terlalu banyak percobaan. Tunggu ${waitSec} detik.` });
      return;
    }

    try {
      const body = await parseJSONBody(req);
      const user = (body.username || '').trim();
      const pass = (body.password || '').trim();

      if (user === authConfig.username && pass === authConfig.password) {
        failedAttempts.delete(clientIP);
        const token = crypto.randomBytes(32).toString('hex');
        createSession(token, user, clientIP);

        res.setHeader('Set-Cookie', `session_token=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000`);
        sendJSON(res, 200, { ok: true, token, username: user, message: 'Login berhasil.' });
      } else {
        attempt.count = (attempt.count || 0) + 1;
        if (attempt.count >= 5) {
          attempt.lockedUntil = Date.now() + 60000;
        }
        failedAttempts.set(clientIP, attempt);
        sendJSON(res, 401, { ok: false, message: 'Username atau password salah.' });
      }
    } catch {
      sendJSON(res, 400, { ok: false, message: 'Payload tidak valid.' });
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/auth/logout') {
    const cookies = parseCookies(req);
    if (cookies.session_token) deleteSession(cookies.session_token);
    res.setHeader('Set-Cookie', 'session_token=; Path=/; HttpOnly; Max-Age=0');
    sendJSON(res, 200, { ok: true, message: 'Logout berhasil.' });
    return;
  }

  // Serve UI Frontend
  if (req.method === 'GET' && (pathname === '/' || pathname === '/index.html')) {
    const indexPath = path.join(__dirname, 'public', 'index.html');
    fs.readFile(indexPath, 'utf8', (err, data) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('Gagal membaca index.html');
        return;
      }
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
        'Pragma': 'no-cache',
        'Expires': '0',
      });
      res.end(data);
    });
    return;
  }

  // Auth Guard for API
  if (pathname.startsWith('/api/')) {
    if (!checkAuth(req)) {
      sendJSON(res, 401, { ok: false, error: 'Unauthorized', message: 'Sesi login diperlukan.' });
      return;
    }
  }

  // Account Settings (Change Username / Password)
  if (req.method === 'GET' && pathname === '/api/settings/account') {
    sendJSON(res, 200, { ok: true, username: authConfig.username });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/settings/account') {
    try {
      const body = await parseJSONBody(req);
      const currentPassword = (body.currentPassword || '').trim();
      const newUsername = (body.newUsername || '').trim();
      const newPassword = (body.newPassword || '').trim();

      if (currentPassword !== authConfig.password) {
        sendJSON(res, 400, { ok: false, message: 'Password saat ini salah.' });
        return;
      }

      if (!newUsername && !newPassword) {
        sendJSON(res, 400, { ok: false, message: 'Tidak ada perubahan yang dimasukkan.' });
        return;
      }

      if (newUsername && newUsername.length < 3) {
        sendJSON(res, 400, { ok: false, message: 'Username baru minimal 3 karakter.' });
        return;
      }

      if (newPassword && newPassword.length < 5) {
        sendJSON(res, 400, { ok: false, message: 'Password baru minimal 5 karakter.' });
        return;
      }

      saveAuthConfig(newUsername || authConfig.username, newPassword || authConfig.password);
      sendJSON(res, 200, {
        ok: true,
        username: authConfig.username,
        message: 'Username & Password admin berhasil diperbarui!'
      });
    } catch (e) {
      sendJSON(res, 400, { ok: false, message: 'Gagal memperbarui pengaturan akun: ' + e.message });
    }
    return;
  }

  // Monitoring
  if (req.method === 'GET' && pathname === '/api/system/stats') {
    sendJSON(res, 200, getSystemStats());
    return;
  }

  // Logs
  if (req.method === 'GET' && pathname === '/api/logs/website') {
    sendJSON(res, 200, { ok: true, logs: getWebsiteLogs() });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/logs/clear') {
    try {
      if (fs.existsSync(LOG_DIR)) {
        const files = fs.readdirSync(LOG_DIR);
        for (let i = 0; i < files.length; i++) {
          if (files[i].endsWith('.log')) {
            fs.writeFileSync(path.join(LOG_DIR, files[i]), `[${new Date().toISOString()}] Log dibersihkan oleh pengguna.\n`);
          }
        }
      }
      sendJSON(res, 200, { ok: true, message: 'Semua berkas log server berhasil dibersihkan.' });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: 'Gagal membersihkan log: ' + e.message });
    }
    return;
  }

  // PM2 Management
  if (req.method === 'GET' && pathname === '/api/pm2/status') {
    sendJSON(res, 200, getPm2Status());
    return;
  }

  if (req.method === 'GET' && pathname === '/api/pm2/logs') {
    const pm2Name = parsedUrl.searchParams.get('name') || '';
    sendJSON(res, 200, { ok: true, logs: getPm2Logs(pm2Name) });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/pm2/action') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      try {
        const data = JSON.parse(body || '{}');
        const action = data.action;
        const target = (data.name || 'all').replace(/[^a-zA-Z0-9_.-]/g, '');
        if (['restart', 'stop', 'start', 'delete'].indexOf(action) === -1) {
          sendJSON(res, 400, { ok: false, message: 'Aksi PM2 tidak valid.' });
          return;
        }
        exec(`pm2 ${action} "${target}" 2>&1`, { timeout: 5000 }, (err, stdout) => {
          if (err) {
            sendJSON(res, 500, { ok: false, message: 'Gagal memproses aksi PM2: ' + (stdout || err.message) });
          } else {
            sendJSON(res, 200, { ok: true, message: `Berhasil menjalankan pm2 ${action} ${target}`, output: stdout });
          }
        });
      } catch (e) {
        sendJSON(res, 400, { ok: false, message: 'Payload tidak valid.' });
      }
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/restart-panel') {
    sendJSON(res, 200, { ok: true, message: 'Server panel sedang dimulai ulang...' });
    restartPanel();
    return;
  }

  // VPS Controls
  if (req.method === 'GET' && pathname === '/api/vps/status') {
    sendJSON(res, 200, { ok: true, running: lastVpsRunningState, vps: vpsConfig });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/vps/start') {
    sendJSON(res, 200, startVpsService());
    return;
  }

  if (req.method === 'POST' && pathname === '/api/vps/stop') {
    sendJSON(res, 200, stopVpsService());
    return;
  }

  if (req.method === 'POST' && pathname === '/api/vps/restart') {
    const result = await restartVpsService();
    sendJSON(res, 200, result);
    return;
  }

  // Device Controls
  if (req.method === 'POST' && pathname === '/api/tunnel/reconnect') {
    if (tunnelProcess) {
      try { tunnelProcess.kill('SIGKILL'); } catch (e) {}
      tunnelProcess = null;
    }
    currentPublicUrl = null;
    clearTimeout(tunnelRetryTimer);
    setTimeout(startPublicTunnel, 500);
    sendJSON(res, 200, { ok: true, message: 'Cloudflare Tunnel sedang dihubungkan ulang...' });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/device/screen-off') {
    sendJSON(res, 200, controlScreen('off'));
    return;
  }

  if (req.method === 'POST' && pathname === '/api/device/screen-on') {
    sendJSON(res, 200, controlScreen('on'));
    return;
  }

  if (req.method === 'POST' && pathname === '/api/device/reboot') {
    sendJSON(res, 200, rebootDevice());
    return;
  }

  // File Manager Endpoints
  if (req.method === 'GET' && pathname === '/api/files/list') {
    const qPath = parsedUrl.searchParams.get('path') || DEFAULT_ROOT_DIR;
    try {
      const data = listDirectory(qPath);
      sendJSON(res, 200, { ok: true, data });
    } catch (e) {
      sendJSON(res, 400, { ok: false, message: e.message });
    }
    return;
  }

  if (req.method === 'GET' && pathname === '/api/files/download') {
    const filePath = parsedUrl.searchParams.get('path');
    if (!filePath || !fs.existsSync(filePath)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('File tidak ditemukan');
      return;
    }

    const stat = fs.statSync(filePath);
    if (stat.isDirectory()) {
      const folderName = path.basename(filePath);
      const parentDir = path.dirname(filePath);

      res.writeHead(200, {
        'Content-Type': 'application/zip',
        'Content-Disposition': `attachment; filename="${encodeURIComponent(folderName)}.zip"`,
      });

      const zipProc = spawn('zip', ['-r', '-', folderName], { cwd: parentDir });
      zipProc.stdout.pipe(res);
      req.on('close', () => zipProc.kill());
      return;
    }

    const filename = path.basename(filePath);
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Length': stat.size,
      'Content-Disposition': `attachment; filename="${encodeURIComponent(filename)}"`,
    });
    fs.createReadStream(filePath).pipe(res);
    return;
  }

  if (req.method === 'POST' && pathname === '/api/files/upload') {
    const targetDir = resolveSafePath(parsedUrl.searchParams.get('dir'));
    if (!fs.existsSync(targetDir)) {
      sendJSON(res, 400, { ok: false, message: 'Direktori tujuan tidak ada.' });
      return;
    }

    handleStreamingUpload(req, targetDir, (err, uploadedFiles) => {
      if (err) {
        sendJSON(res, 500, { ok: false, message: 'Upload gagal: ' + err.message });
      } else {
        sendJSON(res, 200, { ok: true, message: `Berhasil mengupload ${uploadedFiles.length} file & folder.`, files: uploadedFiles });
      }
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/files/unzip') {
    const filePath = resolveSafePath(parsedUrl.searchParams.get('path'));
    if (!fs.existsSync(filePath)) {
      sendJSON(res, 404, { ok: false, message: 'File ZIP tidak ditemukan.' });
      return;
    }

    const targetDir = path.dirname(filePath);
    const isWin = os.platform() === 'win32';
    const unzipCmd = isWin
      ? `tar -xf "${filePath}" -C "${targetDir}"`
      : `unzip -o "${filePath}" -d "${targetDir}"`;

    exec(unzipCmd, { timeout: 60000 }, (err, stdout, stderr) => {
      if (err) {
        sendJSON(res, 500, { ok: false, message: 'Ekstrak gagal: ' + (stderr || err.message) });
      } else {
        sendJSON(res, 200, { ok: true, message: 'File ZIP berhasil diekstrak!' });
      }
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/files/mkdir') {
    try {
      const body = await parseJSONBody(req);
      const targetDir = path.join(resolveSafePath(body.parentPath), body.name);
      fs.mkdirSync(targetDir, { recursive: true });
      sendJSON(res, 200, { ok: true, message: 'Folder berhasil dibuat.' });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/files/create') {
    try {
      const body = await parseJSONBody(req);
      const targetFile = path.join(resolveSafePath(body.parentPath), body.name);
      if (!fs.existsSync(targetFile)) {
        fs.writeFileSync(targetFile, '', 'utf8');
      }
      sendJSON(res, 200, { ok: true, message: 'File berhasil dibuat.' });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/files/delete') {
    try {
      const body = await parseJSONBody(req);
      const target = resolveSafePath(body.path);
      if (fs.existsSync(target)) {
        const stat = fs.statSync(target);
        if (stat.isDirectory()) {
          fs.rmSync(target, { recursive: true, force: true });
        } else {
          fs.unlinkSync(target);
        }
      }
      sendJSON(res, 200, { ok: true, message: 'Berhasil dihapus.' });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/files/rename') {
    try {
      const body = await parseJSONBody(req);
      const oldPath = resolveSafePath(body.oldPath);
      const newPath = path.join(path.dirname(oldPath), body.newName);
      fs.renameSync(oldPath, newPath);
      sendJSON(res, 200, { ok: true, message: 'Nama berhasil diubah.' });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/files/content') {
    try {
      const body = await parseJSONBody(req);
      const target = resolveSafePath(body.path);
      if (!fs.existsSync(target)) {
        sendJSON(res, 404, { ok: false, message: 'File tidak ditemukan.' });
        return;
      }
      const stat = fs.statSync(target);
      if (stat.size > 2 * 1024 * 1024) {
        sendJSON(res, 400, { ok: false, message: 'File terlalu besar untuk diedit langsung di web (> 2MB).' });
        return;
      }
      const content = fs.readFileSync(target, 'utf8');
      sendJSON(res, 200, { ok: true, content });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/files/save') {
    try {
      const body = await parseJSONBody(req);
      const target = resolveSafePath(body.path);
      fs.writeFileSync(target, body.content || '', 'utf8');
      sendJSON(res, 200, { ok: true, message: 'File berhasil disimpan.' });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  // Web Terminal
  if (req.method === 'POST' && pathname === '/api/terminal/stream') {
    try {
      const body = await parseJSONBody(req);
      const command = (body.command || '').trim();
      const termuxHome = process.env.HOME || (os.platform() === 'win32' ? os.homedir() : '/data/data/com.termux/files/home');
      const jobId = body.id || ('job_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7));

      let targetCwd = termuxHome;
      if (body.cwd) {
        let reqCwd = body.cwd;
        if (reqCwd === '~' || reqCwd.startsWith('~/')) {
          reqCwd = path.join(termuxHome, reqCwd === '~' ? '' : reqCwd.substring(2));
        }
        if (fs.existsSync(reqCwd)) {
          targetCwd = reqCwd;
        }
      }

      if (!command) {
        sendJSON(res, 400, { ok: false, message: 'Perintah tidak boleh kosong.' });
        return;
      }

      const isWin = os.platform() === 'win32';
      const shell = isWin ? 'cmd.exe' : 'bash';
      const delim = '___TERM_PWD___';

      const script = isWin
        ? `cd /d "${targetCwd}" & ${command} & echo ${delim}%CD%`
        : `cd "${targetCwd}"\n${command}\necho "${delim}$PWD"`;

      const shellArgs = isWin ? ['/c', script] : ['-c', script];

      res.writeHead(200, {
        'Content-Type': 'text/plain; charset=utf-8',
        'Transfer-Encoding': 'chunked',
        'X-Content-Type-Options': 'nosniff',
        'Cache-Control': 'no-cache, no-transform',
        'Connection': 'keep-alive',
      });

      const termEnv = Object.assign({}, process.env, {
        PYTHONUNBUFFERED: '1',
        FORCE_COLOR: '1',
      });

      const child = spawn(shell, shellArgs, {
        cwd: targetCwd,
        env: termEnv,
        detached: !isWin,
      });

      activeTerminalJobs.set(jobId, { child, pid: child.pid });

      res.write(JSON.stringify({ type: 'init', jobId, pid: child.pid }) + '\n');

      let pwdBuffer = '';
      const onData = (chunk, type) => {
        const str = chunk.toString();
        if (str.includes(delim)) {
          const parts = str.split(delim);
          if (parts[0]) {
            res.write(JSON.stringify({ type, data: parts[0] }) + '\n');
          }
          pwdBuffer += parts.slice(1).join(delim);
        } else if (pwdBuffer) {
          pwdBuffer += str;
        } else {
          res.write(JSON.stringify({ type, data: str }) + '\n');
        }
      };

      child.stdout.on('data', (d) => onData(d, 'out'));
      child.stderr.on('data', (d) => onData(d, 'err'));

      child.on('close', (exitCode) => {
        activeTerminalJobs.delete(jobId);
        let finalCwd = targetCwd;
        const rawPwd = pwdBuffer.trim().split('\n')[0];
        if (rawPwd && fs.existsSync(rawPwd)) {
          finalCwd = rawPwd;
        }
        res.write(JSON.stringify({ type: 'end', exitCode, cwd: finalCwd }) + '\n');
        res.end();
      });

      child.on('error', (err) => {
        activeTerminalJobs.delete(jobId);
        res.write(JSON.stringify({ type: 'err', data: `\n[Error: ${err.message}]\n` }) + '\n');
        res.write(JSON.stringify({ type: 'end', exitCode: 1, cwd: targetCwd }) + '\n');
        res.end();
      });
    } catch (e) {
      if (!res.headersSent) {
        sendJSON(res, 500, { ok: false, message: e.message });
      } else {
        res.end();
      }
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/terminal/input') {
    try {
      const body = await parseJSONBody(req);
      const jobId = body.id;
      const input = body.input !== undefined ? String(body.input) : '';
      if (!jobId || !activeTerminalJobs.has(jobId)) {
        sendJSON(res, 404, { ok: false, message: 'Tidak ada proses terminal aktif dengan ID tersebut.' });
        return;
      }
      const job = activeTerminalJobs.get(jobId);
      if (job && job.child && job.child.stdin && !job.child.stdin.destroyed) {
        job.child.stdin.write(input + '\n');
        sendJSON(res, 200, { ok: true, message: 'Input berhasil dikirim ke proses.' });
      } else {
        sendJSON(res, 400, { ok: false, message: 'Stdin proses tidak aktif.' });
      }
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/terminal/kill') {
    try {
      const body = await parseJSONBody(req);
      const jobId = body.id;
      if (!jobId || !activeTerminalJobs.has(jobId)) {
        sendJSON(res, 200, { ok: true, message: 'Tidak ada proses aktif dengan ID tersebut.' });
        return;
      }
      const job = activeTerminalJobs.get(jobId);
      activeTerminalJobs.delete(jobId);
      if (job && job.child) {
        try {
          if (os.platform() !== 'win32') {
            process.kill(-job.child.pid, 'SIGINT');
          } else {
            job.child.kill('SIGINT');
          }
        } catch (e) {
          try {
            job.child.kill('SIGKILL');
          } catch (e2) {}
        }
      }
      sendJSON(res, 200, { ok: true, message: 'Proses terminal berhasil dihentikan (Ctrl + C).' });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/terminal/exec') {
    try {
      const body = await parseJSONBody(req);
      const command = (body.command || '').trim();
      const termuxHome = process.env.HOME || (os.platform() === 'win32' ? os.homedir() : '/data/data/com.termux/files/home');

      let targetCwd = termuxHome;
      if (body.cwd) {
        let reqCwd = body.cwd;
        if (reqCwd === '~' || reqCwd.startsWith('~/')) {
          reqCwd = path.join(termuxHome, reqCwd === '~' ? '' : reqCwd.substring(2));
        }
        if (fs.existsSync(reqCwd)) {
          targetCwd = reqCwd;
        }
      }

      if (!command) {
        sendJSON(res, 400, { ok: false, message: 'Perintah tidak boleh kosong.' });
        return;
      }

      const isWin = os.platform() === 'win32';
      const shell = isWin ? 'cmd.exe' : 'bash';
      const delim = '___TERM_PWD___';

      const script = isWin
        ? `cd /d "${targetCwd}" & ${command} & echo ${delim}%CD%`
        : `cd "${targetCwd}"\n${command}\necho "${delim}$PWD"`;

      const shellArgs = isWin ? ['/c', script] : ['-c', script];

      const child = spawn(shell, shellArgs, {
        cwd: targetCwd,
        env: process.env,
        timeout: 600000,
      });

      let stdout = '';
      let stderr = '';

      child.stdout.on('data', (d) => (stdout += d.toString()));
      child.stderr.on('data', (d) => (stderr += d.toString()));

      child.on('close', (exitCode) => {
        let finalCwd = targetCwd;
        const delimIdx = stdout.lastIndexOf(delim);
        if (delimIdx !== -1) {
          const rawPwd = stdout.substring(delimIdx + delim.length).trim();
          stdout = stdout.substring(0, delimIdx);
          if (rawPwd && fs.existsSync(rawPwd)) {
            finalCwd = rawPwd;
          }
        }

        sendJSON(res, 200, {
          ok: true,
          exitCode,
          stdout,
          stderr,
          cwd: finalCwd,
        });
      });

      child.on('error', (err) => {
        sendJSON(res, 500, { ok: false, message: err.message });
      });
    } catch (e) {
      sendJSON(res, 500, { ok: false, message: e.message });
    }
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('404 Not Found');
});

// ------------------------------------------------------------------
// INISIALISASI & START SERVER
// ------------------------------------------------------------------
server.on('connection', (sock) => {
  activeSockets.add(sock);
  sock.on('close', () => activeSockets.delete(sock));
});

server.listen(PANEL_PORT, '0.0.0.0', () => {
  const localIps = getLocalIPs();
  console.log(`\n==================================================`);
  console.log(`🚀 Lenz Mini Server Aktif di Port ${PANEL_PORT}`);
  console.log(`🏠 Akses Lokal: http://127.0.0.1:${PANEL_PORT}`);
  localIps.forEach((ip) => {
    console.log(`   - http://${ip.address}:${PANEL_PORT} (${ip.iface})`);
  });
  console.log(`🔑 Login: user="${authConfig.username}" pass="${authConfig.password}"`);
  console.log(`==================================================\n`);

  startPublicTunnel();
  startVpsTunnel();
  setupVpsCliHelpers();
});

// Proteksi sinyal: Abaikan Ctrl+C agar server tidak sengaja terhenti di terminal
process.on('SIGINT', () => {
  console.log('>> [SIGINT Diabaikan] Server diproteksi agar tetap berjalan terus. Gunakan tombol restart di dashboard atau pkill node.');
});

// Proteksi global: Tangkap Promise rejection & exception agar server tidak mati mendadak
process.on('unhandledRejection', (reason) => {
  console.error('[unhandledRejection] Ditangkap:', reason && reason.message ? reason.message : String(reason));
});

process.on('uncaughtException', (err) => {
  console.error('[uncaughtException] Ditangkap:', err && err.message ? err.message : String(err));
});
