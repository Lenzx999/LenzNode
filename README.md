# LenzNode — Mini Server & OpenSSH (Native Termux Edition)

Transformasikan smartphone Android (**Android 5.0 s/d 16+**, ARM32/ARM64/x86_64) menjadi **Mini Server Linux & OpenSSH** hemat daya, ringan, dan siap pakai 24/7.

> **Arsitektur Native Termux**: Berjalan tanpa PRootDistro (hemat RAM hanya ~30–50 MB, tanpa overhead CPU, hemat penyimpanan 2 GB, dan bebas risiko bootloop).

---

## Fitur Utama

* **Web Dashboard Glassmorphism (Port 8080)**
  * Antarmuka modern dengan dukungan tema gelap (*dark mode*) dan terang (*frosted glass*).
  * Kompresi otomatis HTTP (Gzip/Deflate) untuk transfer data cepat dan hemat kuota.
  * Keamanan autentikasi berbasis sesi dengan proteksi anti-brute force.
* **Monitoring Daya & Baterai (Android 5 – 16+)**
  * Deteksi telemetri pengisian daya real-time: **Watt (Daya)**, **Tegangan (Volt)**, **Arus (Ampere)**, dan **Suhu Baterai**.
  * Multi-Tier Scanner: Sysfs, Termux:API, dan Dynamic CPU Modeler (akurat di Android 14/15/16 tanpa root).
* **Monitoring Spesifikasi & Metrik Sistem**
  * Pantau beban CPU %, penggunaan RAM, sisa kapasitas storage, uptime sistem, serta sensor suhu SoC.
* **Akses Publik Bebas Blokir (Cloudflare Tunnel)**
  * Terhubung otomatis ke Cloudflare Tunnel untuk akses jarak jauh dari luar jaringan Wi-Fi tanpa port forwarding.
  * URL publik tunnel otomatis ditampilkan langsung di terminal saat server pertama kali dijalankan.
* **Web File Manager**
  * Akses direktori penyimpanan Termux (`~`) dan penyimpanan internal Android (`/sdcard`).
  * Upload, download (otomatis ZIP), buat berkas/folder, rename, delete, serta built-in text editor.
* **Web Terminal & Console**
  * Eksekusi shell Linux langsung dari browser dengan live streaming output, riwayat perintah, dan tombol interupsi Ctrl + C.
* **Manajer Log & PM2 Process Manager**
  * Monitoring live log server serta status proses Node.js di PM2 (Start, Stop, Restart, Log).
* **OpenSSH Server Native (Port 2222)**
  * Akses SSH aman dan cepat langsung ke shell Termux.

---

## Preview Tampilan Web Dashboard

| Dashboard Monitoring (Desktop) | Tampilan Mobile |
| :---: | :---: |
| ![Dashboard Desktop](screenshots/monitoring.png) | ![Tampilan Mobile](screenshots/mobile_view.png) |

| Web File Manager | Web Terminal & Console |
| :---: | :---: |
| ![File Manager](screenshots/file_manager.png) | ![Terminal](screenshots/terminal.png) |

| Server & PM2 Logs |
| :---: |
| ![Server Logs](screenshots/logs_pm2.png) |

---

## Kebutuhan Sistem & Kompatibilitas

| Parameter | Spesifikasi Minimal | Rekomendasi |
| :--- | :--- | :--- |
| **Sistem Operasi** | Android 5.0 (Lollipop / SDK 21) | Android 7.0 s/d 16+ |
| **Arsitektur CPU** | ARM32 (`armhf`), x86 | ARM64 (`aarch64`), x86_64 |
| **Kebutuhan RAM** | 512 MB fisik | 1 GB – 2 GB+ |
| **Ruang Penyimpanan** | Minimal 250 MB | 1 GB+ |
| **Akses Root** | Tidak Perlu (Non-Root) | Non-Root (HP Root tetap didukung) |
| **Pemakaian RAM Idle** | ~35 MB – 55 MB | Sangat hemat baterai |

---

## Panduan Instalasi (1 Perintah)

Buka aplikasi **Termux**, lalu jalankan perintah berikut:

```bash
pkg update -y && pkg install git -y
git clone https://github.com/Lenzx999/LenzNode.git
cd LenzNode
bash install.sh
```

> **Catatan Termux**: Gunakan aplikasi Termux dari **F-Droid** atau GitHub Releases resmi. Untuk Android 5 & 6, gunakan rilis khusus Termux `apt-android-5`. Hindari Termux dari Google Play Store karena sudah tidak aktif.

---

## Akses Dashboard & SSH

Saat server berjalan (`bash ~/LenzNode/start.sh` atau perintah `lenznode`), terminal akan menampilkan informasi alamat akses:

```text
  ╭─ LenzNode ──────────────────────────────
  │  ●  panel       port 8080
  │  ●  ssh         port 2222
  │  ●  tunnel      connected
  │
  │  ➜  Local:    http://127.0.0.1:8080/
  │  ➜  Network:  http://192.168.1.15:8080/
  │  ➜  Public:   https://xxxx-xxxx.trycloudflare.com
  ╰─ Ready ─────────────────────────────────
```

* **Web Dashboard**: Buka browser di URL lokal `http://<IP-HP>:8080` atau URL Publik Cloudflare.
  * **User default**: `admin`
  * **Password default**: `admin123` *(Dapat diganti pada menu Settings)*
* **SSH Remote Console**:
  ```bash
  ssh <user-termux>@<IP-HP> -p 2222
  ```

---

## Perintah Kontrol (`start.sh`)

Gunakan perintah cepat berikut di Termux:

```bash
./start.sh          # Menjalankan server (Pilihan Interaktif: Dual Mode)
                    # [1] Lokal Saja (Wi-Fi / LAN, Hemat Kuota & RAM)
                    # [2] Dengan Public Tunnel Cloudflare Online 24/7
./start.sh --local  # Menjalankan langsung mode lokal tanpa menu
./start.sh --tunnel # Menjalankan langsung dengan tunnel Cloudflare
./start.sh status   # Mengecek status layanan & link tunnel
./start.sh stop     # Menghentikan server
./start.sh restart  # Memulai ulang server
./start.sh logs     # Memantau log live
./start.sh update   # Memperbarui source code dari GitHub
```

---

## Lisensi & Developer

* **Developer**: Lenz
* **Lisensi**: MIT License
