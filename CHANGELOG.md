# Changelog

Semua catatan perubahan dan riwayat pembaruan versi pada **LenzNode** didokumentasikan di berkas ini.

Format changelog ini mengacu pada standar rilis berbasis versi semantik (*Semantic Versioning*).

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
