#!/bin/bash

# =============================================================================
# BREBES-WAF
# First-Time Installation & Deployment Script
#
# File    : scripts/deploy-first-time.sh
# Version : 1.2.0
# Author  : Brebes CSIRT
#
# Purpose:
#   First-time installation, dependency setup, configuration and deployment
#   of BREBES-WAF.
#
# Supported:
#   Ubuntu 22.04+
#
# Components:
#   - Nginx
#   - ModSecurity v3
#   - Nginx ModSecurity Connector
#   - Nginx NDK module
#   - OWASP CRS
#   - BREBES-WAF Rules
#   - Git
#   - Curl
#   - CA Certificates
#   - Unzip
#
# Installation:
#
#   cd /opt/Brebes-WAF
#   sudo ./scripts/deploy-first-time.sh
#
# After first installation:
#
#   ./scripts/deploy.sh
#
# =============================================================================

set -euo pipefail


# =============================================================================
# Configuration
# =============================================================================

BREBES_WAF_HOME="/opt/Brebes-WAF"

NGINX_MAIN_CONF="/etc/nginx/nginx.conf"

MODSECURITY_CONF="/etc/nginx/modsecurity.conf"
MODSECURITY_INCLUDE="/etc/nginx/modsecurity_includes.conf"

MODSECURITY_DIR="/etc/nginx/modsecurity"
CRS_SYSTEM_DIR="${MODSECURITY_DIR}"
CRS_LOAD_FILE="${CRS_SYSTEM_DIR}/crs-load.conf"
CRS_REPOSITORY_FILE="${BREBES_WAF_HOME}/nginx/modsecurity/crs-load.conf"

RULES_DIR="${BREBES_WAF_HOME}/rules"

UBUNTU_MAIN_REPOSITORY="http://archive.ubuntu.com/ubuntu"
UBUNTU_SECURITY_REPOSITORY="http://security.ubuntu.com/ubuntu"

APT_BACKUP_DIR="/root/brebes-waf-apt-backup"

NGINX_BACKUP_DIR="/root/brebes-waf-nginx-backup"

MODSECURITY_MODULE_PACKAGE="libnginx-mod-http-modsecurity"
NGINX_NDK_PACKAGE="libnginx-mod-http-ndk"
CRS_PACKAGE="modsecurity-crs"

MODSECURITY_MODULE_PATH="/usr/lib/nginx/modules/ngx_http_modsecurity_module.so"
NDK_MODULE_PATH="/usr/lib/nginx/modules/ndk_http_module.so"

MODSECURITY_MODULE_CONFIG="/etc/nginx/modules-enabled/50-mod-http-modsecurity.conf"
MODSECURITY_MODULE_AVAILABLE="/etc/nginx/modules-available/mod-http-modsecurity.conf"


# =============================================================================
# Colors
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


# =============================================================================
# Helper Functions
# =============================================================================

log_info()
{
    echo -e "${BLUE}[INFO]${NC} $1"
}


log_ok()
{
    echo -e "${GREEN}[ OK ]${NC} $1"
}


log_warn()
{
    echo -e "${YELLOW}[WARN]${NC} $1"
}


log_error()
{
    echo -e "${RED}[ERROR]${NC} $1"
}


log_section()
{
    echo
    echo "============================================================"
    echo " $1"
    echo "============================================================"
}


command_exists()
{
    command -v "$1" >/dev/null 2>&1
}


package_installed()
{
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null \
        | grep -q "install ok installed"
}


die()
{
    log_error "$1"
    exit 1
}


# =============================================================================
# Root Check
# =============================================================================

if [[ "${EUID}" -ne 0 ]]; then

    log_error "Script harus dijalankan sebagai root."

    echo
    echo "Gunakan:"
    echo
    echo "    sudo $0"
    echo

    exit 1

fi


# =============================================================================
# BREBES-WAF Repository Check
# =============================================================================

log_section "BREBES-WAF Repository Check"

if [[ ! -d "${BREBES_WAF_HOME}" ]]; then

    die "BREBES-WAF repository tidak ditemukan:

    ${BREBES_WAF_HOME}"

fi

log_ok "BREBES-WAF repository ditemukan:"
echo "    ${BREBES_WAF_HOME}"


if [[ ! -d "${RULES_DIR}" ]]; then

    die "BREBES-WAF rules directory tidak ditemukan:

    ${RULES_DIR}"

fi

log_ok "BREBES-WAF rules directory ditemukan."


# =============================================================================
# Operating System Check
# =============================================================================

log_section "Operating System Check"

if [[ ! -f /etc/os-release ]]; then

    die "/etc/os-release tidak ditemukan."

fi

source /etc/os-release

