# Lenz Mini Server & Ubuntu VPS (Termux Universal Edition)

Transformasikan smartphone Android lama atau baru (Android 5.0 s/d 14+, arsitektur ARM32/ARM64/x86_64) menjadi **Mini Server & Distro Linux Ubuntu VPS** berfitur lengkap yang dapat dikendalikan penuh secara lokal maupun jarak jauh melalui Web Dashboard modern.

---

## 🌟 Fitur Utama Server

* 🌐 **Web Dashboard Modern (Port 8080)**
  * Antarmuka web gelap (*dark mode*) yang responsif di layar HP, tablet, maupun laptop/PC.
  * Autentikasi sesi aman dengan proteksi *anti-brute force*.
* 📊 **Monitoring Sistem Real-Time**
  * Pantau penggunaan CPU %, RAM (MB/%), Kapasitas Penyimpanan Disk, Uptime, Baterai, dan Sensor Suhu SoC & Core CPU secara *live*.
* 📁 **Web File Manager Lengkap**
  * Jelajahi direktori Termux (`~`) dan penyimpanan internal Android (`/sdcard`).
  * Upload file & folder, unduh file/folder (otomatis ZIP), buat file/folder, ubah nama, hapus, ekstrak ZIP, serta text editor built-in.
* 💻 **Web Terminal / Bash Console**
  * Jalankan perintah Linux/Termux langsung dari browser dengan *live chunk streaming*, riwayat perintah (*arrow up/down*), dan dukungan interupsi **Ctrl + C**.
* 📋 **Manajer Log & PM2 Process Manager**
  * Pantau dan kelola proses Node.js di PM2 (Start, Stop, Restart, Cek Log) serta pantau live log server panel.
* 🖥️ **Ubuntu Linux VPS (PRoot + OpenSSH Port 2222)**
  * Distro Linux Ubuntu asli di dalam Android tanpa perlu root.
  * Dilengkapi OpenSSH Server aktif di port `2222` dan CLI helper tools bawaan (`vps-fix`, `vps-install`, `termux-fix`, `termux-install`).
* 🌍 **Akses Publik Bebas Blokir (Cloudflare Tunnel)**
  * Dilengkapi tunnel otomatis agar dashboard dan SSH dapat diakses dari luar jaringan (data seluler/luar kota) tanpa perlu IP publik statis atau port forwarding modem.

---

## 📱 Rekomendasi Versi Termux Sesuai Versi Android

Installer otomatis mendeteksi versi Android dan arsitektur CPU perangkat Anda. Agar instalasi berjalan lancar, gunakan versi Termux yang sesuai:

