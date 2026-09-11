#!/bin/bash

# =============================================================================
# BREBES-WAF
# Dependency Check & Installation Script
#
# File    : scripts/check-dependencies.sh
# Version : 1.0.0
# Author  : Brebes CSIRT
#
# Purpose:
#   Check and install required software for BREBES-WAF.
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
#   - Git
#   - Curl
#   - CA Certificates
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

BREBES_WAF_HOME="/opt/Brebes-WAF"

MODSECURITY_MODULE_PACKAGE="libnginx-mod-http-modsecurity"
MODSECURITY_LIBRARY_PACKAGE="libmodsecurity3"
MODSECURITY_DEV_PACKAGE="libmodsecurity-dev"
NGINX_NDK_PACKAGE="libnginx-mod-http-ndk"
CRS_PACKAGE="modsecurity-crs"

REQUIRED_PACKAGES=(
    nginx
    curl
    ca-certificates
    git
    unzip
    "$MODSECURITY_MODULE_PACKAGE"
    "$MODSECURITY_LIBRARY_PACKAGE"
    "$MODSECURITY_DEV_PACKAGE"
    "$NGINX_NDK_PACKAGE"
    "$CRS_PACKAGE"
)

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
# OS Check
# =============================================================================

log_section "Operating System Check"

if [[ ! -f /etc/os-release ]]; then
    log_error "/etc/os-release tidak ditemukan."
    exit 1
fi

source /etc/os-release

echo "OS          : ${PRETTY_NAME:-unknown}"
echo "ID          : ${ID:-unknown}"
echo "Version     : ${VERSION_ID:-unknown}"
echo "Architecture: $(dpkg --print-architecture)"

if [[ "${ID}" != "ubuntu" ]]; then
    log_warn "Script ini dibuat khusus untuk Ubuntu."
    log_warn "Sistem terdeteksi: ${PRETTY_NAME:-unknown}"
    echo
    read -r -p "Tetap lanjutkan? [y/N]: " ANSWER

    if [[ ! "${ANSWER}" =~ ^[Yy]$ ]]; then
        log_info "Installation dibatalkan."
        exit 0
    fi
fi

# =============================================================================
# APT Check
# =============================================================================

log_section "APT Check"

if ! command_exists apt-get; then
    log_error "apt-get tidak ditemukan."
    log_error "Script ini membutuhkan sistem berbasis Debian/Ubuntu."
    exit 1
fi

log_ok "apt-get tersedia."

# =============================================================================
# Repository Check
# =============================================================================

log_section "APT Repository"

log_info "Updating package index..."

apt-get update

log_ok "APT package index berhasil diperbarui."

# =============================================================================
# Universe Repository
# =============================================================================

log_info "Memastikan repository Universe tersedia..."

if command_exists add-apt-repository; then

    if grep -RqsE '^[[:space:]]*deb .* universe' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        log_ok "Repository Universe tersedia."
    else
        log_info "Mengaktifkan repository Universe..."

        apt-get install -y software-properties-common

        add-apt-repository -y universe

        apt-get update

        log_ok "Repository Universe berhasil diaktifkan."
    fi

else

    log_warn "add-apt-repository belum tersedia."
    log_info "Installing software-properties-common..."

    apt-get install -y software-properties-common

    add-apt-repository -y universe

    apt-get update

    log_ok "Repository Universe berhasil diaktifkan."

fi

# =============================================================================
# Package Check
# =============================================================================

log_section "Package Dependency Check"

MISSING_PACKAGES=()

for PACKAGE in "${REQUIRED_PACKAGES[@]}"
do
    if package_installed "$PACKAGE"; then
        VERSION=$(dpkg-query -W -f='${Version}' "$PACKAGE" 2>/dev/null || echo "unknown")

        log_ok "$PACKAGE [$VERSION]"
    else
        log_warn "$PACKAGE belum terinstall."
        MISSING_PACKAGES+=("$PACKAGE")
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
        echo "    - $PACKAGE"
    done

    echo

    apt-get install -y "${MISSING_PACKAGES[@]}"

    log_ok "Semua dependency yang diperlukan berhasil diproses."

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

    log_error "Nginx tidak ditemukan setelah proses installation."
    exit 1

fi

# =============================================================================
# Nginx Service Check
# =============================================================================

log_section "Nginx Service"

if systemctl is-enabled nginx >/dev/null 2>&1; then
    log_ok "Nginx enabled."
else
    log_info "Mengaktifkan Nginx saat boot..."

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
        systemctl status nginx --no-pager || true
        exit 1
    fi

fi

# =============================================================================
# Nginx Configuration Test
# =============================================================================

log_section "Nginx Configuration Test"

if nginx -t; then
    log_ok "Nginx configuration valid."
else
    log_error "Nginx configuration tidak valid."
    exit 1
fi

# =============================================================================
# ModSecurity Library Check
# =============================================================================

log_section "ModSecurity v3 Check"

MODSECURITY_FOUND=false

