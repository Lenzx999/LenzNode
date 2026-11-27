# Changelog

Semua catatan perubahan dan riwayat pembaruan versi pada **LenzNode** didokumentasikan di berkas ini.

Format changelog ini mengacu pada standar rilis berbasis versi semantik (*Semantic Versioning*).

---

## v2.2.8 (2026-11-27)

### Android APK Edition (Standalone PRoot, Dual-Mode & Multi-ABI CI)
* **Edisi Aplikasi Android Mandiri (`com.lenznode.app`) Tanpa Membutuhkan Termux**:
  * Menghadirkan aplikasi Android asli (`android-app/`) dengan *Foreground Service*, `PARTIAL_WAKE_LOCK`, dan `WifiLock` yang otomatis menyiapkan lingkungan Ubuntu 22.04 minimal di dalam PRoot, memasang dependensi inti (`openssh-server`, Node.js LTS, `git`, `curl`, `cloudflared`), serta menjalankan Web Dashboard LenzNode di `http://127.0.0.1:8080`.
  * **Dual-Mode (Host Server & Remote Client)**: Pengguna dapat memilih **"Jadikan HP Ini Server"** atau **"Akses Server HP Lain"** langsung dari aplikasi (tersimpan & dapat diganti kapan saja), lengkap dengan autentikasi **Token Akses (`lnz_...`)** via `POST /api/auth/token`, `GET /api/settings/access`, dan `POST /api/settings/access/regenerate` di `panel/server.js` + menu **Pengaturan ➜ Jaringan & Tunnel** di Web Dashboard.
  * **OTA Update 1-Klik & App Center di Mode APK**: Pembaruan sistem dari GitHub (`codeload.github.com`) berjalan langsung di mode `android-apk` tanpa membutuhkan folder `.git`, sambil menjaga kredensial `auth-config.json` (termasuk `accessToken`), log, dan aplikasi terpasang (`9router`, `immich`, `nextcloud`).
  * Mempertahankan desain tema *Obsidian Dark glassmorphism* LenzNode secara penuh dengan ikon resmi baru pada launcher dan header aplikasi, serta transisi otomatis ke *WebView* berakselerasi perangkat keras (dukungan WebSocket, unggah/unduh berkas File Manager, keyboard terminal `adjustResize`, dan tombol kembali).
  * **Keamanan & Anti-Decompilation**: R8 minification & resource shrinking aktif di rilis (`isMinifyEnabled = true`), `android:allowBackup="false"`, debugging WebView dinonaktifkan di build rilis, serta aset runtime diproteksi di dalam `assets/lenznode-bundle.dat` (JS/HTML terobfuskasi + ZIP ter-XOR).
  * Menambahkan **Native Hardware Bridge** (`127.0.0.1:48080`) di aplikasi Android beserta dukungan `LENZ_BRIDGE_URL` pada `panel/server.js` untuk membaca status baterai, suhu, menyalakan senter (*torch*), getar, dan wakelock secara langsung ketika akses `/sys` dibatasi di dalam PRoot.
  * Menyediakan dukungan dua arsitektur dalam split APK terpisah: **Modern 64-bit (`LenzNode-modern-arm64-v8a.apk`)** dan **Lama 32-bit (`LenzNode-lama-armeabi-v7a.apk`)** dengan `targetSdkVersion = 28` agar terminal Ubuntu bebas menjalankan binary hasil `apt install`.
* **Otomatisasi Build & Packaging GitHub Actions (`.github/workflows/build-apk.yml`)**:
  * Menambahkan skrip `android-app/scripts/fetch-android-bins.sh` untuk mengunduh, memverifikasi SHA256, mengekstrak `proot` (+ `libtalloc`, `libandroid-shmem`) dari Termux APT dan `busybox-static` dari Alpine Linux, melakukan patching ELF `DT_NEEDED`/`RUNPATH` agar kompatibel dengan `jniLibs`, mengobfuskasi `panel/`, serta membungkus runtime ke `assets/lenznode-bundle.dat`.
  * Menjalankan unit test JVM, Android Lint, build & penandatanganan kedua split APK rilis, verifikasi isi APK via `aapt2`, `apksigner`, dan `dexdump`, lalu mengunggah hasil APK sebagai GitHub Actions Artifacts / GitHub Release.

### Stability & Anti-Signal 9 Optimization (Termux)
* **Pencegahan `Process completed (signal 9)` / Phantom Process Killer (Android 12+)**:
  * Menambahkan caching 15 detik pada fungsi `getDiskInfo()` di `panel/server.js` agar pemantauan metrik WebSocket (`/ws/stats`) dan `/api/system/stats` tidak terus-menerus memicu pembuatan sub-proses `df` setiap 2 detik (mengurangi beban proses anak di Android secara drastis).
  * Menaikkan batas `--max-memory-restart` PM2 di `start.sh` dari `120M` menjadi `256M` agar selaras dengan batas heap `--max-old-space-size=128` dan mencegah loop restart paksa saat penggunaan RAM normal meningkat.
  * Menambahkan pengaktifan ulang `termux-wake-lock` otomatis di `panel/server.js` saat server melakukan boot/restart serta memisahkan stream input (`</dev/null`) pada peluncuran `nohup` di `start.sh`.

---

## v2.2.7 (2026-11-26)