| Versi Android | Rekomendasi Aplikasi Termux | Tautan Unduh |
| :--- | :--- | :--- |
| **Android 5.0 & 6.0** *(Legacy / 32-bit)* | Termux **v0.119.0-beta.3** varian **`apt-android-5`** (`armeabi-v7a` atau `universal`) | [GitHub Releases v0.119.0-beta.3](https://github.com/termux/termux-app/releases/tag/v0.119.0-beta.3) |
| **Android 7.0 s/d 14+** *(Modern / 64-bit)* | Termux versi terbaru dari **F-Droid** atau GitHub Releases resmi | [F-Droid Termux](https://f-droid.org/packages/com.termux/) / [GitHub Releases](https://github.com/termux/termux-app/releases) |

> ⚠️ **Catatan Penting**: Jangan gunakan aplikasi Termux dari Google Play Store karena sudah tidak diperbarui dan repositorinya tidak berfungsi.

---

## 🚀 Panduan Instalasi (Langkah demi Langkah)

### Langkah 1: Persiapan Aplikasi di HP
1. Pasang aplikasi **Termux** yang sesuai dengan versi Android HP Anda.
2. *(Opsional)* Pasang juga **Termux:Boot** dari halaman rilis yang sama agar server otomatis menyala saat HP direstart.

### Langkah 2: Eksekusi Instalasi Otomatis (Pilih Salah Satu Metode)

#### 🔹 Metode A: Langsung dari Git (Direkomendasikan)
Buka aplikasi **Termux**, lalu jalankan:
```bash
pkg update -y && pkg install git -y
git clone https://github.com/Lenzx999/panel.git ~/panel
cd ~/panel
bash install.sh
```

#### 🔹 Metode B: Dari File ZIP / Penyimpanan Internal HP
Jika Anda memindahkan file secara manual ke folder `Download`:
```bash
termux-setup-storage
cd ~/storage/downloads/panel
bash install.sh
```
*(Atau jika berupa ZIP: `cd ~/storage/downloads && unzip panel.zip -d ~/ && cd ~/panel && bash install.sh`)*

#### Proses yang Dijalankan `install.sh` Secara Otomatis:
1. Mengaktifkan `termux-wake-lock` agar CPU HP tidak tidur saat layar mati.
2. Memasang paket Termux: `nodejs`, `pm2`, `python`, `openssh`, `ffmpeg`, `libwebp`, `proot`, `curl`, `wget`, `zip`, `unzip`.
3. Mengunduh dan mengonfigurasi Rootfs Linux Ubuntu sesuai arsitektur CPU perangkat (`armhf`, `arm64`, atau `amd64`).
4. Menyiapkan OpenSSH Server Ubuntu di port `2222`.
5. Memasang skrip autostart dan langsung meluncurkan server.

---

## 🌐 Cara Mengakses & Kredensial Default

Setelah server menyala, pastikan perangkat lain (laptop/HP lain) terhubung ke **satu jaringan Wi-Fi yang sama**.

| Layanan | URL / Alamat Akses | Kredensial Default |
| :--- | :--- | :--- |
| **Web Dashboard** | `http://<IP-HP>:8080` *(atau via domain publik Cloudflare)* | Username: `admin`<br>Password: `admin123` *(Dapat diubah di menu Pengaturan Akun)* |
| **Ubuntu VPS (SSH)** | `ssh root@<IP-HP> -p 2222`<br>atau `ssh ubuntu@<IP-HP> -p 2222` | Password: `ubuntu123` |
| **Masuk VPS via Termux** | Ketik: `ubuntu` di Termux | Langsung masuk terminal root Ubuntu |

> 💡 *Alamat IP lokal HP dan link publik HTTPS akan ditampilkan secara otomatis di Web Dashboard dan terminal saat server dijalankan.*

---

## ⚙️ Perintah Kontrol Server (`start.sh`)

Gunakan script `start.sh` di Termux untuk mengelola layanan:

* **Menjalankan Server**:
  ```bash
  bash ~/panel/start.sh
  ```
* **Melihat Status Layanan**:
  ```bash
  bash ~/panel/start.sh status
  ```
* **Mematikan Server**:
  ```bash
  bash ~/panel/start.sh stop
  ```
* **Memulai Ulang (Restart)**:
  ```bash
  bash ~/panel/start.sh restart
  ```

---

---

## 🛠️ CLI Helper Tools & Perintah Cepat

### Di Termux Host
* `lenz-server` : Menjalankan atau merestart seluruh layanan Lenz Mini Server & VPS.
* `lenz-vps`    : Masuk langsung ke sesi interaktif Ubuntu Linux VPS.
* `lenz-status` : Menampilkan status operasional port panel (8080) dan SSH (2222).
* `lenz-stop`   : Menghentikan seluruh proses server dan VPS.
* `termux-fix`  : Memperbaiki package manager dpkg di Termux host.

### Di Terminal Ubuntu VPS
* `panel-status` : Menampilkan ringkasan penggunaan CPU, RAM, Suhu, Baterai, dan link website secara instan.
* `panel-restart`: Mengirim sinyal restart ke panel server dari dalam VPS.
* `vps-install <nama-paket>`: Memasang paket apt di Ubuntu dengan mekanisme auto-fix jika terjadi dependensi error.
* `vps-fix`    : Membersihkan file lock dpkg/apt dan memperbaiki konfigurasi paket rusak.

---

## ❄️ Tips Menjaga Suhu & Stabilitas Operasional 24/7

Jika HP digunakan sebagai server non-stop:

1. **Kunci Aplikasi di Pengaturan Manajemen Daya Android**:
   * Buka Pengaturan Baterai / iManager HP -> Izinkan konsumsi daya latar belakang tinggi untuk **Termux**.
   * Nonaktifkan fitur *Auto-Sleep* / Penghemat Baterai Ekstrem.
2. **Setelan Kebijakan Wi-Fi**:
   * Pengaturan Wi-Fi HP -> Lanjutan -> Atur **Keep Wi-Fi on during sleep** ke **Always**.
3. **Pencegahan Suhu Panas (Overheat)**:
   * Lepas casing/pelindung HP agar panas bodi mudah terbuang.
   * Gunakan kipas pendingin mini USB (fan 5V) yang mengarah langsung ke bodi belakang HP.
   * Gunakan charger dengan daya stabil untuk menjaga kesehatan baterai.

---

## 👤 Author & Lisensi

* **Author / Developer**: **Lenz**
* **Project**: Lenz Mini Server & Ubuntu VPS
* **Lisensi**: MIT License

