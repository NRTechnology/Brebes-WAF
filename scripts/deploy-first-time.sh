#!/bin/bash

# =============================================================================
# BREBES-WAF
# First-Time Installation & Deployment Script
#
# File    : scripts/deploy-first-time.sh
# Version : 1.3.2
# Author  : Brebes CSIRT
#
# Purpose:
#   First-time installation, dependency setup, ModSecurity configuration,
#   OWASP CRS configuration, BREBES-WAF rule deployment and Nginx activation.
#
# Supported:
#   Ubuntu 26.04 (primary)
#   Ubuntu 24.04
#   Ubuntu 22.04
#
# IMPORTANT:
#   - ModSecurity configuration follows the monitoredreverser baseline.
#   - SecResponseBodyAccess is ON with MIME and 1 MiB limits for performance.
#   - Audit logging uses Concurrent format, matching monitoredreverser.
#   - Existing configuration is backed up BEFORE modification.
#   - Original configuration backup:
#       /opt/Brebes-WAF/backup/orig/<YYYYMMDD-HHMMSS>/
#
# After first installation:
#   ./scripts/deploy.sh
#
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# Configuration
# =============================================================================

BREBES_WAF_HOME="/opt/Brebes-WAF"

NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SNIPPETS="/etc/nginx/snippets"
NGINX_CONF_D="/etc/nginx/conf.d"
NGINX_MODULES_ENABLED="/etc/nginx/modules-enabled"
NGINX_MODULES_AVAILABLE="/etc/nginx/modules-available"

MODSECURITY_CONF="/etc/nginx/modsecurity.conf"
MODSECURITY_INCLUDE="/etc/nginx/modsecurity_includes.conf"
MODSECURITY_DIR="/etc/nginx/modsecurity"

CRS_LOAD_FILE="${MODSECURITY_DIR}/crs-load.conf"
CRS_REPOSITORY_FILE="${BREBES_WAF_HOME}/nginx/modsecurity/crs-load.conf"

RULES_DIR="${BREBES_WAF_HOME}/rules"

# Ubuntu repositories
UBUNTU_MAIN_REPOSITORY="http://archive.ubuntu.com/ubuntu"
UBUNTU_SECURITY_REPOSITORY="http://security.ubuntu.com/ubuntu"

# Original configuration backup
ORIGINAL_BACKUP_ROOT="${BREBES_WAF_HOME}/backup/orig"
BACKUP_TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
CURRENT_BACKUP_DIR="${ORIGINAL_BACKUP_ROOT}/${BACKUP_TIMESTAMP}"

# ModSecurity runtime/logging
MODSECURITY_AUDIT_DIR="/var/log/nginx/modsecurity"
MODSECURITY_DEBUG_LOG="${MODSECURITY_AUDIT_DIR}/debug.log"

# Match monitoredreverser Concurrent audit configuration
MODSECURITY_AUDIT_STORAGE_DIR="${MODSECURITY_AUDIT_DIR}"

MODSECURITY_MODULE_PACKAGE="libnginx-mod-http-modsecurity"
NGINX_NDK_PACKAGE="libnginx-mod-http-ndk"
CRS_PACKAGE="modsecurity-crs"

MODSECURITY_MODULE_PATH="/usr/lib/nginx/modules/ngx_http_modsecurity_module.so"
NDK_MODULE_PATH="/usr/lib/nginx/modules/ndk_http_module.so"

MODSECURITY_MODULE_CONFIG="/etc/nginx/modules-enabled/50-mod-http-modsecurity.conf"
MODSECURITY_MODULE_AVAILABLE="/etc/nginx/modules-available/mod-http-modsecurity.conf"

# Baseline values copied from monitoredreverser
REQUEST_BODY_LIMIT="134217728"
REQUEST_BODY_NO_FILES_LIMIT="131072"
JSON_DEPTH_LIMIT="512"
ARGUMENTS_LIMIT="1000"
PCRE_MATCH_LIMIT="100000"
PCRE_RECURSION_LIMIT="100000"

# Response-body inspection is enabled with conservative limits.
# Only selected MIME types are inspected and the inspection is limited to 1 MiB.
RESPONSE_BODY_ACCESS="On"
RESPONSE_BODY_MIME_TYPES="text/plain text/html text/xml application/json"
RESPONSE_BODY_LIMIT="1048576"
RESPONSE_BODY_LIMIT_ACTION="ProcessPartial"

# monitoredreverser audit baseline
AUDIT_ENGINE="RelevantOnly"
AUDIT_RELEVANT_STATUS='^(?:5|4(?!04))'
AUDIT_PARTS="ABCDEFHIJZ"
AUDIT_TYPE="Concurrent"

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

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

log_section() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

die() {
    log_error "$*"
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null |
        grep -q "install ok installed"
}

file_backup() {
    local src="$1"
    local relative="$2"

    if [[ -e "$src" ]]; then
        mkdir -p "${CURRENT_BACKUP_DIR}/$(dirname "$relative")"
        cp -a "$src" "${CURRENT_BACKUP_DIR}/${relative}"
        log_ok "Backup: ${src}"
    fi
}

rollback_nginx_conf() {
    if [[ -f "${CURRENT_BACKUP_DIR}/etc/nginx/nginx.conf" ]]; then
        cp -a \
            "${CURRENT_BACKUP_DIR}/etc/nginx/nginx.conf" \
            "${NGINX_MAIN_CONF}"
        log_ok "nginx.conf dipulihkan dari backup."
    fi
}

on_error() {
    local exit_code=$?
    log_error "Deployment berhenti pada line ${BASH_LINENO[0]:-unknown} dengan exit code ${exit_code}."
    log_warn "Original configuration backup tersedia di:"
    echo "    ${CURRENT_BACKUP_DIR}"
    exit "${exit_code}"
}

trap on_error ERR

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

[[ -d "${BREBES_WAF_HOME}" ]] ||
    die "BREBES-WAF repository tidak ditemukan: ${BREBES_WAF_HOME}"

