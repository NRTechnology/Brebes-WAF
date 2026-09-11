#!/bin/bash

# =============================================================================
# BREBES-WAF
# Dependency Check & Installation Script
#
# File    : scripts/check-dependencies.sh
# Version : 1.1.0
# Author  : Brebes CSIRT
#
# Purpose:
#   Check and install required software for BREBES-WAF.
#
# Supported:
#   Ubuntu 22.04+
#
# Repository:
#   Ubuntu Official Main Repository
#
# Components:
#   - Nginx
#   - ModSecurity v3
#   - Nginx ModSecurity Connector
#   - Nginx NDK module
#   - OWASP CRS
#   - Git
#   - Curl
#   - CA Certificates
#   - Unzip
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

BREBES_WAF_HOME="/opt/Brebes-WAF"

UBUNTU_MAIN_REPOSITORY="http://archive.ubuntu.com/ubuntu"
UBUNTU_SECURITY_REPOSITORY="http://security.ubuntu.com/ubuntu"

APT_BACKUP_DIR="/root/brebes-waf-apt-backup"

MODSECURITY_MODULE_PACKAGE="libnginx-mod-http-modsecurity"
NGINX_NDK_PACKAGE="libnginx-mod-http-ndk"
CRS_PACKAGE="modsecurity-crs"

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
# Operating System Check
# =============================================================================

log_section "Operating System Check"

if [[ ! -f /etc/os-release ]]; then

    log_error "/etc/os-release tidak ditemukan."
    exit 1

fi

source /etc/os-release

echo "OS            : ${PRETTY_NAME:-unknown}"
echo "ID            : ${ID:-unknown}"
echo "Version       : ${VERSION_ID:-unknown}"
echo "Architecture  : $(dpkg --print-architecture)"

if [[ "${ID:-}" != "ubuntu" ]]; then

    log_error "Operating system bukan Ubuntu."
    log_error "BREBES-WAF dependency script ini hanya mendukung Ubuntu."

    exit 1

fi

UBUNTU_CODENAME="${VERSION_CODENAME:-}"

if [[ -z "${UBUNTU_CODENAME}" ]] && command_exists lsb_release; then
    UBUNTU_CODENAME=$(lsb_release -sc)
fi

if [[ -z "${UBUNTU_CODENAME}" ]]; then

    log_error "Ubuntu codename tidak dapat dideteksi."
    exit 1

fi

echo "Codename      : ${UBUNTU_CODENAME}"

# =============================================================================
# Ubuntu Version Check
# =============================================================================

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

    log_error "apt-get tidak ditemukan."
    exit 1

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
# Detect Ubuntu Repository Configuration
# =============================================================================

log_section "Ubuntu Repository Configuration"

UBUNTU_SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"

# -------------------------------------------------------------------------
# Ubuntu 24.04+ / Deb822 format
# -------------------------------------------------------------------------

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

    # ---------------------------------------------------------------------
    # Traditional sources.list
    # ---------------------------------------------------------------------

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

            # Do not modify ubuntu.sources itself.
            if [[ "${SOURCE_FILE}" != "/etc/apt/sources.list.d/ubuntu.list" ]]; then

                BACKUP_FILE="${SOURCE_FILE}.brebes-waf-backup"

                cp -a "${SOURCE_FILE}" "${BACKUP_FILE}"

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
# Check Required Package Availability
# =============================================================================

log_section "Package Availability Check"

# -------------------------------------------------------------------------
# Detect ModSecurity library package
# -------------------------------------------------------------------------

MODSECURITY_LIBRARY_PACKAGE=""

if apt-cache show libmodsecurity3 >/dev/null 2>&1; then

    MODSECURITY_LIBRARY_PACKAGE="libmodsecurity3"

elif apt-cache show libmodsecurity3t64 >/dev/null 2>&1; then

    MODSECURITY_LIBRARY_PACKAGE="libmodsecurity3t64"

else

    log_error "Package ModSecurity v3 tidak tersedia pada repository."
    exit 1

fi

log_ok "ModSecurity library package:"
echo "    ${MODSECURITY_LIBRARY_PACKAGE}"

# -------------------------------------------------------------------------
# Detect ModSecurity development package
# -------------------------------------------------------------------------

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
# Package Check
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

    log_error "Nginx tidak ditemukan setelah installation."
    exit 1

fi

# =============================================================================
# Nginx Service
# =============================================================================

log_section "Nginx Service"

if systemctl is-enabled nginx >/dev/null 2>&1; then

    log_ok "Nginx enabled."

else

    log_info "Mengaktifkan Nginx..."

    systemctl enable nginx

    log_ok "Nginx enabled."

