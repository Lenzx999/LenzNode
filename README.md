<div align="center">

  <img src="screenshots/monitoring.png" alt="LenzNode Web Dashboard" width="100%" style="max-width: 860px; border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.35);">

  <br/><br/>

  <h1>LenzNode</h1>
  <p><strong>Mini Server Linux, Penyimpanan Cloud Pribadi &amp; AI Gateway untuk Android (Aplikasi APK &amp; Termux)</strong></p>

  <p>
    <a href="https://github.com/Lenzx999/LenzNode/releases/latest"><img src="https://img.shields.io/badge/version-v2.2.14-blue?style=flat-square" alt="Version"></a>
    <img src="https://img.shields.io/badge/platform-Android%206.0%E2%80%9316%20%7C%20Termux-10B981?style=flat-square" alt="Platform">
    <img src="https://img.shields.io/badge/ABI-arm64--v8a%20%7C%20armeabi--v7a-06B6D4?style=flat-square" alt="ABI">
    <img src="https://img.shields.io/badge/node-%3E%3D18.0.0-8B5CF6?style=flat-square" alt="Node.js">
    <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/changelog-view-f97316?style=flat-square" alt="Changelog"></a>
    <img src="https://img.shields.io/badge/license-MIT-EAB308?style=flat-square" alt="License">
  </p>

  <p>
    <a href="https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-modern-arm64-v8a.apk"><img src="https://img.shields.io/badge/Download%20APK-Android%206.0%E2%80%9316%20(64--bit)-10B981?style=for-the-badge&logo=android&logoColor=white" alt="Download APK 64-bit"></a>
    <a href="https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-lama-armeabi-v7a.apk"><img src="https://img.shields.io/badge/Download%20APK-Android%206.0%E2%80%9316%20(32--bit)-0284C7?style=for-the-badge&logo=android&logoColor=white" alt="Download APK 32-bit"></a>
    <a href="https://github.com/Lenzx999/LenzNode/releases/latest"><img src="https://img.shields.io/badge/Semua%20Rilis-GitHub%20Releases-18181B?style=for-the-badge&logo=github&logoColor=white" alt="GitHub Releases"></a>
  </p>

</div>

---

## Download Aplikasi (APK) — 1 Klik

Klik tautan di bawah sesuai arsitektur perangkat Android Anda (mendukung **Android 6.0 hingga Android 16**, tanpa perlu login GitHub atau membuka menu *Actions*):

| Kompatibilitas Sistem | Arsitektur | File APK | Unduh Langsung |
| :--- | :--- | :--- | :--- |
| **Android 6.0 – 16** (rekomendasi untuk perangkat 64-bit) | `arm64-v8a` | `LenzNode-modern-arm64-v8a.apk` | [**Download APK (64-bit)**](https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-modern-arm64-v8a.apk) |
| **Android 6.0 – 16** (khusus perangkat 32-bit) | `armeabi-v7a` | `LenzNode-lama-armeabi-v7a.apk` | [**Download APK (32-bit)**](https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-lama-armeabi-v7a.apk) |