[[ -d "${RULES_DIR}" ]] ||
    die "BREBES-WAF rules directory tidak ditemukan: ${RULES_DIR}"

log_ok "Repository ditemukan:"
echo "    ${BREBES_WAF_HOME}"

log_ok "Rules directory ditemukan:"
echo "    ${RULES_DIR}"

if command_exists git && [[ -d "${BREBES_WAF_HOME}/.git" ]]; then
    echo
    echo "Git:"
    git -C "${BREBES_WAF_HOME}" rev-parse --show-toplevel 2>/dev/null || true
    git -C "${BREBES_WAF_HOME}" log -1 --oneline 2>/dev/null || true
fi

# =============================================================================
# Operating System Check
# =============================================================================

log_section "Operating System Check"

[[ -f /etc/os-release ]] ||
    die "/etc/os-release tidak ditemukan."

# shellcheck disable=SC1091
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] ||
    die "Operating system bukan Ubuntu."

UBUNTU_CODENAME="${VERSION_CODENAME:-}"

if [[ -z "${UBUNTU_CODENAME}" ]] && command_exists lsb_release; then
    UBUNTU_CODENAME="$(lsb_release -sc)"
fi

[[ -n "${UBUNTU_CODENAME}" ]] ||
    die "Ubuntu codename tidak dapat dideteksi."

echo "OS            : ${PRETTY_NAME:-unknown}"
echo "ID            : ${ID:-unknown}"
echo "Version       : ${VERSION_ID:-unknown}"
echo "Codename      : ${UBUNTU_CODENAME}"
echo "Architecture  : $(dpkg --print-architecture)"

# Ubuntu 26.04 is the primary BREBES-WAF baseline.
case "${UBUNTU_CODENAME}" in
    resolute)
        log_ok "Ubuntu 26.04 Resolute detected (PRIMARY BASELINE)."
        ;;

    noble)
        log_warn "Ubuntu 24.04 Noble detected."
        log_warn "BREBES-WAF primary baseline is Ubuntu 26.04."
        ;;

    jammy)
        log_warn "Ubuntu 22.04 Jammy detected."
        log_warn "BREBES-WAF primary baseline is Ubuntu 26.04."
        ;;

    *)
        die "Ubuntu version/codename tidak didukung: ${UBUNTU_CODENAME}"
        ;;
esac

# =============================================================================
# APT Check
# =============================================================================

log_section "APT Check"

command_exists apt-get ||
    die "apt-get tidak ditemukan."

log_ok "apt-get tersedia."

# =============================================================================
# Original Configuration Backup
# =============================================================================

log_section "Original Configuration Backup"

mkdir -p "${CURRENT_BACKUP_DIR}"

log_info "Backup konfigurasi existing ke:"
echo "    ${CURRENT_BACKUP_DIR}"
echo

# Nginx
file_backup "${NGINX_MAIN_CONF}" "etc/nginx/nginx.conf"
file_backup "${NGINX_MODULES_ENABLED}" "etc/nginx/modules-enabled"
file_backup "${NGINX_MODULES_AVAILABLE}" "etc/nginx/modules-available"
file_backup "${NGINX_SITES_ENABLED}" "etc/nginx/sites-enabled"
file_backup "${NGINX_SITES_AVAILABLE}" "etc/nginx/sites-available"
file_backup "${NGINX_SNIPPETS}" "etc/nginx/snippets"
file_backup "${NGINX_CONF_D}" "etc/nginx/conf.d"

# ModSecurity
file_backup "${MODSECURITY_CONF}" "etc/nginx/modsecurity.conf"
file_backup "${MODSECURITY_INCLUDE}" "etc/nginx/modsecurity_includes.conf"
file_backup "${MODSECURITY_DIR}" "etc/nginx/modsecurity"

# APT
file_backup "/etc/apt/sources.list" "etc/apt/sources.list"
file_backup "/etc/apt/sources.list.d" "etc/apt/sources.list.d"

# ModSecurity runtime configuration if present
file_backup "/etc/modsecurity" "etc/modsecurity"
file_backup "/etc/modsecurity-crs" "etc/modsecurity-crs"

{
    echo "BREBES-WAF original configuration backup"
    echo "Timestamp : ${BACKUP_TIMESTAMP}"
    echo "Hostname  : $(hostname -f 2>/dev/null || hostname)"
    echo "OS        : ${PRETTY_NAME:-unknown}"
    echo "Codename  : ${UBUNTU_CODENAME}"
    echo "Version   : ${VERSION_ID:-unknown}"
    echo "Script    : ${0}"
} > "${CURRENT_BACKUP_DIR}/BACKUP-INFO.txt"

chmod 0700 "${CURRENT_BACKUP_DIR}"

log_ok "Original configuration backup selesai."

# =============================================================================
# Ubuntu Repository Configuration
# =============================================================================

log_section "Ubuntu Repository Configuration"

UBUNTU_SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"

if [[ -f "${UBUNTU_SOURCES_FILE}" ]]; then

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

    log_ok "Ubuntu Deb822 repository dikonfigurasi."

else

    cat > /etc/apt/sources.list <<EOF
deb ${UBUNTU_MAIN_REPOSITORY} ${UBUNTU_CODENAME} main restricted universe multiverse
deb ${UBUNTU_MAIN_REPOSITORY} ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb ${UBUNTU_MAIN_REPOSITORY} ${UBUNTU_CODENAME}-backports main restricted universe multiverse
deb ${UBUNTU_SECURITY_REPOSITORY} ${UBUNTU_CODENAME}-security main restricted universe multiverse
EOF

    log_ok "Ubuntu traditional sources.list dikonfigurasi."

fi

echo
echo "Active BREBES-WAF Ubuntu repository:"
echo "    Main     : ${UBUNTU_MAIN_REPOSITORY}"
echo "    Security : ${UBUNTU_SECURITY_REPOSITORY}"

# =============================================================================
# APT Update
# =============================================================================

log_section "APT Update"

apt-get update

log_ok "APT package index berhasil diperbarui."

# =============================================================================
# Detect ModSecurity Packages
# =============================================================================