echo "OS            : ${PRETTY_NAME:-unknown}"
echo "ID            : ${ID:-unknown}"
echo "Version       : ${VERSION_ID:-unknown}"
echo "Architecture  : $(dpkg --print-architecture)"


if [[ "${ID:-}" != "ubuntu" ]]; then

    die "Operating system bukan Ubuntu.

BREBES-WAF installer ini hanya mendukung Ubuntu."

fi


UBUNTU_CODENAME="${VERSION_CODENAME:-}"

if [[ -z "${UBUNTU_CODENAME}" ]] && command_exists lsb_release; then

    UBUNTU_CODENAME=$(lsb_release -sc)

fi


if [[ -z "${UBUNTU_CODENAME}" ]]; then

    die "Ubuntu codename tidak dapat dideteksi."

fi


echo "Codename      : ${UBUNTU_CODENAME}"


case "${UBUNTU_CODENAME}" in

    jammy)

        log_ok "Ubuntu 22.04 Jammy Jellyfish detected."

        ;;

    noble)

        log_ok "Ubuntu 24.04 Noble Numbat detected."

        ;;

    *)

        log_warn "Ubuntu version/codename belum diuji secara khusus:"
        echo "    ${UBUNTU_CODENAME}"

        ;;

esac


# =============================================================================
# APT Check
# =============================================================================

log_section "APT Check"

if ! command_exists apt-get; then

    die "apt-get tidak ditemukan."

fi

log_ok "apt-get tersedia."


# =============================================================================
# Backup APT Repository Configuration
# =============================================================================

log_section "APT Repository Backup"

BACKUP_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

CURRENT_BACKUP_DIR="${APT_BACKUP_DIR}/${BACKUP_TIMESTAMP}"

mkdir -p "${CURRENT_BACKUP_DIR}"

log_info "Backup repository configuration..."


if [[ -f /etc/apt/sources.list ]]; then

    cp -a \
        /etc/apt/sources.list \
        "${CURRENT_BACKUP_DIR}/sources.list"

    log_ok "Backed up /etc/apt/sources.list"

fi


if [[ -d /etc/apt/sources.list.d ]]; then

    cp -a \
        /etc/apt/sources.list.d \
        "${CURRENT_BACKUP_DIR}/sources.list.d"

    log_ok "Backed up /etc/apt/sources.list.d"

fi


echo
echo "APT Backup:"
echo "    ${CURRENT_BACKUP_DIR}"


# =============================================================================
# Ubuntu Repository Configuration
# =============================================================================

log_section "Ubuntu Repository Configuration"

UBUNTU_SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"


if [[ -f "${UBUNTU_SOURCES_FILE}" ]]; then

    log_info "Ubuntu Deb822 repository detected:"
    echo "    ${UBUNTU_SOURCES_FILE}"

    cat > "${UBUNTU_SOURCES_FILE}" <<EOF
