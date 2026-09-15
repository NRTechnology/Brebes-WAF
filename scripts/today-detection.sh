#!/bin/bash

# =============================================================================
# BREBES-WAF
# Detection Log Analysis - Today
#
# File    : scripts/today-detection.sh
# Version : 1.0
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
TODAY=$(date +%Y%m%d)
LOG_DIR="${LOG_BASE_DIR}/${TODAY}"

if [ ! -d "$LOG_DIR" ]; then
    echo "=================================================="
    echo "BREBES-WAF - TODAY DETECTION"
    echo "=================================================="
    echo "Tanggal   : $TODAY"
    echo "Log Dir   : $LOG_DIR"
    echo
    echo "Belum ada direktori log untuk hari ini."
    exit 0
fi

find "$LOG_DIR" -type f -print0 | while IFS= read -r -d '' LOG
do
    echo "=================================================="
    echo "Log File : $LOG"
    echo "=================================================="

    echo "===== BREBES-WAF ====="

    BREBES_WAF_RESULT=$(strings "$LOG" 2>/dev/null | grep -F "BREBES-WAF" || true)

    if [ -n "$BREBES_WAF_RESULT" ]; then
        echo "$BREBES_WAF_RESULT"
    else
        echo "Tidak ada detection BREBES-WAF."
    fi

    echo
    echo "===== OWASP CRS ====="

    CRS_RESULT=$(
        strings "$LOG" 2>/dev/null |
        grep 'id "' |
        grep -v "BREBES-WAF" ||
        true
    )

    if [ -n "$CRS_RESULT" ]; then
        echo "$CRS_RESULT"
    else
        echo "Tidak ada detection OWASP CRS."
    fi

    echo
done