log_section "ModSecurity Package Detection"

MODSECURITY_LIBRARY_PACKAGE=""

# Ubuntu 26.04 may use the t64 package naming depending on repository state.
if apt-cache show libmodsecurity3t64 >/dev/null 2>&1; then
    MODSECURITY_LIBRARY_PACKAGE="libmodsecurity3t64"
elif apt-cache show libmodsecurity3 >/dev/null 2>&1; then
    MODSECURITY_LIBRARY_PACKAGE="libmodsecurity3"
else
    die "Package ModSecurity v3 tidak tersedia pada repository."
fi

MODSECURITY_DEV_PACKAGE=""

if apt-cache show libmodsecurity-dev >/dev/null 2>&1; then
    MODSECURITY_DEV_PACKAGE="libmodsecurity-dev"
fi

log_ok "ModSecurity library package:"
echo "    ${MODSECURITY_LIBRARY_PACKAGE}"

if [[ -n "${MODSECURITY_DEV_PACKAGE}" ]]; then
    log_ok "ModSecurity development package:"
    echo "    ${MODSECURITY_DEV_PACKAGE}"
else
    log_warn "libmodsecurity-dev tidak tersedia. Tidak wajib untuk runtime."
fi

# =============================================================================
# Required Packages
# =============================================================================

log_section "Package Dependency Check"

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

MISSING_PACKAGES=()

for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
    if package_installed "${PACKAGE}"; then
        VERSION="$(dpkg-query -W -f='${Version}' "${PACKAGE}" 2>/dev/null || echo unknown)"
        log_ok "${PACKAGE} [${VERSION}]"
    else
        log_warn "${PACKAGE} belum terinstall."
        MISSING_PACKAGES+=("${PACKAGE}")
    fi
done

if [[ "${#MISSING_PACKAGES[@]}" -gt 0 ]]; then
    log_section "Installing Missing Packages"

    echo "Package yang akan diinstall:"
    printf '    - %s\n' "${MISSING_PACKAGES[@]}"
    echo

    apt-get install -y "${MISSING_PACKAGES[@]}"

    log_ok "Missing packages berhasil diinstall."
else
    log_ok "Semua package dependency sudah tersedia."
fi

# =============================================================================
# Nginx Check
# =============================================================================

log_section "Nginx Check"

command_exists nginx ||
    die "Nginx tidak ditemukan setelah installation."

NGINX_VERSION="$(nginx -v 2>&1 | sed 's/^nginx version: //')"

log_ok "Nginx tersedia."
echo "    Version: ${NGINX_VERSION}"

# =============================================================================
# ModSecurity v3 Library Check
# =============================================================================

log_section "ModSecurity v3 Library Check"

MODSECURITY_FOUND=false

if ldconfig -p 2>/dev/null | grep -q "libmodsecurity"; then
    log_ok "ModSecurity v3 shared library ditemukan."
    ldconfig -p 2>/dev/null | grep "libmodsecurity" || true
    MODSECURITY_FOUND=true
fi

for PACKAGE in libmodsecurity3 libmodsecurity3t64; do
    if package_installed "${PACKAGE}"; then
        VERSION="$(dpkg-query -W -f='${Version}' "${PACKAGE}" 2>/dev/null || echo unknown)"
        log_ok "${PACKAGE} installed [${VERSION}]"
        MODSECURITY_FOUND=true
    fi
done

[[ "${MODSECURITY_FOUND}" == "true" ]] ||
    die "ModSecurity v3 library tidak ditemukan."

# =============================================================================
# Nginx ModSecurity Module Check
# =============================================================================

log_section "Nginx ModSecurity Module Check"

[[ -f "${MODSECURITY_MODULE_PATH}" ]] ||
    die "ngx_http_modsecurity_module.so tidak ditemukan:
    ${MODSECURITY_MODULE_PATH}"

log_ok "ModSecurity Nginx module ditemukan:"
echo "    ${MODSECURITY_MODULE_PATH}"

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

    log_ok "ModSecurity module configuration sudah aktif:"
    echo "    ${MODSECURITY_MODULE_CONFIG}"

elif [[ -f "${MODSECURITY_MODULE_AVAILABLE}" ]]; then

    ln -sf \
        "${MODSECURITY_MODULE_AVAILABLE}" \
        "${MODSECURITY_MODULE_CONFIG}"

    log_ok "ModSecurity Nginx module berhasil diaktifkan."

else

    die "ModSecurity module configuration tidak ditemukan:
    ${MODSECURITY_MODULE_AVAILABLE}"

fi

# =============================================================================
# Prepare ModSecurity Runtime Directories
# =============================================================================

log_section "ModSecurity Runtime Directories"

mkdir -p "${MODSECURITY_DIR}"
mkdir -p "${MODSECURITY_AUDIT_STORAGE_DIR}"
mkdir -p "/var/lib/modsecurity/tmp"
mkdir -p "/var/lib/modsecurity/data"

chmod 0755 "${MODSECURITY_DIR}"
chmod 0755 "${MODSECURITY_AUDIT_STORAGE_DIR}"
chmod 0700 "/var/lib/modsecurity/tmp"
chmod 0700 "/var/lib/modsecurity/data"

# Give Nginx/ModSecurity access to private runtime directories.
chown -R www-data:www-data \
    "/var/lib/modsecurity/tmp" \
    "/var/lib/modsecurity/data" \
    2>/dev/null || true

log_ok "ModSecurity configuration directory:"
echo "    ${MODSECURITY_DIR}"

log_ok "Concurrent audit storage directory:"
echo "    ${MODSECURITY_AUDIT_STORAGE_DIR}"

log_ok "Private temporary directory:"
echo "    /var/lib/modsecurity/tmp"

log_ok "Private persistent data directory:"
echo "    /var/lib/modsecurity/data"

# =============================================================================
# Generate ModSecurity Base Configuration
# =============================================================================

log_section "ModSecurity Base Configuration"