if ldconfig -p 2>/dev/null | grep -q "libmodsecurity"; then

    log_ok "ModSecurity v3 library ditemukan."

    ldconfig -p 2>/dev/null | grep "libmodsecurity" || true

    MODSECURITY_FOUND=true

fi

if package_installed "libmodsecurity3"; then

    VERSION=$(dpkg-query -W -f='${Version}' libmodsecurity3 2>/dev/null || echo "unknown")

    log_ok "libmodsecurity3 installed."
    echo "    Version: ${VERSION}"

    MODSECURITY_FOUND=true

fi

if package_installed "libmodsecurity3t64"; then

    VERSION=$(dpkg-query -W -f='${Version}' libmodsecurity3t64 2>/dev/null || echo "unknown")

    log_ok "libmodsecurity3t64 installed."
    echo "    Version: ${VERSION}"

    MODSECURITY_FOUND=true

fi

if [[ "${MODSECURITY_FOUND}" != "true" ]]; then
    log_error "ModSecurity v3 library tidak ditemukan."
    exit 1
fi

# =============================================================================
# ModSecurity Nginx Module Check
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
# Nginx Module Configuration Check
# =============================================================================

log_section "Nginx Module Configuration"

if [[ -f /etc/nginx/modules-enabled/50-mod-http-modsecurity.conf ]]; then

    log_ok "ModSecurity Nginx module configuration tersedia:"
    echo "    /etc/nginx/modules-enabled/50-mod-http-modsecurity.conf"

else

    log_warn "ModSecurity module configuration tidak ditemukan."

    if [[ -f /etc/nginx/modules-available/mod-http-modsecurity.conf ]]; then

        log_info "Membuat symlink module configuration..."

        ln -sf \
            /etc/nginx/modules-available/mod-http-modsecurity.conf \
            /etc/nginx/modules-enabled/50-mod-http-modsecurity.conf

        log_ok "ModSecurity module configuration diaktifkan."

    else

        log_error "Module configuration ModSecurity tidak ditemukan."
        exit 1

    fi

fi

# =============================================================================
# ModSecurity Directive Check
# =============================================================================

log_section "ModSecurity Directive Check"

if nginx -T 2>/dev/null | grep -q "modsecurity_module"; then

    log_ok "ModSecurity module dikenali oleh Nginx."

else

    log_warn "ModSecurity module belum terdeteksi melalui nginx -T."

fi

# =============================================================================
# ModSecurity Configuration Check
# =============================================================================

log_section "ModSecurity Configuration"

if [[ -f /etc/nginx/modsecurity.conf ]]; then

    log_ok "ModSecurity configuration ditemukan:"
    echo "    /etc/nginx/modsecurity.conf"

else

    log_warn "ModSecurity configuration tidak ditemukan."

fi

if [[ -f /etc/nginx/modsecurity_includes.conf ]]; then

    log_ok "ModSecurity include configuration ditemukan:"
    echo "    /etc/nginx/modsecurity_includes.conf"

else

    log_info "modsecurity_includes.conf belum tersedia."

    if [[ -f /usr/share/nginx/docs/modsecurity/modsecurity_includes.conf ]]; then

        log_info "Template ModSecurity include tersedia dari package."

    fi

fi

# =============================================================================
# OWASP CRS Check
# =============================================================================

log_section "OWASP CRS Check"

CRS_FOUND=false

if package_installed "modsecurity-crs"; then

    CRS_VERSION=$(dpkg-query -W -f='${Version}' modsecurity-crs 2>/dev/null || echo "unknown")

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
    if [[ -d "$CRS_PATH" ]]; then

        log_ok "Potential CRS directory ditemukan:"
        echo "    $CRS_PATH"

        CRS_FOUND=true

    fi
done

if [[ "${CRS_FOUND}" != "true" ]]; then
    log_warn "OWASP CRS tidak terdeteksi."
else
    log_ok "OWASP CRS tersedia."
fi

# =============================================================================
# Git Check
# =============================================================================

log_section "Git Check"

if command_exists git; then

    GIT_VERSION=$(git --version)

    log_ok "$GIT_VERSION"

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

    log_ok "$CURL_VERSION"

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

if [[ -d "$BREBES_WAF_HOME" ]]; then

    log_ok "BREBES-WAF directory ditemukan:"
    echo "    $BREBES_WAF_HOME"

else

    log_warn "BREBES-WAF directory belum tersedia:"
    echo "    $BREBES_WAF_HOME"

fi

# =============================================================================
# Final Nginx Test
# =============================================================================

log_section "Final Nginx Test"

if nginx -t; then

    log_ok "Final Nginx configuration test berhasil."

else

    log_error "Final Nginx configuration test gagal."
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
# Summary
# =============================================================================

log_section "BREBES-WAF Dependency Summary"

echo
echo "Component:"
echo

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
    echo "    [WARN] OWASP CRS"
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
echo "============================================================"
echo " BREBES-WAF Dependency Check Completed"
echo "============================================================"
echo

log_ok "System siap untuk tahap konfigurasi BREBES-WAF."

echo
echo "Next step:"
echo
echo "    ./scripts/deployfirsttime.sh"
echo