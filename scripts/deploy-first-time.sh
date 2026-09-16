#!/usr/bin/env bash

# ============================================================
# BREBES-WAF
# First Time Deployment Script
#
# Version : 1.3.0
# Date    : 2026-09-15
#
# Purpose:
#   - Prepare dependencies
#   - Install/enable ModSecurity for Nginx
#   - Configure ModSecurity baseline
#   - Configure OWASP CRS
#   - Load BREBES-WAF rules
#   - Configure Nginx reverser log format
#   - Validate ModSecurity audit log configuration
#   - Validate Nginx configuration
#
# Performance policy:
#   SecResponseBodyAccess Off
#
# IMPORTANT:
#   Response-body inspection is intentionally disabled.
#   CRS response rules such as 951240 may still exist in CRS,
#   but BREBES-WAF does not enable response-body inspection.
# ============================================================

set -Eeuo pipefail

# ============================================================
# VARIABLES
# ============================================================

SCRIPT_VERSION="1.3.0"
RELEASE_DATE="2026-09-15"

PROJECT_DIR="/opt/Brebes-WAF"

RULES_DIR="${PROJECT_DIR}/rules"

NGINX_MAIN_CONFIG="/etc/nginx/nginx.conf"

MODSEC_DIR="/etc/nginx"
MODSEC_CONFIG="${MODSEC_DIR}/modsecurity.conf"
MODSEC_INCLUDE="${MODSEC_DIR}/modsecurity_includes.conf"

MODSEC_LOG_DIR="/var/log/nginx/modsecurity"
MODSEC_AUDIT_LOG="${MODSEC_LOG_DIR}/audit.log"
MODSEC_DEBUG_LOG="${MODSEC_LOG_DIR}/debug.log"

CRS_SYSTEM_DIR="/usr/share/modsecurity-crs"
CRS_RULES_DIR="${CRS_SYSTEM_DIR}/rules"

CRS_GENERATED_LOAD="/etc/nginx/modsecurity-crs-load.conf"
BREBES_RULES_LOAD="/etc/nginx/brebes-waf-rules.conf"

BACKUP_ROOT="/var/backups/brebes-waf"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

APT_PACKAGES=(
    nginx
    curl
    ca-certificates
    gnupg
    lsb-release
    apt-transport-https
)

# ============================================================
# COLORS
# ============================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# ============================================================
# LOG FUNCTIONS
# ============================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN} $*${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

# ============================================================
# ERROR HANDLER
# ============================================================

CURRENT_STEP="initialization"

on_error() {
    local exit_code=$?

    echo
    log_error "Deployment gagal."
    log_error "Step       : ${CURRENT_STEP}"
    log_error "Exit code  : ${exit_code}"

    if [[ -d "${BACKUP_DIR}" ]]; then
        log_warn "Backup tersedia di:"
        echo "  ${BACKUP_DIR}"
    fi

    exit "${exit_code}"
}

trap on_error ERR

# ============================================================
# ROOT CHECK
# ============================================================

require_root() {
    CURRENT_STEP="root privilege check"

    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Script ini harus dijalankan sebagai root."
        exit 1
    fi

    log_ok "Running as root"
}

# ============================================================
# PROJECT CHECK
# ============================================================

check_project() {
    CURRENT_STEP="project directory check"

    if [[ ! -d "${PROJECT_DIR}" ]]; then
        log_error "Project BREBES-WAF tidak ditemukan:"
        echo "  ${PROJECT_DIR}"
        exit 1
    fi

    if [[ ! -d "${RULES_DIR}" ]]; then
        log_error "Rules directory tidak ditemukan:"
        echo "  ${RULES_DIR}"
        exit 1
    fi

    log_ok "Project directory : ${PROJECT_DIR}"
    log_ok "Rules directory   : ${RULES_DIR}"
}

# ============================================================
# SYSTEM INFORMATION
# ============================================================