cat > "${MODSECURITY_CONF}" <<'EOF'
# =============================================================================
# BREBES-WAF
# ModSecurity v3 Base Configuration
#
# Baseline:
#   monitoredreverser
#
# Important:
#   SecResponseBodyAccess is ON with MIME and 1 MiB limits for performance.
#   Audit logging uses Concurrent format.
# =============================================================================

# -----------------------------------------------------------------------------
# Rule engine
# -----------------------------------------------------------------------------

SecRuleEngine On

# -----------------------------------------------------------------------------
# Request body handling
# -----------------------------------------------------------------------------

SecRequestBodyAccess On

SecRequestBodyLimit 134217728
SecRequestBodyNoFilesLimit 131072
SecRequestBodyLimitAction Reject

# Enable XML request body parser.
SecRule REQUEST_HEADERS:Content-Type "^(?:application(?:/soap\+|/)|text/)xml" \
    "id:'200000',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML"

# Enable JSON request body parser.
SecRule REQUEST_HEADERS:Content-Type "^application/json" \
    "id:'200001',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=JSON"

# Optional JSON subtype parser.
# SecRule REQUEST_HEADERS:Content-Type "^application/[a-z0-9.-]+[+]json" \
#     "id:'200006',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=JSON"

# JSON parser depth.
SecRequestBodyJsonDepthLimit 512

# Maximum number of arguments.
SecArgumentsLimit 1000

# Reject requests that exceed the argument limit.
SecRule &ARGS "@ge 1000" \
    "id:'200007',phase:2,t:none,log,deny,status:400,msg:'Failed to fully parse request body due to large argument count',severity:2"

# Verify request body parsing.
SecRule REQBODY_ERROR "!@eq 0" \
    "id:'200002',phase:2,t:none,log,deny,status:400,msg:'Failed to parse request body.',logdata:'%{reqbody_error_msg}',severity:2"

# Strict multipart validation.
SecRule MULTIPART_STRICT_ERROR "!@eq 0" \
    "id:'200003',phase:2,t:none,log,deny,status:400,msg:'Multipart request body failed strict validation: PE %{REQBODY_PROCESSOR_ERROR}, BQ %{MULTIPART_BOUNDARY_QUOTED}, BW %{MULTIPART_BOUNDARY_WHITESPACE}, DB %{MULTIPART_DATA_BEFORE}, DA %{MULTIPART_DATA_AFTER}, HF %{MULTIPART_HEADER_FOLDING}, LF %{MULTIPART_LF_LINE}, SM %{MULTIPART_MISSING_SEMICOLON}, IQ %{MULTIPART_INVALID_QUOTING}, IP %{MULTIPART_INVALID_PART}, IH %{MULTIPART_INVALID_HEADER_FOLDING}, FL %{MULTIPART_FILE_LIMIT_EXCEEDED}'"

# Detect unmatched multipart boundary.
SecRule MULTIPART_UNMATCHED_BOUNDARY "@eq 1" \
    "id:'200004',phase:2,t:none,log,deny,msg:'Multipart parser detected a possible unmatched boundary.'"

# -----------------------------------------------------------------------------
# PCRE tuning
# -----------------------------------------------------------------------------

SecPcreMatchLimit 100000
SecPcreMatchLimitRecursion 100000

# Detect ModSecurity internal errors.
SecRule TX:/^MSC_/ "!@streq 0" \
    "id:'200005',phase:2,t:none,deny,msg:'ModSecurity internal error flagged: %{MATCHED_VAR_NAME}'"

# -----------------------------------------------------------------------------
# Response body handling
# -----------------------------------------------------------------------------

# Enabled for response-body security inspection.
# Performance controls: selected MIME types, 1 MiB inspection limit,
# and ProcessPartial for larger responses.
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml application/json
SecResponseBodyLimit 1048576
SecResponseBodyLimitAction ProcessPartial

# -----------------------------------------------------------------------------
# Filesystem configuration
# -----------------------------------------------------------------------------

SecTmpDir /var/lib/modsecurity/tmp/
SecDataDir /var/lib/modsecurity/data/

# -----------------------------------------------------------------------------
# File upload handling
# -----------------------------------------------------------------------------

# Keep upload handling disabled unless a future BREBES-WAF feature requires it.
# The actual upload security policy is implemented by BREBES-WAF rules.
#
# SecUploadDir /var/lib/modsecurity/upload/
# SecUploadKeepFiles RelevantOnly
# SecUploadFileMode 0600

# -----------------------------------------------------------------------------
# Debug log
# -----------------------------------------------------------------------------

SecDebugLog /var/log/nginx/modsecurity/debug.log
SecDebugLogLevel 0

# -----------------------------------------------------------------------------
# Audit log
#
# This follows monitoredreverser:
#   RelevantOnly
#   4xx except 404 + 5xx
#   Concurrent
#   Storage directory
# -----------------------------------------------------------------------------

SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"

SecAuditLogParts ABCDEFHIJZ

SecAuditLogType Concurrent
SecAuditLogStorageDir /var/log/nginx/modsecurity/

# -----------------------------------------------------------------------------
# Miscellaneous
# -----------------------------------------------------------------------------

SecArgumentSeparator &
SecCookieFormat 0

SecUnicodeMapFile /etc/nginx/unicode.mapping 20127

SecStatusEngine Off
EOF

chmod 0644 "${MODSECURITY_CONF}"

touch "${MODSECURITY_DEBUG_LOG}"
chown www-data:adm "${MODSECURITY_DEBUG_LOG}" 2>/dev/null || true
chmod 0640 "${MODSECURITY_DEBUG_LOG}"

log_ok "ModSecurity configuration dibuat:"
echo "    ${MODSECURITY_CONF}"

# =============================================================================
# ModSecurity Configuration Validation
# =============================================================================

log_section "ModSecurity Configuration Validation"

check_exact_directive() {
    local directive="$1"
    local expected="$2"

    if grep -Eq \
        "^[[:space:]]*${directive}[[:space:]]+${expected}([[:space:]]*)$" \
        "${MODSECURITY_CONF}"; then
        log_ok "${directive}: ${expected}"
    else
        die "${directive} tidak sesuai. Expected: ${expected}"
    fi
}

