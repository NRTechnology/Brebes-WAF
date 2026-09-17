**# BREBES-WAF**

Web Application Firewall Security Ruleset untuk melindungi aplikasi web menggunakan:

\- Nginx

\- ModSecurity v3

\- OWASP Core Rule Set (CRS)

\- BREBES-WAF Rules

**---**

**## Installation Guide**

**## Prerequisites**

BREBES-WAF menggunakan **\*\*Ubuntu Server 26.04 LTS\*\*** sebagai standar deployment.

Persyaratan:

\- Ubuntu Server 26.04 LTS

\- Root atau user dengan akses \`sudo\`

\- Internet Connection

\- Git

**### Supported Ubuntu Version**

\| Ubuntu Version | Status |

\|---|---|

\| Ubuntu Server 26.04 LTS | **\*\*Standard\*\*** |

\| Ubuntu Server 24.04 LTS | Compatibility |

\| Ubuntu Server 22.04 LTS | Compatibility |

Ubuntu Server 26.04 LTS digunakan sebagai baseline utama untuk pengembangan, testing, dan deployment BREBES-WAF.

Versi Ubuntu lainnya dapat digunakan apabila seluruh dependency tersedia dan proses deployment berhasil melalui validation.

**---**

**## 1. Install Ubuntu Server 26.04 LTS**

Install **\*\*Ubuntu Server 26.04 LTS\*\*** pada server yang akan digunakan sebagai BREBES-WAF.

Setelah instalasi selesai, login menggunakan user dengan akses \`sudo\`.

Perbarui sistem:

\`\`\`bash

sudo apt update

sudo apt upgrade -y

\`\`\`

**---**

**## 2. Install Git**

\`\`\`bash

sudo apt install -y git

git --version

\`\`\`

**---**

**## 3. Change to the /opt Directory**

\`\`\`bash

cd /opt

\`\`\`

**---**

**## 4. Clone the Repository**

Clone branch \`main\` yang merupakan stable branch:

\`\`\`bash

sudo git clone https\://github.com/NRTechnology/Brebes-WAF.git

cd /opt/Brebes-WAF

\`\`\`

Verifikasi branch:

\`\`\`bash

git branch

\`\`\`

Pastikan branch yang digunakan adalah:

\`\`\`text

main

\`\`\`

**---**

**## 5. Check and Prepare Dependencies**

BREBES-WAF menyediakan script untuk melakukan pemeriksaan dan persiapan dependency.

\`\`\`bash

sudo chmod +x scripts/check-dependencies.sh

sudo ./scripts/check-dependencies.sh

\`\`\`

Script melakukan pemeriksaan terhadap:

\- Ubuntu version

\- Ubuntu repository

\- Nginx

\- ModSecurity v3

\- Nginx ModSecurity Connector

\- Nginx NDK

\- OWASP CRS

\- Git

\- curl

\- CA certificates

\- ModSecurity configuration

\- Nginx configuration

**---**

**## 6. First-Time Deployment**

Untuk instalasi pertama BREBES-WAF:

\`\`\`bash

sudo chmod +x scripts/deploy-first-time.sh

sudo chmod +x scripts/create-reverse-proxy.sh

sudo ./scripts/deploy-first-time.sh

\`\`\`

Script \`deploy-first-time.sh\` digunakan untuk persiapan dan deployment awal BREBES-WAF.

Proses mencakup:

\- Pemeriksaan environment

\- Pemeriksaan dependency

\- Pemeriksaan konfigurasi Nginx

\- Pemeriksaan ModSecurity

\- Pemeriksaan OWASP CRS

\- Persiapan \`crs-load.conf\`

\- Pembuatan konfigurasi ModSecurity

\- Pembuatan \`/etc/nginx/modsecurity\_includes.conf\`

\- Automatic rule discovery

\- Pemeriksaan \`log\_format reverser\`

\- Pemeriksaan global Nginx access log

\- Pemeriksaan \`modsecurity on\`

\- Pemeriksaan \`modsecurity\_rules\_file\`

\- Validasi jumlah BREBES-WAF rules

\- Validasi konfigurasi Nginx

\- Backup konfigurasi

\- Deployment configuration

\- Verification setelah deployment

**---**

**## 7. Nginx Configuration**

Konfigurasi utama:

\`\`\`text

/etc/nginx/nginx.conf

\`\`\`

Format access log \`reverser\`:

\`\`\`nginx

log\_format reverser

  '$remote\_addr '

  '[$time\_local] '

  '"$request" '

  '$status '

  '$body\_bytes\_sent '

  '"$http\_referer" '

  '"$http\_user\_agent" '

  'host="$host" '

  'xff="$http\_x\_forwarded\_for" '

  'rt=$request\_time '

  'urt=$upstream\_response\_time '

  'upstream="$upstream\_addr"';

\`\`\`

Global access log:

\`\`\`nginx

access\_log /var/log/nginx/access.log reverser;

\`\`\`

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

`proxy-common.conf` dibuat oleh `deploy-first-time.sh` setelah Nginx dipastikan tersedia.

**Create Reverse Proxy Script**

Script:

```text
scripts/create-reverse-proxy.sh
```

digunakan untuk membuat virtual host reverse proxy Nginx secara otomatis.

Parameter:

```text
<DOMAIN>
<SSL_CERTIFICATE_PATH>
<SSL_CERTIFICATE_KEY_PATH>
<PROXY_PASS>
```

Usage:

```bash
sudo ./scripts/create-reverse-proxy.sh \
    <DOMAIN> \
    <SSL_CERTIFICATE_PATH> \
    <SSL_CERTIFICATE_KEY_PATH> \
    <PROXY_PASS>
