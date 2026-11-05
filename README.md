# BREBES-WAF

**Web Application Firewall (WAF) untuk reverse proxy Nginx**

BREBES-WAF adalah ruleset dan perangkat otomasi konfigurasi keamanan untuk membantu melindungi aplikasi web yang ditempatkan di belakang reverse proxy Nginx. BREBES-WAF mengintegrasikan ModSecurity v3, OWASP Core Rule Set (CRS), dan aturan khusus BREBES-WAF, disertai skrip untuk persiapan dependency, deployment, pembuatan virtual host reverse proxy, serta analisis detection log.

## About

BREBES-WAF dirancang sebagai lapisan pertahanan di depan aplikasi web. Request yang melewati Nginx dapat diperiksa oleh ModSecurity dan ruleset yang dikonfigurasi, sementara log Nginx dan ModSecurity dapat digunakan untuk pemantauan, analisis false positive, dan investigasi insiden.

### Ringkasan Fitur

- **Reverse proxy Nginx** — pembuatan virtual host HTTPS dengan konfigurasi proxy bersama.
- **ModSecurity v3** — engine inspeksi request dan response yang terintegrasi dengan Nginx.
- **OWASP Core Rule Set (CRS)** — lapisan aturan keamanan umum untuk aplikasi web.
- **BREBES-WAF Rules** — aturan terkelompok untuk core, upload, webshell, WordPress, malware, generic security, Git, dan kebutuhan lokal.
- **Otomasi deployment** — skrip untuk persiapan dependency, deployment rules/configuration, serta pembuatan reverse proxy.
- **Audit dan analisis detection** — dukungan pencatatan audit ModSecurity dan analisis log berdasarkan domain serta tanggal.
- **False-positive exclusion management** — skrip untuk membuat pengecualian rule secara terarah berdasarkan host, endpoint, metode HTTP, source Rule ID, dan target parameter.
- **Backup dan validasi konfigurasi** — alur deployment mencakup backup serta validasi konfigurasi Nginx sebelum konfigurasi digunakan.
- **Monitoring dan investigasi** — korelasi Nginx access log, error log, ModSecurity audit log, application log, dan system log.

### Arsitektur Singkat

```text
Client
  |
  v
Nginx Reverse Proxy + TLS
  |
  v
ModSecurity v3
  |
  +--> OWASP Core Rule Set (CRS)
  |
  +--> BREBES-WAF Rules
  |
  v
Backend Web Application

Log:
Nginx Access/Error Log + ModSecurity Audit Log
  |
  v
Detection Analysis & Incident Investigation
```

### Komponen Utama

| Komponen | Peran |
|---|---|
| Nginx | Terminasi TLS dan reverse proxy ke backend aplikasi |
| ModSecurity v3 | Engine inspeksi keamanan web |
| OWASP CRS | Aturan keamanan umum |
| BREBES-WAF Rules | Aturan tambahan sesuai kategori perlindungan |
| `install-requirements.sh` | Pemeriksaan dependency dan persiapan/deployment awal |
| `deploy.sh` | Deployment lanjutan konfigurasi dan rules |
| `create-reverse-proxy.sh` | Membuat virtual host reverse proxy |
| `analyze-detection.sh` | Menganalisis ModSecurity audit log berdasarkan domain dan tanggal |
| `add-exclusion.sh` | Membuat pengecualian rule ModSecurity untuk menangani false positive secara spesifik |
| `remove-exclusions.sh` | Menghapus pengecualian berdasarkan Custom Rule ID serta memperbarui registry dengan mekanisme backup |

### Platform dan Repository

- **Baseline deployment:** Ubuntu Server 26.04 LTS.
- **Kompatibilitas yang dicantumkan:** Ubuntu Server 24.04 LTS dan 22.04 LTS, dengan syarat dependency tersedia dan validasi berhasil.
- **Repository:** <https://github.com/NRTechnology/Brebes-WAF>
- **Branch stabil:** `main`.

### Batasan Penggunaan

BREBES-WAF merupakan salah satu lapisan keamanan, bukan pengganti secure coding, patch management, autentikasi dan kontrol akses yang kuat, keamanan jaringan, backup, monitoring, maupun incident response. Efektivitas setiap aturan harus divalidasi pada lingkungan target dan diuji terhadap request legitimate untuk mengurangi false positive. Tidak semua aturan melakukan pemblokiran; beberapa aturan memang hanya mencatat indikator untuk kebutuhan monitoring.

---

## Daftar Isi