check_exact_directive "SecRuleEngine" "On"
check_exact_directive "SecRequestBodyAccess" "On"
check_exact_directive "SecRequestBodyLimit" "134217728"
check_exact_directive "SecRequestBodyNoFilesLimit" "131072"
check_exact_directive "SecRequestBodyLimitAction" "Reject"
check_exact_directive "SecRequestBodyJsonDepthLimit" "512"
check_exact_directive "SecArgumentsLimit" "1000"
check_exact_directive "SecPcreMatchLimit" "100000"
check_exact_directive "SecPcreMatchLimitRecursion" "100000"
check_exact_directive "SecResponseBodyAccess" "On"
check_exact_directive "SecResponseBodyMimeType" "text/plain text/html text/xml application/json"
check_exact_directive "SecResponseBodyLimit" "1048576"
check_exact_directive "SecResponseBodyLimitAction" "ProcessPartial"
check_exact_directive "SecTmpDir" "/var/lib/modsecurity/tmp/"
check_exact_directive "SecDataDir" "/var/lib/modsecurity/data/"
check_exact_directive "SecDebugLog" "/var/log/nginx/modsecurity/debug.log"
check_exact_directive "SecDebugLogLevel" "0"
check_exact_directive "SecAuditEngine" "RelevantOnly"
check_exact_directive "SecAuditLogParts" "ABCDEFHIJZ"
check_exact_directive "SecAuditLogType" "Concurrent"
check_exact_directive "SecAuditLogStorageDir" "/var/log/nginx/modsecurity/"
check_exact_directive "SecArgumentSeparator" "&"
check_exact_directive "SecCookieFormat" "0"
check_exact_directive "SecUnicodeMapFile" "/etc/nginx/unicode.mapping 20127"
check_exact_directive "SecStatusEngine" "Off"

if grep -Eq \
    '^[[:space:]]*SecAuditLogRelevantStatus[[:space:]]+"?\^\(\?:5\|4\(\?!04\)\)"?[[:space:]]*$' \
    "${MODSECURITY_CONF}"; then
    log_ok "SecAuditLogRelevantStatus: ${AUDIT_RELEVANT_STATUS}"
else
    die "SecAuditLogRelevantStatus tidak sesuai."
fi

# Required parser/security rules
for RULE_ID in 200000 200001 200002 200003 200004 200005 200007; do
    if grep -Eq "id:'${RULE_ID}'" "${MODSECURITY_CONF}"; then
        log_ok "Base ModSecurity rule ${RULE_ID}: FOUND"
    else
        die "Base ModSecurity rule ${RULE_ID} tidak ditemukan."
    fi
done

log_ok "ModSecurity baseline sesuai monitoredreverser dengan response-body inspection ON dan tuning performa."

# =============================================================================
# OWASP CRS
# =============================================================================

log_section "OWASP CRS Configuration"

if [[ -f "${CRS_LOAD_FILE}" ]]; then
    log_ok "System CRS load configuration ditemukan:"
    echo "    ${CRS_LOAD_FILE}"

elif [[ -f "${CRS_REPOSITORY_FILE}" ]]; then
    cp -a \
        "${CRS_REPOSITORY_FILE}" \
        "${CRS_LOAD_FILE}"

    log_ok "CRS load configuration disalin dari repository:"
    echo "    ${CRS_REPOSITORY_FILE}"

else
    die "OWASP CRS load configuration tidak ditemukan:
System:
    ${CRS_LOAD_FILE}
Repository:
    ${CRS_REPOSITORY_FILE}"
fi

[[ -s "${CRS_LOAD_FILE}" ]] ||
    die "CRS load configuration kosong: ${CRS_LOAD_FILE}"

chmod 0644 "${CRS_LOAD_FILE}"

log_ok "OWASP CRS load configuration siap."

CRS_FOUND=false

if package_installed "${CRS_PACKAGE}"; then
    CRS_VERSION="$(dpkg-query -W -f='${Version}' "${CRS_PACKAGE}" 2>/dev/null || echo unknown)"
    log_ok "OWASP CRS package installed [${CRS_VERSION}]"
    CRS_FOUND=true
fi

CRS_LOCATIONS=(
    "/usr/share/modsecurity-crs"
    "/usr/share/modsecurity-crs/owasp-crs"
    "/etc/modsecurity"
    "/etc/modsecurity-crs"
    "/etc/nginx/modsecurity"
)

for CRS_PATH in "${CRS_LOCATIONS[@]}"; do
    if [[ -d "${CRS_PATH}" ]]; then
        log_ok "CRS directory ditemukan: ${CRS_PATH}"
        CRS_FOUND=true
    fi
done

[[ "${CRS_FOUND}" == "true" ]] ||
    die "OWASP CRS tidak ditemukan."

# =============================================================================
# BREBES-WAF Rule Discovery
# =============================================================================

log_section "BREBES-WAF Rule Discovery"

mapfile -d '' RULE_FILES < <(
    find "${RULES_DIR}" \
        -type f \
        -name '*.conf' \
        -print0 |
        sort -z
)

[[ "${#RULE_FILES[@]}" -gt 0 ]] ||
    die "Tidak ada BREBES-WAF rule (*.conf) ditemukan: ${RULES_DIR}"

log_ok "BREBES-WAF rules ditemukan: ${#RULE_FILES[@]} file"

for RULE_FILE in "${RULE_FILES[@]}"; do
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

for RULE_FILE in "${RULE_FILES[@]}"; do
    printf 'Include %s\n' "${RULE_FILE}" >> "${TEMP_INCLUDE}"
done

[[ -s "${TEMP_INCLUDE}" ]] ||
    die "Gagal menghasilkan ModSecurity include."

mv -f "${TEMP_INCLUDE}" "${MODSECURITY_INCLUDE}"
chmod 0644 "${MODSECURITY_INCLUDE}"