```

Contoh generic:

```bash
sudo ./scripts/create-reverse-proxy.sh \
    app.example.com \
    /var/ssl_cert/example.com.crt \
    /var/ssl_cert/example.com.key \
    http://192.0.2.10:8080
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

**---**

**## 8. ModSecurity**

BREBES-WAF menggunakan **\*\*ModSecurity v3\*\***.

Konfigurasi utama:

\`\`\`text

/etc/nginx/modsecurity.conf

\`\`\`

Generated include:

\`\`\`text

/etc/nginx/modsecurity\_includes.conf

\`\`\`

Konfigurasi Nginx:

\`\`\`nginx

modsecurity on;

modsecurity\_rules\_file /etc/nginx/modsecurity\_includes.conf;

\`\`\`

**---**

**## 9. OWASP Core Rule Set**

BREBES-WAF menggunakan OWASP Core Rule Set sebagai salah satu security layer.

Konfigurasi CRS:

\`\`\`text

/etc/nginx/modsecurity/crs-load.conf

\`\`\`

Struktur rule:

\`\`\`text

rules/

├── 00-core/

├── 10-upload/

├── 20-webshell/

├── 30-wordpress/

├── 40-malware/

├── 50-generic/

├── 60-git/

└── 90-local/

\`\`\`

Deployment script secara otomatis mencari file \`\*.conf\` pada:

\`\`\`text

/opt/Brebes-WAF/rules/

\`\`\`

**---**

**## 10. ModSecurity Response Body Inspection**

BREBES-WAF mengaktifkan response body inspection:

\`\`\`apache

SecResponseBodyAccess On

\`\`\`

MIME type yang diperiksa:

\`\`\`text

text/plain

text/html

text/xml

application/json

\`\`\`

Batas response body:

\`\`\`apache

SecResponseBodyLimit 1048576

SecResponseBodyLimitAction ProcessPartial

\`\`\`

Konfigurasi ini membantu pemeriksaan security event pada response aplikasi dengan tetap mempertimbangkan penggunaan resource.

**---**

**## 11. ModSecurity Audit Logging**

\`\`\`apache

SecAuditEngine RelevantOnly

SecAuditLogRelevantStatus "^(?:5|4(?!04))"

SecAuditLogParts ABCDEFHIJZ

SecAuditLogType Concurrent

SecAuditLogStorageDir /var/log/nginx/modsecurity/

\`\`\`

Audit log digunakan untuk detection analysis, incident investigation, false positive analysis, rule tuning, security monitoring, dan incident response.

**---**

**## 12. Create the ModSecurity Audit Log Directory**

\`\`\`bash

sudo mkdir -p /var/log/nginx/modsecurity

sudo chown www-data\:adm /var/log/nginx/modsecurity

sudo chmod 750 /var/log/nginx/modsecurity

\`\`\`

First-time deployment script dapat melakukan persiapan directory sesuai konfigurasi deployment.

**---**

**## 13. Verify the Installation**

\`\`\`bash

sudo nginx -t

sudo systemctl status nginx

\`\`\`

Expected result:

\`\`\`text

syntax is ok

test is successful

\`\`\`

**---**

**## 14. Verify Effective Nginx Configuration**

\`\`\`bash

sudo nginx -T > /tmp/nginx-effective.txt 2>&1

\`\`\`

Periksa konfigurasi utama:

\`\`\`bash

grep -nE 'log\_format reverser|access\_log /var/log/nginx/access.log reverser|modsecurity on|modsecurity\_rules\_file' /tmp/nginx-effective.txt

\`\`\`

Konfigurasi penting:

\`\`\`nginx

log\_format reverser

access\_log /var/log/nginx/access.log reverser;

modsecurity on;

modsecurity\_rules\_file /etc/nginx/modsecurity\_includes.conf;

\`\`\`

**---**

**## 15. Verify ModSecurity Include**

\`\`\`bash

sudo cat /etc/nginx/modsecurity\_includes.conf

\`\`\`

File harus memuat:

\`\`\`text

/etc/nginx/modsecurity.conf

/etc/nginx/modsecurity/crs-load.conf

\`\`\`

serta BREBES-WAF rules dari:

\`\`\`text

/opt/Brebes-WAF/rules/

\`\`\`

Contoh:

\`\`\`text

Include /opt/Brebes-WAF/rules/10-upload/1001001-upload-allowed-extension.conf

Include /opt/Brebes-WAF/rules/20-webshell/alfa/2002000-fingerprint.conf

Include /opt/Brebes-WAF/rules/60-git/6001001-git-directory.conf

\`\`\`

**---**

**## 16. Deployment After First Installation**

Setelah first-time deployment berhasil, deployment berikutnya menggunakan:

\`\`\`bash

sudo ./scripts/deploy.sh

\`\`\`

Jika diperlukan:

\`\`\`bash

sudo chmod +x scripts/deploy.sh

\`\`\`

**### Deployment Workflow**

First-time deployment:

\`\`\`text

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

\`\`\`

Deployment berikutnya:

\`\`\`text

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

\`\`\`

**---**

**## 17. Check Recent Detected Activities**

Audit log:

\`\`\`text

/var/log/nginx/modsecurity/

\`\`\`

File audit log terbaru:

\`\`\`bash

find /var/log/nginx/modsecurity -type f | sort | tail -1

\`\`\`

Display:

\`\`\`bash

cat "$(find /var/log/nginx/modsecurity -type f | sort | tail -1)"

\`\`\`

Jika diperlukan:

\`\`\`bash

strings "$(find /var/log/nginx/modsecurity -type f | sort | tail -1)"

\`\`\`

**---**

**## 18. Search BREBES-WAF Detection**

\`\`\`bash

grep -R "BREBES-WAF" /var/log/nginx/modsecurity

\`\`\`

Detection terbaru:

\`\`\`bash

find /var/log/nginx/modsecurity -type f -exec strings {} \\; | grep "BREBES-WAF" | tail -1

\`\`\`

**---**

**## 19. Detection Log Analysis**

**### Check Last Detection**

\`\`\`bash

sudo chmod +x scripts/check-last-detection.sh

sudo ./scripts/check-last-detection.sh

\`\`\`

Script digunakan untuk membantu menampilkan detection BREBES-WAF dan OWASP CRS berdasarkan domain yang diperiksa.

**### Today Detection**

\`\`\`bash

sudo chmod +x scripts/today-detection.sh

sudo ./scripts/today-detection.sh

\`\`\`

Hasil detection dipisahkan menjadi:

\`\`\`text

\===== BREBES-WAF =====

\`\`\`

dan:

\`\`\`text

\===== OWASP CRS =====

\`\`\`

**---**

**## 20. Backup and Rollback**

Generated configuration:

\`\`\`text

/etc/nginx/modsecurity\_includes.conf

\`\`\`

Backup:

\`\`\`text

/etc/nginx/modsecurity\_includes.conf.bak

\`\`\`

Workflow:

\`\`\`text

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

\`\`\`

Apabila validasi atau reload gagal, konfigurasi sebelumnya dapat dipulihkan menggunakan mekanisme rollback pada deployment script.

**---**

**## 21. BREBES-WAF Rules**

\| Range | Category | Description |

\|---|---|---|

\| \`1000000-1000999\` | Core | Core BREBES-WAF rules |

\| \`1001000-1001999\` | Upload | Upload protection |

\| \`2001000-2001999\` | Webshell | Webshell detection/protection |

\| \`3001000-3001999\` | WordPress | WordPress protection |

\| \`4001000-4001999\` | Malware | Malware detection |

\| \`5001000-5001999\` | Generic | Generic security rules |

\| \`6001000-6001999\` | Git | Git repository protection |

\| \`9001000-9001999\` | Local | Local/deployment-specific rules |

**---**

**## 22. Git Repository Protection**

Perlindungan mencakup:

\`\`\`text

/.git/

/.git/config

/.git/HEAD

/.git/index

/.git/logs/

/.git/objects/

/.git/refs/

\`\`\`

Rule Git:

\`\`\`text

rules/60-git/

\`\`\`

**---**

**## 23. Upload Protection**

BREBES-WAF menyediakan upload protection untuk mengurangi risiko:

\- Malicious file upload

\- Executable file upload

\- Webshell upload

\- Server-side script upload

\- Penyalahgunaan upload directory

Allowed extensions dikontrol melalui BREBES-WAF upload rules.

**---**

**## 24. Testing**

Setiap perubahan rule harus melalui:

\`\`\`text

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

\`\`\`

**### Positive Test**

Request berbahaya yang seharusnya diblokir:

\`\`\`text

HTTP 403

\`\`\`

**### Negative Test**

Request legitimate harus tetap dapat diproses:

\`\`\`text

HTTP 200

\`\`\`

atau response normal aplikasi.

**### False Positive Analysis**

Setiap rule baru harus diuji terhadap request legitimate untuk memastikan rule tidak terlalu agresif.

**---**

**## 25. Operational Logging**

Analisis keamanan sebaiknya dilakukan dengan mengkorelasikan:

\`\`\`text

Nginx Access Log

        +

Nginx Error Log

        +

ModSecurity Audit Log

        +

Application Log

        +

System Log

\`\`\`

Timestamp filesystem tidak boleh digunakan sebagai satu-satunya dasar untuk menentukan waktu suatu aktivitas dalam investigasi insiden.

Metadata filesystem dapat berubah atau dimanipulasi.

**---**

**## 26. Repository Structure**

\`\`\`text

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

│   ├── check-dependencies.sh

│   ├── check-last-detection.sh

│   ├── create-reverse-proxy.sh

│   ├── deploy-first-time.sh

│   ├── deploy.sh

│   └── today-detection.sh

|

└── tests/

\`\`\`

**---**

**## 27. Recommended Deployment**

Untuk deployment baru:

\`\`\`bash

cd /opt

sudo git clone https\://github.com/NRTechnology/Brebes-WAF.git

cd /opt/Brebes-WAF

sudo chmod +x scripts/check-dependencies.sh

sudo chmod +x scripts/deploy-first-time.sh

sudo ./scripts/check-dependencies.sh

sudo ./scripts/deploy-first-time.sh

\`\`\`

Setelah selesai:

\`\`\`bash

sudo nginx -t

sudo systemctl status nginx

\`\`\`

Verifikasi:

\`\`\`bash

sudo nginx -T > /tmp/nginx-effective.txt 2>&1

\`\`\`

**---**

**### Create Reverse Proxy**

Setelah Nginx dan BREBES-WAF siap, buat konfigurasi reverse proxy:

```bash
sudo ./scripts/create-reverse-proxy.sh \
    app.example.com \
    /var/ssl_cert/example.com.crt \
    /var/ssl_cert/example.com.key \
    http://192.0.2.10:8080
