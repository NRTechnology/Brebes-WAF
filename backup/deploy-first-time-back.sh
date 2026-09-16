#!/bin/bash
#
# =============================================================================
# BREBES-WAF Deployment Script
# Author  : Brebes CSIRT
# Version : 1.2
# =============================================================================
#

set -euo pipefail

BREBES_WAF_HOME="/opt/Brebes-WAF"
RULES_DIR="${BREBES_WAF_HOME}/rules"

OUTPUT="/etc/nginx/modsecurity_includes.conf"
BACKUP="${OUTPUT}.bak"

# OWASP CRS configuration
CRS_SYSTEM_DIR="/etc/nginx/modsecurity"
CRS_LOAD_FILE="${CRS_SYSTEM_DIR}/crs-load.conf"

# CRS file included in BREBES-WAF repository
CRS_REPOSITORY_FILE="${BREBES_WAF_HOME}/nginx/modsecurity/crs-load.conf"


echo "========================================================="
echo " BREBES-WAF Deployment"
echo "========================================================="


# =============================================================================
# Check Root
# =============================================================================

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Please run as root."
    exit 1
fi


# =============================================================================
# Check BREBES-WAF Home
# =============================================================================

if [[ ! -d "$BREBES_WAF_HOME" ]]; then
    echo "[ERROR] BREBES-WAF directory not found:"
    echo "        $BREBES_WAF_HOME"
    exit 1
fi


# =============================================================================
# Check Rules Directory
# =============================================================================

if [[ ! -d "$RULES_DIR" ]]; then
    echo "[ERROR] Rules directory not found:"
    echo "        $RULES_DIR"
    exit 1
fi


# =============================================================================
# Check OWASP CRS Load File
# =============================================================================

echo "[0/4] Checking OWASP CRS configuration..."


if [[ -f "$CRS_LOAD_FILE" ]]; then

    echo "[OK] CRS configuration found:"
    echo "     $CRS_LOAD_FILE"

else

    echo "[WARN] CRS configuration not found:"
    echo "       $CRS_LOAD_FILE"

    if [[ -f "$CRS_REPOSITORY_FILE" ]]; then

        echo "[INFO] Copying CRS configuration from BREBES-WAF repository..."
        echo "       Source : $CRS_REPOSITORY_FILE"
        echo "       Target : $CRS_LOAD_FILE"

        mkdir -p "$CRS_SYSTEM_DIR"

        cp "$CRS_REPOSITORY_FILE" "$CRS_LOAD_FILE"

        echo "[OK] CRS configuration installed."

    else

        echo "[ERROR] CRS configuration is not available in repository:"
        echo "        $CRS_REPOSITORY_FILE"
        echo
        echo "[ERROR] Deployment aborted."
        exit 1

    fi

fi


# =============================================================================
# Validate CRS Load File
# =============================================================================

if [[ ! -s "$CRS_LOAD_FILE" ]]; then
    echo "[ERROR] CRS load file exists but is empty:"
    echo "        $CRS_LOAD_FILE"
    exit 1
fi


# =============================================================================
# Count Rules
# =============================================================================

RULE_COUNT=$(find "$RULES_DIR" \
    -type f \
    -name "*.conf" \
    | wc -l)


if [[ "$RULE_COUNT" -eq 0 ]]; then
    echo "[ERROR] No ModSecurity rules found."
    exit 1
fi


echo
echo "[INFO] BREBES-WAF rules detected : $RULE_COUNT"
echo


# =============================================================================
# Generate ModSecurity Include File
# =============================================================================

echo "[1/4] Generating ModSecurity Include File..."


TMPFILE=$(mktemp)


cleanup() {
    rm -f "$TMPFILE"
}

trap cleanup EXIT


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

include ${CRS_LOAD_FILE}

#
# BREBES-WAF Rules
#

EOF


LC_ALL=C find "$RULES_DIR" \
    -type f \
    -name "*.conf" \
    -print0 \
| sort -z \
| while IFS= read -r -d '' file
do
    echo "Include $file" >> "$TMPFILE"
done


# =============================================================================
# Backup Existing Include File
# =============================================================================

if [[ -f "$OUTPUT" ]]; then

    cp "$OUTPUT" "$BACKUP"

    echo "[INFO] Existing ModSecurity include file backed up:"
    echo "       $BACKUP"

fi


# =============================================================================
# Install New Include File
# =============================================================================

mv "$TMPFILE" "$OUTPUT"


# =============================================================================
# Test Nginx Configuration
# =============================================================================

echo "[2/4] Testing Nginx Configuration..."


if nginx -t; then

    echo "[OK] Nginx configuration test successful."

else

    echo
    echo "[ERROR] Nginx configuration test failed."

    if [[ -f "$BACKUP" ]]; then

        cp "$BACKUP" "$OUTPUT"

        echo "[INFO] Previous ModSecurity include file restored:"
        echo "       $OUTPUT"

    fi

    exit 1

fi


# =============================================================================
# Reload Nginx
# =============================================================================

echo "[3/4] Reloading Nginx..."


if systemctl reload nginx; then

    echo "[OK] Nginx reload successful."

else

    echo
    echo "[ERROR] Nginx reload failed."

    if [[ -f "$BACKUP" ]]; then

        cp "$BACKUP" "$OUTPUT"

        echo "[INFO] Previous ModSecurity include file restored."

    fi

    exit 1

fi


# =============================================================================
# Deployment Successful
# =============================================================================

echo "[4/4] Deployment Successful"

echo
echo "-----------------------------------------"
echo "BREBES-WAF"
echo "-----------------------------------------"
echo "Loaded Rules : $RULE_COUNT"
echo "CRS Config   : $CRS_LOAD_FILE"
echo "Include File : $OUTPUT"
echo "Backup File  : $BACKUP"
echo "-----------------------------------------"