- [About](#about)
- [Installation Guide](#installation-guide)
- [Prerequisites](#prerequisites)
- [Nginx Configuration](#7-nginx-configuration)
- [ModSecurity](#8-modsecurity)
- [OWASP Core Rule Set](#9-owasp-core-rule-set)
- [Deployment](#16-deployment-after-first-installation)
- [Detection Log Analysis](#19-detection-log-analysis)
- [Managing False-Positive Exclusions](#managing-false-positive-exclusions)
- [BREBES-WAF Rules](#21-brebes-waf-rules)
- [Testing](#24-testing)
- [Repository Structure](#26-repository-structure)
- [Security Philosophy](#29-security-philosophy)
- [License](#license)

---

## Installation Guide

## Prerequisites

BREBES-WAF menggunakan ****Ubuntu Server 26.04 LTS**** sebagai standar deployment.

Persyaratan:

- Ubuntu Server 26.04 LTS

- Root atau user dengan akses `sudo`

- Internet Connection

- Git

### Supported Ubuntu Version

| Ubuntu Version | Status |

|---|---|

| Ubuntu Server 26.04 LTS | ****Standard**** |

| Ubuntu Server 24.04 LTS | Compatibility |

| Ubuntu Server 22.04 LTS | Compatibility |

Ubuntu Server 26.04 LTS digunakan sebagai baseline utama untuk pengembangan, testing, dan deployment BREBES-WAF.

Versi Ubuntu lainnya dapat digunakan apabila seluruh dependency tersedia dan proses deployment berhasil melalui validation.

---

## 1. Install Ubuntu Server 26.04 LTS

Install ****Ubuntu Server 26.04 LTS**** pada server yang akan digunakan sebagai BREBES-WAF.

Setelah instalasi selesai, login menggunakan user dengan akses `sudo`.

Perbarui sistem:

```bash

sudo apt update

sudo apt upgrade -y

```

---

## 2. Install Git

```bash

sudo apt install -y git

git --version

```

---

## 3. Change to the /opt Directory

```bash

cd /opt

```

---

## 4. Clone the Repository

Clone branch `main` yang merupakan stable branch:

```bash

sudo git clone https://github.com/NRTechnology/Brebes-WAF.git

cd /opt/Brebes-WAF

```

Verifikasi branch:

```bash

git branch

```

Pastikan branch yang digunakan adalah:

```text

main

```

---

## 5. Check and Prepare Dependencies

BREBES-WAF menyediakan script untuk melakukan pemeriksaan dan persiapan dependency.

```bash

sudo chmod +x scripts/install-requirements.sh

sudo ./scripts/install-requirements.sh

```

Script melakukan pemeriksaan terhadap:

- Ubuntu version

- Ubuntu repository

- Nginx

- ModSecurity v3

- Nginx ModSecurity Connector

- Nginx NDK

- OWASP CRS

- Git

- curl

- CA certificates

- ModSecurity configuration

- Nginx configuration

---

## 6. First-Time Deployment

Untuk instalasi pertama BREBES-WAF:

```bash

sudo chmod +x scripts/install-requirements.sh

sudo chmod +x scripts/create-reverse-proxy.sh

sudo ./scripts/install-requirements.sh

```

Script `install-requirements.sh` digunakan untuk persiapan dan deployment awal BREBES-WAF.

Proses mencakup:

- Pemeriksaan environment

- Pemeriksaan dependency

- Pemeriksaan konfigurasi Nginx

- Pemeriksaan ModSecurity

- Pemeriksaan OWASP CRS

- Persiapan `crs-load.conf`

- Pembuatan konfigurasi ModSecurity

- Pembuatan `/etc/nginx/modsecurity_includes.conf`

- Automatic rule discovery

- Pemeriksaan `log_format reverser`

- Pemeriksaan global Nginx access log

- Pemeriksaan `modsecurity on`

- Pemeriksaan `modsecurity_rules_file`

- Validasi jumlah BREBES-WAF rules

- Validasi konfigurasi Nginx

- Backup konfigurasi

- Deployment configuration

- Verification setelah deployment

---

## 7. Nginx Configuration

Konfigurasi utama:

```text

/etc/nginx/nginx.conf

```

Format access log `reverser`:

```nginx

log_format reverser

  '$remote_addr '

  '[$time_local] '

  '"$request" '

  '$status '

  '$body_bytes_sent '

  '"$http_referer" '

  '"$http_user_agent" '

  'host="$host" '

  'xff="$http_x_forwarded_for" '

  'rt=$request_time '

  'urt=$upstream_response_time '

  'upstream="$upstream_addr"';

```

Global access log:

```nginx

access_log /var/log/nginx/access.log reverser;

```

Format ini digunakan untuk security monitoring, detection analysis, incident investigation, dan korelasi dengan ModSecurity Audit Log.

### Reverse Proxy Configuration

BREBES-WAF menyediakan shared proxy configuration dan script untuk membantu membuat konfigurasi reverse proxy Nginx secara konsisten.

**Proxy Common Snippet**

Shared proxy configuration:

```text
/etc/nginx/snippets/proxy-common.conf
```

Snippet digunakan oleh virtual host reverse proxy melalui:

```nginx
location / {
    proxy_pass <PROXY_PASS>;
    include snippets/proxy-common.conf;
}
```

Konfigurasi shared snippet:

```nginx
proxy_http_version 1.1;

proxy_set_header Host $host;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Port $server_port;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Real-IP $remote_addr;

proxy_set_header Accept-Encoding "";
```

Fungsi utama:

- Menstandarkan HTTP version untuk komunikasi proxy.
- Meneruskan hostname asli ke backend.
- Meneruskan protocol asli melalui `X-Forwarded-Proto`.
- Meneruskan port asli melalui `X-Forwarded-Port`.
- Meneruskan alamat client melalui `X-Forwarded-For` dan `X-Real-IP`.
- Meminta backend tidak mengirim response terkompresi melalui `Accept-Encoding`.

`proxy-common.conf` dibuat oleh `install-requirements.sh` setelah Nginx dipastikan tersedia.

**Create Reverse Proxy Script**

Script:

```text
scripts/create-reverse-proxy.sh
```

digunakan untuk membuat virtual host reverse proxy Nginx secara otomatis.

Opsi:

| Opsi | Wajib | Keterangan |
|---|---|---|
| `--domain` | Ya | Domain aplikasi, misalnya `app.example.com`. |
| `--ssl-cert` | Ya | Path file sertifikat SSL/TLS, misalnya `/var/ssl_cert/example.com.crt`. |
| `--ssl-key` | Ya | Path file private key SSL/TLS, misalnya `/var/ssl_cert/example.com.key`. |
| `--proxy-pass` | Ya | URL backend aplikasi, misalnya `http://192.0.2.10:8080`. |
| `-h`, `--help` | Tidak | Menampilkan bantuan penggunaan. |

Usage:

```bash
sudo ./scripts/create-reverse-proxy.sh \
    --domain app.example.com \
    --ssl-cert /var/ssl_cert/example.com.crt \
    --ssl-key /var/ssl_cert/example.com.key \
    --proxy-pass http://192.0.2.10:8080
```

Menampilkan bantuan:

```bash
sudo ./scripts/create-reverse-proxy.sh --help
```

Script menghasilkan:

```text
/etc/nginx/sites-available/<DOMAIN>.conf
/etc/nginx/sites-enabled/<DOMAIN>.conf
/var/log/nginx/<DOMAIN>.access.log
/var/log/nginx/<DOMAIN>.error.log
```

Konfigurasi reverse proxy yang dihasilkan mencakup:

- HTTP → HTTPS redirect.
- TLS 1.2 dan TLS 1.3.
- SSL certificate dan private key.
- Reverse proxy ke backend.
- Shared `proxy-common.conf`.
- Access log dengan format `reverser`.
- Error log per domain.
- `client_body_buffer_size 10M`.
- `client_max_body_size 128M`.

Sebelum membuat konfigurasi, script memeriksa:

- Nginx tersedia.
- SSL certificate tersedia.
- SSL certificate key tersedia.
- `proxy-common.conf` tersedia.

Setelah konfigurasi dibuat, script menjalankan:

```bash
nginx -t
```

Script **tidak melakukan reload Nginx secara otomatis**.

Setelah konfigurasi direview dan `nginx -t` berhasil:

```bash
sudo systemctl reload nginx
```

Verifikasi effective configuration:

```bash
sudo nginx -T > /tmp/nginx-effective.txt 2>&1
grep -nE 'server_name|proxy_pass|access_log|error_log' /tmp/nginx-effective.txt
```

Workflow:

```text
Nginx installed
       |
       v
proxy-common.conf
       |
       v
create-reverse-proxy.sh
       |
       v
Generate virtual host
       |
       v
nginx -t
       |
       v
Review
       |
       v
Reload Nginx
       |
       v
Verify
```

---

## 8. ModSecurity

BREBES-WAF menggunakan ****ModSecurity v3****.

Konfigurasi utama:

```text

/etc/nginx/modsecurity.conf

```

Generated include:

```text

/etc/nginx/modsecurity_includes.conf

```

Konfigurasi Nginx:

```nginx

modsecurity on;

modsecurity_rules_file /etc/nginx/modsecurity_includes.conf;

```

---

## 9. OWASP Core Rule Set

BREBES-WAF menggunakan OWASP Core Rule Set sebagai salah satu security layer.

Konfigurasi CRS:

```text

/etc/nginx/modsecurity/crs-load.conf

```

Struktur rule:

```text

rules/

├── 00-core/

├── 10-upload/

├── 20-webshell/

├── 30-wordpress/

├── 40-malware/

├── 50-generic/

├── 60-git/

└── 90-local/

```

Deployment script secara otomatis mencari file `*.conf` pada:

```text

/opt/Brebes-WAF/rules/

```

---

## 10. ModSecurity Response Body Inspection

BREBES-WAF mengaktifkan response body inspection:

```apache

SecResponseBodyAccess On

```

MIME type yang diperiksa:

```text

text/plain

text/html

text/xml

application/json

```

Batas response body:

```apache

SecResponseBodyLimit 1048576

SecResponseBodyLimitAction ProcessPartial

```

Konfigurasi ini membantu pemeriksaan security event pada response aplikasi dengan tetap mempertimbangkan penggunaan resource.

---

## ModSecurity Baseline

Konfigurasi dasar installer menggunakan nilai berikut:

| Directive | Nilai |
|---|---|
| `SecRuleEngine` | `On` |
| `SecRequestBodyAccess` | `On` |
| `SecRequestBodyLimit` | `134217728` (128 MiB) |
| `SecRequestBodyNoFilesLimit` | `131072` |
| `SecRequestBodyLimitAction` | `Reject` |
| `SecArgumentsLimit` | `1000` |
| `SecRequestBodyJsonDepthLimit` | `512` |
| `SecPcreMatchLimit` | `100000` |
| `SecPcreMatchLimitRecursion` | `100000` |
| `SecResponseBodyAccess` | `On` |
| `SecResponseBodyLimit` | `1048576` (1 MiB) |
| `SecResponseBodyLimitAction` | `ProcessPartial` |

Installer juga memasang rule dasar `200007` untuk menolak request dengan jumlah argumen berlebih (status 400). Jangan menaikkan batas argumen hanya agar request pengujian tertentu dapat melewati parser; evaluasi kebutuhan aplikasi dan dampak keamanan terlebih dahulu.

---

## 11. ModSecurity Audit Logging

```apache

SecAuditEngine RelevantOnly

SecAuditLogRelevantStatus "^(?:5|4(?!04))"

SecAuditLogParts ABCDEFHIJZ

SecAuditLogType Concurrent

SecAuditLogStorageDir /var/log/nginx/modsecurity/

```

Audit log digunakan untuk detection analysis, incident investigation, false positive analysis, rule tuning, security monitoring, dan incident response.

---

## 12. Create the ModSecurity Audit Log Directory

```bash

sudo mkdir -p /var/log/nginx/modsecurity

sudo chown www-data:adm /var/log/nginx/modsecurity

sudo chmod 750 /var/log/nginx/modsecurity

```

First-time deployment script dapat melakukan persiapan directory sesuai konfigurasi deployment.

---

## 13. Verify the Installation

```bash

sudo nginx -t

sudo systemctl status nginx

```

Expected result:

```text

syntax is ok

test is successful

```

---

## 14. Verify Effective Nginx Configuration

```bash

sudo nginx -T > /tmp/nginx-effective.txt 2>&1

```

Periksa konfigurasi utama:

```bash

grep -nE 'log_format reverser|access_log /var/log/nginx/access.log reverser|modsecurity on|modsecurity_rules_file' /tmp/nginx-effective.txt

```

Konfigurasi penting:

```nginx

log_format reverser

access_log /var/log/nginx/access.log reverser;

modsecurity on;

modsecurity_rules_file /etc/nginx/modsecurity_includes.conf;

```

---

## 15. Verify ModSecurity Include

```bash

sudo cat /etc/nginx/modsecurity_includes.conf

```

File harus memuat:

```text

/etc/nginx/modsecurity.conf

/etc/nginx/modsecurity/crs-load.conf

```

serta BREBES-WAF rules dari:

```text

/opt/Brebes-WAF/rules/

```

Contoh:

```text

Include /opt/Brebes-WAF/rules/10-upload/1001001-upload-allowed-extension.conf

Include /opt/Brebes-WAF/rules/20-webshell/alfa/2002000-fingerprint.conf

Include /opt/Brebes-WAF/rules/60-git/6001001-git-directory.conf

```

---

## 16. Deployment After First Installation

Setelah first-time deployment berhasil, deployment berikutnya menggunakan:

```bash

sudo ./scripts/deploy.sh

```

Jika diperlukan:

```bash

sudo chmod +x scripts/deploy.sh

```

### Deployment Workflow

First-time deployment:

```text

Check Dependencies

        |

        v

First-Time Deployment

        |

        v

Generate Configuration

        |

        v

Validate

        |

        v

nginx -t

        |

        v

Reload Nginx

        |

        v

Verify

        |

        v

BREBES-WAF Active

```

Deployment berikutnya:

```text

Update Repository

        |

        v

deploy.sh

        |

        v

Backup

        |

        v

Generate

        |

        v

Validate

        |

        v

nginx -t

        |

        v

Reload

        |

        v

Verify

```

---

## 17. Check Recent Detected Activities

Audit log:

```text

/var/log/nginx/modsecurity/

```

File audit log terbaru:

```bash

find /var/log/nginx/modsecurity -type f | sort | tail -1

```

Display:

```bash

cat "$(find /var/log/nginx/modsecurity -type f | sort | tail -1)"

```

Jika diperlukan:

```bash

strings "$(find /var/log/nginx/modsecurity -type f | sort | tail -1)"

```

---

## 18. Search BREBES-WAF Detection

```bash

grep -R "BREBES-WAF" /var/log/nginx/modsecurity

```

Detection terbaru:

```bash

find /var/log/nginx/modsecurity -type f -exec strings {} \\; | grep "BREBES-WAF" | tail -1

```

---

**## 19. Detection Log Analysis

Gunakan `scripts/analyze-detection.sh` untuk menganalisis ModSecurity audit log berdasarkan domain dan tanggal.

```bash
sudo chmod +x scripts/analyze-detection.sh

# Analisis tanggal hari ini
sudo ./scripts/analyze-detection.sh app.example.com

# Analisis tanggal tertentu (YYYYMMDD)
sudo ./scripts/analyze-detection.sh app.example.com 20261023
```

Audit log dibaca dari:

```text
/var/log/nginx/modsecurity/<YYYYMMDD>/
```

Domain dicocokkan berdasarkan header `Host` pada section B. Pesan deteksi dibaca dari section H. Nilai `[hostname "..."]` pada section H tidak digunakan untuk menentukan domain karena dapat berisi alamat server/backend.

Ringkasan menampilkan jumlah audit log yang diproses, log yang cocok dengan domain, log deteksi, serta jumlah baris deteksi BREBES-WAF dan OWASP CRS.

Catatan: rule dasar ModSecurity seperti `200007` tidak otomatis dihitung sebagai deteksi BREBES-WAF atau OWASP CRS. Untuk investigasi, cocokkan hasil analyzer dengan Nginx access/error log dan audit log mentah.


### Managing False-Positive Exclusions

BREBES-WAF menyediakan dua script untuk mengelola pengecualian false positive:

- `scripts/add-exclusion.sh` — membuat custom exclusion berdasarkan host, endpoint, metode HTTP, source Rule ID, dan target parameter.
- `scripts/remove-exclusions.sh` — menghapus custom exclusion berdasarkan Custom Rule ID, termasuk memperbarui registry.

Pengecualian harus dibuat secara spesifik agar cakupan pengurangan inspeksi tetap terbatas.

#### A. Membuat exclusion dengan `add-exclusion.sh`

Script mendukung parameter berikut:

| Opsi | Wajib | Keterangan |
|---|---|---|
| `--url` | Ya | URL aplikasi yang mengalami false positive. Host dan URI path diambil dari URL. Query string dan fragment tidak digunakan sebagai bagian pencocokan endpoint. |
| `--method` | Ya | Satu atau beberapa metode HTTP, dipisahkan koma. Contoh: `POST` atau `GET,POST`. |
| `--rule-id` | Ya | Source Rule ID yang menghasilkan deteksi, misalnya Rule ID OWASP CRS. |
| `--target` | Tidak | Satu atau beberapa target parameter, dipisahkan koma. Contoh: `ARGS:field1,ARGS:field2`. Jika tidak diberikan, seluruh source Rule ID dikecualikan dalam scope host, metode, dan endpoint yang ditentukan. |
| `--name` | Tidak | Nama aplikasi untuk keterangan exclusion. |
| `--description` | Tidak | Penjelasan alasan pembuatan exclusion. |
| `--dry-run` | Tidak | Menampilkan ringkasan dan konfigurasi yang akan dibuat tanpa mengubah file maupun registry. |
| `--force` | Tidak | Menjalankan pembuatan tanpa meminta konfirmasi interaktif. Gunakan dengan hati-hati. |
| `-h`, `--help` | Tidak | Menampilkan bantuan penggunaan. |

**Catatan mengenai cakupan exclusion:**

- `--method` menerima daftar metode HTTP yang dipisahkan koma. Metode dinormalisasi ke huruf kapital.
- `--target` menerima daftar target yang dipisahkan koma.
- Jika `--target` dihilangkan, script membuat pengecualian seluruh source Rule ID pada kombinasi host, metode, dan URI path tersebut. Ini memiliki dampak lebih luas daripada pengecualian target tertentu.
- Jika `--target` diberikan, hanya target yang disebutkan yang dikecualikan dari source Rule ID tersebut.
- Query string pada URL tidak menjadi bagian pencocokan endpoint. Exclusion berlaku pada URI path yang sama, termasuk request dengan query string berbeda.
- Rule yang dihasilkan menyertakan pesan dan tag `BREBES-WAF/EXCLUSION` untuk membantu identifikasi event exclusion pada logging ModSecurity. Ketersediaan event pada log tetap bergantung pada konfigurasi audit/error logging yang aktif.

#### Workflow pembuatan exclusion

**1. Analisis detection terlebih dahulu**

Identifikasi domain, endpoint, metode HTTP, source Rule ID, dan target parameter dari ModSecurity audit log. Jangan menggunakan final blocking rule sebagai source Rule ID apabila audit log menunjukkan rule deteksi yang lebih spesifik.

**2. Jalankan simulasi**

Contoh berikut menggunakan domain dokumentasi:

```bash
sudo ./scripts/add-exclusion.sh \
    --url 'https://app.example.com/user/process?id=123' \
    --method POST \
    --rule-id 933210 \
    --target 'ARGS:document_type' \
    --description 'False positive pada parameter document_type' \
    --dry-run
```

Contoh beberapa metode HTTP dan beberapa target:

```bash
sudo ./scripts/add-exclusion.sh \
    --url 'https://app.example.com/user/process' \
    --method GET,POST \
    --rule-id 933210 \
    --target 'ARGS:field1,ARGS:field2' \
    --description 'False positive pada parameter aplikasi' \
    --dry-run
```

Contoh pengecualian seluruh source Rule ID pada scope endpoint (tanpa `--target`):

```bash
sudo ./scripts/add-exclusion.sh \
    --url 'https://app.example.com/user/process' \
    --method POST \
    --rule-id 933210 \
    --description 'False positive terkonfirmasi pada endpoint' \
    --dry-run
```

Penggunaan tanpa `--target` harus dipertimbangkan lebih hati-hati karena seluruh target pada source Rule ID tersebut tidak lagi diperiksa dalam scope yang cocok.

**3. Buat exclusion**

Jika hasil simulasi sudah benar, jalankan kembali perintah tanpa `--dry-run`:

```bash
sudo ./scripts/add-exclusion.sh \
    --url 'https://app.example.com/user/process?id=123' \
    --method POST \
    --rule-id 933210 \
    --target 'ARGS:document_type' \
    --description 'False positive pada parameter document_type'
```

Script menampilkan konfigurasi yang akan dibuat dan meminta konfirmasi. Setelah disetujui, script membuat file exclusion di `rules/99-custom-exclusions/` dan mendaftarkan Custom Rule ID pada `RULE-ID.txt`.

Untuk penggunaan non-interaktif, opsi `--force` dapat digunakan setelah seluruh parameter dan hasil simulasi dipastikan benar.

**4. Periksa file dan registry**

```bash
ls -lah rules/99-custom-exclusions/
cat rules/99-custom-exclusions/RULE-ID.txt
```

Pastikan file exclusion dan Custom Rule ID tercatat dengan benar.

**5. Deploy dan validasi**

```bash
sudo ./scripts/deploy.sh
```

Deployment membangun ulang file `/etc/nginx/modsecurity_includes.conf`, memvalidasi konfigurasi dengan `nginx -t`, lalu melakukan reload Nginx apabila validasi berhasil. Periksa hasil deployment sebelum melanjutkan pengujian aplikasi.

**6. Verifikasi hasil pada aplikasi**

Lakukan pengujian request legitimate yang sebelumnya terkena false positive. Periksa kembali ModSecurity audit log dan Nginx access/error log untuk memastikan request berhasil serta tidak ada dampak yang tidak diinginkan.

#### B. Menghapus exclusion dengan `remove-exclusions.sh`

Gunakan `scripts/remove-exclusions.sh` untuk menghapus satu exclusion berdasarkan Custom Rule ID. Script menghapus file `.conf` yang cocok dan menghapus ID terkait dari `RULE-ID.txt`.

Opsi yang tersedia:

| Opsi | Wajib | Keterangan |
|---|---|---|
| `--rule-id` | Ya | Custom Rule ID yang akan dihapus, misalnya `9900001`. |
| `--dry-run` | Tidak | Menampilkan file dan registry yang akan diubah tanpa melakukan penghapusan. |
| `--force` | Tidak | Menjalankan penghapusan tanpa meminta konfirmasi interaktif. Gunakan dengan hati-hati. |
| `-h`, `--help` | Tidak | Menampilkan bantuan penggunaan. |

**1. Simulasikan penghapusan**

```bash
sudo ./scripts/remove-exclusions.sh --rule-id 9900001 --dry-run
```

Periksa Custom Rule ID dan file yang akan dihapus. Pastikan ID tersebut memang exclusion yang ingin dinonaktifkan.

**2. Hapus exclusion**

```bash
sudo ./scripts/remove-exclusions.sh --rule-id 9900001
```

Script meminta konfirmasi sebelum menghapus. Setelah disetujui, script:

- Memastikan Custom Rule ID tercatat pada `RULE-ID.txt`.
- Memastikan file exclusion yang sesuai ditemukan secara unik.
- Membuat backup file exclusion dan registry.
- Menghapus file exclusion.
- Memperbarui registry secara atomik.
- Melakukan verifikasi hasil dan menyediakan mekanisme rollback jika pembaruan gagal.

Backup penghapusan disimpan di:

```text
/opt/Brebes-WAF/backup/remove-exclusions/<timestamp>-<rule-id>/
```

**3. Periksa hasil penghapusan**

```bash
grep -n '9900001' rules/99-custom-exclusions/RULE-ID.txt
find rules/99-custom-exclusions/ -maxdepth 1 -type f -name '9900001-*.conf' -print
```

Kedua perintah seharusnya tidak menghasilkan output untuk ID yang sudah dihapus.

**4. Deploy ulang konfigurasi**

Penghapusan file dan registry di repository belum otomatis mengubah konfigurasi ModSecurity yang sedang digunakan Nginx. Jalankan:

```bash
sudo ./scripts/deploy.sh
```

Pastikan `nginx -t` berhasil dan deployment melakukan reload. Kemudian verifikasi:

```bash
grep -n '9900001' /etc/nginx/modsecurity_includes.conf
```

Pastikan Custom Rule ID yang dihapus tidak lagi tercantum dalam konfigurasi include.

#### Lokasi dan pengelolaan file

```text
rules/
└── 99-custom-exclusions/
    ├── README.md
    ├── RULE-ID.txt
    └── <custom-rule-id>-<application>-<endpoint>.conf
```

- `RULE-ID.txt` berisi daftar Custom Rule ID yang digunakan oleh exclusion; file ini bukan daftar seluruh Rule ID OWASP CRS atau BREBES-WAF.
- Setiap file exclusion memiliki satu Custom Rule ID dan satu source Rule ID. Scope-nya dapat mencakup satu atau beberapa metode HTTP dan, jika ditentukan, satu atau beberapa target.
- Custom Rule ID dipilih oleh script berdasarkan registry dan pemeriksaan benturan ID yang dilakukannya.
- Deployment memasukkan file `.conf` di direktori `rules/99-custom-exclusions/` ke konfigurasi ModSecurity.
- `add-exclusion.sh` dan `remove-exclusions.sh` mengelola file exclusion serta registry. Perubahan baru diterapkan ke konfigurasi aktif setelah `deploy.sh` berhasil.
- Backup penghapusan disimpan di direktori `backup/remove-exclusions/`.
- Simpan dan kelola file exclusion sesuai kebijakan repository dan `.gitignore` yang digunakan pada instalasi. Jangan menghapus file exclusion lokal saat memperbarui repository tanpa meninjau dampaknya.

#### Prinsip keamanan

- Buat exclusion hanya setelah false positive dikonfirmasi melalui audit log dan konteks request aplikasi.
- Pilih source Rule ID yang benar-benar menghasilkan deteksi, bukan sekadar rule evaluasi akhir seperti `949110`.
- Utamakan pengecualian target tertentu. Penggunaan `--target` yang dihilangkan menonaktifkan pemeriksaan seluruh source Rule ID pada scope host, metode, dan endpoint yang cocok.
- Batasi exclusion pada host, metode, dan endpoint yang diperlukan.
- Exclusion terhadap suatu target berarti target tersebut tidak diperiksa oleh source Rule ID yang ditentukan pada scope tersebut; rule lain tetap dapat memeriksa request.
- `--dry-run` hanya menampilkan rencana perubahan. Validasi sintaks ModSecurity dilakukan pada tahap deployment melalui `nginx -t`.
- Setelah deployment, verifikasi dengan request aktual. Keberhasilan `nginx -t` saja belum membuktikan bahwa exclusion bekerja sesuai harapan.
- Saat menghapus exclusion, jalankan `deploy.sh` agar konfigurasi aktif ikut diperbarui.
- Catat alasan, bukti audit log, waktu perubahan, dan hasil verifikasi untuk kebutuhan audit serta pemeliharaan.

Untuk melihat seluruh opsi:

```bash
sudo ./scripts/add-exclusion.sh --help
sudo ./scripts/remove-exclusions.sh --help
```

---

## 20. Backup and Rollback

Generated configuration:

```text

/etc/nginx/modsecurity_includes.conf

```

Backup:

```text

/etc/nginx/modsecurity_includes.conf.bak

```

Workflow:

```text

Backup

   |

   v

Generate

   |

   v

Validate

   |

   v

nginx -t

   |

   v

Reload

   |

   v

Verify

```

Apabila validasi atau reload gagal, konfigurasi sebelumnya dapat dipulihkan menggunakan mekanisme rollback pada deployment script.

---

## 21. BREBES-WAF Rules

| Range | Category | Description |

|---|---|---|

| `1000000-1000999` | Core | Core BREBES-WAF rules |

| `1001000-1001999` | Upload | Upload protection |

| `2001000-2001999` | Webshell | Webshell detection/protection |

| `3001000-3001999` | WordPress | WordPress protection |

| `4001000-4001999` | Malware | Malware detection |

| `5001000-5001999` | Generic | Generic security rules |

| `6001000-6001999` | Git | Git repository protection |

| `9001000-9001999` | Local | Local/deployment-specific rules |

---

**### Generic Rules saat ini

| Rule ID | File | Fungsi | Tindakan |
|---|---|---|---|
| `5001001` | `rules/50-generic/5001001-block-content-encoding-gzip.conf` | Mencatat respons dengan header `Content-Encoding: gzip`. | `pass` + logging; tidak memblokir respons. |
| `5001002` | `rules/50-generic/5001002-php2shell-upload-progress.conf` | Mendeteksi argumen `PHP_SESSION_UPLOAD_PROGRESS` sebagai indikator permintaan mencurigakan. | `pass` + audit logging; deteksi saja, bukan pemblokiran. |

Rule `5001002` bukan pengganti patch keamanan PHP. Request juga dapat ditolak lebih awal oleh batas parser ModSecurity atau OWASP CRS sebelum rule ini menghasilkan log. Karena itu, tidak adanya log `5001002` tidak dengan sendirinya membuktikan bahwa request lolos dari seluruh perlindungan.

---

## 22. Git Repository Protection

Perlindungan mencakup:

```text

/.git/

/.git/config

/.git/HEAD

/.git/index

/.git/logs/

/.git/objects/

/.git/refs/

```

Rule Git:

```text

rules/60-git/

```

---

## 23. Upload Protection

BREBES-WAF menyediakan upload protection untuk mengurangi risiko:

- Malicious file upload

- Executable file upload

- Webshell upload

- Server-side script upload

- Penyalahgunaan upload directory

Allowed extensions dikontrol melalui BREBES-WAF upload rules.

---

## 24. Testing

Setiap perubahan rule harus melalui:

```text

Rule Development

        |

        v

Syntax Validation

        |

        v

Positive Test

        |

        v

Negative Test

        |

        v

False Positive Analysis

        |

        v

Deployment

        |

        v

Production Verification

```

### Positive Test

Request berbahaya yang seharusnya diblokir:

```text

HTTP 403

```

### Negative Test

Request legitimate harus tetap dapat diproses:

```text

HTTP 200

```

atau response normal aplikasi.

### False Positive Analysis

Setiap rule baru harus diuji terhadap request legitimate untuk memastikan rule tidak terlalu agresif.

---

## 25. Operational Logging

Analisis keamanan sebaiknya dilakukan dengan mengkorelasikan:

```text

Nginx Access Log

        +

Nginx Error Log

        +

ModSecurity Audit Log

        +

Application Log

        +

System Log

```

Timestamp filesystem tidak boleh digunakan sebagai satu-satunya dasar untuk menentukan waktu suatu aktivitas dalam investigasi insiden.

Metadata filesystem dapat berubah atau dimanipulasi.

---

## 26. Repository Structure

```text

BREBES-WAF/

|

├── changelog/

│   └── CHANGELOG.md

|

├── docs/

|

├── nginx/

│   ├── nginx.conf

│   └── modsecurity/

│       └── crs-load.conf

|

├── rules/

│   ├── 00-core/

│   ├── 10-upload/

│   ├── 20-webshell/

│   ├── 30-wordpress/

│   ├── 40-malware/

│   ├── 50-generic/

│   ├── 60-git/

│   └── 90-local/

|

├── samples/

|

├── scripts/
│   ├── add-exclusion.sh
│   ├── remove-exclusions.sh
│   ├── analyze-detection.sh
│   ├── create-reverse-proxy.sh
│   ├── deploy.sh
│   └── install-requirements.sh

└── tests/

```

---

**## 27. Recommended Deployment

Untuk instalasi baru:

```bash
cd /opt
sudo git clone https://github.com/NRTechnology/Brebes-WAF.git
cd /opt/Brebes-WAF

sudo chmod +x scripts/install-requirements.sh
sudo ./scripts/install-requirements.sh
```

Installer memerlukan hak root/sudo dan membuat backup konfigurasi existing sebelum modifikasi. Setelah selesai, verifikasi:

```bash
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo nginx -T > /tmp/nginx-effective.txt 2>&1
```

Buat virtual host reverse proxy setelah sertifikat TLS dan alamat origin siap:

```bash
sudo chmod +x scripts/create-reverse-proxy.sh
sudo ./scripts/create-reverse-proxy.sh \\
    app.example.com \\
    /var/ssl_cert/example.com.crt \\
    /var/ssl_cert/example.com.key \\
    http://192.0.2.10:8080
```

Script pembuatan virtual host menjalankan `nginx -t`, tetapi tidak melakukan reload otomatis. Review konfigurasi, lalu jalankan `sudo systemctl reload nginx` setelah validasi berhasil.

---

## 28. Subsequent Deployment

Setelah BREBES-WAF terpasang:

```bash

cd /opt/Brebes-WAF

git pull --ff-only origin main

sudo ./scripts/deploy.sh

```

---

## 29. Security Philosophy

BREBES-WAF dikembangkan berdasarkan prinsip:

- Defense in Depth

- Least Privilege

- Secure by Default

- Fail Safely

- Explicit Allow

- Minimal Exposure

- Continuous Monitoring

- Continuous Improvement

BREBES-WAF merupakan salah satu lapisan keamanan dan tidak menggantikan:

- Secure coding

- Patch management

- Authentication security

- Access control

- Network security

- Endpoint security

- Backup

- Monitoring

- Incident response

---

## License

Informasi lisensi BREBES-WAF mengikuti ketentuan lisensi yang ditetapkan pada repository project.

---

****BREBES-WAF****

****Brebes CSIRT****

Web Application Firewall Security Ruleset

Nginx  

\+  

ModSecurity v3  

\+  

OWASP CRS  

\+  

BREBES-WAF Rules
