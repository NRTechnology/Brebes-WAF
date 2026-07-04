#!/bin/bash
#
# =============================================================================
# BREBES-WAF Deployment Script
# Author  : Brebes CSIRT
# Version : 1.1
# =============================================================================
#

set -euo pipefail

BREBES_WAF_HOME="/opt/Brebes-WAF"
RULES_DIR="${BREBES_WAF_HOME}/rules"
OUTPUT="/etc/nginx/modsecurity_includes.conf"
BACKUP="${OUTPUT}.bak"

echo "========================================================="
echo " BREBES-WAF Deployment"
echo "========================================================="

#
# Check Root
#
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Please run as root."
    exit 1
fi

#
# Check Rules Directory
#
if [[ ! -d "$RULES_DIR" ]]; then
    echo "[ERROR] Rules directory not found:"
    echo "        $RULES_DIR"
    exit 1
fi

#
# Count Rules
#
RULE_COUNT=$(find "$RULES_DIR" -type f -name "*.conf" | wc -l)

if [[ "$RULE_COUNT" -eq 0 ]]; then
    echo "[ERROR] No ModSecurity rules found."
    exit 1
fi

echo "[1/4] Generating ModSecurity Include File..."

TMPFILE=$(mktemp)

cat > "$TMPFILE" <<EOF
#
# =============================================================================
# BREBES-WAF
# Auto Generated File
# DO NOT EDIT MANUALLY
#
# Generated : $(date)
# Rule Count: ${RULE_COUNT}
# =============================================================================
#

include modsecurity.conf

#
# OWASP CRS
#
#include /etc/nginx/modsecurity/crs-load.conf

#
# BREBES-WAF Rules
#

EOF

LC_ALL=C find "$RULES_DIR" \
    -type f \
    -name "*.conf" \
| sort \
| while read -r file
do
    echo "Include $file" >> "$TMPFILE"
done

#
# Backup Existing File
#
if [[ -f "$OUTPUT" ]]; then
    cp "$OUTPUT" "$BACKUP"
fi

mv "$TMPFILE" "$OUTPUT"

echo "[2/4] Testing Nginx Configuration..."

if nginx -t; then

    echo "[3/4] Reloading Nginx..."

    systemctl reload nginx

    echo "[4/4] Deployment Successful"

    echo
    echo "-----------------------------------------"
    echo "Loaded Rules : $RULE_COUNT"
    echo "Include File : $OUTPUT"
    echo "Backup File  : $BACKUP"
    echo "-----------------------------------------"

else

    echo "[ERROR] nginx configuration test failed."

    if [[ -f "$BACKUP" ]]; then
        cp "$BACKUP" "$OUTPUT"
        echo "[INFO] Previous include file restored."
    fi

    exit 1

fi