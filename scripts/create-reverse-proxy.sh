#!/usr/bin/env bash
# =============================================================================
# BREBES-WAF
# Nginx Reverse Proxy Configuration Generator
#
# File    : scripts/create-reverse-proxy.sh
# Version : 1.1.2
#
# Changes:
#   - Uses brebes_waf_json instead of reverser for new virtual hosts.
#   - Refuses to overwrite an existing vhost or enabled site.
#   - Verifies that brebes_waf_json is defined exactly once in active Nginx
#     configuration before generating a virtual host.
#   - Validates Nginx configuration and rolls back only files created by this
#     execution if validation fails.
#   - Verifies the active vhost using directives, not nginx -T header paths.
#   - Registers EXIT-based rollback so explicit die/exit failures also clean up.
#   - Fixes printf newline handling in post-generation nginx -T verification.
#   - Does not reload or restart Nginx automatically.
#
# Existing virtual hosts and running configurations are not modified.
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# Configuration
# =============================================================================

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_SNIPPET="/etc/nginx/snippets/proxy-common.conf"
JSON_LOG_FORMAT_NAME="brebes_waf_json"
NGINX_JSON_LOG_FORMAT_FILE="/etc/nginx/conf.d/brebes-waf-log-format.conf"

# =============================================================================
# Colors and helpers
# =============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

log_info()  { printf '%b[INFO]%b %s\n' "${BLUE}" "${NC}" "$*"; }
log_ok()    { printf '%b[ OK ]%b %s\n' "${GREEN}" "${NC}" "$*"; }
log_warn()  { printf '%b[WARN]%b %s\n' "${YELLOW}" "${NC}" "$*"; }
log_error() { printf '%b[ERROR]%b %s\n' "${RED}" "${NC}" "$*" >&2; }

die() {
    log_error "$*"
    exit 1
}

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