show_system_info() {
    CURRENT_STEP="system information"

    echo
    echo "BREBES-WAF First Time Deployment"
    echo "Version      : ${SCRIPT_VERSION}"
    echo "Release Date : ${RELEASE_DATE}"
    echo

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release

        echo "OS           : ${PRETTY_NAME:-unknown}"
        echo "Architecture : $(dpkg --print-architecture 2>/dev/null || uname -m)"
    fi

    echo "Hostname     : $(hostname)"
    echo "Kernel       : $(uname -r)"
    echo
}

# ============================================================
# APT UPDATE
# ============================================================

apt_update() {
    CURRENT_STEP="APT update"

    log_info "Updating APT package index..."

    apt-get update

    log_ok "APT package index updated"
}

# ============================================================
# BASIC DEPENDENCIES
# ============================================================

install_basic_dependencies() {
    CURRENT_STEP="basic dependency installation"

    log_info "Installing basic dependencies..."

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y "${APT_PACKAGES[@]}"

    log_ok "Basic dependencies installed"
}

# ============================================================
# MODSECURITY
# ============================================================

install_modsecurity() {
    CURRENT_STEP="ModSecurity package installation"

    local modsec_pkg=""

    if apt-cache show libmodsecurity3t64 >/dev/null 2>&1; then
        modsec_pkg="libmodsecurity3t64"
    elif apt-cache show libmodsecurity3 >/dev/null 2>&1; then
        modsec_pkg="libmodsecurity3"
    fi

    if [[ -z "${modsec_pkg}" ]]; then
        log_error "Paket libmodsecurity3/libmodsecurity3t64 tidak ditemukan."
        exit 1
    fi

    log_info "Detected ModSecurity package: ${modsec_pkg}"

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        "${modsec_pkg}" \
        libnginx-mod-http-modsecurity

    log_ok "ModSecurity installed"
}

# ============================================================
# ENABLE NGINX MODSECURITY MODULE
# ============================================================

enable_modsecurity_module() {
    CURRENT_STEP="Nginx ModSecurity module"

    local module_conf="/etc/nginx/modules-enabled/50-mod-http-modsecurity.conf"

    if [[ -f "${module_conf}" ]]; then
        log_ok "Nginx ModSecurity module already enabled"
        return
    fi

    local available_conf="/usr/share/nginx/modules-available/mod-http-modsecurity.conf"

    if [[ -f "${available_conf}" ]]; then
        ln -s "${available_conf}" "${module_conf}"
        log_ok "Enabled Nginx ModSecurity module"
        return
    fi

    local found_conf

    found_conf="$(
        find /usr/share/nginx/modules-available \
            -maxdepth 1 \
            -type f \
            -name '*modsecurity*.conf' \
            | head -n 1
    )"

    if [[ -n "${found_conf}" ]]; then
        ln -s "${found_conf}" "${module_conf}"

        log_ok "Enabled Nginx ModSecurity module:"
        echo "  ${found_conf}"
        return
    fi

    log_error "Konfigurasi module ModSecurity Nginx tidak ditemukan."
    exit 1
}

# ============================================================
# PREPARE LOG DIRECTORY
# ============================================================

prepare_log_directory() {
    CURRENT_STEP="ModSecurity log directory"

    mkdir -p "${MODSEC_LOG_DIR}"

    chown root:adm "${MODSEC_LOG_DIR}" 2>/dev/null || true
    chmod 0750 "${MODSEC_LOG_DIR}"

    touch "${MODSEC_AUDIT_LOG}"
    touch "${MODSEC_DEBUG_LOG}"

    chown www-data:adm "${MODSEC_AUDIT_LOG}" 2>/dev/null || true
    chown www-data:adm "${MODSEC_DEBUG_LOG}" 2>/dev/null || true

    chmod 0640 "${MODSEC_AUDIT_LOG}"
    chmod 0640 "${MODSEC_DEBUG_LOG}"

    log_ok "ModSecurity log directory prepared:"
    echo "  ${MODSEC_LOG_DIR}"
}

# ============================================================
# BACKUP
# ============================================================

