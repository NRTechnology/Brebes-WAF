#!/bin/bash

# =============================================================================
# BREBES-WAF
# Detection Log Analysis - Today
#
# File    : scripts/today-detection.sh
# Version : 1.1.0
# Author  : Brebes CSIRT
#
# Purpose:
#   Analyze ModSecurity detection logs generated today.
#
# Output:
#   - BREBES-WAF detections
#   - OWASP CRS detections
# =============================================================================

set -u

LOG_BASE_DIR="/var/log/nginx/modsecurity"
TODAY="$(date +%Y%m%d)"
LOG_DIR="${LOG_BASE_DIR}/${TODAY}"

echo
echo "============================================================"
echo " BREBES-WAF Detection Analysis - Today"
echo "============================================================"
echo
echo "Date : ${TODAY}"
echo "Log  : ${LOG_DIR}"
echo

if [[ ! -d "${LOG_DIR}" ]]; then
    echo "Belum ada direktori log untuk hari ini."
    echo
    echo "============================================================"
    echo " Detection Analysis Completed"
    echo "============================================================"
    exit 0
fi

TOTAL_LOGS=0
DETECTION_LOGS=0
BREBES_WAF_COUNT=0
CRS_COUNT=0

while IFS= read -r -d '' LOG
do
    TOTAL_LOGS=$((TOTAL_LOGS + 1))

    LOG_CONTENT="$(strings "${LOG}" 2>/dev/null || true)"

    [[ -z "${LOG_CONTENT}" ]] && continue

    # -------------------------------------------------------------------------
    # Extract section H
    # -------------------------------------------------------------------------

    DETECTIONS="$(
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
    )"

    [[ -z "${DETECTIONS}" ]] && continue

    # -------------------------------------------------------------------------
    # BREBES-WAF
    # -------------------------------------------------------------------------

    BREBES_WAF="$(
        printf '%s\n' "${DETECTIONS}" |
        grep -F "BREBES-WAF" ||
        true
    )"

    # -------------------------------------------------------------------------
    # OWASP CRS
    # -------------------------------------------------------------------------

    CRS="$(
        printf '%s\n' "${DETECTIONS}" |
        grep -F '[id "' |
        grep -F '[ver "OWASP_CRS/' ||
        true
    )"

    # -------------------------------------------------------------------------
    # Skip logs without actual BREBES-WAF / CRS detection
    # -------------------------------------------------------------------------

    if [[ -z "${BREBES_WAF}" && -z "${CRS}" ]]; then
        continue
    fi

    DETECTION_LOGS=$((DETECTION_LOGS + 1))

    if [[ -n "${BREBES_WAF}" ]]; then
        CURRENT_BREBES_WAF_COUNT="$(
            printf '%s\n' "${BREBES_WAF}" |
            grep -c "BREBES-WAF" ||
            true
        )

        [[ -z "${CURRENT_BREBES_WAF_COUNT}" ]] &&
            CURRENT_BREBES_WAF_COUNT=0

        BREBES_WAF_COUNT=$(
            (
                printf '%s\n' "${BREBES_WAF}" |
                grep -c "BREBES-WAF" ||
                true
            )
        )

        BREBES_WAF_COUNT=$((BREBES_WAF_COUNT))
    fi

    if [[ -n "${CRS}" ]]; then
        CRS_LINES="$(
            printf '%s\n' "${CRS}" |
            grep -c '\[id "' ||
            true
        )

        [[ -z "${CRS_LINES}" ]] && CRS_LINES=0

        CRS_COUNT=$((CRS_COUNT + CRS_LINES))
    fi

    # -------------------------------------------------------------------------
    # Display detection
    # -------------------------------------------------------------------------

    echo "============================================================"
    echo " Log File : ${LOG}"
    echo "============================================================"

    if [[ -n "${BREBES_WAF}" ]]; then
        echo
        echo "===== BREBES-WAF ====="
        printf '%s\n' "${BREBES_WAF}"
    fi

    if [[ -n "${CRS}" ]]; then
        echo
        echo "===== OWASP CRS ====="
        printf '%s\n' "${CRS}"
    fi

    echo

done < <(
    find "${LOG_DIR}" \
        -type f \
        -print0 2>/dev/null |
    sort -z
)

echo "============================================================"
echo " Detection Analysis Summary"
echo "============================================================"
echo
echo "Date                   : ${TODAY}"
echo "Total audit logs       : ${TOTAL_LOGS}"
echo "Detection logs         : ${DETECTION_LOGS}"
echo "BREBES-WAF detections  : ${BREBES_WAF_COUNT}"
echo "OWASP CRS detections   : ${CRS_COUNT}"
echo

if [[ "${DETECTION_LOGS}" -eq 0 ]]; then
    echo "No BREBES-WAF/OWASP CRS detection found."
    echo
fi

echo "============================================================"
echo " Detection Analysis Completed"
echo "============================================================"
echo