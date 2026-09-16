# BREBES-WAF Changelog

Semua perubahan penting pada project **BREBES-WAF** dicatat dalam file ini.

Format changelog mengikuti prinsip **Keep a Changelog** dan **Semantic Versioning**.

---

## [Unreleased]

Perubahan yang sedang dikembangkan dan belum masuk ke release resmi.

### Added

Belum ada.

### Changed

Belum ada.

### Deprecated

Belum ada.

### Removed

Belum ada.

### Fixed

Belum ada.

### Security

Belum ada.

### Documentation

Belum ada.

---

## [1.2.0] - 2026-09-16

Release ketiga BREBES-WAF.

Release ini menyempurnakan proses **first-time deployment**, validasi konfigurasi Nginx dan ModSecurity, standardisasi logging, serta response body inspection untuk meningkatkan visibility terhadap security event.

Release **1.2.0 telah melalui pengujian dan validasi sebelum digunakan**.

### Added

#### 1. Nginx Reverser Access Log Configuration

Menambahkan konfigurasi otomatis global Nginx access log menggunakan format:

    access_log /var/log/nginx/access.log reverser;

Konfigurasi digunakan untuk:

- Standardisasi access logging.
- Mendukung korelasi Nginx Access Log dengan ModSecurity Audit Log.
- Mendukung detection analysis.
- Mendukung incident investigation.

---

#### 2. ModSecurity Response Body Inspection

Mengaktifkan pemeriksaan response body:

    SecResponseBodyAccess On

Response body inspection dibatasi pada MIME type:

    text/plain
    text/html
    text/xml
    application/json

Batas response body:

    SecResponseBodyLimit 1048576

Action:

    SecResponseBodyLimitAction ProcessPartial

Konfigurasi ini memberikan kemampuan pemeriksaan response aplikasi dengan tetap membatasi penggunaan resource.

---

### Changed

#### 1. First-Time Deployment Script

Menyempurnakan:

    scripts/deploy-first-time.sh

Perubahan mencakup:

- Memastikan `log_format reverser` tersedia.
- Memastikan global `access_log` menggunakan format `reverser`.
- Memastikan ModSecurity aktif.
- Memastikan `modsecurity_rules_file` tersedia.
- Meningkatkan validasi generated ModSecurity include.
- Meningkatkan validasi jumlah BREBES-WAF rule yang dimuat.
- Mempertahankan backup konfigurasi sebelum perubahan.
- Mempertahankan validasi `nginx -t`.
- Memastikan effective Nginx configuration dapat diverifikasi setelah deployment.

---

#### 2. ModSecurity Audit Logging

Menstandarkan konfigurasi audit logging:

    SecAuditEngine RelevantOnly
    SecAuditLogRelevantStatus "^(?:5|4(?!04))"
    SecAuditLogParts ABCDEFHIJZ
    SecAuditLogType Concurrent
    SecAuditLogStorageDir /var/log/nginx/modsecurity/

Konfigurasi digunakan untuk mendukung pencatatan security event yang relevan.

---

### Deprecated

Belum ada.

---

### Removed

Belum ada.

---

### Fixed

#### 1. ModSecurity Include Validation

Memperbaiki validasi generated file:

    /etc/nginx/modsecurity_includes.conf

Validasi sekarang menangani directive ModSecurity `Include` tanpa mengharuskan penggunaan semicolon dan tidak bergantung pada penggunaan huruf besar atau kecil.

---

#### 2. BREBES-WAF Rule Include Count

Memperbaiki pemeriksaan jumlah custom rule BREBES-WAF pada:

    /etc/nginx/modsecurity_includes.conf

