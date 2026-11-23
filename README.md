<div align="center">

  <img src="screenshots/monitoring.png" alt="LenzNode Web Dashboard" width="100%" style="max-width: 860px; border-radius: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.35);">

  <br/><br/>

  <h1>LenzNode</h1>
  <p><strong>Mini Linux Server, Private Cloud Storage & AI Gateway for Android (Termux)</strong></p>

  <p>
    Ubah smartphone Android bekas menjadi Mini Server Linux, Cloud Storage pribadi, dan AI Gateway mandiri yang hemat daya, ringan, dan siap beroperasi 24 jam nonstop tanpa perlu akses root.
  </p>

  <p>
    <a href="https://github.com/Lenzx999/LenzNode/releases"><img src="https://img.shields.io/badge/version-v2.2.3-blue?style=flat-square" alt="Version"></a>
    <img src="https://img.shields.io/badge/platform-Android%20%7C%20Termux%20%7C%20Linux-10B981?style=flat-square" alt="Platform">
    <img src="https://img.shields.io/badge/node-%3E%3D18.0.0-8B5CF6?style=flat-square" alt="Node.js">
    <a href="https://lenznity.my.id"><img src="https://img.shields.io/badge/website-lenznity.my.id-0EA5E9?style=flat-square" alt="Website"></a>
    <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/changelog-view-f97316?style=flat-square" alt="Changelog"></a>
    <img src="https://img.shields.io/badge/license-MIT-EAB308?style=flat-square" alt="License">
  </p>

  <p>
    <a href="#-quick-install-cukup-1-baris">🚀 Quick Install</a> •
    <a href="#-fitur-unggulan">✨ Fitur Unggulan</a> •
    <a href="#-perintah-cli-lenz">⚡ CLI Commands</a> •
    <a href="#-ekosistem--website-resmi">🌐 Ekosistem Web</a> •
    <a href="CHANGELOG.md">📝 Changelog</a>
  </p>

</div>

---

## 🚀 Quick Install (Cukup 1 Baris)

Buka aplikasi **Termux**, salin perintah di bawah ini, tempelkan (*paste*), lalu tekan **Enter**:

```bash
pkg update -y && pkg install git -y && rm -rf LenzNode && git clone https://github.com/Lenzx999/LenzNode.git && cd LenzNode && bash install.sh
```

