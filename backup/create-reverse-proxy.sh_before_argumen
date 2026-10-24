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
    echo "Usage:"
    echo "  $0 <domain> <ssl_certificate> <ssl_certificate_key> <proxy_pass>"
    echo
    echo "Example:"
    echo "  $0 app.example.com \\"
    echo "     /var/ssl_cert/star.example.com.crt \\"
    echo "     /var/ssl_cert/star.example.com.key \\"
    echo "     http://15.0.2.6"
    exit 1
}

# =============================================================================
# Arguments
# =============================================================================

if [ "$#" -ne 4 ]; then
    usage
fi

DOMAIN="$1"
SSL_CERTIFICATE="$2"
SSL_CERTIFICATE_KEY="$3"
PROXY_PASS="$4"

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