backup_file() {
    local file="$1"

    if [[ ! -e "${file}" ]]; then
        return 0
    fi

    local relative

    if [[ "${file}" == /etc/* ]]; then
        relative="${file#/etc/}"
    else
        relative="$(basename "${file}")"
    fi

    mkdir -p "${BACKUP_DIR}/$(dirname "${relative}")"

    cp -a "${file}" \
        "${BACKUP_DIR}/${relative}"
}

backup_existing_configuration() {
    CURRENT_STEP="configuration backup"

    mkdir -p "${BACKUP_DIR}"

    log_info "Creating configuration backup:"
    echo "  ${BACKUP_DIR}"

    backup_file "${NGINX_MAIN_CONFIG}"
    backup_file "${MODSEC_CONFIG}"
    backup_file "${MODSEC_INCLUDE}"
    backup_file "${CRS_GENERATED_LOAD}"
    backup_file "${BREBES_RULES_LOAD}"

    if [[ -d /etc/nginx/sites-enabled ]]; then
        mkdir -p "${BACKUP_DIR}/nginx/sites-enabled"

        cp -a /etc/nginx/sites-enabled/. \
            "${BACKUP_DIR}/nginx/sites-enabled/" \
            2>/dev/null || true
    fi

    if [[ -d /etc/nginx/conf.d ]]; then
        mkdir -p "${BACKUP_DIR}/nginx/conf.d"

        cp -a /etc/nginx/conf.d/. \
            "${BACKUP_DIR}/nginx/conf.d/" \
            2>/dev/null || true
    fi

    log_ok "Configuration backup completed"
}

# ============================================================
# MODSECURITY BASE CONFIG
# ============================================================

create_modsecurity_config() {
    CURRENT_STEP="ModSecurity base configuration"

    cat > "${MODSEC_CONFIG}" <<'EOF'
# ============================================================
# BREBES-WAF ModSecurity Base Configuration
# ============================================================

SecRuleEngine On

# ------------------------------------------------------------
# Request Body
# ------------------------------------------------------------

SecRequestBodyAccess On
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecRequestBodyLimitAction Reject

# ------------------------------------------------------------
# Response Body
#
# Intentionally OFF for BREBES-WAF performance.
#
# Manual tracing can be performed from application logs,
# audit logs and reverse-proxy logs when required.
# ------------------------------------------------------------

SecResponseBodyAccess Off

# ------------------------------------------------------------
# PCRE
# ------------------------------------------------------------

SecPcreMatchLimit 100000
SecPcreMatchLimitRecursion 100000

# ------------------------------------------------------------
# Audit Logging
# ------------------------------------------------------------

SecAuditEngine RelevantOnly

SecAuditLogRelevantStatus "^(?:5|4(?!04))"

SecAuditLogParts ABIJDEFHZ

SecAuditLogType Serial

SecAuditLog /var/log/nginx/modsecurity/audit.log

# ------------------------------------------------------------
# Debug Logging
#
# Keep disabled in production.
# ------------------------------------------------------------

SecDebugLog /var/log/nginx/modsecurity/debug.log
SecDebugLogLevel 0

# ------------------------------------------------------------
# Temporary/Data Directory
# ------------------------------------------------------------

SecTmpDir /tmp
SecDataDir /tmp
EOF

    log_ok "Created ${MODSEC_CONFIG}"
}

# ============================================================
# CRS DISCOVERY
# ============================================================

find_crs() {
    CURRENT_STEP="OWASP CRS discovery"

    if [[ ! -d "${CRS_RULES_DIR}" ]]; then
        log_error "OWASP CRS rules directory tidak ditemukan:"
        echo "  ${CRS_RULES_DIR}"
        exit 1
    fi

    local count

    count="$(
        find "${CRS_RULES_DIR}" \
            -type f \
            -name '*.conf' \
            | wc -l
    )"

    if [[ "${count}" -eq 0 ]]; then
        log_error "Tidak ada CRS rule (*.conf) ditemukan."
        exit 1
    fi

    log_ok "OWASP CRS rules found: ${count}"
}

# ============================================================
# GENERATE RULE LOAD FILES
# ============================================================

generate_rule_load_files() {
    CURRENT_STEP="ModSecurity rule load files"

    # --------------------------------------------------------
    # OWASP CRS
    # --------------------------------------------------------

    : > "${CRS_GENERATED_LOAD}"

    cat >> "${CRS_GENERATED_LOAD}" <<'EOF'
# ============================================================
# BREBES-WAF - OWASP CRS Load
# Generated automatically by deploy-first-time.sh
# ============================================================

EOF

    mapfile -t CRS_FILES < <(
        find "${CRS_RULES_DIR}" \
            -type f \
            -name '*.conf' \
            -print0 |
        sort -z |
        xargs -0 -r -n1 printf '%s\n'
    )

    if [[ "${#CRS_FILES[@]}" -eq 0 ]]; then
        log_error "CRS rules tidak ditemukan."
        exit 1
    fi

    local file

    for file in "${CRS_FILES[@]}"; do
        printf 'Include "%s"\n' "${file}" \
            >> "${CRS_GENERATED_LOAD}"
    done

    # --------------------------------------------------------
    # BREBES-WAF
    # --------------------------------------------------------

    : > "${BREBES_RULES_LOAD}"

    cat >> "${BREBES_RULES_LOAD}" <<'EOF'
# ============================================================
# BREBES-WAF - Custom Rules
# Generated automatically by deploy-first-time.sh
# ============================================================

EOF

    mapfile -t BREBES_FILES < <(
        find "${RULES_DIR}" \
            -type f \
            -name '*.conf' \
            -print0 |
        sort -z |
        xargs -0 -r -n1 printf '%s\n'
    )

    if [[ "${#BREBES_FILES[@]}" -eq 0 ]]; then
        log_error "BREBES-WAF rules tidak ditemukan."
        exit 1
    fi

    for file in "${BREBES_FILES[@]}"; do
        printf 'Include "%s"\n' "${file}" \
            >> "${BREBES_RULES_LOAD}"
    done

    log_ok "Generated CRS load:"
    echo "  ${CRS_GENERATED_LOAD}"

    log_ok "Generated BREBES-WAF rule load:"
    echo "  ${BREBES_RULES_LOAD}"

    log_ok "CRS rules     : ${#CRS_FILES[@]}"
    log_ok "BREBES-WAF     : ${#BREBES_FILES[@]}"
}

# ============================================================
# FINAL MODSECURITY INCLUDE
# ============================================================

create_final_modsecurity_include() {
    CURRENT_STEP="final ModSecurity include"

    cat > "${MODSEC_INCLUDE}" <<EOF
# ============================================================
# BREBES-WAF ModSecurity Master Include
# Generated: ${TIMESTAMP}
# Version  : ${SCRIPT_VERSION}
# ============================================================

Include "${MODSEC_CONFIG}"

Include "${CRS_GENERATED_LOAD}"

Include "${BREBES_RULES_LOAD}"
EOF

    log_ok "Created ${MODSEC_INCLUDE}"
}

# ============================================================
# ENSURE NGINX MODSECURITY DIRECTIVES
# ============================================================

ensure_nginx_modsecurity() {
    CURRENT_STEP="Nginx ModSecurity directives"

    if [[ ! -f "${NGINX_MAIN_CONFIG}" ]]; then
        log_error "Nginx main config tidak ditemukan."
        exit 1
    fi

    python3 - "${NGINX_MAIN_CONFIG}" "${MODSEC_INCLUDE}" <<'PY'
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
include_path = sys.argv[2]

text = config_path.read_text()
lines = text.splitlines()

# ------------------------------------------------------------
# Remove existing global ModSecurity directives.
# ------------------------------------------------------------

new_lines = []

for line in lines:
    stripped = line.strip()

    if stripped.startswith("modsecurity on;"):
        continue

    if stripped.startswith("modsecurity_rules_file "):
        continue

    new_lines.append(line)

lines = new_lines

# ------------------------------------------------------------
# Find http block.
# ------------------------------------------------------------

http_start = None
http_end = None
brace = 0
inside_http = False

for i, line in enumerate(lines):
    stripped = line.strip()

    if not inside_http and stripped.startswith("http") and "{" in stripped:
        inside_http = True
        http_start = i
        brace = stripped.count("{") - stripped.count("}")
        continue

    if inside_http:
        brace += line.count("{") - line.count("}")

        if brace == 0:
            http_end = i
            break

if http_start is None or http_end is None:
    raise SystemExit("Tidak menemukan http {} pada nginx.conf")

# ------------------------------------------------------------
# Insert directives immediately before closing http block.
# ------------------------------------------------------------

directives = [
    "",
    "        # ====================================================",
    "        # BREBES-WAF ModSecurity",
    "        # ====================================================",
    "        modsecurity on;",
    f"        modsecurity_rules_file {include_path};",
]

lines[http_end:http_end] = directives

config_path.write_text("\n".join(lines) + "\n")
PY

    log_ok "Nginx ModSecurity directives configured"
}

# ============================================================
# ENSURE REVERSER LOG FORMAT
# ============================================================

ensure_reverser_log_format() {
    CURRENT_STEP="Nginx reverser log format"

    python3 - "${NGINX_MAIN_CONFIG}" <<'PY'
import sys
from pathlib import Path

config_path = Path(sys.argv[1])

text = config_path.read_text()
lines = text.splitlines()

# ------------------------------------------------------------
# Remove existing reverser log_format blocks.
# ------------------------------------------------------------

new_lines = []
i = 0

while i < len(lines):
    line = lines[i]

    if line.strip().startswith("log_format reverser "):
        i += 1

        while i < len(lines):
            if ";" in lines[i]:
                i += 1
                break

            i += 1

        continue

    new_lines.append(line)
    i += 1

lines = new_lines

# ------------------------------------------------------------
# Find http block.
# ------------------------------------------------------------

http_start = None
http_end = None
brace = 0
inside_http = False

for i, line in enumerate(lines):
    stripped = line.strip()

    if not inside_http and stripped.startswith("http") and "{" in stripped:
        inside_http = True
        http_start = i
        brace = stripped.count("{") - stripped.count("}")
        continue

    if inside_http:
        brace += line.count("{") - line.count("}")

        if brace == 0:
            http_end = i
            break

if http_start is None or http_end is None:
    raise SystemExit("Tidak menemukan http {}")

# ------------------------------------------------------------
# Standard BREBES-WAF reverser format.
# ------------------------------------------------------------

reverser = [
    "",
    "        # ====================================================",
    "        # BREBES-WAF Reverse Proxy Access Log",
    "        # ====================================================",
    "        log_format reverser",
    "          '$remote_addr '",
    "          '[$time_local] '",
    "          '\"$request\" '",
    "          '$status '",
    "          '$body_bytes_sent '",
    "          '\"$http_referer\" '",
    "          '\"$http_user_agent\" '",
    "          'host=\"$host\" '",
    "          'xff=\"$http_x_forwarded_for\" '",
    "          'rt=$request_time '",
    "          'urt=$upstream_response_time '",
    "          'upstream=\"$upstream_addr\"';",
    "",
]

lines[http_start + 1:http_start + 1] = reverser

config_path.write_text("\n".join(lines) + "\n")
PY

    log_ok "Nginx reverser log format configured"
}

# ============================================================
# CHECK MODSECURITY AUDIT LOG FORMAT
# ============================================================

check_modsecurity_log_format() {
    CURRENT_STEP="ModSecurity audit log format validation"

    log_step "CHECK MODSECURITY AUDIT LOG FORMAT"

    local errors=0

    # --------------------------------------------------------
    # SecAuditEngine
    # --------------------------------------------------------

    if grep -Eq \
        '^[[:space:]]*SecAuditEngine[[:space:]]+RelevantOnly([[:space:]]|$)' \
        "${MODSEC_CONFIG}"; then

        log_ok "SecAuditEngine = RelevantOnly"
    else
        log_error "SecAuditEngine bukan RelevantOnly"
        errors=$((errors + 1))
    fi

    # --------------------------------------------------------
    # SecAuditLogRelevantStatus
    # --------------------------------------------------------

    if grep -Eq \
        '^[[:space:]]*SecAuditLogRelevantStatus[[:space:]]+' \
        "${MODSEC_CONFIG}"; then

        log_ok "SecAuditLogRelevantStatus configured"
    else
        log_error "SecAuditLogRelevantStatus tidak ditemukan"
        errors=$((errors + 1))
    fi

    # --------------------------------------------------------
    # SecAuditLogParts
    # --------------------------------------------------------

    local audit_parts

    audit_parts="$(
        awk '
        /^[[:space:]]*SecAuditLogParts[[:space:]]+/ {
            print $2
        }
        ' "${MODSEC_CONFIG}" |
        tail -n 1
    )"

    if [[ "${audit_parts}" == "ABIJDEFHZ" ]]; then
        log_ok "SecAuditLogParts = ${audit_parts}"
    else
        log_error "SecAuditLogParts tidak sesuai."
        echo "  Expected : ABIJDEFHZ"
        echo "  Current  : ${audit_parts:-NOT FOUND}"
        errors=$((errors + 1))
    fi

    # --------------------------------------------------------
    # Required audit sections
    # --------------------------------------------------------

    local required_part

    for required_part in A B I J D E F H Z; do

        if [[ "${audit_parts}" == *"${required_part}"* ]]; then
            log_ok "Audit section ${required_part} enabled"
        else
            log_error "Audit section ${required_part} tidak tersedia"
            errors=$((errors + 1))
        fi

    done

    # --------------------------------------------------------
    # Audit type
    # --------------------------------------------------------

    if grep -Eq \
        '^[[:space:]]*SecAuditLogType[[:space:]]+Serial([[:space:]]|$)' \
        "${MODSEC_CONFIG}"; then

        log_ok "SecAuditLogType = Serial"
    else
        log_error "SecAuditLogType bukan Serial"
        errors=$((errors + 1))
    fi

    # --------------------------------------------------------
    # Audit log
    # --------------------------------------------------------

    local audit_log

    audit_log="$(
        awk '
        /^[[:space:]]*SecAuditLog[[:space:]]+/ {
            print $2
        }
        ' "${MODSEC_CONFIG}" |
        tail -n 1
    )"

    if [[ "${audit_log}" == "${MODSEC_AUDIT_LOG}" ]]; then
        log_ok "SecAuditLog = ${MODSEC_AUDIT_LOG}"
    else
        log_error "SecAuditLog tidak sesuai."
        echo "  Expected : ${MODSEC_AUDIT_LOG}"
        echo "  Current  : ${audit_log:-NOT FOUND}"
        errors=$((errors + 1))
    fi

    # --------------------------------------------------------
    # Response body policy
    # --------------------------------------------------------

    local response_body_access

    response_body_access="$(
        awk '
        /^[[:space:]]*SecResponseBodyAccess[[:space:]]+/ {
            print $2
        }
        ' "${MODSEC_CONFIG}" |
        tail -n 1
    )"

    if [[ "${response_body_access}" == "Off" ]]; then
        log_ok "SecResponseBodyAccess = Off"
    else
        log_error "SecResponseBodyAccess harus Off."
        echo "  Current : ${response_body_access:-NOT FOUND}"
        errors=$((errors + 1))
    fi

    # --------------------------------------------------------
    # Result
    # --------------------------------------------------------

    if [[ "${errors}" -gt 0 ]]; then
        log_error "ModSecurity audit log validation FAILED."
        return 1
    fi

    log_ok "ModSecurity audit log validation PASSED"
}

# ============================================================
# CHECK REVERSER LOG FORMAT
# ============================================================

check_reverser_log_format() {
    CURRENT_STEP="Nginx reverser log format validation"

    log_step "CHECK NGINX REVERSER LOG FORMAT"

    local errors=0

    if ! grep -qE 'log_format reverser' \
        "${NGINX_MAIN_CONFIG}"; then

        log_error "log_format reverser tidak ditemukan."
        return 1
    fi

    log_ok "log_format reverser ditemukan"

    local required_fields=(
        '\$remote_addr'
        '\$time_local'
        '\$request'
        '\$status'
        '\$body_bytes_sent'
        '\$http_referer'
        '\$http_user_agent'
        'host="\$host"'
        'xff="\$http_x_forwarded_for"'
        'rt=\$request_time'
        'urt=\$upstream_response_time'
        'upstream="\$upstream_addr"'
    )

    local field

    for field in "${required_fields[@]}"; do

        if grep -qF "${field}" \
            "${NGINX_MAIN_CONFIG}"; then

            log_ok "reverser field OK: ${field}"
        else
            log_error "reverser field MISSING: ${field}"
            errors=$((errors + 1))
        fi

    done

    if [[ "${errors}" -gt 0 ]]; then
        log_error "Nginx reverser log validation FAILED."
        return 1
    fi

    log_ok "Nginx reverser log validation PASSED"
}

# ============================================================
# CHECK LOG DIRECTORY
# ============================================================

check_log_directory() {
    CURRENT_STEP="log directory validation"

    log_step "CHECK LOG DIRECTORY"

    if [[ ! -d "${MODSEC_LOG_DIR}" ]]; then
        log_error "ModSecurity log directory tidak ada."
        return 1
    fi

    log_ok "Log directory exists:"
    echo "  ${MODSEC_LOG_DIR}"

    if [[ ! -f "${MODSEC_AUDIT_LOG}" ]]; then
        touch "${MODSEC_AUDIT_LOG}"
    fi

    if [[ ! -f "${MODSEC_DEBUG_LOG}" ]]; then
        touch "${MODSEC_DEBUG_LOG}"
    fi

    log_ok "Audit log exists:"
    echo "  ${MODSEC_AUDIT_LOG}"

    log_ok "Debug log exists:"
    echo "  ${MODSEC_DEBUG_LOG}"
}

# ============================================================
# FIX LOG PERMISSIONS
# ============================================================

fix_log_permissions() {
    CURRENT_STEP="ModSecurity log permissions"

    mkdir -p "${MODSEC_LOG_DIR}"

    touch "${MODSEC_AUDIT_LOG}"
    touch "${MODSEC_DEBUG_LOG}"

    chown www-data:adm "${MODSEC_AUDIT_LOG}" 2>/dev/null || true
    chown www-data:adm "${MODSEC_DEBUG_LOG}" 2>/dev/null || true

    chmod 0640 "${MODSEC_AUDIT_LOG}"
    chmod 0640 "${MODSEC_DEBUG_LOG}"

    log_ok "ModSecurity log permissions configured"
}

# ============================================================
# NGINX CONFIG DUMP
# ============================================================

test_nginx_dump() {
    CURRENT_STEP="nginx -T"

    log_step "NGINX CONFIGURATION DUMP"

    local dump_file="/tmp/brebes-waf-nginx-test-${TIMESTAMP}.txt"

    nginx -T >"${dump_file}" 2>&1

    log_ok "nginx -T PASSED"

    echo
    echo "Configuration dump:"
    echo "  ${dump_file}"
}

# ============================================================
# NGINX CONFIG TEST
# ============================================================

test_nginx() {
    CURRENT_STEP="nginx -t"

    log_step "NGINX CONFIGURATION TEST"

    nginx -t

    log_ok "nginx -t PASSED"
}

# ============================================================
# VERIFY MODSECURITY RUNTIME
# ============================================================

verify_modsecurity_loaded() {
    CURRENT_STEP="ModSecurity runtime verification"

    log_step "VERIFY MODSECURITY RUNTIME"

    local output

    output="$(nginx -T 2>&1)"

    if grep -q "modsecurity on;" <<<"${output}"; then
        log_ok "modsecurity on; detected"
    else
        log_error "modsecurity on; tidak ditemukan."
        return 1
    fi

    if grep -q \
        "modsecurity_rules_file ${MODSEC_INCLUDE};" \
        <<<"${output}"; then

        log_ok "BREBES-WAF ModSecurity include detected"
    else
        log_error "BREBES-WAF ModSecurity include tidak ditemukan."
        return 1
    fi

    if grep -q \
        "log_format reverser" \
        <<<"${output}"; then

        log_ok "reverser log format detected"
    else
        log_error "reverser log format tidak ditemukan."
        return 1
    fi
}

# ============================================================
# EXISTING AUDIT LOG CHECK
# ============================================================

check_existing_audit_records() {
    CURRENT_STEP="existing ModSecurity audit record validation"

    log_step "CHECK EXISTING MODSECURITY AUDIT RECORD"

    if [[ ! -s "${MODSEC_AUDIT_LOG}" ]]; then
        log_warn "Audit log masih kosong."
        log_warn "Ini normal pada first deployment."
        return 0
    fi

    log_info "Audit log sudah memiliki data."

    local sections

    sections="$(
        grep -oE '^---[^-]+---[A-Z]--$' \
            "${MODSEC_AUDIT_LOG}" 2>/dev/null |
        sed -E 's/^.*---([A-Z])--$/\1/' |
        sort -u |
        tr '\n' ' '
    )"

    if [[ -n "${sections}" ]]; then
        log_ok "Detected audit sections:"
        echo "  ${sections}"
    else
        log_warn "Belum menemukan section audit serial."
        log_warn "Kemungkinan belum ada transaction yang diaudit."
    fi

    local part

    for part in A B H Z; do

        if grep -qE "^---[^-]+---${part}--$" \
            "${MODSEC_AUDIT_LOG}" 2>/dev/null; then

            log_ok "Audit section ${part} detected"
        else
            log_warn "Audit section ${part} belum ditemukan"
        fi

    done
}

# ============================================================
# NGINX SERVICE CHECK
# ============================================================

check_nginx_service() {
    CURRENT_STEP="Nginx service validation"

    if systemctl is-active --quiet nginx; then
        log_ok "Nginx service is active"
    else
        log_error "Nginx service is NOT active."
        systemctl status nginx --no-pager || true
        return 1
    fi
}

# ============================================================
# RELOAD NGINX
# ============================================================

reload_nginx() {
    CURRENT_STEP="Nginx reload"

    log_step "RELOAD NGINX"

    systemctl reload nginx

    log_ok "Nginx reloaded"
}

# ============================================================
# FINAL SUMMARY
# ============================================================

final_summary() {
    CURRENT_STEP="final summary"

    echo
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN} BREBES-WAF FIRST TIME DEPLOYMENT COMPLETED${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo
    echo "Version              : ${SCRIPT_VERSION}"
    echo "Release Date         : ${RELEASE_DATE}"
    echo
    echo "Project              : ${PROJECT_DIR}"
    echo
    echo "ModSecurity config   : ${MODSEC_CONFIG}"
    echo "ModSecurity include  : ${MODSEC_INCLUDE}"
    echo "CRS load             : ${CRS_GENERATED_LOAD}"
    echo "BREBES-WAF rules     : ${BREBES_RULES_LOAD}"
    echo
    echo "Audit log            : ${MODSEC_AUDIT_LOG}"
    echo "Debug log            : ${MODSEC_DEBUG_LOG}"
    echo
    echo "Response inspection  : OFF"
    echo "Audit log type       : Serial"
    echo "Audit log parts      : ABIJDEFHZ"
    echo "Audit engine         : RelevantOnly"
    echo
    echo "Reverser log format  : reverser"
    echo
    echo "Backup               : ${BACKUP_DIR}"
    echo
    echo -e "${GREEN}============================================================${NC}"
    echo " BREBES-WAF is ready."
    echo -e "${GREEN}============================================================${NC}"
}

# ============================================================
# MAIN
# ============================================================

main() {

    require_root

    show_system_info

    check_project

    log_step "PREPARE SYSTEM"

    apt_update
    install_basic_dependencies
    install_modsecurity

    log_step "PREPARE NGINX MODSECURITY"

    enable_modsecurity_module
    prepare_log_directory

    log_step "BACKUP"

    backup_existing_configuration

    log_step "CONFIGURE MODSECURITY"

    create_modsecurity_config

    log_step "CONFIGURE OWASP CRS"

    find_crs

    log_step "GENERATE RULE LOAD"

    generate_rule_load_files
    create_final_modsecurity_include

    log_step "CONFIGURE NGINX"

    ensure_nginx_modsecurity
    ensure_reverser_log_format

    log_step "VALIDATE LOGGING"

    fix_log_permissions
    check_modsecurity_log_format
    check_reverser_log_format
    check_log_directory
    check_existing_audit_records

    log_step "VALIDATE NGINX"

    test_nginx_dump
    test_nginx
    verify_modsecurity_loaded

    log_step "ACTIVATE"

    reload_nginx
    check_nginx_service

    final_summary
}

main "$@"