> **Tips memilih:** Pilih **`arm64-v8a` (64-bit)** terlebih dahulu. Jika pemasangan ditolak oleh sistem dengan keterangan tidak kompatibel, unduh **`armeabi-v7a` (32-bit)**.  
> Halaman rilis lengkap: [**github.com/Lenzx999/LenzNode/releases**](https://github.com/Lenzx999/LenzNode/releases/latest)

---

## 2 Edisi Resmi LenzNode

LenzNode tersedia dalam **2 edisi** yang memakai mesin server dan dashboard yang sama:

| Edisi | Kompatibilitas Android | Cara Pasang | Lingkungan Sistem |
| :--- | :--- | :--- | :--- |
| **Aplikasi Android (APK)** | **Android 6.0 – 16** (`minSdk 23`) | [**Unduh & pasang file `.apk`**](https://github.com/Lenzx999/LenzNode/releases/latest) | **Ubuntu 22.04 PRoot** mandiri (tanpa Termux) |
| **Termux CLI** | **Android 5.0 – 16+** (via Termux) / Linux | Jalankan `install.sh` di Termux | **Native Termux** |

---

## Edisi 1: Aplikasi Android (APK)

Cocok untuk pengguna **Android 6.0 sampai Android 16** yang ingin langsung menjalankan server tanpa memasang Termux.

### Pilihan File APK

| File APK | Arsitektur | Kompatibilitas | Unduh |
| :--- | :--- | :--- | :--- |
| `LenzNode-modern-arm64-v8a.apk` | `arm64-v8a` (64-bit) | Android 6.0 – 16 (perangkat 64-bit) | [**Download**](https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-modern-arm64-v8a.apk) |
| `LenzNode-lama-armeabi-v7a.apk` | `armeabi-v7a` (32-bit) | Android 6.0 – 16 (perangkat 32-bit) | [**Download**](https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-lama-armeabi-v7a.apk) |

### Mode Operasi Aplikasi
- **Jadikan HP Ini Server (Host Mode)**: Menyiapkan Ubuntu 22.04 minimal, Node.js, OpenSSH (`2222`), `cloudflared`, dan Dashboard (`8080`). Dilengkapi **Terminal PTY interaktif** (mirip Termux/Termius dengan tombol `ESC`, `TAB`, `CTRL`, `ALT`, panah) dan **File Manager** gaya ZArchiver (tekan lama untuk salin, bagikan ke aplikasi/URL ber-PIN, edit, ubah nama, hapus).
- **Akses Server Lain (Remote Client Mode)**: Hubungkan aplikasi ke server LenzNode lain menggunakan alamat IP lokal / URL Tunnel dan **Token Akses (`lnz_...`)** dari menu *Pengaturan ➜ Jaringan*.

---

## Edisi 2: Termux CLI

Buka aplikasi **Termux** (disarankan versi [F-Droid](https://f-droid.org/packages/com.termux/)), lalu jalankan:

```bash
pkg update -y && pkg install git -y && rm -rf LenzNode && git clone https://github.com/Lenzx999/LenzNode.git && cd LenzNode && bash install.sh
```

---

## Perbedaan Perintah Terminal (Aplikasi APK vs Termux)

Karena **Versi Aplikasi APK** berjalan di atas **Ubuntu 22.04**, perintahnya berbeda dengan **Termux**:

| Kebutuhan | Versi Aplikasi Android (Ubuntu) | Versi Termux |
| :--- | :--- | :--- |
| Perbarui daftar paket | `apt update` | `pkg update` |
| Pasang paket / aplikasi | `apt install <nama-paket> -y` | `pkg install <nama-paket> -y` |
| Hapus paket | `apt remove <nama-paket>` | `pkg uninstall <nama-paket>` |
| Folder kerja awal | `/root/workspace` | `~/workspace` |
| Kelola / update LenzNode | Lewat menu **Pengaturan** & **Logs** di aplikasi | `lenz status`, `lenz update`, `lenz restart`, `lenz stop`, `lenz logs` |
| Jalankan manual | Otomatis saat aplikasi dibuka | `./start.sh` atau `lenz restart` |

---

## Akses Dashboard & Login Default

- **Di HP sendiri**: `http://127.0.0.1:8080`
- **Satu jaringan Wi-Fi**: `http://<IP-Lokal-HP>:8080`
- **Dari internet (Tunnel)**: URL Cloudflare Tunnel yang tampil di *Pengaturan ➜ Jaringan*
- **Login bawaan**: Username `admin` | Password `admin123` *(otomatis tersinkron dengan password SSH port `2222`, segera ubah di menu Pengaturan)*

---

## Fitur Utama

- **Pemantauan Real-Time**: CPU, RAM, penyimpanan, suhu, baterai, dan kontrol senter.
- **Terminal Terpisah Sesuai Platform**: Terminal PTY penuh ala Termux/Termius di Aplikasi Android, serta Web Terminal streaming di browser website.
- **File Manager**: Mendukung tekan lama, salin/tempel folder, ekstrak/unduh ZIP, bagikan langsung ke aplikasi lain, atau buat tautan berbagi ber-PIN dengan batas waktu.
- **Logs Server & PM2**: Pembaruan otomatis saat tab dibuka dengan filter kategori (`Semua`, `Keamanan`, `Jaringan`, `Sistem`, `Error`) serta pemilihan log per proses PM2.
- **App Center & Pembaruan 1-Klik**: Pasang layanan seperti **9Router**, **Nextcloud**, dan **Immich**, serta pembaruan langsung dari GitHub.

---

## Agar Server Tetap Aktif 24 Jam

1. Buka *Pengaturan HP ➜ Aplikasi ➜ LenzNode (atau Termux) ➜ Baterai*, pilih **Tidak Dibatasi (*Unrestricted*)**.
2. Kunci aplikasi **LenzNode** / **Termux** di menu *Recent Apps* agar tidak ditutup sistem.

---

## Catatan Rilis & Lisensi

- Riwayat pembaruan lengkap tersedia di [CHANGELOG.md](CHANGELOG.md).
- Pengembang: **Lenz** ([@Lenzx999](https://github.com/Lenzx999)) — [lenznity.my.id](https://lenznity.my.id) • Lisensi **MIT**.
