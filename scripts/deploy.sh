#!/bin/bash
#
# =============================================================================
# BREBES-WAF Deployment Script
# Author  : Brebes CSIRT
# Version : 1.3
# =============================================================================
#

set -euo pipefail

BREBES_WAF_HOME="/opt/Brebes-WAF"
RULES_DIR="${BREBES_WAF_HOME}/rules"
CUSTOM_EXCLUSIONS_DIR="${RULES_DIR}/99-custom-exclusions"
RULE_ID_FILE="${CUSTOM_EXCLUSIONS_DIR}/RULE-ID.txt"
OUTPUT="/etc/nginx/modsecurity_includes.conf"
BACKUP="${OUTPUT}.bak"

echo "========================================================="
echo " BREBES-WAF Deployment"
echo "========================================================="

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Please run as root."
    exit 1
fi

if [[ ! -d "$RULES_DIR" ]]; then
    echo "[ERROR] Rules directory not found: $RULES_DIR"
    exit 1
fi

if [[ ! -d "$CUSTOM_EXCLUSIONS_DIR" ]]; then
    echo "[ERROR] Custom exclusions directory not found: $CUSTOM_EXCLUSIONS_DIR"
    exit 1
fi

if [[ ! -f "$RULE_ID_FILE" ]]; then
    echo "[ERROR] Rule ID registry not found: $RULE_ID_FILE"
    exit 1
fi

WORKDIR=$(mktemp -d)
TMPFILE="${WORKDIR}/modsecurity_includes.conf"
REGISTRY_IDS="${WORKDIR}/registry-ids.txt"
CONFIG_IDS="${WORKDIR}/config-ids.txt"
DUPLICATE_IDS="${WORKDIR}/duplicate-ids.txt"
trap 'rm -rf "$WORKDIR"' EXIT

#
# Validate RULE-ID.txt: one numeric Rule ID per line.
# Blank lines and comments beginning with # are ignored.
#
echo "[1/5] Validating Custom Exclusions Rule ID Registry..."

if ! awk '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 !~ /^[0-9]+$/) {
            printf "[ERROR] Invalid RULE-ID.txt entry at line %d: %s\n", NR, $0
            invalid = 1
        } else {
            print $0
        }
    }
    END { if (invalid) exit 1 }
' "$RULE_ID_FILE" > "$REGISTRY_IDS"; then
    exit 1
fi

awk '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        count[$0]++
    }
    END {
        for (id in count)
            if (count[id] > 1)
                print id
    }
' "$RULE_ID_FILE" | sort -n > "$DUPLICATE_IDS"

if [[ -s "$DUPLICATE_IDS" ]]; then
    echo "[ERROR] Duplicate Rule ID in RULE-ID.txt:"
    sed 's/^/        /' "$DUPLICATE_IDS"
    exit 1
fi

sort -n "$REGISTRY_IDS" -o "$REGISTRY_IDS"

#
# Extract Rule IDs from custom exclusion configuration files.
#
: > "$CONFIG_IDS"
while IFS= read -r -d '' file; do
    grep -Eo 'id:[[:space:]]*[0-9]+' "$file" 2>/dev/null \
        | sed -E 's/^id:[[:space:]]*//' >> "$CONFIG_IDS" || true
done < <(find "$CUSTOM_EXCLUSIONS_DIR" -type f -name "*.conf" -print0)

#
# Detect duplicate IDs across custom exclusion *.conf files.
#
: > "$DUPLICATE_IDS"
while IFS= read -r -d '' file; do
    grep -Eo 'id:[[:space:]]*[0-9]+' "$file" 2>/dev/null \
        | sed -E 's/^id:[[:space:]]*//' \
        | while IFS= read -r id; do
            printf '%s\t%s\n' "$id" "$file"
        done
done < <(find "$CUSTOM_EXCLUSIONS_DIR" -type f -name "*.conf" -print0) \
    | sort -k1,1n \
    | awk -F '\t' '
        $1 == previous {
            if (!reported) print previous_file
            print $2
            reported = 1
            next
        }
        {
            previous = $1
            previous_file = $2
            reported = 0
        }
    ' > "$DUPLICATE_IDS"

if [[ -s "$DUPLICATE_IDS" ]]; then
    echo "[ERROR] Duplicate Rule ID across custom exclusion files:"
    cat "$DUPLICATE_IDS"
    exit 1
fi

sort -n "$CONFIG_IDS" -o "$CONFIG_IDS"
comm -23 "$CONFIG_IDS" "$REGISTRY_IDS" > "${WORKDIR}/unregistered-ids.txt"
comm -13 "$CONFIG_IDS" "$REGISTRY_IDS" > "${WORKDIR}/unused-ids.txt"

if [[ -s "${WORKDIR}/unregistered-ids.txt" ]]; then
    echo "[ERROR] Rule ID in custom *.conf not registered in RULE-ID.txt:"
    sed 's/^/        /' "${WORKDIR}/unregistered-ids.txt"
    exit 1
fi

if [[ -s "${WORKDIR}/unused-ids.txt" ]]; then
    echo "[ERROR] Rule ID registered but not found in custom *.conf:"
    sed 's/^/        /' "${WORKDIR}/unused-ids.txt"
    exit 1
fi

CUSTOM_RULE_COUNT=$(wc -l < "$CONFIG_IDS" | tr -d ' ')
echo "[INFO] Custom exclusion Rule IDs validated: ${CUSTOM_RULE_COUNT}"

#
# Collect ModSecurity rules.
# Only *.conf files are included; README.md and RULE-ID.txt are not.
#
mapfile -d '' RULE_FILES < <(
    find "$RULES_DIR" -type f -name "*.conf" -print0 | sort -z
)

RULE_COUNT="${#RULE_FILES[@]}"
if [[ "$RULE_COUNT" -eq 0 ]]; then
    echo "[ERROR] No ModSecurity rules found."
    exit 1
fi

echo "[INFO] ModSecurity rules found: ${RULE_COUNT}"

#
# Generate ModSecurity Include File
#
echo "[2/5] Generating ModSecurity Include File..."

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
include /etc/nginx/modsecurity/crs-load.conf

#
# BREBES-WAF Rules
#

EOF

for file in "${RULE_FILES[@]}"; do
    printf 'Include %s\n' "$file" >> "$TMPFILE"
done

if [[ -f "$OUTPUT" ]]; then
    cp "$OUTPUT" "$BACKUP"
fi

mv "$TMPFILE" "$OUTPUT"

echo "[3/5] Testing Nginx Configuration..."

if nginx -t; then
    echo "[4/5] Reloading Nginx..."
    systemctl reload nginx

    echo "[5/5] Deployment Successful"
    echo
    echo "-----------------------------------------"
    echo "Loaded Rules         : $RULE_COUNT"
    echo "Custom Exclusion IDs : $CUSTOM_RULE_COUNT"
    echo "Include File         : $OUTPUT"
    echo "Backup File          : $BACKUP"
    echo "Rule ID Registry     : $RULE_ID_FILE"
    echo "-----------------------------------------"
else
    echo "[ERROR] nginx configuration test failed."

    if [[ -f "$BACKUP" ]]; then
        cp "$BACKUP" "$OUTPUT"
        echo "[INFO] Previous include file restored."
    else
        echo "[WARNING] No previous backup available."
        echo "[WARNING] Generated include file remains at: $OUTPUT"
    fi

    exit 1
fi
