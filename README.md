# LenzNode — Mini Server & OpenSSH (Native Termux Edition)

Transformasikan smartphone Android lama atau baru (**Android 5.0 s/d 16+**, arsitektur ARM32/ARM64/x86_64) menjadi **Mini Server Linux & OpenSSH** berfitur lengkap yang dapat dikendalikan penuh secara lokal maupun jarak jauh melalui Web Dashboard modern.

> ⚡ **Optimasi Baru (v2.0)**: Menggunakan arsitektur **100% Native Termux** tanpa PRootDistro. Jauh lebih ringan (hanya ~40–60 MB RAM), hemat penyimpanan hingga 2 GB, performa CPU native tanpa emulasi, bebas risiko bootloop, serta mendukung monitoring daya & watt baterai akurat hingga Android 16!

---

## 🌟 Fitur Utama Server

* 🌐 **Web Dashboard Modern & Clean (Port 8080)**
  * Desain antarmuka gelap (*OLED dark mode*) modern berbasis Design DNA, responsif untuk layar HP, tablet, maupun laptop/PC.
  * Autentikasi sesi aman dengan proteksi *anti-brute force*.
* 🔋 **Monitoring Daya & Baterai Multi-Tier (Android 5 – 16+)**
  * Mendeteksi pengisian daya secara *real-time*: **Daya (Watt)** `+X.XX W` (Charging) / `-X.XX W` (Discharging), **Tegangan (Volt)**, **Arus (Ampere)**, dan **Suhu Baterai**.
  * Multi-Tier Hardware Scanner: Sysfs, Termux:API, Framework Android, serta Dynamic CPU Modeler (tetap akurat di Android 14/15/16 meskipun tanpa root).
* 📊 **Monitoring Sistem Real-Time**
  * Pantau penggunaan CPU %, RAM (MB/%), Kapasitas Penyimpanan Disk, Uptime, Baterai, dan Sensor Suhu SoC & Core CPU secara *live*.
* 🌍 **Akses Publik Bebas Blokir (Cloudflare Tunnel)**
  * Dilengkapi tunnel otomatis agar dashboard dapat diakses dari luar jaringan (data seluler/luar kota) tanpa perlu IP publik statis atau port forwarding modem.
  * **Link publik tunnel langsung ditampilkan di terminal saat server pertama kali dijalankan!**
* 📁 **Web File Manager Lengkap**
  * Jelajahi direktori Termux (`~`) dan penyimpanan internal Android (`/sdcard`).
  * Upload file & folder, unduh file/folder (otomatis ZIP), buat file/folder, ubah nama, hapus, ekstrak ZIP, serta text editor built-in.
* 💻 **Web Terminal / Bash Console**
  * Jalankan perintah Linux/Termux langsung dari browser dengan *live chunk streaming*, riwayat perintah (*arrow up/down*), dan dukungan interupsi **Ctrl + C**.
* 📋 **Manajer Log & PM2 Process Manager**
  * Pantau dan kelola proses Node.js di PM2 (Start, Stop, Restart, Cek Log) serta pantau live log server panel.
* 🖥️ **OpenSSH Server Native (Port 2222)**
  * Layanan SSH native Termux yang super cepat tanpa overhead PRoot.
  * Dilengkapi CLI helper tools bawaan (`termux-fix`, `termux-install`, `lenznode`).

---

## 📸 Preview Tampilan Web Dashboard

| 📊 Dashboard (Dekstop) | 📱 Tampilan Mobile |
| :---: | :---: |
| ![Dashboard Desktop](screenshots/monitoring.png) | ![Tampilan Mobile](screenshots/mobile_view.png) |

| 📁 Web File Manager | 💻 Web Terminal & Console |
| :---: | :---: |
| ![File Manager](screenshots/file_manager.png) | ![Terminal](screenshots/terminal.png) |

| 📋 Server Logs |
| :---: |
| ![Server Logs](screenshots/logs_pm2.png) |

---

## 📋 Spesifikasi Minimal & Penggunaan Sumber Daya

### 1. Spesifikasi Perangkat Minimal (Hardware & OS)
| Komponen | Spesifikasi Minimal | Rekomendasi Ideal |
| :--- | :--- | :--- |
| **Sistem Operasi** | Android 5.0 (Lollipop / SDK 21) | Android 7.0 s/d 16+ |
| **Arsitektur CPU** | ARM32 (`armhf`) / x86 | ARM64 (`aarch64`) / x86_64 |
| **RAM Fisik HP** | **512 MB** | **1 GB – 2 GB+** |
| **Penyimpanan Bebas** | Minimal **250 MB** *(Hemat 2 GB dibanding distro PRoot!)* | **1 GB+** (ruang untuk file upload) |
| **Status Root** | **Tanpa Root (Non-Root)** | Non-Root (didukung juga untuk HP Root) |