```

Review konfigurasi:

```bash
sudo nginx -T
```

Kemudian reload:

```bash
sudo systemctl reload nginx
```

**---**

**## 28. Subsequent Deployment**

Setelah BREBES-WAF terpasang:

\`\`\`bash

cd /opt/Brebes-WAF

git pull --ff-only origin main

sudo ./scripts/deploy.sh

\`\`\`

**---**

**## 29. Security Philosophy**

BREBES-WAF dikembangkan berdasarkan prinsip:

\- Defense in Depth

\- Least Privilege

\- Secure by Default

\- Fail Safely

\- Explicit Allow

\- Minimal Exposure

\- Continuous Monitoring

\- Continuous Improvement

BREBES-WAF merupakan salah satu lapisan keamanan dan tidak menggantikan:

\- Secure coding

\- Patch management

\- Authentication security

\- Access control

\- Network security

\- Endpoint security

\- Backup

\- Monitoring

\- Incident response

**---**

**## License**

Informasi lisensi BREBES-WAF mengikuti ketentuan lisensi yang ditetapkan pada repository project.

**---**

**\*\*BREBES-WAF\*\***

**\*\*Brebes CSIRT\*\***

Web Application Firewall Security Ruleset

Nginx  

\+  

ModSecurity v3  

\+  

OWASP CRS  

\+  

BREBES-WAF Rules