Catatan:
  - Virtual host baru menggunakan format access log brebes_waf_json.
  - Konfigurasi virtual host yang sudah ada tidak akan ditimpa.
  - Nginx tidak di-reload otomatis.
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
            [[ $# -ge 2 && -n "${2:-}" ]] || { usage; die "Opsi --domain membutuhkan nilai."; }
            DOMAIN="$2"
            shift 2
            ;;
        --ssl-cert)
            [[ $# -ge 2 && -n "${2:-}" ]] || { usage; die "Opsi --ssl-cert membutuhkan nilai."; }
            SSL_CERTIFICATE="$2"
            shift 2
            ;;
        --ssl-key)
            [[ $# -ge 2 && -n "${2:-}" ]] || { usage; die "Opsi --ssl-key membutuhkan nilai."; }
            SSL_CERTIFICATE_KEY="$2"
            shift 2
            ;;
        --proxy-pass)
            [[ $# -ge 2 && -n "${2:-}" ]] || { usage; die "Opsi --proxy-pass membutuhkan nilai."; }
            PROXY_PASS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            die "Opsi tidak dikenal: $1"
            ;;
    esac
done

[[ -n "${DOMAIN}" && -n "${SSL_CERTIFICATE}" &&
   -n "${SSL_CERTIFICATE_KEY}" && -n "${PROXY_PASS}" ]] ||
    { usage; die "Semua opsi --domain, --ssl-cert, --ssl-key, dan --proxy-pass wajib diisi."; }

# =============================================================================
# Derived paths
# =============================================================================

CONFIG_FILE="${NGINX_SITES_AVAILABLE}/${DOMAIN}.conf"
ENABLED_LINK="${NGINX_SITES_ENABLED}/${DOMAIN}.conf"
ACCESS_LOG="/var/log/nginx/${DOMAIN}.access.log"
ERROR_LOG="/var/log/nginx/${DOMAIN}.error.log"

TEMP_CONFIG=""
CONFIG_CREATED=false
LINK_CREATED=false

# =============================================================================
# Rollback only what this execution created
# =============================================================================

cleanup_on_error() {
    local exit_code=$?
    trap - EXIT

    if [[ -n "${TEMP_CONFIG}" && -e "${TEMP_CONFIG}" ]]; then
        rm -f -- "${TEMP_CONFIG}"
    fi

    if [[ "${exit_code}" -ne 0 ]]; then
        if [[ "${LINK_CREATED}" == "true" && -L "${ENABLED_LINK}" ]]; then
            rm -f -- "${ENABLED_LINK}"
            log_warn "Symlink yang dibuat oleh script ini dihapus saat rollback."
        fi

        if [[ "${CONFIG_CREATED}" == "true" && -f "${CONFIG_FILE}" ]]; then
            rm -f -- "${CONFIG_FILE}"
            log_warn "File konfigurasi yang dibuat oleh script ini dihapus saat rollback."
        fi

        log_error "Pembuatan reverse proxy gagal (exit code ${exit_code})."
        log_warn "Tidak ada konfigurasi virtual host lama yang ditimpa."
    fi

    return "${exit_code}"
}

# Register rollback handler. On successful exit (status 0), it leaves the
# generated configuration in place. On failure, it removes only artifacts
# created by this execution.
trap cleanup_on_error EXIT

# =============================================================================
# Preconditions and validation
# =============================================================================

[[ "${EUID}" -eq 0 ]] || die "Script harus dijalankan sebagai root."

command -v nginx >/dev/null 2>&1 || die "Nginx tidak ditemukan."
command -v awk >/dev/null 2>&1 || die "awk tidak ditemukan."
command -v grep >/dev/null 2>&1 || die "grep tidak ditemukan."

# Restrict domain to DNS hostname characters to prevent Nginx config injection.
if [[ ! "${DOMAIN}" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$ ]]; then
    die "Format domain tidak valid: ${DOMAIN}"
fi

# Reject whitespace and Nginx statement delimiters in values inserted into config.
for value_name in SSL_CERTIFICATE SSL_CERTIFICATE_KEY PROXY_PASS; do
    value="${!value_name}"
    if [[ "${value}" =~ [[:space:]\;\{\}] ]]; then
        die "Nilai ${value_name} mengandung karakter yang tidak diizinkan."
    fi
done

[[ "${PROXY_PASS}" =~ ^https?://[^/[:space:]]+(/[^[:space:]]*)?$ ]] ||
    die "Format --proxy-pass harus berupa URL http:// atau https:// yang valid."

[[ -f "${SSL_CERTIFICATE}" && -r "${SSL_CERTIFICATE}" ]] ||
    die "SSL certificate tidak ditemukan atau tidak dapat dibaca: ${SSL_CERTIFICATE}"

[[ -f "${SSL_CERTIFICATE_KEY}" && -r "${SSL_CERTIFICATE_KEY}" ]] ||
    die "SSL certificate key tidak ditemukan atau tidak dapat dibaca: ${SSL_CERTIFICATE_KEY}"

[[ -f "${NGINX_SNIPPET}" ]] ||
    die "Nginx proxy common snippet tidak ditemukan: ${NGINX_SNIPPET}"

# Do not overwrite or replace any existing virtual host or enabled entry.
if [[ -e "${CONFIG_FILE}" || -L "${CONFIG_FILE}" ]]; then
    die "Konfigurasi sudah ada: ${CONFIG_FILE}. Script tidak akan menimpa konfigurasi existing."
fi

if [[ -e "${ENABLED_LINK}" || -L "${ENABLED_LINK}" ]]; then
    die "Site sudah ada di sites-enabled: ${ENABLED_LINK}. Tidak ada perubahan yang dilakukan."
fi

# =============================================================================
# Verify JSON log format is already active exactly once
# =============================================================================

log_info "Memeriksa deklarasi ${JSON_LOG_FORMAT_NAME} pada konfigurasi Nginx aktif ..."

NGINX_DUMP="$(nginx -T 2>&1)" ||
    die "nginx -T gagal. Perbaiki konfigurasi Nginx yang ada sebelum membuat virtual host."

JSON_FORMAT_COUNT="$(
    printf '%s\n' "${NGINX_DUMP}" |
        awk -v name="${JSON_LOG_FORMAT_NAME}" '
            $1 == "log_format" && $2 == name { count++ }
            END { print count+0 }
        '
)"

if [[ "${JSON_FORMAT_COUNT}" -ne 1 ]]; then
    die "Format ${JSON_LOG_FORMAT_NAME} harus terdefinisi tepat satu kali pada konfigurasi aktif (ditemukan: ${JSON_FORMAT_COUNT}). Tidak ada file yang dibuat."
fi

if ! printf '%s\n' "${NGINX_DUMP}" |
    grep -Fq "# configuration file ${NGINX_JSON_LOG_FORMAT_FILE}:"; then
    log_warn "File dedicated ${NGINX_JSON_LOG_FORMAT_FILE} tidak terdeteksi pada dump nginx -T."
    log_info "Format JSON ditemukan pada konfigurasi aktif; melanjutkan tanpa mengubah include."
fi

log_ok "Format ${JSON_LOG_FORMAT_NAME} ditemukan tepat satu kali."

# =============================================================================
# Prepare directories and configuration
# =============================================================================

mkdir -p "${NGINX_SITES_AVAILABLE}" "${NGINX_SITES_ENABLED}"

TEMP_CONFIG="$(mktemp "${NGINX_SITES_AVAILABLE}/.${DOMAIN}.conf.tmp.XXXXXX")"

cat > "${TEMP_CONFIG}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    access_log ${ACCESS_LOG} ${JSON_LOG_FORMAT_NAME};
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

    access_log ${ACCESS_LOG} ${JSON_LOG_FORMAT_NAME};
    error_log ${ERROR_LOG};

    client_body_buffer_size 10M;
    client_max_body_size 128M;

    location / {
        proxy_pass ${PROXY_PASS};
        include snippets/proxy-common.conf;
    }
}
EOF

chmod 0644 "${TEMP_CONFIG}"

# Atomic placement. CONFIG_FILE was checked absent above.
mv -- "${TEMP_CONFIG}" "${CONFIG_FILE}"
TEMP_CONFIG=""
CONFIG_CREATED=true

# Create the enabled symlink only after the available file exists.
ln -s "${CONFIG_FILE}" "${ENABLED_LINK}"
LINK_CREATED=true

# =============================================================================
# Nginx validation and post-check
# =============================================================================

echo
log_info "Testing Nginx configuration ..."

nginx -t

# Verify the vhost by effective directives, not by nginx -T comment header path.
# nginx -T may report a symlink path or a resolved target depending on include layout.
NGINX_DUMP_AFTER="$(nginx -T 2>&1)" ||
    die "nginx -T gagal setelah pembuatan virtual host."

VHOST_SERVER_NAME_COUNT="$(
    printf '%s\n' "${NGINX_DUMP_AFTER}" |
        awk -v domain="${DOMAIN}" '
            $1 == "server_name" && $2 == domain { count++ }
            END { print count+0 }
        '
)"

if [[ "${VHOST_SERVER_NAME_COUNT}" -ne 2 ]]; then
    die "Verifikasi virtual host gagal: server_name ${DOMAIN} ditemukan ${VHOST_SERVER_NAME_COUNT} kali pada nginx -T (diharapkan 2)."
fi

VHOST_JSON_LOG_COUNT="$(
    printf '%s\n' "${NGINX_DUMP_AFTER}" |
        awk -v path="${ACCESS_LOG}" -v format="${JSON_LOG_FORMAT_NAME}" '
            $1 == "access_log" && $2 == path && $3 == format { count++ }
            END { print count+0 }
        '
)"

if [[ "${VHOST_JSON_LOG_COUNT}" -ne 2 ]]; then
    die "Verifikasi access_log JSON gagal: diharapkan tepat 2 deklarasi, ditemukan ${VHOST_JSON_LOG_COUNT}."
fi

# Verify the generated vhost does not contain legacy reverser access logging.
if grep -Eq '^[[:space:]]*access_log[[:space:]].*[[:space:]]reverser([[:space:]]*;|[[:space:]])' "${CONFIG_FILE}"; then
    die "Ditemukan access_log reverser pada konfigurasi baru."
fi

log_ok "Konfigurasi Nginx valid."
log_ok "Virtual host ditemukan pada konfigurasi aktif."
log_ok "Dua deklarasi access_log menggunakan ${JSON_LOG_FORMAT_NAME}."
log_ok "Tidak ada access_log reverser pada virtual host baru."

# =============================================================================
# Summary
# =============================================================================

echo
echo "============================================================"
echo " BREBES-WAF Reverse Proxy Configuration"
echo "============================================================"
echo
echo "Domain       : ${DOMAIN}"
echo "Proxy Pass   : ${PROXY_PASS}"
echo "SSL Cert     : ${SSL_CERTIFICATE}"
echo "SSL Key      : ${SSL_CERTIFICATE_KEY}"
echo "Access Log   : ${ACCESS_LOG}"
echo "Log Format   : ${JSON_LOG_FORMAT_NAME}"
echo "Error Log    : ${ERROR_LOG}"
echo "Config       : ${CONFIG_FILE}"
echo "Site enabled : ${ENABLED_LINK}"
echo
echo "[ OK ] Reverse proxy configuration berhasil dibuat."
echo "[ OK ] Konfigurasi virtual host existing tidak ditimpa."
echo
echo "Nginx belum di-reload."
echo "Untuk menerapkan konfigurasi baru:"
echo
echo "    systemctl reload nginx"
echo
