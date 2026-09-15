#!/bin/bash
# =============================================================================
# BREBES-WAF
# Detection Log Analysis by Domain
#
# File    : scripts/check-last-detection.sh
# Version : 1.3.1
# Author  : Brebes CSIRT
#
# Purpose:
#   Analyze ModSecurity audit logs based on HTTP Host header.
#
# Usage:
#   ./scripts/check-last-detection.sh <domain>
#   ./scripts/check-last-detection.sh <domain> <YYYYMMDD>
#
# Example:
#   ./scripts/check-last-detection.sh sppdkominfo.brebeskab.go.id
#   ./scripts/check-last-detection.sh sppdkominfo.brebeskab.go.id 20260915
#
# Important:
#   ModSecurity [hostname "..."] is NOT used as domain identity.
#   Domain is obtained from "Host:" in audit log section B.
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

LOG_BASE_DIR="/var/log/nginx/modsecurity"

# =============================================================================
# Argument
# =============================================================================

if [[ $# -lt 1 ]]; then

    echo
    echo "Usage:"
    echo
    echo "    $0 <domain>"
    echo
    echo "Example:"
    echo
    echo "    $0 sppdkominfo.brebeskab.go.id"
    echo
    echo "Optional date:"
    echo
    echo "    $0 sppdkominfo.brebeskab.go.id 20260915"
    echo

    exit 1
fi

DOMAIN="$1"

# =============================================================================
# Domain Validation
# =============================================================================

if [[ ! "${DOMAIN}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then

    echo
    echo "[ERROR] Invalid domain name:"
    echo "        ${DOMAIN}"
    echo

    exit 1
fi

# =============================================================================
# Date
# =============================================================================

if [[ $# -ge 2 ]]; then
    DATE="$2"
else
    DATE=$(date +%Y%m%d)
fi

# =============================================================================
# Date Validation
# =============================================================================

if [[ ! "${DATE}" =~ ^[0-9]{8}$ ]]; then

    echo
    echo "[ERROR] Invalid date format:"
    echo "        ${DATE}"
    echo
    echo "Expected:"
    echo "        YYYYMMDD"
    echo

    exit 1
fi

LOG_DIR="${LOG_BASE_DIR}/${DATE}"

# =============================================================================
# Header
# =============================================================================

echo
echo "============================================================"
echo " BREBES-WAF Detection Analysis"
echo "============================================================"
echo
echo "Domain : ${DOMAIN}"
echo "Date   : ${DATE}"
echo

# =============================================================================
# Check Log Directory
# =============================================================================

if [[ ! -d "${LOG_DIR}" ]]; then

    echo "[INFO] Detection log directory tidak ditemukan:"
    echo
    echo "       ${LOG_DIR}"
    echo

    exit 0
fi

# =============================================================================
# Find Log Files
# =============================================================================

mapfile -d '' LOG_FILES < <(
    find "${LOG_DIR}" \
        -type f \
        -print0 |
    sort -z
)

if [[ "${#LOG_FILES[@]}" -eq 0 ]]; then

    echo "[INFO] Tidak ada log file pada:"
    echo
    echo "       ${LOG_DIR}"
    echo

    exit 0
fi

# =============================================================================
# Search Detection
# =============================================================================

FOUND=false

for LOG in "${LOG_FILES[@]}"
do

    # =========================================================================
    # Read audit log
    # =========================================================================

    LOG_CONTENT=$(
        cat "${LOG}" 2>/dev/null || true
    )

    [[ -z "${LOG_CONTENT}" ]] && continue

    # =========================================================================
    # Extract Host from section B
    #
    # Example:
    #
    # ---xxxx---B--
    # GET /api/test HTTP/1.1
    # Host: sppdkominfo.brebeskab.go.id
    #
    # =========================================================================

    REQUEST_HOST=$(
        printf '%s\n' "${LOG_CONTENT}" |
        awk '
            /^---.*---B--$/ {
                in_request=1
                next
            }

            /^---.*---[A-Z]--$/ {
                if (in_request) {
                    exit
                }
            }

            in_request && /^Host:[[:space:]]*/ {
                sub(/^Host:[[:space:]]*/, "")
                gsub(/\r/, "")
                print
                exit
            }
        ' |
        xargs
    )

    # =========================================================================
    # Skip when Host does not match requested domain
    #
    # Case insensitive.
    # =========================================================================

    if [[ "${REQUEST_HOST,,}" != "${DOMAIN,,}" ]]; then
        continue
    fi

    # =========================================================================
    # Extract section H
    #
    # Section H contains ModSecurity detection messages.
    # =========================================================================

    DETECTION_RESULT=$(
        printf '%s\n' "${LOG_CONTENT}" |
        awk '
            /^---.*---H--$/ {
                in_detection=1
                next
            }

            /^---.*---[A-Z]--$/ {
                if (in_detection) {
                    exit
                }
            }

            in_detection {
                print
            }
        '
    )

    [[ -z "${DETECTION_RESULT}" ]] && continue

    # =========================================================================
    # BREBES-WAF Detection
    # =========================================================================

    BREBES_WAF_RESULT=$(
        printf '%s\n' "${DETECTION_RESULT}" |
        grep -F "BREBES-WAF" ||
        true
    )

    # =========================================================================
    # OWASP CRS Detection
    #
    # CRS entries contain:
    #
    #   [id "XXXXXX"]
    #
    # Exclude BREBES-WAF.
    # =========================================================================

    CRS_RESULT=$(
        printf '%s\n' "${DETECTION_RESULT}" |
        grep 'id "' |
        grep -v "BREBES-WAF" ||
        true
    )

    # =========================================================================
    # Skip if no detection
    # =========================================================================

    if [[ -z "${BREBES_WAF_RESULT}" ]] &&
       [[ -z "${CRS_RESULT}" ]]; then
        continue
    fi

    FOUND=true

    # =========================================================================
    # Display Detection
    # =========================================================================

    echo "============================================================"
    echo " Log File : ${LOG}"
    echo " Domain   : ${REQUEST_HOST}"
    echo "============================================================"
    echo

    # =========================================================================
    # BREBES-WAF
    # =========================================================================

    if [[ -n "${BREBES_WAF_RESULT}" ]]; then

        echo "===== BREBES-WAF ====="
        printf '%s\n' "${BREBES_WAF_RESULT}"
        echo

    fi

    # =========================================================================
    # OWASP CRS
    # =========================================================================

    if [[ -n "${CRS_RESULT}" ]]; then

        echo "===== OWASP CRS ====="
        printf '%s\n' "${CRS_RESULT}"
        echo

    fi

done

# =============================================================================
# No Detection
# =============================================================================

if [[ "${FOUND}" != "true" ]]; then

    echo
    echo "============================================================"
    echo " Detection Result"
    echo "============================================================"
    echo
    echo "Tidak ditemukan detection untuk domain:"
    echo
    echo "    ${DOMAIN}"
    echo
    echo "Tanggal:"
    echo
    echo "    ${DATE}"
    echo

fi

# =============================================================================
# Completed
# =============================================================================

echo
echo "============================================================"
echo " Detection Analysis Completed"
echo "============================================================"
echo