log_ok "ModSecurity include berhasil dibuat:"
echo "    ${MODSECURITY_INCLUDE}"

# =============================================================================
# Nginx Global ModSecurity
# =============================================================================

log_section "Nginx Global ModSecurity Configuration"

[[ -f "${NGINX_MAIN_CONF}" ]] ||
    die "Nginx main configuration tidak ditemukan: ${NGINX_MAIN_CONF}"

# Enable ModSecurity in http context.
if grep -Eq \
    '^[[:space:]]*modsecurity[[:space:]]+on;' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "Global ModSecurity sudah aktif."

else

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

# Ensure rules file exists.
if grep -Eq \
    '^[[:space:]]*modsecurity_rules_file[[:space:]]+/etc/nginx/modsecurity_includes\.conf;' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "ModSecurity rules file sudah dikonfigurasi."

else

    sed -i \
        '/^[[:space:]]*modsecurity[[:space:]]\+on;/a\
        modsecurity_rules_file /etc/nginx/modsecurity_includes.conf;' \
        "${NGINX_MAIN_CONF}"

    log_ok "ModSecurity rules file berhasil dikonfigurasi."

fi

# =============================================================================
# Nginx reverser Log Format
# =============================================================================

log_section "Nginx reverser Log Format Check"

if grep -Eq \
    '^[[:space:]]*log_format[[:space:]]+reverser([[:space:]]|$)' \
    "${NGINX_MAIN_CONF}"; then

    log_ok "log_format reverser ditemukan."

else

    log_info "log_format reverser belum tersedia. Menambahkan ke http {}..."

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

# Validate important reverser fields.
for FIELD in \
    'host="$host"' \
    'xff="$http_x_forwarded_for"' \
    'rt=$request_time' \
    'urt=$upstream_response_time' \
    'upstream="$upstream_addr"'
do
    if grep -Fq "${FIELD}" "${NGINX_MAIN_CONF}"; then
        log_ok "reverser field: ${FIELD}"
    else
        log_warn "reverser field belum ditemukan: ${FIELD}"
    fi
done

# =============================================================================
# Display Configuration
# =============================================================================

log_section "BREBES-WAF Configuration Review"

echo "--- ModSecurity configuration ---"
grep -E \
    '^[[:space:]]*(SecRuleEngine|SecRequestBodyAccess|SecRequestBodyLimit|SecRequestBodyNoFilesLimit|SecRequestBodyLimitAction|SecRequestBodyJsonDepthLimit|SecArgumentsLimit|SecPcreMatchLimit|SecPcreMatchLimitRecursion|SecResponseBodyAccess|SecTmpDir|SecDataDir|SecDebugLog|SecDebugLogLevel|SecAuditEngine|SecAuditLogRelevantStatus|SecAuditLogParts|SecAuditLogType|SecAuditLogStorageDir|SecArgumentSeparator|SecCookieFormat|SecUnicodeMapFile|SecStatusEngine)[[:space:]]+' \
    "${MODSECURITY_CONF}" || true

echo
echo "--- Nginx global ModSecurity ---"
grep -E \
    '^[[:space:]]*(modsecurity|modsecurity_rules_file)[[:space:]]+' \
    "${NGINX_MAIN_CONF}" || true

echo
echo "--- Nginx reverser log format ---"
awk '
    /^[[:space:]]*log_format[[:space:]]+reverser([[:space:]]|$)/ {
        found=1
    }
    found {
        print
        if ($0 ~ /;[[:space:]]*$/) exit
    }
' "${NGINX_MAIN_CONF}" || true

# =============================================================================
# Verify ModSecurity Include
# =============================================================================

log_section "ModSecurity Include Check"

[[ -f "${MODSECURITY_INCLUDE}" ]] ||
    die "ModSecurity include tidak ditemukan: ${MODSECURITY_INCLUDE}"

[[ -s "${MODSECURITY_INCLUDE}" ]] ||
    die "ModSecurity include kosong: ${MODSECURITY_INCLUDE}"

INCLUDE_COUNT="$(grep -Eic '^[[:space:]]*include[[:space:]]+[^[:space:]]+' "${MODSECURITY_INCLUDE}" || true)"

[[ "${INCLUDE_COUNT}" -gt 0 ]] ||
    die "Tidak ada include directive di ${MODSECURITY_INCLUDE}"

log_ok "ModSecurity include tersedia."
echo "    Include directives: ${INCLUDE_COUNT}"

# =============================================================================
# Effective Nginx Configuration
# =============================================================================

log_section "Effective Nginx Configuration Check"

NGINX_DUMP="$(nginx -T 2>&1)" || {
    echo "${NGINX_DUMP}"
    rollback_nginx_conf
    die "Gagal membaca effective Nginx configuration."
}

if echo "${NGINX_DUMP}" |
    grep -Eq '^[[:space:]]*modsecurity[[:space:]]+on;'; then
    log_ok "ModSecurity aktif pada effective Nginx configuration."
else
    rollback_nginx_conf
    die "ModSecurity tidak aktif pada effective Nginx configuration."
fi

if echo "${NGINX_DUMP}" |
    grep -Eq '^[[:space:]]*modsecurity_rules_file[[:space:]]+/etc/nginx/modsecurity_includes\.conf;'; then
    log_ok "BREBES-WAF ModSecurity include aktif."
else
    rollback_nginx_conf
    die "BREBES-WAF ModSecurity include belum terdeteksi."
fi

if echo "${NGINX_DUMP}" |
    grep -Eq '^[[:space:]]*log_format[[:space:]]+reverser([[:space:]]|$)'; then
    log_ok "log_format reverser aktif."
else
    rollback_nginx_conf
    die "log_format reverser belum terdeteksi."
fi

if echo "${NGINX_DUMP}" |
    grep -Eq 'load_module.*ngx_http_modsecurity_module'; then
    log_ok "ModSecurity Nginx module loaded."
else
    rollback_nginx_conf
    die "ModSecurity Nginx module tidak terdeteksi pada effective configuration."
fi

# =============================================================================
# Nginx Configuration Test
# =============================================================================

