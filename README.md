<div align="center">

  <img src="screenshots/monitoring.png" alt="LenzNode Web Dashboard" width="100%" style="max-width: 860px; border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.35);">

  <br/><br/>

  <h1>LenzNode</h1>
  <p><strong>Mini Server Linux, Penyimpanan Cloud Pribadi &amp; AI Gateway untuk Android (Aplikasi APK &amp; Termux)</strong></p>

  <p>
    <a href="https://github.com/Lenzx999/LenzNode/releases/latest"><img src="https://img.shields.io/badge/version-v2.2.14-blue?style=flat-square" alt="Version"></a>
    <img src="https://img.shields.io/badge/Android-6.0%E2%80%9316-10B981?style=flat-square" alt="Android">
    <img src="https://img.shields.io/badge/arsitektur-64--bit%20%7C%2032--bit-06B6D4?style=flat-square" alt="Arsitektur">
    <img src="https://img.shields.io/badge/node-%3E%3D18.0.0-8B5CF6?style=flat-square" alt="Node.js">
    <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/changelog-view-f97316?style=flat-square" alt="Changelog"></a>
    <img src="https://img.shields.io/badge/license-MIT-EAB308?style=flat-square" alt="License">
  </p>

  <p>
    <a href="https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-arm64-v8a.apk"><img src="https://img.shields.io/badge/Download%20APK-Android%208.0%E2%80%9316%20(64--bit)-10B981?style=for-the-badge&logo=android&logoColor=white" alt="Download APK 64-bit"></a>
    <a href="https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-armeabi-v7a.apk"><img src="https://img.shields.io/badge/Download%20APK-Android%206.0%E2%80%937.1%20(32--bit)-0284C7?style=for-the-badge&logo=android&logoColor=white" alt="Download APK 32-bit"></a>
    <a href="https://github.com/Lenzx999/LenzNode/releases/latest"><img src="https://img.shields.io/badge/Semua%20Rilis-GitHub%20Releases-18181B?style=for-the-badge&logo=github&logoColor=white" alt="GitHub Releases"></a>
  </p>

</div>

---

## Download Aplikasi (APK)

Pilih file APK sesuai versi Android di perangkat Anda (langsung terunduh tanpa perlu login GitHub):

| Versi Android | File APK | Keterangan | Unduh Langsung |
| :--- | :--- | :--- | :--- |
| **Android 8.0 – 16** | `LenzNode-arm64-v8a.apk` | **Rekomendasi** untuk mayoritas HP Android saat ini (64-bit) | [**Download (64-bit)**](https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-arm64-v8a.apk) |
| **Android 6.0 – 7.1** | `LenzNode-armeabi-v7a.apk` | Untuk perangkat Android lawas atau sistem 32-bit | [**Download (32-bit)**](https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-armeabi-v7a.apk) |

> Halaman rilis lengkap: [**github.com/Lenzx999/LenzNode/releases**](https://github.com/Lenzx999/LenzNode/releases/latest)

---

## 2 Pilihan Cara Pakai

LenzNode tersedia dalam **2 versi** dengan fitur server dan dashboard yang sama:

| Pilihan | Cocok Untuk | Cara Pasang | Sistem |
| :--- | :--- | :--- | :--- |
| **Aplikasi Android (APK)** | **Android 6.0 – 16** | [**Unduh & pasang file `.apk`**](https://github.com/Lenzx999/LenzNode/releases/latest) | **Ubuntu 22.04** langsung di dalam aplikasi |
| **Termux CLI** | Pengguna **Termux** (Android 5.0–16+) | Jalankan perintah `install.sh` di Termux | **Termux** |

---

## Cara 1: Aplikasi Android (APK)

Cocok bagi pengguna yang ingin langsung memakai server tanpa perlu memasang Termux.

### Pilihan File APK

| File APK | Versi Android | Unduh |
| :--- | :--- | :--- |
| `LenzNode-arm64-v8a.apk` | **Android 8.0 – 16** (64-bit, rekomendasi) | [**Download**](https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-arm64-v8a.apk) |
| `LenzNode-armeabi-v7a.apk` | **Android 6.0 – 7.1** (32-bit) | [**Download**](https://github.com/Lenzx999/LenzNode/releases/latest/download/LenzNode-armeabi-v7a.apk) |

### Mode Penggunaan di Aplikasi
- **Jadikan HP Ini Server**: Menyiapkan Linux Ubuntu 22.04, Node.js, OpenSSH (`2222`), `cloudflared`, dan Dashboard (`8080`). Sudah dilengkapi **Terminal** bawaan lengkap (tombol `ESC`, `TAB`, `CTRL`, `ALT`, panah) dan **File Manager** (tekan lama untuk salin, bagikan ke aplikasi lain, buat link ber-PIN, edit, ubah nama, hapus).
- **Akses Server Lain**: Hubungkan aplikasi ke server LenzNode lain memakai IP lokal atau URL Tunnel beserta **Token Akses (`lnz_...`)** dari menu *Pengaturan ➜ Jaringan*.

---

## Cara 2: Termux CLI

Buka aplikasi **Termux** (disarankan versi [F-Droid](https://f-droid.org/packages/com.termux/)), lalu jalankan:

```bash
pkg update -y && pkg install git -y && rm -rf LenzNode && git clone https://github.com/Lenzx999/LenzNode.git && cd LenzNode && bash install.sh
```

---

## Perbedaan Perintah Terminal (Aplikasi APK vs Termux)

Karena **Aplikasi APK** memakai sistem **Ubuntu 22.04**, perintahnya berbeda dengan **Termux**:

| Kebutuhan | Aplikasi Android (APK) | Termux |
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

- **Pemantauan Real-Time**: Pantau CPU, RAM, penyimpanan, suhu, baterai, serta kontrol senter.
- **Terminal Bawaan**: Ketik perintah langsung di Terminal aplikasi Android maupun lewat Terminal di browser.
- **File Manager**: Tekan lama untuk salin/tempel folder, ekstrak atau unduh ZIP, bagikan ke aplikasi lain, atau buat link unduh ber-PIN.
- **Logs Server & PM2**: Pembaruan otomatis dengan filter kategori (`Semua`, `Keamanan`, `Jaringan`, `Sistem`, `Error`) dan pilihan log per aplikasi.
- **App Center & Pembaruan 1-Klik**: Pasang layanan seperti **9Router**, **Nextcloud**, dan **Immich**, serta update langsung dari GitHub.

---

## Agar Server Tetap Aktif 24 Jam

1. Buka *Pengaturan HP ➜ Aplikasi ➜ LenzNode (atau Termux) ➜ Baterai*, pilih **Tidak Dibatasi (*Unrestricted*)**.
2. Kunci aplikasi **LenzNode** / **Termux** di menu *Recent Apps* agar tidak ditutup sistem.

---

## Catatan Rilis & Lisensi

- Riwayat pembaruan lengkap tersedia di [CHANGELOG.md](CHANGELOG.md).
- Pengembang: **Lenz** ([@Lenzx999](https://github.com/Lenzx999)) — [lenznity.my.id](https://lenznity.my.id) • Lisensi **MIT**.
