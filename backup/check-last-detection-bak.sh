#!/bin/bash

# =============================================================================
# BREBES-WAF
# Detection Log Analysis by Domain
#
# File    : scripts/check-last-detection.sh
# Version : 1.2.1
# Author  : Brebes CSIRT
#
# Purpose:
#   Analyze ModSecurity detection logs based on domain name.
#
# Usage:
#
#   ./scripts/check-last-detection.sh <domain>
#
# Example:
#
#   ./scripts/check-last-detection.sh csirtlab.brebeskab.go.id
#
# Optional date:
#
#   ./scripts/check-last-detection.sh csirtlab.brebeskab.go.id 20260915
#
# Output:
#   - Only log files containing detection are displayed.
#   - BREBES-WAF detection is displayed separately.
#   - OWASP CRS detection is displayed separately.
#   - Log files without detection are skipped.
#
# =============================================================================

set -euo pipefail


# =============================================================================
# Configuration
# =============================================================================

LOG_BASE_DIR="/var/log/nginx/modsecurity"


# =============================================================================
# Argument Check
# =============================================================================

if [[ $# -lt 1 ]]; then

    echo
    echo "Usage:"
    echo
    echo "    $0 <domain>"
    echo
    echo "Example:"
    echo
    echo "    $0 csirtlab.brebeskab.go.id"
    echo
    echo "Optional date:"
    echo
    echo "    $0 csirtlab.brebeskab.go.id 20260915"
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
# Search Detection by Domain
# =============================================================================

FOUND=false


for LOG in "${LOG_FILES[@]}"
do

    # -------------------------------------------------------------------------
    # Read log content
    # -------------------------------------------------------------------------

    LOG_CONTENT=$(
        strings "${LOG}" 2>/dev/null || true
    )


    # -------------------------------------------------------------------------
    # Check whether this log contains the requested domain
    # -------------------------------------------------------------------------

    if ! printf '%s\n' "${LOG_CONTENT}" |
        grep -Fqi -- "${DOMAIN}"; then

        continue

    fi


    # -------------------------------------------------------------------------
    # BREBES-WAF Detection
    #
    # The domain is used to identify the relevant audit log.
    # Once the log belongs to the requested domain, search the complete
    # audit log for BREBES-WAF detection.
    # -------------------------------------------------------------------------

    BREBES_WAF_RESULT=$(
        printf '%s\n' "${LOG_CONTENT}" |
        grep -F "BREBES-WAF" ||
        true
    )


    # -------------------------------------------------------------------------
    # OWASP CRS Detection
    #
    # CRS detection normally contains:
    #
    #   id "XXXXXX"
    #
    # Exclude BREBES-WAF entries.
    # -------------------------------------------------------------------------

    CRS_RESULT=$(
        printf '%s\n' "${LOG_CONTENT}" |
        grep 'id "' |
        grep -v "BREBES-WAF" ||
        true
    )


    # -------------------------------------------------------------------------
    # Skip log when there is no detection
    # -------------------------------------------------------------------------

    if [[ -z "${BREBES_WAF_RESULT}" ]] &&
       [[ -z "${CRS_RESULT}" ]]; then

        continue

    fi


    # -------------------------------------------------------------------------
    # Detection found
    # -------------------------------------------------------------------------

    FOUND=true


    echo "============================================================"
    echo " Log File : ${LOG}"
    echo "============================================================"


    # -------------------------------------------------------------------------
    # BREBES-WAF
    # -------------------------------------------------------------------------

    if [[ -n "${BREBES_WAF_RESULT}" ]]; then

        echo
        echo "===== BREBES-WAF ====="
        echo "${BREBES_WAF_RESULT}"

    fi


    # -------------------------------------------------------------------------
    # OWASP CRS
    # -------------------------------------------------------------------------

    if [[ -n "${CRS_RESULT}" ]]; then

        echo
        echo "===== OWASP CRS ====="
        echo "${CRS_RESULT}"

    fi


    echo

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