log_section "Final Nginx Configuration Test"

if nginx -t; then
    log_ok "Nginx configuration valid."
else
    rollback_nginx_conf
    die "Nginx configuration tidak valid."
fi

# =============================================================================
# ModSecurity Audit Log Validation
# =============================================================================

log_section "ModSecurity Audit Log Format Validation"

echo "Expected configuration:"
echo "    Engine           : ${AUDIT_ENGINE}"
echo "    Relevant status  : ${AUDIT_RELEVANT_STATUS}"
echo "    Parts            : ${AUDIT_PARTS}"
echo "    Type             : ${AUDIT_TYPE}"
echo "    Storage          : ${MODSECURITY_AUDIT_STORAGE_DIR}"
echo "    Response body    : ${RESPONSE_BODY_ACCESS}"
echo

# The Concurrent format creates transaction files under the storage directory.
# We do not create a fake audit transaction during first-time installation.
# Existing records are inspected when available.

AUDIT_FILE_COUNT="$(
    find "${MODSECURITY_AUDIT_STORAGE_DIR}" \
        -type f \
        ! -name 'debug.log' \
        2>/dev/null |
        wc -l |
        tr -d ' '
)"

echo "Existing audit transaction files: ${AUDIT_FILE_COUNT}"

if [[ "${AUDIT_FILE_COUNT}" -eq 0 ]]; then

    log_warn "Belum ada audit transaction file."
    log_warn "Format Concurrent akan divalidasi kembali setelah traffic menghasilkan detection."

else

    log_ok "Concurrent audit transaction files ditemukan."

    # Inspect a sample of existing files.
    SAMPLE_COUNT=0

    while IFS= read -r -d '' AUDIT_FILE; do

        SAMPLE_COUNT=$((SAMPLE_COUNT + 1))

        echo
        echo "Audit sample #${SAMPLE_COUNT}:"
        echo "    ${AUDIT_FILE}"

        if grep -aEq '^---.*---A--$' "${AUDIT_FILE}"; then
            log_ok "Section A ditemukan."
        else
            log_warn "Section A tidak ditemukan."
        fi

        if grep -aEq '^---.*---B--$' "${AUDIT_FILE}"; then
            log_ok "Section B ditemukan."
        else
            log_warn "Section B tidak ditemukan."
        fi

        if grep -aEq '^---.*---H--$' "${AUDIT_FILE}"; then
            log_ok "Section H ditemukan."
        else
            log_warn "Section H tidak ditemukan."
        fi

        if grep -aEq '^---.*---Z--$' "${AUDIT_FILE}"; then
            log_ok "Section Z ditemukan."
        else
            log_warn "Section Z tidak ditemukan."
        fi

        # Host is expected in section B for BREBES-WAF domain analysis.
        REQUEST_HOST="$(
            awk '
                /^---.*---B--$/ {
                    in_request=1
                    next
                }

                /^---.*---[A-Z]--$/ {
                    if (in_request) exit
                }

                in_request && /^Host:[[:space:]]*/ {
                    sub(/^Host:[[:space:]]*/, "")
                    print
                    exit
                }
            ' "${AUDIT_FILE}" 2>/dev/null || true
        )"

        if [[ -n "${REQUEST_HOST}" ]]; then
            log_ok "HTTP Host ditemukan: ${REQUEST_HOST}"
        else
            log_warn "HTTP Host tidak ditemukan pada section B."
        fi

        # H section is where ModSecurity messages/detections are expected.
        if grep -aEq '^---.*---H--$' "${AUDIT_FILE}"; then
            H_CONTENT="$(
                awk '
                    /^---.*---H--$/ {
                        in_h=1
                        next
                    }

                    /^---.*---[A-Z]--$/ {
                        if (in_h) exit
                    }

                    in_h {
                        print
                    }
                ' "${AUDIT_FILE}" 2>/dev/null || true
            )"

            if echo "${H_CONTENT}" | grep -aq "ModSecurity:"; then
                log_ok "ModSecurity detection message ditemukan pada H."
            else
                log_info "Section H ada, tetapi sample tidak berisi string ModSecurity."
            fi
        fi

        # Limit validation to 3 sample files.
        if [[ "${SAMPLE_COUNT}" -ge 3 ]]; then
            break
        fi

    done < <(
        find "${MODSECURITY_AUDIT_STORAGE_DIR}" \
            -type f \
            ! -name 'debug.log' \
            -print0 2>/dev/null |
            sort -z
    )

fi

# =============================================================================
# ModSecurity Audit Storage Permissions
# =============================================================================

log_section "ModSecurity Audit Storage Permission Check"

AUDIT_DIR_OWNER="$(stat -c '%U:%G' "${MODSECURITY_AUDIT_STORAGE_DIR}")"
AUDIT_DIR_MODE="$(stat -c '%a' "${MODSECURITY_AUDIT_STORAGE_DIR}")"

echo "    Owner : ${AUDIT_DIR_OWNER}"
echo "    Mode  : ${AUDIT_DIR_MODE}"

# Concurrent audit files are generated by the Nginx worker process.
# Keep directory accessible to the Nginx user while not making it world-writable.
if [[ "${AUDIT_DIR_MODE}" == "755" ]]; then
    log_ok "Audit storage permission: 0755"
else
    log_warn "Audit storage permission: ${AUDIT_DIR_MODE}"
fi

# =============================================================================
# ModSecurity Effective Configuration Check
# =============================================================================

log_section "ModSecurity Effective Configuration Check"

# Verify the generated base configuration is actually included.
if grep -Fq "include ${MODSECURITY_CONF}" "${MODSECURITY_INCLUDE}"; then
    log_ok "ModSecurity base configuration included."
else
    die "ModSecurity base configuration tidak termasuk dalam include."
fi

if grep -Fq "include ${CRS_LOAD_FILE}" "${MODSECURITY_INCLUDE}"; then
    log_ok "OWASP CRS load configuration included."
else
    die "OWASP CRS load configuration tidak termasuk dalam include."
fi