Validasi dapat mengenali seluruh directive:

    Include /opt/Brebes-WAF/rules/.../*.conf

sehingga rule yang telah berhasil dimuat tidak menyebabkan false failure pada proses deployment.

---

#### 3. Global Nginx Access Log Validation

Menambahkan validasi terhadap:

    access_log /var/log/nginx/access.log reverser;

Validasi dilakukan terhadap konfigurasi Nginx dan effective configuration.

---

### Security

#### 1. Response Body Security Inspection

Response body inspection digunakan untuk mendukung pemeriksaan response aplikasi oleh ModSecurity dan OWASP CRS.

Kemampuan ini dapat membantu mendeteksi:

- Information leakage.
- Database error disclosure.
- Outbound anomaly.
- Informasi sensitif yang muncul pada response aplikasi.

Pemeriksaan dibatasi berdasarkan MIME type dan ukuran response untuk mempertimbangkan penggunaan resource.

---

#### 2. Security Logging Standardization

Standardisasi logging mendukung korelasi:

    Nginx Access Log
          +
    ModSecurity Audit Log

untuk:

- Detection analysis.
- False positive analysis.
- Incident investigation.
- Security monitoring.
- Incident response.

---

### Documentation

#### 1. First-Time Deployment Documentation

Dokumentasi first-time deployment diperbarui mengikuti implementasi terbaru pada:

    scripts/deploy-first-time.sh

Baseline:

    CSIRT Lab Reverser

Konfigurasi utama yang divalidasi:

    log_format reverser
    access_log /var/log/nginx/access.log reverser;
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsecurity_includes.conf;

---

## [1.1.0] - 2026-09-11

Release kedua BREBES-WAF.

Release ini menambahkan automation untuk pemeriksaan dan instalasi dependency, standardisasi repository Ubuntu, deteksi package ModSecurity, dukungan Ubuntu Deb822 repository, serta peningkatan persiapan environment sebelum deployment BREBES-WAF.

Release **1.1.0 telah melalui pengujian dan validasi sebelum digunakan**.

### Added

#### 1. BREBES-WAF Dependency Check & Installation

Menambahkan script:

    scripts/check-dependencies.sh

Script digunakan untuk melakukan pemeriksaan dan persiapan dependency yang diperlukan oleh BREBES-WAF sebelum proses deployment.

Fungsi utama:

- Memeriksa sistem operasi Ubuntu.
- Memeriksa versi dan codename Ubuntu.
- Memeriksa dependency BREBES-WAF.
- Memeriksa Nginx.
- Memeriksa ModSecurity v3.
- Memeriksa Nginx ModSecurity Connector.
- Memeriksa Nginx NDK module.
- Memeriksa OWASP Core Rule Set (CRS).
- Memeriksa Git.
- Memeriksa curl.
- Memeriksa CA certificates.
- Menginstal dependency yang belum tersedia.
- Memastikan service Nginx tersedia dan berjalan.
- Memastikan module ModSecurity Nginx tersedia.
- Memastikan module NDK tersedia.
- Memastikan konfigurasi module Nginx tersedia.
- Memastikan konfigurasi ModSecurity tersedia.
- Memastikan OWASP CRS tersedia.
- Melakukan validasi konfigurasi Nginx.
- Memastikan environment siap digunakan oleh BREBES-WAF.

Tujuan:

- Mengurangi kegagalan deployment akibat dependency yang belum tersedia.
- Menstandarkan environment BREBES-WAF.
- Mempermudah instalasi pada server baru.
- Mengurangi konfigurasi manual.
- Memastikan dependency utama tersedia sebelum deployment.

---

#### 2. Ubuntu Official Repository Configuration

Menambahkan kemampuan pada:

    scripts/check-dependencies.sh

untuk memastikan repository Ubuntu menggunakan repository resmi Ubuntu.

Repository utama:

    http://archive.ubuntu.com/ubuntu

Repository security:

    http://security.ubuntu.com/ubuntu

Komponen repository:

    main
    restricted
    universe
    multiverse

Script melakukan backup konfigurasi repository sebelum melakukan perubahan.

Tujuan:

- Mengurangi masalah dependency akibat repository mirror yang bermasalah.
- Memastikan package BREBES-WAF tersedia dari repository Ubuntu resmi.
- Menstandarkan sumber package pada proses deployment.
- Memudahkan deployment pada server baru.

---

#### 3. APT Repository Backup

Menambahkan mekanisme backup konfigurasi APT sebelum perubahan repository Ubuntu dilakukan.

Backup mencakup:

    /etc/apt/sources.list

dan:

    /etc/apt/sources.list.d/

Tujuan:

- Memungkinkan konfigurasi repository dikembalikan apabila terjadi masalah.
- Mengurangi risiko perubahan repository yang tidak dapat dipulihkan.
- Menyediakan jejak konfigurasi sebelum proses deployment.

---

#### 4. Ubuntu Deb822 Repository Support

Menambahkan dukungan terhadap format repository Ubuntu berbasis Deb822:

    /etc/apt/sources.list.d/ubuntu.sources

Hal ini memungkinkan BREBES-WAF menangani sistem Ubuntu yang menggunakan format repository modern selain format:

    /etc/apt/sources.list

---

#### 5. ModSecurity Package Detection

Menambahkan pemeriksaan otomatis terhadap package ModSecurity yang tersedia pada sistem Ubuntu.

Script mendeteksi library ModSecurity yang sesuai dengan sistem, termasuk:

    libmodsecurity3

atau:

    libmodsecurity3t64

Pemeriksaan dilakukan sebelum proses instalasi dependency BREBES-WAF.

Tujuan:

- Menyesuaikan instalasi dengan versi Ubuntu.
- Menghindari hard-code nama package yang tidak tersedia pada versi Ubuntu tertentu.
- Meningkatkan kompatibilitas deployment.

---

#### 6. Git Repository Protection

Menambahkan kategori rule khusus untuk melindungi repository Git yang terekspos melalui web server.

Direktori:

    rules/60-git/

Rule:

    rules/60-git/6001001-git-directory.conf
    rules/60-git/6001002-git-files.conf
    rules/60-git/6001003-git-sensitive-path.conf

Perlindungan ditujukan terhadap akses seperti:

    /.git/
    /.git/config
    /.git/HEAD
    /.git/index
    /.git/logs/
    /.git/logs/HEAD
    /.git/objects/
    /.git/refs/

Risiko yang dikurangi:

- Source Code Disclosure.
- Repository Metadata Disclosure.
- Commit History Disclosure.
- Credential Disclosure.
- Information Disclosure.
- Application Reconnaissance.

---

#### 7. Git Protection Test Script

Menambahkan script PowerShell untuk menguji Git Repository Protection.

File:

    tests/test-brebes-waf-git.ps1

Endpoint yang diuji:

    /.git/
    /.git/config
    /.git/HEAD
    /.git/index
    /.git/logs/
    /.git/logs/HEAD
    /.git/objects/
    /.git/refs/
    /.git/refs/heads/main

Interpretasi hasil:

    403  = BLOCKED
    200  = VULNERABLE
    404  = NOT FOUND
    Other = CHECK

Script digunakan sebagai bagian dari security testing BREBES-WAF.

---

#### 8. Git Test Repository

Menambahkan repository Git test yang memiliki struktur `.git` sebenarnya untuk keperluan pengujian BREBES-WAF.

Struktur test repository mencakup:

    .git/
    ├── HEAD
    ├── config
    ├── index
    ├── logs/
    ├── objects/
    └── refs/

Repository test digunakan untuk memastikan rule Git Repository Protection mampu mendeteksi dan memblokir akses terhadap repository Git yang terekspos.

---

#### 9. First-Time Deployment Script

Menambahkan script deployment khusus untuk deployment pertama kali.

File:

    scripts/deploy-first-time.sh

Fungsi:

- Menyiapkan environment BREBES-WAF.
- Memastikan konfigurasi ModSecurity tersedia.
- Memastikan OWASP CRS tersedia.
- Menyiapkan `crs-load.conf`.
- Menghasilkan konfigurasi ModSecurity include.
- Melakukan validasi konfigurasi Nginx.
- Melakukan deployment secara aman.

---

#### 10. Detection Log Analysis

Menambahkan script untuk membantu analisis log deteksi BREBES-WAF dan OWASP CRS.

File:

    scripts/lastday-detection.sh

Script memisahkan hasil deteksi menjadi:

    ===== BREBES-WAF =====

dan:

    ===== OWASP CRS =====

Tujuan:

- Mempermudah analisis security event.
- Mempermudah pemeriksaan rule yang aktif.
- Membantu analisis false positive.
- Membantu proses incident response.

---

#### 11. OWASP CRS Integration

Menambahkan integrasi dengan OWASP Core Rule Set melalui:

    /etc/nginx/modsecurity/crs-load.conf

BREBES-WAF menggunakan OWASP CRS sebagai salah satu lapisan deteksi keamanan dan menambahkan custom rules BREBES-WAF di atasnya.

---

### Changed

#### 1. Automatic Rule Discovery

Deployment BREBES-WAF sekarang secara otomatis mencari seluruh file rule dengan extension:

    *.conf

di dalam:

    /opt/Brebes-WAF/rules/

Contoh kategori:

    rules/00-core/
    rules/10-upload/
    rules/20-webshell/
    rules/30-wordpress/
    rules/40-malware/
    rules/50-generic/
    rules/60-git/
    rules/90-local/

Rule tidak perlu didaftarkan satu per satu secara manual pada konfigurasi utama.

---

#### 2. Deployment Script

File:

    scripts/deploy.sh

Deployment script melakukan pemeriksaan terhadap:

    /etc/nginx/modsecurity/crs-load.conf

Jika file tersedia, file tersebut digunakan.

Jika file tidak tersedia, deployment script mencari repository file:

    /opt/Brebes-WAF/nginx/modsecurity/crs-load.conf

Jika ditemukan, file akan disalin ke:

    /etc/nginx/modsecurity/crs-load.conf

Jika kedua file tidak tersedia, deployment dihentikan.

---

#### 3. ModSecurity Include Generation

Deployment script menghasilkan:

    /etc/nginx/modsecurity_includes.conf

File tersebut memuat:

    modsecurity.conf
    crs-load.conf
    BREBES-WAF Rules

Contoh:

    include modsecurity.conf
    include /etc/nginx/modsecurity/crs-load.conf
    Include /opt/Brebes-WAF/rules/00-core/...
    Include /opt/Brebes-WAF/rules/10-upload/...
    Include /opt/Brebes-WAF/rules/20-webshell/...
    Include /opt/Brebes-WAF/rules/30-wordpress/...
    Include /opt/Brebes-WAF/rules/40-malware/...
    Include /opt/Brebes-WAF/rules/50-generic/...
    Include /opt/Brebes-WAF/rules/60-git/...
    Include /opt/Brebes-WAF/rules/90-local/...

---

#### 4. Deployment Backup

Deployment sekarang melakukan backup terhadap konfigurasi sebelumnya:

    /etc/nginx/modsecurity_includes.conf.bak

Backup dilakukan sebelum konfigurasi baru diterapkan.

Tujuan:

- Mempermudah recovery.
- Mengurangi risiko downtime.
- Memungkinkan konfigurasi sebelumnya dipulihkan apabila deployment gagal.

---

#### 5. Deployment Rollback

Deployment script memiliki mekanisme rollback apabila validasi konfigurasi atau reload Nginx gagal.

Tahapan:

    Backup
       ↓
    Generate
       ↓
    nginx -t
       ↓
    Reload Nginx
       ↓
    Verify

Apabila proses gagal, konfigurasi sebelumnya akan dipulihkan dari:

    /etc/nginx/modsecurity_includes.conf.bak

---

#### 6. Nginx Configuration Validation

Deployment hanya dilanjutkan apabila:

    nginx -t

berhasil.

Expected result:

    syntax is ok
    test is successful

Tujuan:

- Mencegah konfigurasi invalid diterapkan.
- Mengurangi risiko downtime.
- Memastikan konfigurasi WAF dapat dimuat oleh Nginx.

---

#### 7. Deployment Preparation Workflow

Proses deployment BREBES-WAF kini dapat diawali dengan pemeriksaan dependency secara otomatis menggunakan:

    ./scripts/check-dependencies.sh

Setelah dependency dinyatakan tersedia dan environment siap, proses deployment dapat dilanjutkan menggunakan:

    ./scripts/deploy-first-time.sh

atau:

    ./scripts/deploy.sh

Workflow:

    Check Dependency
          ↓
    Prepare Environment
          ↓
    Deploy BREBES-WAF
          ↓
    Validate Nginx
          ↓
    Reload Nginx
          ↓
    Verify
          ↓
    BREBES-WAF Active

---

### Deprecated

Belum ada.

---

### Removed

Belum ada.

---

### Fixed

#### 1. Upload Extension False Positive

Memperbaiki false positive pada:

    rules/10-upload/1001003-upload-deny-extension.conf

Sebelumnya terdapat kondisi multipart request dengan:

    MULTIPART_FILENAME

yang kosong dapat dianggap sebagai filename yang harus diperiksa extension-nya.

Kondisi tersebut dapat menyebabkan request legitimate ditolak.

Rule kemudian diperbaiki agar filename kosong tidak dianggap sebagai file dengan extension yang tidak diperbolehkan.

Revision rule:

    rev:'2'

Tujuan:

- Mengurangi false positive.
- Tetap mempertahankan upload protection.
- Memastikan request multipart legitimate tidak ditolak secara tidak semestinya.

---

#### 2. Empty Rules Directory Protection

Deployment script sekarang menghentikan proses apabila tidak ditemukan file:

    *.conf

pada:

    /opt/Brebes-WAF/rules/

Hal ini mencegah deployment menghasilkan konfigurasi WAF tanpa custom rules BREBES-WAF.

---

#### 3. Dependency Availability

Memperbaiki proses deployment yang sebelumnya dapat dilanjutkan ketika dependency BREBES-WAF belum tersedia.

Dengan dependency checker, kondisi dependency dapat diketahui terlebih dahulu sebelum deployment.

---

#### 4. ModSecurity Package Compatibility

Memperbaiki ketergantungan terhadap nama package ModSecurity tertentu dengan melakukan deteksi package yang tersedia pada sistem Ubuntu.

BREBES-WAF dapat menangani perbedaan nama package library ModSecurity, seperti:

    libmodsecurity3

dan:

    libmodsecurity3t64

---

### Security

#### 1. Exposed Git Repository Protection

BREBES-WAF `1.1.0` mempertahankan perlindungan terhadap repository Git yang terekspos melalui web server.

Akses terhadap:

    /.git/

dan resource di bawahnya harus diperlakukan sebagai aktivitas berisiko tinggi.

Perlindungan mencakup:

    .git/config
    .git/HEAD
    .git/index
    .git/logs/
    .git/objects/
    .git/refs/

Risiko:

- Source Code Disclosure.
- Credential Disclosure.
- Repository Metadata Disclosure.
- Commit History Disclosure.
- Information Disclosure.

---

#### 2. Upload Security

BREBES-WAF `1.1.0` mempertahankan kontrol terhadap file upload untuk mengurangi risiko:

- Malicious file upload.
- Executable file upload.
- Webshell upload.
- Server-side script upload.
- Penyalahgunaan upload directory.

---

#### 3. Secure Deployment

Deployment menggunakan:

- Configuration backup.
- Configuration validation.
- Controlled reload.
- Rollback mechanism.
- Automatic rule discovery.
- Dependency validation.

Tujuan utama adalah mencegah perubahan konfigurasi WAF yang invalid atau tidak lengkap diterapkan ke server production.

---

#### 4. Dependency Validation

Sebelum deployment, dependency utama BREBES-WAF diperiksa untuk memastikan environment memenuhi persyaratan yang diperlukan.

Validasi mencakup:

- Nginx.
- ModSecurity v3.
- Nginx ModSecurity Connector.
- Nginx NDK.
- OWASP CRS.
- Git.
- curl.
- CA certificates.
- Konfigurasi ModSecurity.
- Konfigurasi BREBES-WAF.

---

#### 5. Repository Configuration Backup

Konfigurasi repository Ubuntu dibackup sebelum dilakukan perubahan.

Hal ini memberikan kemampuan recovery terhadap konfigurasi APT apabila terjadi masalah selama proses persiapan environment.

---

### Documentation

#### 1. Changelog

Dokumentasi perubahan project dicatat melalui:

    changelog/CHANGELOG.md

Changelog digunakan untuk mencatat:

- Rule baru.
- Perubahan rule.
- Security fix.
- Bug fix.
- False positive fix.
- Perubahan deployment.
- Perubahan testing.
- Perubahan dependency.
- Perubahan repository.
- Perubahan dokumentasi.
- Release version.

---

#### 2. Dependency Installation Documentation

Menambahkan dokumentasi mengenai:

- Persyaratan sistem.
- Dependency BREBES-WAF.
- Pemeriksaan dependency.
- Instalasi dependency.
- Repository Ubuntu.
- ModSecurity v3.
- OWASP CRS.
- Nginx ModSecurity Connector.
- Nginx NDK.
- Proses first-time deployment.

---

#### 3. Rule ID Convention

BREBES-WAF menggunakan pembagian Rule ID berdasarkan kategori.

| Range | Kategori | Keterangan |
|---|---|---|
| `1000000-1000999` | Core | Rule dasar BREBES-WAF |
| `1001000-1001999` | Upload | Perlindungan file upload |
| `2001000-2001999` | Webshell | Deteksi dan pencegahan webshell |
| `3001000-3001999` | WordPress | Perlindungan WordPress |
| `4001000-4001999` | Malware | Deteksi malware |
| `5001000-5001999` | Generic | Rule keamanan umum |
| `6001000-6001999` | Git | Perlindungan repository Git |
| `9001000-9001999` | Local | Rule khusus deployment/local environment |

---

#### 4. Rule Naming Convention

Nama file rule menggunakan format:

    <RULE_ID>-<description>.conf

Contoh:

    1001003-upload-deny-extension.conf
    6001001-git-directory.conf
    6001002-git-files.conf
    6001003-git-sensitive-path.conf

---

#### 5. Deployment Documentation

Dokumentasi deployment diperbarui untuk mencakup workflow:

    check-dependencies.sh
           ↓
    deploy-first-time.sh
           ↓
    deploy.sh
           ↓
    nginx -t
           ↓
    Reload
           ↓
    Verify

---

## Rule ID Convention

BREBES-WAF menggunakan range Rule ID sebagai berikut:

    1000000-1000999    Core
    1001000-1001999    Upload
    2001000-2001999    Webshell
    3001000-3001999    WordPress
    4001000-4001999    Malware
    5001000-5001999    Generic
    6001000-6001999    Git
    9001000-9001999    Local

Range dapat dikembangkan sesuai kebutuhan project.

---

## Deployment Principles

Deployment BREBES-WAF mengikuti prinsip:

    Validate
        ↓
    Backup
        ↓
    Generate
        ↓
    Test
        ↓
    Reload
        ↓
    Verify

### Validate

Memastikan:

- Script dijalankan sebagai root.
- Directory BREBES-WAF tersedia.
- Directory rules tersedia.
- File `.conf` tersedia.
- OWASP CRS tersedia.
- `crs-load.conf` tersedia.
- Dependency utama tersedia.

### Backup

Menyimpan konfigurasi sebelumnya:

    /etc/nginx/modsecurity_includes.conf.bak

### Generate

Membuat:

    /etc/nginx/modsecurity_includes.conf

### Test

Menjalankan:

    nginx -t

### Reload

Menjalankan:

    systemctl reload nginx

### Verify

Memastikan:

- Nginx aktif.
- ModSecurity aktif.
- OWASP CRS aktif.
- BREBES-WAF rules aktif.
- Detection log tersedia.
- Request berbahaya dapat diblokir.

---

## Testing Principles

Setiap rule baru harus melalui:

    Rule Development
          ↓
    Syntax Validation
          ↓
    Positive Test
          ↓
    Negative Test
          ↓
    False Positive Analysis
          ↓
    Deployment
          ↓
    Production Verification

### Positive Test

Request berbahaya yang seharusnya diblokir harus menghasilkan:

    HTTP 403

### Negative Test

Request legitimate harus tetap dapat diproses oleh aplikasi.

Contoh:

    HTTP 200

atau response normal aplikasi.

### False Positive Analysis

Setiap rule baru harus diuji terhadap request legitimate untuk memastikan rule tidak terlalu agresif.

---

## Git Protection Testing

Endpoint test:

    https://csirtlab.brebeskab.go.id/brebes-waf-git-test

Test:

    /.git/
    /.git/config
    /.git/HEAD
    /.git/index
    /.git/logs/
    /.git/logs/HEAD
    /.git/objects/
    /.git/refs/
    /.git/refs/heads/main

Expected result:

    HTTP 403

Jika mendapatkan:

    HTTP 200

maka endpoint dianggap berpotensi vulnerable dan perlu dilakukan investigasi.

Jika mendapatkan:

    HTTP 404

berarti resource tidak ditemukan, tetapi kondisi tersebut tidak secara otomatis membuktikan bahwa rule WAF berhasil memblokir request.

---

## Upload Protection Testing

### Allowed Extensions

    .png
    .jpg
    .jpeg
    .webp
    .pdf
    .txt
    .rtf
    .doc
    .docx
    .odt
    .xls
    .xlsx
    .csv
    .ods
    .ppt
    .pptx
    .odp

### Disallowed Extensions

Contoh:

    .php
    .php5
    .phtml
    .phar
    .cgi
    .pl
    .py
    .sh
    .exe

Pengujian harus memastikan file legitimate tidak diblokir dan file dengan extension yang tidak diizinkan ditolak sesuai rule.

---

## Operational Logging

Log BREBES-WAF digunakan untuk:

- Detection analysis.
- Incident investigation.
- False positive analysis.
- Rule tuning.
- Security monitoring.
- Incident response.

Analisis WAF sebaiknya dilakukan bersama:

    Nginx Access Log
    Nginx Error Log
    ModSecurity Audit Log
    Application Log
    System Log

Timestamp filesystem tidak boleh digunakan sebagai satu-satunya dasar untuk menentukan waktu terjadinya suatu aktivitas dalam investigasi insiden.

Metadata file dapat berubah dan dapat dimanipulasi.

---

## Versioning

BREBES-WAF menggunakan format:

    MAJOR.MINOR.PATCH

Contoh:

    1.0.0
    1.1.0
    1.1.1

### MAJOR

Digunakan untuk perubahan besar atau breaking change.

Contoh:

    1.x.x → 2.x.x

### MINOR

Digunakan untuk penambahan fitur atau rule baru yang tidak menyebabkan breaking change.

Contoh:

    1.0.0 → 1.1.0

### PATCH

Digunakan untuk:

- Bug fix.
- False positive fix.
- Rule tuning.
- Security fix kecil.
- Perbaikan dokumentasi.

Contoh:

    1.1.0 → 1.1.1

---

## Release Policy

Release BREBES-WAF mengikuti prinsip:

    Development
        ↓
    Testing
        ↓
    Review
        ↓
    Release
        ↓
    Production

### Development

Perubahan yang belum selesai berada pada:

    ## [Unreleased]

### Release

Setelah perubahan selesai dan telah diuji, perubahan dipindahkan ke release version.

Contoh:

    ## [Unreleased]

menjadi:

    ## [1.1.0] - 2026-09-11

### Release Date

Tanggal release menggunakan format:

    YYYY-MM-DD

Contoh:

    2026-09-11

---

## Change Categories

Changelog menggunakan kategori:

- Added
- Changed
- Deprecated
- Removed
- Fixed
- Security
- Documentation

### Added

Fitur, rule, script, atau kemampuan baru.

### Changed

Perubahan terhadap fitur atau konfigurasi yang sudah ada.

### Deprecated

Fitur atau rule yang mulai tidak direkomendasikan.

### Removed

Fitur atau rule yang dihapus.

### Fixed

Perbaikan bug dan false positive.

### Security

Perubahan yang berkaitan langsung dengan keamanan.

### Documentation

Perubahan dokumentasi.

---

## Maintenance Guidelines

Sebelum menambahkan rule baru:

1. Tentukan kategori rule.
2. Tentukan Rule ID.
3. Gunakan nama file yang konsisten.
4. Tambahkan rule ke repository.
5. Buat positive test.
6. Buat negative test.
7. Uji false positive.
8. Jalankan `nginx -t`.
9. Deploy menggunakan deployment script.
10. Verifikasi log.
11. Update `CHANGELOG.md`.

---

## Recommended Development Workflow

Workflow pengembangan BREBES-WAF:

    Create Rule
        ↓
    Local Testing
        ↓
    Security Testing
        ↓
    False Positive Testing
        ↓
    Code Review
        ↓
    Git Commit
        ↓
    Git Push
        ↓
    Deployment
        ↓
    Production Verification
        ↓
    Changelog Update

---

## Git Workflow

Branch utama:

    main

Branch pengembangan:

    development

Perubahan baru dikembangkan pada:

    development

Setelah testing selesai, perubahan dapat diajukan melalui Pull Request menuju:

    main

Alur:

    development
          │
          ▼
       Testing
          │
          ▼
      Code Review
          │
          ▼
     Pull Request
          │
          ▼
        main
          │
          ▼
    Release / Production

---

## Changelog Maintenance

Setiap perubahan penting harus dicatat pada:

    changelog/CHANGELOG.md

Perubahan yang wajib dicatat:

- Rule baru.
- Perubahan Rule ID.
- Perubahan konfigurasi ModSecurity.
- Perubahan OWASP CRS.
- Perubahan deployment script.
- Perubahan dependency.
- Perubahan repository configuration.
- Perubahan testing script.
- Security fix.
- False positive fix.
- Bug fix.
- Perubahan struktur repository.
- Perubahan dokumentasi penting.

---

## Future Planned Changes

Rencana pengembangan BREBES-WAF:

- Penambahan rule webshell.
- Penambahan rule PHP attack.
- Penambahan rule WordPress security.
- Penambahan rule malware upload.
- Peningkatan upload protection.
- Peningkatan Git protection.
- Automated security testing.
- Automated regression testing.
- Automated rule validation.
- Detection log reporting.
- Deployment verification.
- Security dashboard.
- Rule testing framework.
- Integrasi security monitoring.
- Administrator guide.
- Rule development guide.
- Testing guide.
- Incident response integration guide.

---

## Security Philosophy

BREBES-WAF dikembangkan berdasarkan prinsip:

    Defense in Depth
    Least Privilege
    Secure by Default
    Fail Safely
    Explicit Allow
    Minimal Exposure
    Continuous Monitoring
    Continuous Improvement

BREBES-WAF merupakan salah satu lapisan keamanan dan tidak menggantikan kontrol keamanan lainnya.

Arsitektur defense-in-depth:

    Internet
        │
        ▼
    Firewall
        │
        ▼
    Network Security
        │
        ▼
    Nginx
        │
        ▼
    BREBES-WAF
        │
        ▼
    Application
        │
        ▼
    Database

BREBES-WAF tidak menggantikan:

- Secure coding.
- Patch management.
- Authentication security.
- Access control.
- Network security.
- Endpoint security.
- Backup.
- Monitoring.
- Incident response.

---

## Current Repository Structure

Struktur repository BREBES-WAF:

    BREBES-WAF/
    │
    ├── changelog/
    │   └── CHANGELOG.md
    │
    ├── docs/
    │
    ├── nginx/
    │   ├── nginx.conf
    │   └── modsecurity/
    │       └── crs-load.conf
    │
    ├── rules/
    │   ├── 00-core/
    │   ├── 10-upload/
    │   ├── 20-webshell/
    │   ├── 30-wordpress/
    │   ├── 40-malware/
    │   ├── 50-generic/
    │   ├── 60-git/
    │   │   ├── 6001001-git-directory.conf
    │   │   ├── 6001002-git-files.conf
    │   │   └── 6001003-git-sensitive-path.conf
    │   └── 90-local/
    │
    ├── samples/
    │
    ├── scripts/
    │   ├── check-dependencies.sh
    │   ├── check-last-detection.sh
    │   ├── deploy.sh
    │   ├── deploy-first-time.sh
    │   └── lastday-detection.sh
    │
    └── tests/
        └── test-brebes-waf-git.ps1

---

## Release Checklist

### Version 1.1.0

#### Rules

- [x] Core rule structure.
- [x] Upload protection.
- [x] Git repository protection.
- [x] Git directory protection.
- [x] Git file protection.
- [x] Git sensitive path protection.

#### Deployment

- [x] Automatic rule discovery.
- [x] OWASP CRS integration.
- [x] CRS configuration check.
- [x] CRS repository fallback.
- [x] Configuration generation.
- [x] Configuration backup.
- [x] Nginx syntax validation.
- [x] Deployment rollback.
- [x] First-time deployment script.
- [x] Dependency checking.
- [x] Dependency installation.
- [x] Ubuntu official repository configuration.
- [x] APT repository backup.
- [x] Ubuntu Deb822 repository support.
- [x] ModSecurity package detection.
- [x] Deployment preparation validation.

#### Testing

- [x] Upload extension testing.
- [x] Git protection testing.
- [x] Positive testing.
- [x] Negative testing.
- [x] False positive analysis.
- [x] Dependency testing.
- [x] Deployment testing.
- [x] Nginx configuration validation.

#### Monitoring

- [x] BREBES-WAF detection log analysis.
- [x] OWASP CRS detection log analysis.

#### Documentation

- [x] Changelog.
- [x] Rule ID convention.
- [x] Rule naming convention.
- [x] Dependency documentation.
- [x] Deployment principles.
- [x] Testing principles.
- [x] Git workflow.
- [x] Release policy.

---

## Release History

| Version | Release Date | Status | Description |
|---|---|---|---|
| `Unreleased` | - | Development | Perubahan yang sedang dikembangkan |
| `1.2.0` | `2026-09-16` | **Stable** | First-time deployment enhancement, configuration validation, response body inspection, dan logging standardization |
| `1.1.0` | `2026-09-11` | **Stable** | Dependency automation, Ubuntu repository configuration, ModSecurity package detection, dan deployment preparation |
| `1.0.0` | `2026-09-10` | Stable | Initial BREBES-WAF release |

---

## Unreleased Checklist

### Rules

- [ ] Webshell protection enhancement.
- [ ] PHP attack protection.
- [ ] WordPress protection enhancement.
- [ ] Malware detection enhancement.
- [ ] Generic attack rule enhancement.

### Deployment

- [ ] Deployment verification enhancement.
- [ ] Automated deployment testing.
- [ ] Deployment health check.

### Testing

- [ ] Automated regression testing.
- [ ] Automated rule validation.
- [ ] Automated false positive testing.

### Monitoring

- [ ] Automated daily security report.
- [ ] Security dashboard.
- [ ] Detection statistics.

### Documentation

- [ ] Administrator guide.
- [ ] Rule development guide.
- [ ] Testing guide.
- [ ] Incident response integration guide.

---

## Release Notes

### BREBES-WAF 1.2.0

**Release Date:** 2026-09-16

BREBES-WAF `1.2.0` merupakan release yang menyempurnakan proses first-time deployment dan validasi konfigurasi BREBES-WAF.

Release ini mencakup:

- First-time deployment enhancement.
- Nginx `reverser` access log.
- Global access log validation.
- Effective Nginx configuration validation.
- ModSecurity configuration validation.
- ModSecurity include validation.
- BREBES-WAF rule include validation.
- Response body inspection.
- ModSecurity audit logging standardization.
- Security logging standardization.
- Deployment verification.

Release `1.2.0` telah melalui pengujian dan validasi sebelum digunakan dan menjadi baseline untuk pengembangan BREBES-WAF berikutnya.

---

### BREBES-WAF 1.1.0

**Release Date:** 2026-09-11

BREBES-WAF `1.1.0` merupakan release kedua yang memperluas automation dan deployment preparation dari BREBES-WAF.

Release ini menambahkan:

- Dependency checking.
- Automatic dependency installation.
- Ubuntu official repository configuration.
- APT repository backup.
- Ubuntu Deb822 repository support.
- ModSecurity package detection.
- Deployment dependency validation.
- Improved first-time deployment preparation.

Fokus release:

- Dependency Automation.
- Environment Preparation.
- Ubuntu Repository Standardization.
- ModSecurity Compatibility.
- OWASP CRS Integration.
- Secure Deployment.
- Configuration Backup.
- Deployment Rollback.
- Git Repository Protection.
- Upload Protection.
- Detection Log Analysis.
- Security Testing.

Release `1.1.0` telah melalui pengujian dan validasi sebelum digunakan dan menjadi baseline untuk pengembangan BREBES-WAF berikutnya.

---

### BREBES-WAF 1.0.0

**Release Date:** 2026-09-10

BREBES-WAF `1.0.0` merupakan release stabil pertama yang menyediakan fondasi Web Application Firewall berbasis:

    Nginx

    +

    ModSecurity v3

    +

    OWASP CRS

    +

    BREBES-WAF Rules

Fokus release:

- Upload Protection.
- Git Repository Protection.
- OWASP CRS Integration.
- Deployment Automation.
- Configuration Backup.
- Deployment Rollback.
- Detection Log Analysis.
- Security Testing.
- Rule Organization.

Release `1.0.0` menjadi baseline untuk pengembangan BREBES-WAF berikutnya.

---

## License

Informasi lisensi BREBES-WAF mengikuti ketentuan lisensi yang ditetapkan pada repository project.

---

**BREBES-WAF**

**Brebes CSIRT**

Web Application Firewall Security Ruleset

    Nginx

    +

    ModSecurity v3

    +

    OWASP CRS

    +

    BREBES-WAF Rules