#!/bin/bash

# =============================================================================
# BREBES-WAF
# Nginx Reverse Proxy Configuration Generator
# =============================================================================

set -euo pipefail

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<EOF
Usage:
  $0 --domain <DOMAIN> \\
     --ssl-cert <SSL_CERTIFICATE_PATH> \\
     --ssl-key <SSL_CERTIFICATE_KEY_PATH> \\
     --proxy-pass <PROXY_PASS>

Options:
  --domain      Domain aplikasi, misalnya app.example.com
  --ssl-cert    Path file sertifikat SSL/TLS
  --ssl-key     Path file private key SSL/TLS
  --proxy-pass  URL backend, misalnya http://192.0.2.10:8080
  -h, --help    Tampilkan bantuan

Example:
  sudo $0 \\
    --domain app.example.com \\
    --ssl-cert /var/ssl_cert/example.com.crt \\
    --ssl-key /var/ssl_cert/example.com.key \\
    --proxy-pass http://192.0.2.10:8080
EOF
}

# =============================================================================
# Arguments
# =============================================================================

DOMAIN=""
SSL_CERTIFICATE=""
SSL_CERTIFICATE_KEY=""
PROXY_PASS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "[ERROR] Opsi --domain membutuhkan nilai." >&2
                usage
                exit 1
            fi
            DOMAIN="$2"
            shift 2
            ;;
        --ssl-cert)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "[ERROR] Opsi --ssl-cert membutuhkan nilai." >&2
                usage
                exit 1
            fi
            SSL_CERTIFICATE="$2"
            shift 2
            ;;
        --ssl-key)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "[ERROR] Opsi --ssl-key membutuhkan nilai." >&2
                usage
                exit 1
            fi
            SSL_CERTIFICATE_KEY="$2"
            shift 2
            ;;
        --proxy-pass)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "[ERROR] Opsi --proxy-pass membutuhkan nilai." >&2
                usage
                exit 1
            fi
            PROXY_PASS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Opsi tidak dikenal: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "${DOMAIN}" || -z "${SSL_CERTIFICATE}" || \
      -z "${SSL_CERTIFICATE_KEY}" || -z "${PROXY_PASS}" ]]; then
    echo "[ERROR] Semua opsi berikut wajib diisi: --domain, --ssl-cert, --ssl-key, --proxy-pass." >&2
    usage
    exit 1
fi

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

CONFIG_FILE="${NGINX_SITES_AVAILABLE}/${DOMAIN}.conf"
ACCESS_LOG="/var/log/nginx/${DOMAIN}.access.log"
ERROR_LOG="/var/log/nginx/${DOMAIN}.error.log"

# =============================================================================
# Validation
# =============================================================================

if ! command -v nginx >/dev/null 2>&1; then
    echo "[ERROR] Nginx tidak ditemukan."
    exit 1
fi

if [ ! -f "${SSL_CERTIFICATE}" ]; then
    echo "[ERROR] SSL certificate tidak ditemukan:"
    echo "        ${SSL_CERTIFICATE}"
    exit 1
fi

if [ ! -f "${SSL_CERTIFICATE_KEY}" ]; then
    echo "[ERROR] SSL certificate key tidak ditemukan:"
    echo "        ${SSL_CERTIFICATE_KEY}"
    exit 1
fi

if [ ! -f "/etc/nginx/snippets/proxy-common.conf" ]; then
    echo "[ERROR] Nginx proxy common snippet tidak ditemukan:"
    echo "        /etc/nginx/snippets/proxy-common.conf"
    exit 1
fi

# =============================================================================
# Directory
# =============================================================================

mkdir -p "${NGINX_SITES_AVAILABLE}"
mkdir -p "${NGINX_SITES_ENABLED}"

# =============================================================================
# Configuration
# =============================================================================

cat > "${CONFIG_FILE}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    access_log ${ACCESS_LOG} reverser;
    error_log ${ERROR_LOG};

    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    server_name ${DOMAIN};

    ssl_certificate ${SSL_CERTIFICATE};
    ssl_certificate_key ${SSL_CERTIFICATE_KEY};

    access_log ${ACCESS_LOG} reverser;
    error_log ${ERROR_LOG};

    client_body_buffer_size 10M;
    client_max_body_size 128M;

    location / {
        proxy_pass ${PROXY_PASS};
        include snippets/proxy-common.conf;
    }
}
EOF

# =============================================================================
# Enable Site
# =============================================================================

if [ -L "${NGINX_SITES_ENABLED}/${DOMAIN}.conf" ] || \
   [ -e "${NGINX_SITES_ENABLED}/${DOMAIN}.conf" ]; then
    rm -f "${NGINX_SITES_ENABLED}/${DOMAIN}.conf"
fi

ln -s "${CONFIG_FILE}" "${NGINX_SITES_ENABLED}/${DOMAIN}.conf"

# =============================================================================
# Nginx Validation
# =============================================================================

echo
echo "Testing Nginx configuration..."

nginx -t

echo
echo "[OK] Reverse proxy configuration berhasil dibuat."
echo
echo "Domain       : ${DOMAIN}"
echo "Proxy Pass   : ${PROXY_PASS}"
echo "SSL Cert     : ${SSL_CERTIFICATE}"
echo "SSL Key      : ${SSL_CERTIFICATE_KEY}"
echo "Access Log   : ${ACCESS_LOG}"
echo "Error Log    : ${ERROR_LOG}"
echo "Config       : ${CONFIG_FILE}"
echo
echo "Site enabled : /etc/nginx/sites-enabled/${DOMAIN}.conf"
echo
echo "Nginx belum di-reload."
echo "Untuk menerapkan:"
echo
echo "    systemctl reload nginx"
echo