fi

if systemctl is-active nginx >/dev/null 2>&1; then

    log_ok "Nginx sedang running."

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

    log_error "ModSecurity v3 library tidak ditemukan."
    exit 1

fi

# =============================================================================
# ModSecurity Nginx Module
# =============================================================================

log_section "Nginx ModSecurity Module Check"

MODSECURITY_MODULE=""

if [[ -f /usr/lib/nginx/modules/ngx_http_modsecurity_module.so ]]; then

    MODSECURITY_MODULE="/usr/lib/nginx/modules/ngx_http_modsecurity_module.so"

    log_ok "ModSecurity Nginx module ditemukan:"
    echo "    ${MODSECURITY_MODULE}"

else

    log_error "ngx_http_modsecurity_module.so tidak ditemukan."
    exit 1

fi

# =============================================================================
# Nginx NDK Module
# =============================================================================

log_section "Nginx NDK Module Check"

if [[ -f /usr/lib/nginx/modules/ndk_http_module.so ]]; then

    log_ok "Nginx NDK module ditemukan:"
    echo "    /usr/lib/nginx/modules/ndk_http_module.so"

else

    log_warn "Nginx NDK module tidak ditemukan:"
    echo "    /usr/lib/nginx/modules/ndk_http_module.so"

fi

# =============================================================================
# ModSecurity Module Configuration
# =============================================================================

log_section "ModSecurity Module Configuration"

if [[ -f /etc/nginx/modules-enabled/50-mod-http-modsecurity.conf ]]; then

    log_ok "ModSecurity module configuration tersedia:"
    echo "    /etc/nginx/modules-enabled/50-mod-http-modsecurity.conf"

else

    if [[ -f /etc/nginx/modules-available/mod-http-modsecurity.conf ]]; then

        log_info "Mengaktifkan ModSecurity Nginx module..."

        ln -sf \
            /etc/nginx/modules-available/mod-http-modsecurity.conf \
            /etc/nginx/modules-enabled/50-mod-http-modsecurity.conf

        log_ok "ModSecurity module configuration diaktifkan."

    else

        log_warn "ModSecurity module configuration tidak ditemukan."

    fi

fi

# =============================================================================
# Nginx Global ModSecurity & Reverser Log Configuration
# =============================================================================

log_section "Nginx Global Security Configuration"

NGINX_MAIN_CONF="/etc/nginx/nginx.conf"

if [[ ! -f "${NGINX_MAIN_CONF}" ]]; then
    log_error "Nginx main configuration tidak ditemukan:"
    echo "    ${NGINX_MAIN_CONF}"
    exit 1
fi

# -------------------------------------------------------------------------
# Backup nginx.conf before modification
# -------------------------------------------------------------------------

NGINX_BACKUP_DIR="${APT_BACKUP_DIR}/${BACKUP_TIMESTAMP}"

mkdir -p "${NGINX_BACKUP_DIR}"

cp -a \
    "${NGINX_MAIN_CONF}" \
    "${NGINX_BACKUP_DIR}/nginx.conf"

log_ok "Backup nginx.conf dibuat:"
echo "    ${NGINX_BACKUP_DIR}/nginx.conf"

# -------------------------------------------------------------------------
# Check / Enable ModSecurity
# -------------------------------------------------------------------------

if grep -Eq '^[[:space:]]*modsecurity[[:space:]]+on;' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "Global ModSecurity sudah aktif."

else

    log_warn "Global ModSecurity belum aktif."
    log_info "Mengaktifkan ModSecurity pada http {}..."

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

# -------------------------------------------------------------------------
# Check ModSecurity Rules File
# -------------------------------------------------------------------------

if grep -Eq \
    '^[[:space:]]*modsecurity_rules_file[[:space:]]+/etc/nginx/modsecurity_includes\.conf;' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "ModSecurity rules file sudah dikonfigurasi."

else

    log_warn "ModSecurity rules file belum dikonfigurasi."

    if grep -Eq \
        '^[[:space:]]*modsecurity[[:space:]]+on;' \
        "${NGINX_MAIN_CONF}"; then

        sed -i '/^[[:space:]]*modsecurity[[:space:]]\+on;/a\
        modsecurity_rules_file /etc/nginx/modsecurity_includes.conf;' \
            "${NGINX_MAIN_CONF}"

        log_ok "ModSecurity rules file berhasil dikonfigurasi."

    fi

fi

# -------------------------------------------------------------------------
# Check reverser log_format
# -------------------------------------------------------------------------

if grep -Eq \
    '^[[:space:]]*log_format[[:space:]]+reverser([[:space:]]|$)' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "log_format reverser sudah tersedia."

