#!/bin/bash
# BREBES-WAF Detection Log Analysis by Domain
# File: scripts/check-last-detection.sh
# Version: 1.3.0
# Author: Brebes CSIRT

set -euo pipefail

LOG_BASE_DIR="/var/log/nginx/modsecurity"

DOMAIN="${1:-}"
DATE="${2:-$(date +%Y%m%d)}"

# ============================================================
# Usage
# ============================================================

if [[ -z "${DOMAIN}" ]]; then
    echo "Usage:"
    echo "  $0 <domain> [YYYYMMDD]"
    echo
    echo "Contoh:"
    echo "  $0 brebeskab.go.id"
    echo "  $0 brebeskab.go.id 20260915"
    exit 1
fi

# ============================================================
# Validate date
# ============================================================

if [[ ! "${DATE}" =~ ^[0-9]{8}$ ]]; then
    echo "ERROR: Format tanggal harus YYYYMMDD"
    exit 1
fi

LOG_DIR="${LOG_BASE_DIR}/${DATE}"

if [[ ! -d "${LOG_DIR}" ]]; then
    echo "Tidak ditemukan directory log:"
    echo "  ${LOG_DIR}"
    exit 0
fi

# ============================================================
# Header
# ============================================================

echo "============================================================"
echo " BREBES-WAF Detection Log Analysis"
echo "============================================================"
echo " Domain : ${DOMAIN}"
echo " Date   : ${DATE}"
echo " LogDir : ${LOG_DIR}"
echo "============================================================"
echo

FOUND=false

# ============================================================
# Find audit log files
# ============================================================

mapfile -d '' LOG_FILES < <(
    find "${LOG_DIR}" -type f -print0 | sort -z
)

for LOG in "${LOG_FILES[@]}"; do

    LOG_CONTENT=$(strings "${LOG}" 2>/dev/null || true)

    [[ -z "${LOG_CONTENT}" ]] && continue

    # ========================================================
    # Get Host from section B
    #
    # Example:
    #
    # ---ppKKdaLG---B--
    # GET /api/captcha HTTP/1.1
    # Host: brebeskab.go.id
    #
    # We intentionally DO NOT use:
    #
    # [hostname "15.0.1.7"]
    #
    # because that is ModSecurity/server hostname.
    # ========================================================

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
                print
                exit
            }
        ' |
        tr -d '\r' |
        xargs
    )

    # ========================================================
    # Skip if Host does not match requested domain
    # ========================================================

    if [[ "${REQUEST_HOST,,}" != "${DOMAIN,,}" ]]; then
        continue
    fi

    # ========================================================
    # Extract section H
    #
    # This section contains ModSecurity detections.
    # ========================================================

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

    # ========================================================
    # BREBES-WAF detection
    # ========================================================

    BREBES_WAF_RESULT=$(
        printf '%s\n' "${DETECTION_RESULT}" |
        grep -F "BREBES-WAF" ||
        true
    )

    # ========================================================
    # OWASP CRS detection
    #
    # Detection lines containing [id "..."]
    # but exclude BREBES-WAF.
    # ========================================================

    CRS_RESULT=$(
        printf '%s\n' "${DETECTION_RESULT}" |
        grep 'id "' |
        grep -v "BREBES-WAF" ||
        true
    )

    # ========================================================
    # No detection
    # ========================================================

    if [[ -z "${BREBES_WAF_RESULT}" ]] &&
       [[ -z "${CRS_RESULT}" ]]; then
        continue
    fi

    FOUND=true

    # ========================================================
    # Display
    # ========================================================

    echo "============================================================"
    echo " Log File : ${LOG}"
    echo " Domain   : ${REQUEST_HOST}"
    echo "============================================================"

    # ========================================================
    # Request
    # ========================================================

    REQUEST_LINE=$(
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

            in_request && /^[A-Z]+[[:space:]]/ {
                print
                exit
            }
        '
    )

    if [[ -n "${REQUEST_LINE}" ]]; then
        echo "===== REQUEST ====="
        echo "${REQUEST_LINE}"
        echo
    fi

    # ========================================================
    # BREBES-WAF
    # ========================================================

    if [[ -n "${BREBES_WAF_RESULT}" ]]; then
        echo "===== BREBES-WAF ====="
        printf '%s\n' "${BREBES_WAF_RESULT}"
        echo
    fi

    # ========================================================
    # OWASP CRS
    # ========================================================

    if [[ -n "${CRS_RESULT}" ]]; then
        echo "===== OWASP CRS ====="
        printf '%s\n' "${CRS_RESULT}"
        echo
    fi

done

# ============================================================
# No detection found
# ============================================================

if [[ "${FOUND}" != "true" ]]; then
    echo "Tidak ditemukan detection untuk domain:"
    echo "  ${DOMAIN}"
    echo
fi