Types: deb
URIs: ${UBUNTU_MAIN_REPOSITORY}
Suites: ${UBUNTU_CODENAME} ${UBUNTU_CODENAME}-updates ${UBUNTU_CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: ${UBUNTU_SECURITY_REPOSITORY}
Suites: ${UBUNTU_CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

    log_ok "Ubuntu repository dikonfigurasi ke official Ubuntu repository."

else

    log_info "Menggunakan traditional APT sources.list format."

    cat > /etc/apt/sources.list <<EOF
deb ${UBUNTU_MAIN_REPOSITORY} ${UBUNTU_CODENAME} main restricted universe multiverse
deb ${UBUNTU_MAIN_REPOSITORY} ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb ${UBUNTU_MAIN_REPOSITORY} ${UBUNTU_CODENAME}-backports main restricted universe multiverse
deb ${UBUNTU_SECURITY_REPOSITORY} ${UBUNTU_CODENAME}-security main restricted universe multiverse
EOF

    log_ok "Ubuntu repository dikonfigurasi ke official Ubuntu repository."

fi


# =============================================================================
# Disable Existing Ubuntu Mirror Configuration
# =============================================================================

log_section "Ubuntu Mirror Check"

if [[ -d /etc/apt/sources.list.d ]]; then

    shopt -s nullglob

    for SOURCE_FILE in /etc/apt/sources.list.d/*.list
    do

        if grep -Eqi \
            'archive\.ubuntu\.com|[a-z0-9.-]+\.ubuntu\.com|ports\.ubuntu\.com' \
            "${SOURCE_FILE}" 2>/dev/null; then

            log_info "Ubuntu repository ditemukan di:"
            echo "    ${SOURCE_FILE}"

            if [[ "${SOURCE_FILE}" != "/etc/apt/sources.list.d/ubuntu.list" ]]; then

                BACKUP_FILE="${SOURCE_FILE}.brebes-waf-backup"

                cp -a \
                    "${SOURCE_FILE}" \
                    "${BACKUP_FILE}"

                sed -i \
                    -E 's/^[[:space:]]*deb[[:space:]]/# BREBES-WAF disabled: deb/' \
                    "${SOURCE_FILE}"

                log_ok "Ubuntu mirror lama dinonaktifkan:"
                echo "    ${SOURCE_FILE}"

            fi

        fi

    done

    shopt -u nullglob

fi


# =============================================================================
# Show Active Ubuntu Repository
# =============================================================================

log_section "Active Ubuntu Repository"

if [[ -f /etc/apt/sources.list ]]; then

    echo
    echo "--- /etc/apt/sources.list ---"

    grep -E \
        '^[[:space:]]*deb ' \
        /etc/apt/sources.list \
        || true

fi


if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then

    echo
    echo "--- /etc/apt/sources.list.d/ubuntu.sources ---"

    cat /etc/apt/sources.list.d/ubuntu.sources

fi


# =============================================================================
# APT Update
# =============================================================================

log_section "APT Update"

log_info "Updating Ubuntu package index..."

apt-get update

log_ok "APT update berhasil."


# =============================================================================
# Detect ModSecurity Library Package
# =============================================================================

log_section "ModSecurity Package Detection"

MODSECURITY_LIBRARY_PACKAGE=""

if apt-cache show libmodsecurity3 >/dev/null 2>&1; then

    MODSECURITY_LIBRARY_PACKAGE="libmodsecurity3"

elif apt-cache show libmodsecurity3t64 >/dev/null 2>&1; then

    MODSECURITY_LIBRARY_PACKAGE="libmodsecurity3t64"

else

    die "Package ModSecurity v3 tidak tersedia pada repository."

fi


log_ok "ModSecurity library package:"
echo "    ${MODSECURITY_LIBRARY_PACKAGE}"


# =============================================================================
# Detect ModSecurity Development Package
# =============================================================================

MODSECURITY_DEV_PACKAGE=""

if apt-cache show libmodsecurity-dev >/dev/null 2>&1; then

    MODSECURITY_DEV_PACKAGE="libmodsecurity-dev"

else

    log_warn "libmodsecurity-dev tidak tersedia."
    log_warn "Development package tidak wajib untuk runtime BREBES-WAF."

fi


# =============================================================================
# Required Packages
# =============================================================================

REQUIRED_PACKAGES=(
    nginx
    curl
    ca-certificates
    git
    unzip
    "${MODSECURITY_MODULE_PACKAGE}"
    "${MODSECURITY_LIBRARY_PACKAGE}"
    "${NGINX_NDK_PACKAGE}"
    "${CRS_PACKAGE}"
)


if [[ -n "${MODSECURITY_DEV_PACKAGE}" ]]; then

    REQUIRED_PACKAGES+=(
        "${MODSECURITY_DEV_PACKAGE}"
    )

fi


# =============================================================================
# Package Dependency Check
# =============================================================================

log_section "Package Dependency Check"

MISSING_PACKAGES=()


for PACKAGE in "${REQUIRED_PACKAGES[@]}"
do

    if package_installed "${PACKAGE}"; then

        VERSION=$(dpkg-query \
            -W \
            -f='${Version}' \
            "${PACKAGE}" \
            2>/dev/null \
            || echo "unknown")

        log_ok "${PACKAGE} [${VERSION}]"

    else

        log_warn "${PACKAGE} belum terinstall."

        MISSING_PACKAGES+=(
            "${PACKAGE}"
        )

    fi

done


# =============================================================================
# Install Missing Packages
# =============================================================================

if [[ "${#MISSING_PACKAGES[@]}" -gt 0 ]]; then

    log_section "Installing Missing Packages"

    echo "Package yang akan diinstall:"
    echo

    for PACKAGE in "${MISSING_PACKAGES[@]}"
    do

        echo "    - ${PACKAGE}"

    done

    echo

    apt-get install -y \
        "${MISSING_PACKAGES[@]}"

    log_ok "Missing packages berhasil diinstall."

else

    log_ok "Semua package dependency sudah tersedia."

fi


# =============================================================================
# Nginx Check
# =============================================================================

log_section "Nginx Check"

if command_exists nginx; then

    NGINX_VERSION=$(nginx -v 2>&1 | sed 's/^nginx version: //')

    log_ok "Nginx tersedia."
    echo "    Version: ${NGINX_VERSION}"

else

    die "Nginx tidak ditemukan setelah installation."

fi


# =============================================================================
# ModSecurity v3 Library Check
# =============================================================================

log_section "ModSecurity v3 Check"

MODSECURITY_FOUND=false


if ldconfig -p 2>/dev/null | grep -q "libmodsecurity"; then

    log_ok "ModSecurity v3 library ditemukan."

    ldconfig -p 2>/dev/null \
        | grep "libmodsecurity" \
        || true

    MODSECURITY_FOUND=true

fi


if package_installed "libmodsecurity3"; then

    VERSION=$(dpkg-query \
        -W \
        -f='${Version}' \
        libmodsecurity3 \
        2>/dev/null \
        || echo "unknown")

    log_ok "libmodsecurity3 installed."
    echo "    Version: ${VERSION}"

    MODSECURITY_FOUND=true

fi


if package_installed "libmodsecurity3t64"; then

    VERSION=$(dpkg-query \
        -W \
        -f='${Version}' \
        libmodsecurity3t64 \
        2>/dev/null \
        || echo "unknown")

    log_ok "libmodsecurity3t64 installed."
    echo "    Version: ${VERSION}"

    MODSECURITY_FOUND=true

fi


if [[ "${MODSECURITY_FOUND}" != "true" ]]; then

    die "ModSecurity v3 library tidak ditemukan."

fi


# =============================================================================
# ModSecurity Nginx Module Check
# =============================================================================

log_section "Nginx ModSecurity Module Check"

MODSECURITY_MODULE=""


if [[ -f "${MODSECURITY_MODULE_PATH}" ]]; then

    MODSECURITY_MODULE="${MODSECURITY_MODULE_PATH}"

    log_ok "ModSecurity Nginx module ditemukan:"
    echo "    ${MODSECURITY_MODULE}"

else

    die "ngx_http_modsecurity_module.so tidak ditemukan."

fi


# =============================================================================
# Nginx NDK Module Check
# =============================================================================

log_section "Nginx NDK Module Check"


if [[ -f "${NDK_MODULE_PATH}" ]]; then

    log_ok "Nginx NDK module ditemukan:"
    echo "    ${NDK_MODULE_PATH}"

else

    log_warn "Nginx NDK module tidak ditemukan:"
    echo "    ${NDK_MODULE_PATH}"

fi


# =============================================================================
# Enable ModSecurity Nginx Module
# =============================================================================

log_section "ModSecurity Module Configuration"


if [[ -f "${MODSECURITY_MODULE_CONFIG}" ]]; then

    log_ok "ModSecurity module configuration tersedia:"
    echo "    ${MODSECURITY_MODULE_CONFIG}"

else

    if [[ -f "${MODSECURITY_MODULE_AVAILABLE}" ]]; then

        log_info "Mengaktifkan ModSecurity Nginx module..."

        ln -sf \
            "${MODSECURITY_MODULE_AVAILABLE}" \
            "${MODSECURITY_MODULE_CONFIG}"

        log_ok "ModSecurity module configuration diaktifkan."

    else

        die "ModSecurity module configuration tidak ditemukan:

    ${MODSECURITY_MODULE_AVAILABLE}"

    fi

fi


# =============================================================================
# Nginx Backup
# =============================================================================

log_section "Nginx Configuration Backup"

NGINX_BACKUP_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

CURRENT_NGINX_BACKUP_DIR="${NGINX_BACKUP_DIR}/${NGINX_BACKUP_TIMESTAMP}"

mkdir -p "${CURRENT_NGINX_BACKUP_DIR}"


if [[ -f "${NGINX_MAIN_CONF}" ]]; then

    cp -a \
        "${NGINX_MAIN_CONF}" \
        "${CURRENT_NGINX_BACKUP_DIR}/nginx.conf"

    log_ok "Backup nginx.conf dibuat:"
    echo "    ${CURRENT_NGINX_BACKUP_DIR}/nginx.conf"

fi


# =============================================================================
# Prepare ModSecurity Directory
# =============================================================================

log_section "ModSecurity Directory"

mkdir -p "${MODSECURITY_DIR}"

chmod 0755 "${MODSECURITY_DIR}"

log_ok "ModSecurity directory tersedia:"
echo "    ${MODSECURITY_DIR}"


# =============================================================================
# Prepare ModSecurity Configuration
# =============================================================================

log_section "ModSecurity Configuration"


if [[ -f "${MODSECURITY_CONF}" ]]; then

    log_ok "ModSecurity configuration sudah tersedia:"
    echo "    ${MODSECURITY_CONF}"

else

    log_info "Membuat ModSecurity configuration..."

    cat > "${MODSECURITY_CONF}" <<'EOF'
# =============================================================================
# BREBES-WAF
# ModSecurity v3 Base Configuration
# =============================================================================

SecRuleEngine On

SecRequestBodyAccess On
SecResponseBodyAccess Off

SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecRequestBodyLimitAction Reject

SecPcreMatchLimit 100000
SecPcreMatchLimitRecursion 100000

SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"

SecAuditLogParts ABIJDEFHZ
SecAuditLogType Serial
SecAuditLog /var/log/nginx/modsecurity/audit.log

SecDebugLog /var/log/nginx/modsecurity/debug.log
SecDebugLogLevel 0

SecTmpDir /tmp
SecDataDir /tmp
EOF

    chmod 0644 "${MODSECURITY_CONF}"

    mkdir -p /var/log/nginx/modsecurity

    chmod 0755 /var/log/nginx/modsecurity

    touch /var/log/nginx/modsecurity/audit.log
    touch /var/log/nginx/modsecurity/debug.log

    chown www-data:adm \
        /var/log/nginx/modsecurity/audit.log \
        /var/log/nginx/modsecurity/debug.log

    chmod 0640 \
        /var/log/nginx/modsecurity/audit.log \
        /var/log/nginx/modsecurity/debug.log

    log_ok "ModSecurity configuration dibuat."

fi


# =============================================================================
# Prepare OWASP CRS
# =============================================================================

log_section "OWASP CRS Configuration"


if [[ -f "${CRS_LOAD_FILE}" ]]; then

    log_ok "System CRS load configuration ditemukan:"
    echo "    ${CRS_LOAD_FILE}"

elif [[ -f "${CRS_REPOSITORY_FILE}" ]]; then

    log_info "System CRS load configuration belum tersedia."

    log_info "Menggunakan repository CRS configuration:"

    echo "    ${CRS_REPOSITORY_FILE}"

    cp -a \
        "${CRS_REPOSITORY_FILE}" \
        "${CRS_LOAD_FILE}"

    log_ok "CRS load configuration disalin ke:"
    echo "    ${CRS_LOAD_FILE}"

else

    die "OWASP CRS load configuration tidak ditemukan.

System:
    ${CRS_LOAD_FILE}

Repository:
    ${CRS_REPOSITORY_FILE}"

fi


if [[ ! -s "${CRS_LOAD_FILE}" ]]; then

    die "CRS load configuration kosong:

    ${CRS_LOAD_FILE}"

fi


chmod 0644 "${CRS_LOAD_FILE}"

log_ok "OWASP CRS load configuration siap."


# =============================================================================
# Detect OWASP CRS
# =============================================================================

CRS_FOUND=false

if package_installed "${CRS_PACKAGE}"; then

    CRS_VERSION=$(dpkg-query \
        -W \
        -f='${Version}' \
        "${CRS_PACKAGE}" \
        2>/dev/null \
        || echo "unknown")

    log_ok "OWASP CRS package installed."
    echo "    Version: ${CRS_VERSION}"

    CRS_FOUND=true

fi


CRS_LOCATIONS=(
    "/usr/share/modsecurity-crs"
    "/usr/share/modsecurity-crs/owasp-crs"
    "/etc/modsecurity"
    "/etc/nginx/modsecurity"
)


for CRS_PATH in "${CRS_LOCATIONS[@]}"
do

    if [[ -d "${CRS_PATH}" ]]; then

        log_ok "CRS directory ditemukan:"
        echo "    ${CRS_PATH}"

        CRS_FOUND=true

    fi

done


if [[ "${CRS_FOUND}" != "true" ]]; then

    die "OWASP CRS tidak ditemukan."

fi


# =============================================================================
# Discover BREBES-WAF Rules
# =============================================================================

log_section "BREBES-WAF Rule Discovery"


if [[ ! -d "${RULES_DIR}" ]]; then

    die "Rules directory tidak ditemukan:

    ${RULES_DIR}"

fi


mapfile -d '' RULE_FILES < <(
    find "${RULES_DIR}" \
        -type f \
        -name '*.conf' \
        -print0 \
    | sort -z
)


if [[ "${#RULE_FILES[@]}" -eq 0 ]]; then

    die "Tidak ada BREBES-WAF rule (*.conf) ditemukan:

    ${RULES_DIR}"

fi


log_ok "BREBES-WAF rules ditemukan:"
echo "    ${#RULE_FILES[@]} file"


for RULE_FILE in "${RULE_FILES[@]}"
do

    echo "    - ${RULE_FILE}"

done


# =============================================================================
# Generate ModSecurity Include
# =============================================================================

log_section "Generate ModSecurity Include"


TEMP_INCLUDE="${MODSECURITY_INCLUDE}.tmp.$$"

rm -f "${TEMP_INCLUDE}"


cat > "${TEMP_INCLUDE}" <<EOF
# =============================================================================
# BREBES-WAF
# Generated ModSecurity Include
#
# DO NOT EDIT MANUALLY
#
# Generated by:
#   scripts/deploy-first-time.sh
# =============================================================================

# -----------------------------------------------------------------------------
# ModSecurity Base Configuration
# -----------------------------------------------------------------------------

include ${MODSECURITY_CONF}

# -----------------------------------------------------------------------------
# OWASP CRS
# -----------------------------------------------------------------------------

include ${CRS_LOAD_FILE}

# -----------------------------------------------------------------------------
# BREBES-WAF Rules
# -----------------------------------------------------------------------------

EOF


for RULE_FILE in "${RULE_FILES[@]}"
do

    printf 'include %s;\n' "${RULE_FILE}" >> "${TEMP_INCLUDE}"

done


if [[ ! -s "${TEMP_INCLUDE}" ]]; then

    rm -f "${TEMP_INCLUDE}"

    die "Gagal menghasilkan ModSecurity include."

fi


# =============================================================================
# Backup Existing ModSecurity Include
# =============================================================================

if [[ -f "${MODSECURITY_INCLUDE}" ]]; then

    cp -a \
        "${MODSECURITY_INCLUDE}" \
        "${MODSECURITY_INCLUDE}.bak"

    log_ok "Backup ModSecurity include dibuat:"
    echo "    ${MODSECURITY_INCLUDE}.bak"

fi


mv -f \
    "${TEMP_INCLUDE}" \
    "${MODSECURITY_INCLUDE}"

chmod 0644 "${MODSECURITY_INCLUDE}"

log_ok "ModSecurity include berhasil dibuat:"
echo "    ${MODSECURITY_INCLUDE}"


# =============================================================================
# Nginx Global ModSecurity & Log Configuration
# =============================================================================

log_section "Nginx Global Security Configuration"


if [[ ! -f "${NGINX_MAIN_CONF}" ]]; then

    die "Nginx main configuration tidak ditemukan:

    ${NGINX_MAIN_CONF}"

fi


# -----------------------------------------------------------------------------
# Enable Global ModSecurity
# -----------------------------------------------------------------------------

if grep -Eq \
    '^[[:space:]]*modsecurity[[:space:]]+on;' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "Global ModSecurity sudah aktif."

else

    log_info "Mengaktifkan Global ModSecurity pada http {}..."

    sed -i '/^[[:space:]]*http[[:space:]]*{/a\
\
        ##\
        # BREBES-WAF / ModSecurity\
        ##\
        modsecurity on;\
        modsecurity_rules_file /etc/nginx/modsecurity_includes.conf;\
' "${NGINX_MAIN_CONF}"

    log_ok "Global ModSecurity berhasil diaktifkan."

fi


# -----------------------------------------------------------------------------
# Enable ModSecurity Rules File
# -----------------------------------------------------------------------------

if grep -Eq \
    '^[[:space:]]*modsecurity_rules_file[[:space:]]+/etc/nginx/modsecurity_includes\.conf;' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "ModSecurity rules file sudah dikonfigurasi."

else

    log_info "Menambahkan ModSecurity rules file..."

    sed -i \
        '/^[[:space:]]*modsecurity[[:space:]]\+on;/a\
        modsecurity_rules_file /etc/nginx/modsecurity_includes.conf;' \
        "${NGINX_MAIN_CONF}"

    log_ok "ModSecurity rules file berhasil dikonfigurasi."

fi


# -----------------------------------------------------------------------------
# Enable reverser log_format
# -----------------------------------------------------------------------------

if grep -Eq \
    '^[[:space:]]*log_format[[:space:]]+reverser([[:space:]]|$)' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "log_format reverser sudah tersedia."

else

    log_info "Menambahkan log_format reverser ke http {}..."

    sed -i '/^[[:space:]]*http[[:space:]]*{/a\
\
        ##\
        # BREBES Reverse Proxy Log Format\
        ##\
        log_format reverser\
          '\''$remote_addr '\''\
          '\''[$time_local] '\''\
          '\''"$request" '\''\
          '\''$status '\''\
          '\''$body_bytes_sent '\''\
          '\''"$http_referer" '\''\
          '\''"$http_user_agent" '\''\
          '\''host="$host" '\''\
          '\''xff="$http_x_forwarded_for" '\''\
          '\''rt=$request_time '\''\
          '\''urt=$upstream_response_time '\''\
          '\''upstream="$upstream_addr"'\'';\
' "${NGINX_MAIN_CONF}"

    log_ok "log_format reverser berhasil ditambahkan."

fi


# =============================================================================
# Display Global Security Configuration
# =============================================================================

echo

echo "Global ModSecurity configuration:"

grep -E \
    '^[[:space:]]*(modsecurity|modsecurity_rules_file)[[:space:]]+' \
    "${NGINX_MAIN_CONF}" \
    || true


echo

echo "reverser log format:"

grep -A 12 \
    -E '^[[:space:]]*log_format[[:space:]]+reverser' \
    "${NGINX_MAIN_CONF}" \
    || true


# =============================================================================
# Verify Generated ModSecurity Include
# =============================================================================

log_section "Verify ModSecurity Include"


if [[ ! -f "${MODSECURITY_INCLUDE}" ]]; then

    die "ModSecurity include tidak ditemukan:

    ${MODSECURITY_INCLUDE}"

fi


if [[ ! -s "${MODSECURITY_INCLUDE}" ]]; then

    die "ModSecurity include kosong:

    ${MODSECURITY_INCLUDE}"

fi


log_ok "ModSecurity include tersedia dan tidak kosong."


echo
echo "Include content:"
echo

cat "${MODSECURITY_INCLUDE}"


# =============================================================================
# Verify Effective Nginx Configuration
# =============================================================================

log_section "Effective Nginx Configuration Check"


NGINX_DUMP=""

if ! NGINX_DUMP="$(nginx -T 2>&1)"; then

    log_error "Gagal membaca effective Nginx configuration."

    echo
    echo "${NGINX_DUMP}"
    echo

    log_warn "Melakukan rollback nginx.conf..."

    if [[ -f "${CURRENT_NGINX_BACKUP_DIR}/nginx.conf" ]]; then

        cp -a \
            "${CURRENT_NGINX_BACKUP_DIR}/nginx.conf" \
            "${NGINX_MAIN_CONF}"

        log_ok "nginx.conf berhasil dipulihkan."

    fi

    exit 1

fi


if echo "${NGINX_DUMP}" | grep -Eq \
    '^[[:space:]]*modsecurity[[:space:]]+on;'; then

    log_ok "ModSecurity aktif pada effective Nginx configuration."

else

    log_error "ModSecurity tidak aktif pada effective Nginx configuration."
    exit 1

fi


if echo "${NGINX_DUMP}" | grep -Eq \
    '^[[:space:]]*modsecurity_rules_file[[:space:]]+/etc/nginx/modsecurity_includes\.conf;'; then

    log_ok "BREBES-WAF ModSecurity include aktif."

else

    log_error "BREBES-WAF ModSecurity include belum terdeteksi."
    exit 1

fi


if echo "${NGINX_DUMP}" | grep -Eq \
    '^[[:space:]]*log_format[[:space:]]+reverser([[:space:]]|$)'; then

    log_ok "log_format reverser aktif."

else

    log_error "log_format reverser belum terdeteksi."
    exit 1

fi


if echo "${NGINX_DUMP}" | grep -Eq \
    'load_module.*ngx_http_modsecurity_module'; then

    log_ok "ModSecurity Nginx module loaded."

else

    log_error "ModSecurity Nginx module tidak terdeteksi pada effective configuration."
    exit 1

fi


# =============================================================================
# Final Nginx Configuration Test
# =============================================================================

log_section "Final Nginx Configuration Test"


if nginx -t; then

    log_ok "Nginx configuration valid."

else

    log_error "Nginx configuration tidak valid."

    echo
    echo "Rollback nginx.conf..."

    if [[ -f "${CURRENT_NGINX_BACKUP_DIR}/nginx.conf" ]]; then

        cp -a \
            "${CURRENT_NGINX_BACKUP_DIR}/nginx.conf" \
            "${NGINX_MAIN_CONF}"

        log_ok "nginx.conf berhasil dipulihkan."

    fi

    exit 1

fi


# =============================================================================
# Enable Nginx Service
# =============================================================================

log_section "Nginx Service"


if systemctl is-enabled nginx >/dev/null 2>&1; then

    log_ok "Nginx enabled."

else

    log_info "Mengaktifkan Nginx..."

    systemctl enable nginx

    log_ok "Nginx enabled."

fi


# =============================================================================
# Start / Reload Nginx
# =============================================================================

if systemctl is-active nginx >/dev/null 2>&1; then

    log_info "Nginx sedang running."

    if systemctl reload nginx; then

        log_ok "Nginx berhasil di-reload."

    else

        log_error "Nginx reload gagal."

        systemctl status nginx \
            --no-pager \
            || true

        exit 1

    fi

else

    log_info "Nginx belum running."

    systemctl start nginx


    if systemctl is-active nginx >/dev/null 2>&1; then

        log_ok "Nginx berhasil dijalankan."

    else

        log_error "Nginx gagal dijalankan."

        systemctl status nginx \
            --no-pager \
            || true

        exit 1

    fi

fi


# =============================================================================
# Final Service Check
# =============================================================================

log_section "Final Service Check"


if systemctl is-active nginx >/dev/null 2>&1; then

    log_ok "Nginx: RUNNING"

else

    log_error "Nginx: NOT RUNNING"

    exit 1

fi


# =============================================================================
# Final BREBES-WAF Verification
# =============================================================================

log_section "BREBES-WAF Final Verification"


if [[ -f "${MODSECURITY_CONF}" ]]; then

    log_ok "ModSecurity configuration:"
    echo "    ${MODSECURITY_CONF}"

else

    log_error "ModSecurity configuration tidak ditemukan."

fi


if [[ -f "${CRS_LOAD_FILE}" ]]; then

    log_ok "OWASP CRS configuration:"
    echo "    ${CRS_LOAD_FILE}"

else

    log_error "OWASP CRS configuration tidak ditemukan."

fi


if [[ -f "${MODSECURITY_INCLUDE}" ]]; then

    log_ok "BREBES-WAF include:"
    echo "    ${MODSECURITY_INCLUDE}"

else

    log_error "BREBES-WAF include tidak ditemukan."

fi


RULE_COUNT=$(find "${RULES_DIR}" \
    -type f \
    -name '*.conf' \
    | wc -l)


echo
echo "BREBES-WAF Rules:"
echo "    ${RULE_COUNT} rule file(s)"


# =============================================================================
# Final Summary
# =============================================================================

log_section "BREBES-WAF Installation Summary"


echo

echo "Installation:"
echo "    Status        : SUCCESS"
echo "    Version       : 1.2.0"
echo "    Repository    : ${BREBES_WAF_HOME}"

echo

echo "Operating System:"
echo "    ${PRETTY_NAME}"

echo

echo "Ubuntu Repository:"
echo "    Main         : ${UBUNTU_MAIN_REPOSITORY}"
echo "    Security     : ${UBUNTU_SECURITY_REPOSITORY}"

echo

echo "Ubuntu Codename:"
echo "    ${UBUNTU_CODENAME}"

echo

echo "Components:"

if command_exists nginx; then
    echo "    [OK] Nginx"
else
    echo "    [FAIL] Nginx"
fi


if [[ -n "${MODSECURITY_MODULE}" ]]; then
    echo "    [OK] ModSecurity Nginx Module"
else
    echo "    [FAIL] ModSecurity Nginx Module"
fi


if [[ "${MODSECURITY_FOUND}" == "true" ]]; then
    echo "    [OK] ModSecurity v3 Library"
else
    echo "    [FAIL] ModSecurity v3 Library"
fi


if [[ "${CRS_FOUND}" == "true" ]]; then
    echo "    [OK] OWASP CRS"
else
    echo "    [FAIL] OWASP CRS"
fi


if [[ -f "${MODSECURITY_CONF}" ]]; then
    echo "    [OK] ModSecurity Configuration"
else
    echo "    [FAIL] ModSecurity Configuration"
fi


if [[ -f "${MODSECURITY_INCLUDE}" ]]; then
    echo "    [OK] BREBES-WAF Include"
else
    echo "    [FAIL] BREBES-WAF Include"
fi


if [[ -d "${RULES_DIR}" ]]; then
    echo "    [OK] BREBES-WAF Rules"
else
    echo "    [FAIL] BREBES-WAF Rules"
fi


if command_exists git; then
    echo "    [OK] Git"
else
    echo "    [FAIL] Git"
fi


if command_exists curl; then
    echo "    [OK] Curl"
else
    echo "    [FAIL] Curl"
fi


if package_installed "ca-certificates"; then
    echo "    [OK] CA Certificates"
else
    echo "    [FAIL] CA Certificates"
fi


echo

echo "Nginx Security Configuration:"
echo "    [OK] ModSecurity: ON"
echo "    [OK] BREBES-WAF include"
echo "    [OK] log_format reverser"

echo

echo "Configuration Files:"
echo "    ModSecurity : ${MODSECURITY_CONF}"
echo "    CRS         : ${CRS_LOAD_FILE}"
echo "    WAF Include : ${MODSECURITY_INCLUDE}"

echo

echo "Backup:"
echo "    APT         : ${CURRENT_BACKUP_DIR}"
echo "    Nginx       : ${CURRENT_NGINX_BACKUP_DIR}"

echo

echo "============================================================"
echo " BREBES-WAF First-Time Installation Completed"
echo "============================================================"

echo

log_ok "BREBES-WAF berhasil diinstall dan dikonfigurasi."

echo

echo "Next step:"
echo
echo "    Gunakan scripts/deploy.sh untuk deployment/update rules berikutnya."
echo