else

    log_warn "log_format reverser belum tersedia."
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

# -------------------------------------------------------------------------
# Display Global Security Configuration
# -------------------------------------------------------------------------

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
# ModSecurity Configuration
# =============================================================================

log_section "ModSecurity Configuration"

if [[ -f /etc/nginx/modsecurity.conf ]]; then

    log_ok "ModSecurity configuration ditemukan:"
    echo "    /etc/nginx/modsecurity.conf"

else

    log_warn "ModSecurity configuration belum tersedia:"
    echo "    /etc/nginx/modsecurity.conf"

    log_info "File konfigurasi akan disiapkan oleh deploy-first-time.sh."

fi

# =============================================================================
# BREBES-WAF Include Configuration
# =============================================================================

if [[ -f /etc/nginx/modsecurity_includes.conf ]]; then

    log_ok "BREBES-WAF ModSecurity include ditemukan:"
    echo "    /etc/nginx/modsecurity_includes.conf"

else

    log_info "BREBES-WAF ModSecurity include belum tersedia."

fi

# =============================================================================
# OWASP CRS Check
# =============================================================================

log_section "OWASP CRS Check"

CRS_FOUND=false

if package_installed "modsecurity-crs"; then

    CRS_VERSION=$(dpkg-query \
        -W \
        -f='${Version}' \
        modsecurity-crs \
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

        log_ok "Potential CRS directory ditemukan:"
        echo "    ${CRS_PATH}"

        CRS_FOUND=true

    fi

done

if [[ "${CRS_FOUND}" != "true" ]]; then

    log_error "OWASP CRS tidak ditemukan."
    exit 1

else

    log_ok "OWASP CRS tersedia."

fi

# =============================================================================
# Git Check
# =============================================================================

log_section "Git Check"

if command_exists git; then

    log_ok "$(git --version)"

else

    log_error "Git tidak ditemukan."
    exit 1

fi

# =============================================================================
# Curl Check
# =============================================================================

log_section "Curl Check"

if command_exists curl; then

    CURL_VERSION=$(curl --version | head -n 1)

    log_ok "${CURL_VERSION}"

else

    log_error "curl tidak ditemukan."
    exit 1

fi

# =============================================================================
# CA Certificates Check
# =============================================================================

log_section "CA Certificates Check"

if package_installed "ca-certificates"; then

    log_ok "ca-certificates installed."

else

    log_error "ca-certificates tidak ditemukan."
    exit 1

fi

# =============================================================================
# BREBES-WAF Directory Check
# =============================================================================

log_section "BREBES-WAF Directory Check"

if [[ -d "${BREBES_WAF_HOME}" ]]; then

    log_ok "BREBES-WAF directory ditemukan:"
    echo "    ${BREBES_WAF_HOME}"

else

    log_warn "BREBES-WAF directory belum tersedia:"
    echo "    ${BREBES_WAF_HOME}"

fi

# =============================================================================
# Verify Effective Nginx Configuration
# =============================================================================

log_section "Effective Nginx Configuration Check"

if ! NGINX_DUMP="$(nginx -T 2>&1)"; then
    log_error "Gagal membaca effective Nginx configuration."
    echo
    echo "${NGINX_DUMP}"
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

    log_warn "BREBES-WAF ModSecurity include belum terdeteksi."

fi

if echo "${NGINX_DUMP}" | grep -Eq \
    '^[[:space:]]*log_format[[:space:]]+reverser([[:space:]]|$)'; then

    log_ok "log_format reverser aktif."

else

    log_warn "log_format reverser belum terdeteksi."

fi

# =============================================================================
# Final Nginx Configuration Test
# =============================================================================

log_section "Final Nginx Configuration Test"

if nginx -t; then

    log_ok "Nginx configuration valid."

else

    log_error "Nginx configuration tidak valid."
    exit 1

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
# Final Summary
# =============================================================================

log_section "BREBES-WAF Dependency Summary"

echo

echo "Operating System:"
echo "    ${PRETTY_NAME}"

echo

echo "Ubuntu Repository:"
echo "    Main     : ${UBUNTU_MAIN_REPOSITORY}"
echo "    Security : ${UBUNTU_SECURITY_REPOSITORY}"

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
echo "APT Repository Backup:"
echo "    ${CURRENT_BACKUP_DIR}"

echo

echo "============================================================"
echo " BREBES-WAF Dependency Check Completed"
echo "============================================================"

echo

log_ok "System siap untuk tahap konfigurasi BREBES-WAF."

echo
echo "Next step:"
echo
echo "    ./scripts/deploy-first-time.sh"
echo