> **Catatan**: Unduh dan pasang Termux resmi dari **[F-Droid](https://f-droid.org/packages/com.termux/)**. Jangan gunakan versi Play Store karena sudah kadaluwarsa.

---

## ✨ Fitur Unggulan

* **📊 Web Dashboard Interaktif**: Pemantauan beban sistem (*CPU, RAM, Storage, Baterai, Suhu*) secara waktu nyata (*real-time*) dengan tema Gelap (*Obsidian Dark*) dan Terang (*Clean Glass*).
* **📦 App Center Marketplace**: Pasang aplikasi server siap pakai dengan satu kali klik:
  * **9Router** (*Port 20128*): Multi-Model AI Router & penghemat token coding tools (Claude Code, Cursor, Antigravity, dll).
  * **Nextcloud** (*Port 8088*): Cloud storage pribadi untuk sinkronisasi berkas antar-perangkat, kalender, dan kolaborasi mandiri.
  * **Immich** (*Port 2283*): Solusi backup otomatis foto & video mandiri berkinerja tinggi sebagai alternatif Google Photos.
* **📂 Web File Manager**: Kelola, unggah, unduh, dan edit berkas server langsung dari browser tanpa perlu FTP/SFTP.
* **💻 Web Terminal & Console**: Akses shell Linux langsung dari antarmuka web dengan dukungan riwayat perintah dan shorcut keyboard.
* **🌐 Cloudflare Tunnel Otomatis**: Server otomatis bisa diakses dari mana saja melalui internet publik tanpa butuh IP publik statis atau konfigurasi port forwarding.
* **⚡ Perintah CLI Global `lenz`**: Kelola server dengan perintah singkat dan mudah diingat dari direktori mana saja.

---

## ⚡ Perintah CLI `lenz`

Setelah terpasang, Anda bisa mengendalikan server dari mana saja di terminal Termux dengan perintah:

| Perintah | Deskripsi |
| :--- | :--- |
| `lenz status` | Menampilkan status aktif web panel, SSH, Cloudflare tunnel, dan apps |
| `lenz update` | Memeriksa dan memperbarui LenzNode ke versi terbaru dari GitHub |
| `lenz restart` | Memulai ulang seluruh layanan server |
| `lenz stop` | Menghentikan semua layanan server |
| `lenz logs` | Memantau catatan aktivitas (*live logs*) secara langsung |
| `lenz report` | Mengekspor berkas diagnosa error ke folder **Download** HP |

*(Perintah bawaan `./start.sh` tetap didukung penuh).*

---

## 🌐 Website Resmi

* 🌍 **Website Resmi**: [**lenznity.my.id**](https://lenznity.my.id)

Kunjungi [**lenznity.my.id**](https://lenznity.my.id) untuk melihat portofolio proyek, panduan teknis, dan informasi ekosistem server lainnya.

---

## 📱 Cara Membuka Dashboard Web

Setelah server dijalankan, buka peramban (*Chrome / Firefox*) di HP atau Laptop:

* **Dari HP itu sendiri**: Buka `http://127.0.0.1:8080`
* **Dari Laptop / HP Lain (Satu Wi-Fi)**: Buka alamat IP lokal yang tampil di layar (contoh: `http://192.168.1.3:8080`)
* **Dari Luar Rumah (Mode Publik)**: Buka tautan Cloudflare Tunnel yang tampil di terminal atau log status.

**Kredensial Masuk (Login):**
* Username: `admin`
* Password: `admin123` *(Dapat diubah kapan saja pada menu Pengaturan Dashboard)*

---

## 🔋 3 Tips Agar Server Menyala 24 Jam Nonstop

1. **Matikan Penghemat Baterai**: Buka *Pengaturan HP > Aplikasi > Termux > Baterai*, lalu pilih opsi **"Tidak Dibatasi" (*Unrestricted*)**.
2. **Kunci Aplikasi Termux**: Buka menu aplikasi yang berjalan (*Recent Apps*), lalu aktifkan ikon **Gembok (*Lock*)** pada aplikasi Termux agar tidak terhapus pembersih RAM bawaan sistem.
3. **Ketik `lenz report` Jika Ada Kendala**: Jika mengalami kendala teknis, jalankan `lenz report` untuk mengekspor berkas log diagnosa ke folder `Download/LenzNode-Error.log` sehingga mudah ditinjau.

---

## ⚙️ Kompatibilitas Perangkat

* **Android 7.0 hingga 16+**: Didukung penuh secara *plug-and-play*.
* **RAM Minimum**: 512 MB (disarankan Mode 1 Lokal). Untuk RAM 1 GB ke atas bebas menggunakan Mode Lokal maupun Mode Publik.
* **Dukungan Non-Root & Root**:
  * **HP Biasa (Non-Root)**: Berjalan aman tanpa modifikasi sistem.
  * **HP Root (Magisk / KernelSU)**: Otomatis mendeteksi hak akses root untuk membuka port standar (80 & 22) serta akses root shell.

---

## 📝 Catatan Rilis

Riwayat lengkap pembaruan fitur, perbaikan bug, dan optimasi dapat dilihat di berkas [**CHANGELOG.md**](CHANGELOG.md).

---

## 📄 Lisensi & Pengembang

* **Developer**: Lenz ([@Lenzx999](https://github.com/Lenzx999))
* **Website**: [lenznity.my.id](https://lenznity.my.id)
* **Lisensi**: MIT License