### 2. Penggunaan Sumber Daya (Resource Consumption)
* 🧠 **Penggunaan RAM (Idle)**: **~40 – 60 MB RAM** *(Sangat hemat daya baterai & ringan)*
* 💾 **Penggunaan Ruang Penyimpanan**: **~150 – 300 MB** *(Bebas beban rootfs 2 GB)*
* ⚡ **Waktu Mulai (Startup Time)**: **< 1 Detik**

---

## 📱 Rekomendasi Versi Termux Sesuai Versi Android

Installer otomatis mendeteksi versi Android dan arsitektur CPU perangkat Anda. Gunakan versi Termux yang sesuai:

| Versi Android | Rekomendasi Aplikasi Termux | Tautan Unduh |
| :--- | :--- | :--- |
| **Android 5.0 & 6.0** *(Legacy / 32-bit)* | Termux **v0.119.0-beta.3** varian **`apt-android-5`** (`armeabi-v7a` atau `universal`) | [GitHub Releases v0.119.0-beta.3](https://github.com/termux/termux-app/releases/tag/v0.119.0-beta.3) |
| **Android 7.0 s/d 16+** *(Modern / 64-bit)* | Termux versi terbaru dari **F-Droid** atau GitHub Releases resmi | [F-Droid Termux](https://f-droid.org/packages/com.termux/) / [GitHub Releases](https://github.com/termux/termux-app/releases) |

> ⚠️ **Catatan Penting**: Jangan gunakan aplikasi Termux dari Google Play Store karena sudah tidak diperbarui dan repositorinya tidak berfungsi.

---

## 🚀 Panduan Instalasi (Cukup 1 Perintah!)

Buka aplikasi **Termux**, lalu jalankan:

```bash
pkg update -y && pkg install git -y
git clone https://github.com/Lenzx999/LenzNode.git
cd LenzNode
bash install.sh
```

### Apa yang Dilakukan `install.sh` Secara Otomatis?
1. Mengaktifkan `termux-wake-lock` agar CPU HP tidak tidur saat layar mati.
2. Memasang dependensi: `nodejs`, `pm2`, `python`, `openssh`, `ffmpeg`, `libwebp`, `termux-api`, `cloudflared`, `curl`, `wget`, `zip`, `unzip`.
3. Menyiapkan pendamping Termux:API untuk telemetri baterai & daya non-root di Android 10–16+.
4. Menyiapkan OpenSSH Server aktif di port `2222`.
5. Mengaktifkan auto-start saat reboot HP via `~/.termux/boot/start-server.sh`.
6. **Menjalankan server dan langsung menampilkan link Cloudflare Tunnel di terminal!**

---

## 🌐 Cara Mengakses Server

Setelah server menyala (`bash ~/LenzNode/start.sh` atau `lenznode`), terminal akan menampilkan banner ringkas seperti berikut:

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

### 1. Web Dashboard (Port 8080)
* **Satu Wi-Fi**: Buka browser di HP/Laptop lain, akses `http://<IP-HP>:8080`
* **Jarak Jauh / Data Seluler**: Buka URL Publik Cloudflare (`https://xxxx.trycloudflare.com`)
* **Username**: `admin`
* **Password**: `admin123` *(Dapat diganti di menu Pengaturan Akun)*

### 2. OpenSSH Console (Port 2222)
* **Koneksi Lokal**:
  ```bash
  ssh <user-termux>@<IP-HP> -p 2222
  ```

---

## ⚙️ Perintah Kontrol Server (`start.sh`)

Gunakan script `start.sh` di Termux untuk mengelola server:

* **Menjalankan Server** *(Otomatis cek & terapkan pembaruan GitHub)*:
  ```bash
  ./start.sh
  ```
* **Memperbarui Sistem (Manual Update)**:
  ```bash
  ./start.sh update
  ```
* **Melihat Status Layanan & Link Tunnel**:
  ```bash
  ./start.sh status
  ```
* **Mematikan Server**:
  ```bash
  ./start.sh stop
  ```
* **Memulai Ulang (Restart)**:
  ```bash
  ./start.sh restart
  ```
* **Melihat Log Live**:
  ```bash
  ./start.sh logs
  ```

---

## 🔄 Pembaruan Otomatis (Auto-Update)

1. **Otomatis Saat Server Dinyalakan**:
   Setiap kali `./start.sh` (atau `lenznode`) dijalankan, sistem secara otomatis mengecek ke GitHub. Jika ada pembaruan kode terbaru, LenzNode akan otomatis mengunduh & memperbarui dirinya sebelum server mulai bekerja. Akun dan konfigurasi Anda tetap aman terlindungi.
2. **Pembaruan Manual via Perintah**:
   ```bash
   ./start.sh update
   ```
3. **Pembaruan 1-Baris Universal (Curl)**:
   ```bash
   curl -sL https://raw.githubusercontent.com/Lenzx999/LenzNode/main/update.sh | bash
   ```

---

## 👤 Author & Lisensi

* **Author / Developer**: **Lenz**
* **Project**: LenzNode Mini Server & OpenSSH
* **Lisensi**: MIT License