### App Center Fixes (Immich & Nextcloud)
* **Perbaikan Bug Start/Stop & Status Palsu Immich & Nextcloud**:
  * Memperbaiki *race condition* file `.pid` di `startDynamicAppService()` (`panel/server.js`): menghapus `.pid` basi sebelum start dan tidak lagi menimpa `.pid` dengan PID shell sementara ketika aplikasi dijalankan via `start.sh`.
  * Menyelaraskan validasi port aktif (`2283` untuk Immich, `8088` untuk Nextcloud) hingga 10 detik dan mengembalikan pesan error log asli jika layanan gagal menyala.
  * Memperbaiki skrip `apps/nextcloud/install.sh` dengan menghapus nama paket `php-sqlite` yang tidak tersedia di repositori Termux agar instalasi `php` berjalan sukses.

---

## v2.2.6 (2026-11-24)

### Critical Bug Fixes & Resiliency
* **Penuntasan Akar Masalah Login Remote 9Router AI Gateway**:
  * Injeksi password default hash bcrypt (`$2b$10$...` untuk `123456`) langsung ke database SQLite 9Router (`~/.9router/db/data.sqlite`) via `ensure9RouterPassword()`, mencegah pemicu blokade keamanan Next.js 9Router ("Default password must be changed before remote access").
  * Menyelaraskan variabel lingkungan `INITIAL_PASSWORD="123456"` dengan parameter `--update-env` pada PM2 dan peluncur background, sehingga login remote dari IP LAN (`192.168.x.x`) langsung terautentikasi sukses.
* **Perbaikan Total Kontrol Start/Stop & Sinkronisasi Status 9Router**:
  * Menghilangkan proses hang dan false-detection dengan menghapus fallback IPv6 `::1` pada loopback socket probe `isPortListening` dan memangkas waktu respons probe menjadi 1000ms.
  * Menyelaraskan pendeteksian port di skrip `start-9router.sh` menggunakan Node.js `net.connect` langsung (menggantikan netstat/ss yang tidak memiliki izin baca di Android Termux non-root).
  * Menyempurnakan pembersihan proses `killProcessOnPort()`: mematikan langsung proses anak Next.js dengan `SIGKILL`, memverifikasi pelepasan port sebelum merespons, dan mengembalikan status error nyata (`ok: false`) jika port gagal dibuka/ditutup.
* **Perbaikan Layanan OpenSSH Server Termux (Port 2222)**:
  * Menambahkan indikator status live OpenSSH Server (`vps-live-badge`) serta tombol kendali **"Mulai SSH"** dan **"Hentikan SSH"** pada antarmuka Web Dashboard Pengaturan Akses SSH.
  * Memastikan izin berkas host key privat (`0600`), kunci publik (`0644`), dan folder `$PREFIX/etc/ssh` (`0700`) sesuai standar ketat OpenSSH, mencegah kegagalan silent boot `sshd: no hostkeys available`.
  * Menyelaraskan teks instruksi SSH Publik jika tunnel belum aktif agar pengguna diarahkan menggunakan SSH Lokal di jaringan Wi-Fi.

---

## v2.2.5 (2026-11-24)

### Bug Fixes & System Stability
* **Perbaikan Total Blokade Login Remote 9Router AI Gateway**:
  * Menyelaraskan injeksi `INITIAL_PASSWORD="123456"` di seluruh layer sistem: `~/.bashrc`, `install.sh`, `start.sh`, `update.sh`, peluncur `start-9router.sh`, dan proses backend `server.js`.
  * Memastikan parameter host binding `-H 0.0.0.0` dan proteksi `--skip-update` disematkan saat menjalankan 9Router, mencegah freeze/hang saat booting pada perangkat mobile dan mengizinkan autentikasi remote via IP LAN maupun domain Cloudflare.
* **Sinkronisasi Status Dashboard & Tombol Start/Stop/Restart**:
  * Mengganti indikator visual hardcoded menjadi status deteksi live real-time (`dot-none` saat memuat).
  * Mengimplementasikan modul `killProcessOnPort()` mutlak: membersihkan proses via `~/.9router/launcher.pid`, memindai inode socket `/proc/net/tcp` & `/proc/net/tcp6`, memindai `/proc/[pid]/cmdline`, serta utilitas sistem (`lsof`, `fuser`, `pkill`), sehingga perintah Stop benar-benar mematikan proses dan membebaskan port 20128 secara instan tanpa proses menggantung.
  * Menambahkan status visual loading spinner dan penonaktifan tombol sementara selama transisi Start/Stop/Restart untuk mencegah klik ganda dan race conditions.
  * Menyesuaikan toleransi timeout deteksi socket TCP (2500ms) agar kebal terhadap lonjakan CPU pada perangkat dengan RAM terbatas.
* **Penuntasan Konfigurasi OpenSSH Server Termux**:
  * Memastikan direktori `$PREFIX/var/run`, berkas `$PREFIX/etc/ssh/sshd_config` (`Port 2222`, `PasswordAuthentication yes`, `ListenAddress 0.0.0.0`), dan host key OpenSSH selalu dijamin ada dan valid pada proses startup, instalasi, maupun update OTA.
  * Menyelaraskan kata sandi bawaan `admin123` via `passwd` dengan environment PATH penuh termux bin, sehingga login via SSH lokal (`ssh termux@<ip> -p 2222`) maupun remote tunnel langsung terautentikasi sukses.
  * Menambahkan paket `psmisc` dan `procps` ke installer untuk menjamin perkakas kontrol proses Termux selalu lengkap.

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
