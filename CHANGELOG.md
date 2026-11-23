# Changelog

Semua catatan perubahan dan riwayat pembaruan versi pada **LenzNode** didokumentasikan di berkas ini.

Format changelog ini mengacu pada standar rilis berbasis versi semantik (*Semantic Versioning*).

---

## v2.2.4 (2026-11-23)

### Features
* **1-Click Headless Remote OTA Update (Pembaruan Jarak Jauh)**:
  * Pengguna kini dapat memperbarui seluruh sistem LenzNode langsung dari Web Dashboard tanpa perlu membuka atau menyentuh aplikasi Termux di smartphone (*100% headless & remote friendly*).
  * Tombol interaktif **"Perbarui Sekarang (1-Klik)"** terintegrasi langsung pada banner notifikasi rilis baru dan menu **Pengaturan ➜ Sistem**.
  * Endpoint API backend `/api/system/update/check` dan `/api/system/update/apply` yang mengeksekusi git fetch & reset aman ke repositori GitHub resmi.
  * **Auto Backup & Restore Kredensial**: File autentikasi akun pengguna (`auth.json`) dicadangkan dan dipulihkan secara otomatis selama proses update, sehingga kata sandi dashboard tidak akan pernah ter-reset.
  * **Self-Respawn & Auto-Reload**: Server otomatis memuat ulang instance dirinya sendiri (baik berjalan di bawah PM2 maupun standalone background Termux), dan antarmuka browser otomatis melakukan refresh setelah 3 detik.

---

## v2.2.3 (2026-11-23)

### Bug Fixes & Refinements
* **Perbaikan Autentikasi OpenSSH Native Termux**:
  * Mengganti konfigurasi legacy Ubuntu PRoot (`root • ubuntu123`) di dashboard settings menjadi informasi OpenSSH Termux dinamis (`termux • admin123` / username Termux aktual).
  * Menambahkan inisialisasi otomatis password Termux (`admin123`) pada `install.sh` dan `start.sh` via utilitas `passwd`, sehingga pengguna bisa langsung login SSH tanpa ditolak oleh sistem.
  * Menyelaraskan password OpenSSH secara otomatis setiap kali pengguna mengubah kata sandi di Pengaturan Dashboard Web.
  * Menyesuaikan perintah salin SSH Lokal menjadi `ssh <user>@<ip> -p 2222`.
* **Perbaikan Izin Login Remote 9Router**:
  * Menambahkan injeksi variabel lingkungan `INITIAL_PASSWORD="123456"` pada peluncur `start-9router.sh` dan backend `server.js`.
  * Mengatasi blokade keamanan bawaan 9Router (*"Default password must be changed before remote access"*) saat diakses melalui LAN/Wi-Fi ataupun Cloudflare Tunnel, sehingga sandi default `123456` dapat langsung digunakan untuk masuk ke antarmuka 9Router.
  * Menambahkan petunjuk kata sandi default `123456` pada modal kartu aplikasi 9Router di App Center.
* **Privasi Dokumentasi**:
  * Merapikan berkas dokumentasi `README.md` dan memproteksi endpoint/subdomain privat internal.

---

## v2.2.2 (2026-11-23)

### Features
* **Perintah CLI Global `lenz`**: Seluruh perintah operasional server kini dapat dipanggil langsung dari direktori mana saja di terminal Termux maupun Linux:
  * `lenz update` : Memeriksa dan memperbarui LenzNode ke versi terbaru dari GitHub secara otomatis.
  * `lenz status` : Menampilkan ringkasan status web panel, SSH, tunnel, dan apps.
  * `lenz restart` : Memulai ulang seluruh layanan server.
  * `lenz stop` : Menghentikan layanan yang sedang aktif.
  * `lenz logs` : Menampilkan streaming live logs server.
* **Auto-Register Symlink di PATH**: Menambahkan mekanisme *self-healing* di `start.sh` dan `install.sh` yang otomatis mendaftarkan symlink `lenz` dan `lenznode` ke `$PREFIX/bin` (Termux) atau `/usr/local/bin` (Linux) saat server pertama kali dijalankan.

### Improvements & UI Polish
* **Peningkatan Visibilitas Ikon Immich**: Memperbarui stroke SVG aplikasi Immich ke warna Indigo terang (`#818CF8`) dan menambahkan latar belakang *glass tint* berdimensi (`rgba(99, 102, 241, 0.16)`) dengan garis tepi halus (`rgba(129, 140, 248, 0.32)`). Ikon kini tampak menyala, berdimensi, dan terbaca sangat jelas pada mode gelap maupun mode terang di layar HP.
* **Harmonisasi Palet Warna Tile Apps**: Menyelaraskan aksen warna dan depth kartu aplikasi pada App Center Hub (Nextcloud di `#38BDF8`, 9Router di `#F472B6`, dan Immich di `#818CF8`).
* **Pembaruan Pesan Saran Update**: Memperbarui petunjuk notifikasi update startup agar menyarankan perintah ringkas `lenz update`.

---

## v2.2.1 (2026-11-23)

### Features
* **Ekspansi Katalog App Center (Nextcloud & Immich)**: Menambahkan dua aplikasi self-hosted populer ke katalog resmi LenzNode:
  * **Nextcloud** (Port 8088): Platform cloud storage, sinkronisasi berkas antar-perangkat, kalender, dan kolaborasi mandiri.
  * **Immich** (Port 2283): Solusi backup foto & video mandiri berkinerja tinggi sebagai alternatif Google Photos dengan timeline cerdas.
* **Modal Instalasi & Progress Bar Dinamis**: Antarmuka web instalasi aplikasi kini dilengkapi indikator persentase dinamis, streaming log pemasangan real-time, dan status dot indikator hidup/mati.
* **Fitur Copot Pemasangan (Clean Uninstall)**: Menambahkan tombol dan dialog konfirmasi pembersihan aplikasi terpasang di `apps/<app-id>` secara tuntas.
* **Kompatibilitas Lintas Sistem Operasi**: Mendukung deteksi lingkungan eksekusi bash installer pada Linux, Android Termux, dan Windows testing.

---

## v2.2.0 (2026-11-22)

### Features
* **Universal Dynamic Apps Engine**: Arsitektur modular berbasis `apps/catalog.json` yang memisahkan katalog aplikasi dari logika server inti, memungkinkan katalog diperbarui langsung dari GitHub tanpa mengubah backend.
* **Integrasi Bawaan 9Router**: Multi-model AI gateway dan token saver terintegrasi di Port 20128 untuk menghubungkan perangkat coding tools (Claude Code, Cursor, Codex, Antigravity) ke 40+ provider AI.

---

## v2.1.0 (2026-11-21)

### Features
* **Sistem Update Otomatis (GitHub Sync)**: Pengecekan otomatis hash commit git ke repositori utama dengan opsi pembaruan manual satu langkah.
* **Integrasi Cloudflare Tunnel**: Menghubungkan dashboard lokal ke domain publik dengan enkripsi SSL tanpa konfigurasi port forwarding ataupun IP publik statis.
* **Optimasi Memori Ekstrem**: Pembatasan alokasi memori Node.js (`--max-old-space-size=128`) untuk memastikan stabilitas server pada smartphone berspesifikasi 512MB - 1GB RAM.
