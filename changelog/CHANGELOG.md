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

### Fixed

Belum ada.

### Security

Belum ada.

### Documentation

Belum ada.

---

## [1.0.0] - 2026-09-10

Release stabil pertama BREBES-WAF.

Release ini mencakup struktur dasar project, integrasi OWASP CRS, deployment automation, upload protection, Git repository protection, security testing, detection log analysis, serta mekanisme backup dan rollback.

### Added

#### 1. BREBES-WAF Rule Structure

Menambahkan struktur kategori rule BREBES-WAF:

    rules/
    ├── 00-core/
    ├── 10-upload/
    ├── 20-webshell/
    ├── 30-wordpress/
    ├── 40-malware/
    ├── 50-generic/
    ├── 60-git/
    └── 90-local/

Struktur ini digunakan untuk memisahkan rule berdasarkan fungsi dan kategori keamanan.

Tujuan:

- Mempermudah maintenance.
- Mempermudah audit rule.
- Mempermudah troubleshooting.
- Mempermudah pengembangan rule baru.
- Memisahkan rule berdasarkan kategori serangan.

---

#### 2. Upload Protection

Menambahkan perlindungan terhadap file upload melalui kategori:

    rules/10-upload/

Perlindungan mencakup pemeriksaan extension file yang diizinkan dan penolakan terhadap extension yang tidak diperbolehkan.

Extension yang diizinkan:

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

Contoh extension yang tidak diperbolehkan:

    .php
    .php5
    .phtml
    .phar
    .cgi
    .pl
    .py
    .sh
    .exe

Tujuan:

- Mengurangi risiko malicious file upload.
- Mencegah upload file executable.
- Mengurangi risiko webshell melalui mekanisme upload.
- Memberikan kontrol terhadap jenis file yang dapat di-upload.

---

#### 3. Git Repository Protection

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

#### 4. Git Protection Test Script

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

#### 5. Git Test Repository

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

#### 6. First-Time Deployment Script

Menambahkan script deployment khusus untuk deployment pertama kali.

File:

    scripts/deployfirsttime.sh

Fungsi:

- Menyiapkan environment BREBES-WAF.
- Memastikan konfigurasi ModSecurity tersedia.
- Memastikan OWASP CRS tersedia.
- Menyiapkan `crs-load.conf`.
- Menghasilkan konfigurasi ModSecurity include.
- Melakukan validasi konfigurasi Nginx.
- Melakukan deployment secara aman.

---

#### 7. Detection Log Analysis

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

#### 8. OWASP CRS Integration

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

Deployment script diperbarui untuk melakukan pemeriksaan terhadap:

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

### Security

#### 1. Exposed Git Repository Protection

BREBES-WAF `1.0.0` menambahkan perlindungan terhadap repository Git yang terekspos melalui web server.

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

    Source Code Disclosure
    Credential Disclosure
    Repository Metadata Disclosure
    Commit History Disclosure
    Information Disclosure

---

#### 2. Upload Security

BREBES-WAF `1.0.0` mempertahankan kontrol terhadap file upload untuk mengurangi risiko:

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

Tujuan utama adalah mencegah perubahan konfigurasi WAF yang invalid atau tidak lengkap diterapkan ke server production.

---

### Documentation

#### 1. Changelog

Menambahkan dokumentasi perubahan project melalui:

    changelog/CHANGELOG.md

Changelog digunakan untuk mencatat:

- Rule baru.
- Perubahan rule.
- Security fix.
- Bug fix.
- False positive fix.
- Perubahan deployment.
- Perubahan testing.
- Perubahan dokumentasi.
- Release version.

---

#### 2. Rule ID Convention

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

#### 3. Rule Naming Convention

Nama file rule menggunakan format:

    <RULE_ID>-<description>.conf

Contoh:

    1001003-upload-deny-extension.conf
    6001001-git-directory.conf
    6001002-git-files.conf
    6001003-git-sensitive-path.conf

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

    ## [1.1.0] - 2026-10-01

### Release Date

Tanggal release menggunakan format:

    YYYY-MM-DD

Contoh:

    2026-09-10

---

## Change Categories

Changelog menggunakan kategori:

    Added
    Changed
    Deprecated
    Removed
    Fixed
    Security
    Documentation

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
    │   ├── check-last-detection.sh
    │   ├── deploy.sh
    │   ├── deployfirsttime.sh
    │   └── lastday-detection.sh
    │
    └── tests/
        └── test-brebes-waf-git.ps1

---

## Release Checklist

### Version 1.0.0

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

#### Testing

- [x] Upload extension testing.
- [x] Git protection testing.
- [x] Positive testing.
- [x] Negative testing.
- [x] False positive analysis.

#### Monitoring

- [x] BREBES-WAF detection log analysis.
- [x] OWASP CRS detection log analysis.

#### Documentation

- [x] Changelog.
- [x] Rule ID convention.
- [x] Rule naming convention.
- [x] Deployment principles.
- [x] Testing principles.
- [x] Git workflow.
- [x] Release policy.

---

## Release History

| Version | Release Date | Status | Description |
|---|---|---|---|
| `1.0.0` | `2026-09-10` | Stable | Initial BREBES-WAF release |
| `Unreleased` | - | Development | Changes after version 1.0.0 |

---

## [Unreleased] Checklist

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