BREBES_INCLUDE_COUNT="$(
    grep -Ec \
        '^include /opt/Brebes-WAF/rules/.*\.conf;$' \
        "${MODSECURITY_INCLUDE}" \
        || true
)"

if [[ "${BREBES_INCLUDE_COUNT}" -gt 0 ]]; then
    log_ok "BREBES-WAF rule include: ${BREBES_INCLUDE_COUNT} file(s)"
else
    die "BREBES-WAF rule include tidak ditemukan."
fi

# =============================================================================
# Nginx Service
# =============================================================================

log_section "Nginx Service"

systemctl enable nginx >/dev/null 2>&1 || true
log_ok "Nginx enabled."

if systemctl is-active --quiet nginx; then

    log_info "Nginx sedang running. Melakukan reload..."

    if systemctl reload nginx; then
        log_ok "Nginx berhasil di-reload."
    else
        systemctl status nginx --no-pager || true
        die "Nginx reload gagal."
    fi

else

    log_info "Nginx belum running. Menjalankan Nginx..."

    systemctl start nginx

    if systemctl is-active --quiet nginx; then
        log_ok "Nginx berhasil dijalankan."
    else
        systemctl status nginx --no-pager || true
        die "Nginx gagal dijalankan."
    fi

fi

# =============================================================================
# Runtime Verification
# =============================================================================

log_section "Runtime BREBES-WAF Verification"

RUNTIME_NGINX_DUMP="$(nginx -T 2>&1)" || {
    echo "${RUNTIME_NGINX_DUMP}"
    die "Tidak dapat membaca runtime Nginx configuration."
}

if echo "${RUNTIME_NGINX_DUMP}" |
    grep -Eq 'load_module.*ngx_http_modsecurity_module'; then
    log_ok "Runtime: ModSecurity module loaded."
else
    die "Runtime: ModSecurity module tidak loaded."
fi

if echo "${RUNTIME_NGINX_DUMP}" |
    grep -Eq '^[[:space:]]*modsecurity[[:space:]]+on;'; then
    log_ok "Runtime: ModSecurity ON."
else
    die "Runtime: ModSecurity OFF / tidak ditemukan."
fi

if echo "${RUNTIME_NGINX_DUMP}" |
    grep -Eq '^[[:space:]]*modsecurity_rules_file[[:space:]]+/etc/nginx/modsecurity_includes\.conf;'; then
    log_ok "Runtime: BREBES-WAF rules include loaded."
else
    die "Runtime: BREBES-WAF rules include tidak ditemukan."
fi

if systemctl is-active --quiet nginx; then
    log_ok "Runtime: Nginx RUNNING."
else
    die "Runtime: Nginx NOT RUNNING."
fi

# =============================================================================
# Final Summary
# =============================================================================

RULE_COUNT="$(find "${RULES_DIR}" -type f -name '*.conf' | wc -l | tr -d ' ')"

log_section "BREBES-WAF First-Time Installation Summary"

echo
echo "Status:"
echo "    Installation          : SUCCESS"
echo "    BREBES-WAF            : ${BREBES_WAF_HOME}"
echo "    Ubuntu                : ${PRETTY_NAME:-unknown}"
echo "    Codename              : ${UBUNTU_CODENAME}"
echo "    Nginx                 : RUNNING"
echo "    ModSecurity           : ON"
echo "    ModSecurity module    : LOADED"
echo "    OWASP CRS             : READY"
echo "    BREBES-WAF Rules      : ${RULE_COUNT} file(s)"
echo
echo "ModSecurity:"
echo "    Request body          : ON"
echo "    Request body limit    : 128 MB"
echo "    JSON parser           : ON"
echo "    XML parser            : ON"
echo "    JSON depth            : ${JSON_DEPTH_LIMIT}"
echo "    Arguments limit       : ${ARGUMENTS_LIMIT}"
echo "    PCRE match limit      : ${PCRE_MATCH_LIMIT}"
echo "    PCRE recursion        : ${PCRE_RECURSION_LIMIT}"
echo "    Response body         : ${RESPONSE_BODY_ACCESS}"
echo "    Response MIME         : ${RESPONSE_BODY_MIME_TYPES}"
echo "    Response limit        : ${RESPONSE_BODY_LIMIT} bytes"
echo "    Response limit action : ${RESPONSE_BODY_LIMIT_ACTION}"
echo
echo "Audit logging:"
echo "    Engine                : ${AUDIT_ENGINE}"
echo "    Relevant status       : 4xx except 404 + 5xx"
echo "    Format                : ${AUDIT_TYPE}"
echo "    Parts                 : ${AUDIT_PARTS}"
echo "    Storage               : ${MODSECURITY_AUDIT_STORAGE_DIR}"
echo
echo "Nginx logging:"
echo "    Format                : reverser"
echo "    Host                  : host=\"\$host\""
echo "    X-Forwarded-For       : xff=\"\$http_x_forwarded_for\""
echo "    Request time          : rt=\$request_time"
echo "    Upstream time         : urt=\$upstream_response_time"
echo "    Upstream address      : upstream=\"\$upstream_addr\""
echo
echo "Ubuntu repository:"
echo "    Main                  : ${UBUNTU_MAIN_REPOSITORY}"
echo "    Security              : ${UBUNTU_SECURITY_REPOSITORY}"
echo
echo "Configuration:"
echo "    ModSecurity           : ${MODSECURITY_CONF}"
echo "    CRS                   : ${CRS_LOAD_FILE}"
echo "    WAF Include           : ${MODSECURITY_INCLUDE}"
echo "    Nginx                 : ${NGINX_MAIN_CONF}"
echo
echo "Original backup:"
echo "    ${CURRENT_BACKUP_DIR}"
echo
echo "============================================================"
echo " BREBES-WAF First-Time Installation Completed"
echo "============================================================"
echo

log_ok "BREBES-WAF berhasil diinstall dan dikonfigurasi."

echo
echo "Next step:"
echo "    Gunakan scripts/deploy.sh untuk deployment/update rules berikutnya."
echo
