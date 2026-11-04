#!/bin/bash

# =============================================================================
# BREBES-WAF
# =============================================================================
# Script  : analyze-detection.sh
# Version : 1.4.0
#
# Description:
#   Analyze ModSecurity audit logs for a specific domain and date.
#   Displays BREBES-WAF, OWASP CRS, and other ModSecurity rule detections,
#   including a frequency summary grouped by Rule ID.
#
# Usage:
#   ./analyze-detection.sh <domain> [YYYYMMDD]
#
# Example:
#   ./analyze-detection.sh app.example.com
#   ./analyze-detection.sh app.example.com 20260915
#
# Audit log structure:
#   ---xxxx---B--
#   POST /path HTTP/1.1
#   Host: example.brebeskab.go.id
#   ...
#   ---xxxx---H--
#   ModSecurity: Access denied ... [id "2001001"] ...
#
# Domain detection is based on HTTP Host from section B.
# Do NOT use [hostname "..."] from section H to identify the domain.
# =============================================================================

set -u

# =============================================================================
# Configuration
# =============================================================================

BASE_DIR="/var/log/nginx/modsecurity"

# =============================================================================
# Functions
# =============================================================================

usage() {
    cat <<EOF

Usage:
  $0 <domain> [YYYYMMDD]

Example:
  $0 app.example.com
  $0 app.example.com 20260915

EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

normalize_host() {
    local host="$1"

    # Remove CR/LF and surrounding whitespace.
    host="${host//$'\r'/}"
    host="${host//$'\n'/}"
    host="${host#"${host%%[![:space:]]*}"}"
    host="${host%"${host##*[![:space:]]}"}"

    # Hostnames are case-insensitive; a trailing DNS dot is optional.
    host="${host%.}"

    # Remove a numeric port from ordinary hostname:port or IPv4:port.
    # Do not alter IPv6 literals, which contain more than one colon.
    if [[ "$host" =~ ^([^:]+):[0-9]+$ ]]; then
        host="${BASH_REMATCH[1]}"
    fi

    printf '%s' "${host,,}"
}

# =============================================================================
# Arguments and validation
# =============================================================================

DOMAIN="${1:-}"
DATE="${2:-$(date +%Y%m%d)}"

if [[ -z "$DOMAIN" ]]; then
    usage
    exit 1
fi

DOMAIN="$(normalize_host "$DOMAIN")"

if [[ -z "$DOMAIN" || "$DOMAIN" == *"/"* || "$DOMAIN" == *" "* ]]; then
    die "Invalid domain: ${DOMAIN}"
fi

# Strict date format and real calendar-date validation prevent path traversal
# and accidental access to an unintended log directory.
if [[ ! "$DATE" =~ ^[0-9]{8}$ ]]; then
    die "Invalid date format. Use YYYYMMDD."
fi

NORMALIZED_DATE="$(date -d "$DATE" +%Y%m%d 2>/dev/null)" ||
    die "Invalid calendar date: ${DATE}"

if [[ "$NORMALIZED_DATE" != "$DATE" ]]; then
    die "Invalid calendar date: ${DATE}"
fi

LOG_DIR="${BASE_DIR}/${DATE}"

# =============================================================================
# Dependency checks
# =============================================================================

for command_name in awk date find grep sort strings; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "Required command not found: ${command_name}"
done

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
# Validate log directory
# =============================================================================

if [[ ! -d "$LOG_DIR" ]]; then
    die "Log directory not found: ${LOG_DIR}"
fi

if [[ ! -r "$LOG_DIR" || ! -x "$LOG_DIR" ]]; then
    die "Log directory is not readable/searchable: ${LOG_DIR}"
fi

# Collect files first, preserving filenames with spaces and special characters.
# Check find's exit status explicitly instead of silently treating errors as
# an empty directory.
FIND_ERROR_FILE="$(mktemp)" || die "Unable to create temporary file."

if ! find "$LOG_DIR" -type f -print0 2>"$FIND_ERROR_FILE" |
    sort -z >"${FIND_ERROR_FILE}.sorted"; then
    cat "$FIND_ERROR_FILE" >&2
    rm -f "$FIND_ERROR_FILE" "${FIND_ERROR_FILE}.sorted"
    die "Failed to enumerate audit log files."
fi

if [[ -s "$FIND_ERROR_FILE" ]]; then
    cat "$FIND_ERROR_FILE" >&2
    rm -f "$FIND_ERROR_FILE" "${FIND_ERROR_FILE}.sorted"
    die "Errors occurred while enumerating audit log files."
fi

mapfile -d '' LOG_FILES <"${FIND_ERROR_FILE}.sorted"
rm -f "$FIND_ERROR_FILE" "${FIND_ERROR_FILE}.sorted"

if [[ "${#LOG_FILES[@]}" -eq 0 ]]; then
    echo "No audit log files found in: ${LOG_DIR}"
    echo
    echo "============================================================"
    echo " Detection Analysis Completed"
    echo "============================================================"
    echo
    exit 0
fi

# =============================================================================
# Statistics
# =============================================================================

TOTAL_LOGS=0
READABLE_LOGS=0
MATCHED_DOMAIN_LOGS=0
DETECTION_LOGS=0
BREBES_WAF_COUNT=0
CRS_COUNT=0
OTHER_RULE_COUNT=0
UNCLASSIFIED_ID_COUNT=0

declare -A RULE_ID_COUNTS=()
declare -A RULE_ID_CATEGORIES=()

# =============================================================================
# Process audit logs
# =============================================================================

for LOG in "${LOG_FILES[@]}"; do
    TOTAL_LOGS=$((TOTAL_LOGS + 1))

    if [[ ! -r "$LOG" ]]; then
        echo "WARNING: Cannot read file: ${LOG}" >&2
        continue
    fi

    # ModSecurity audit logs may contain binary/NUL bytes. strings keeps the
    # printable text required by this analyzer and avoids Bash NUL warnings.
    LOG_CONTENT="$(strings "$LOG" 2>/dev/null)" || {
        echo "WARNING: Failed to read audit log: ${LOG}" >&2
        continue
    }

    if [[ -z "$LOG_CONTENT" ]]; then
        continue
    fi

    READABLE_LOGS=$((READABLE_LOGS + 1))

    # Extract HTTP Host only from section B. Header names are case-insensitive.
    REQUEST_HOST="$(
        printf '%s\n' "$LOG_CONTENT" |
        awk '
            /^---.*---B--$/ {
                in_request=1
                next
            }
            /^---.*---[A-Z]--$/ {
                if (in_request) exit
            }
            in_request {
                line=$0
                sub(/\r$/, "", line)
                if (tolower(line) ~ /^host:[[:space:]]*/) {
                    sub(/^[^:]*:[[:space:]]*/, "", line)
                    print line
                    exit
                }
            }
        '
    )"

    REQUEST_HOST="$(normalize_host "$REQUEST_HOST")"

    if [[ -z "$REQUEST_HOST" ]]; then
        continue
    fi

    if [[ "$REQUEST_HOST" != "$DOMAIN" ]]; then
        continue
    fi

    MATCHED_DOMAIN_LOGS=$((MATCHED_DOMAIN_LOGS + 1))

    # Extract section H. Do not use hostname metadata in this section for
    # request-domain matching.
    DETECTIONS="$(
        printf '%s\n' "$LOG_CONTENT" |
        awk '
            /^---.*---H--$/ {
                in_detection=1
                next
            }
            /^---.*---[A-Z]--$/ {
                if (in_detection) exit
            }
            in_detection {
                print
            }
        '
    )"

    [[ -z "$DETECTIONS" ]] && continue

    BREBES_WAF="$(
        printf '%s\n' "$DETECTIONS" |
        grep -F 'BREBES-WAF' || true
    )"

    # A CRS event is identified by CRS metadata, not merely by the presence
    # of an [id "..."] field. Other ModSecurity rules are retained separately.
    CRS="$(
        printf '%s\n' "$DETECTIONS" |
        grep -E 'OWASP_CRS/|owasp-crs|REQUEST-[A-Z0-9_-]+\.conf' |
        grep -v -F 'BREBES-WAF' || true
    )"

    # Preserve rule events not recognized as BREBES-WAF or CRS. This avoids
    # silently dropping vendor/local ModSecurity rules from the report.
    OTHER_RULES="$(
        printf '%s\n' "$DETECTIONS" |
        grep -E '\[id "[0-9]+"\]' |
        grep -v -F 'BREBES-WAF' |
        grep -v -E 'OWASP_CRS/|owasp-crs|REQUEST-[A-Z0-9_-]+\.conf' || true
    )"

    if [[ -z "$BREBES_WAF" && -z "$CRS" && -z "$OTHER_RULES" ]]; then
        continue
    fi

    DETECTION_LOGS=$((DETECTION_LOGS + 1))

    # Count BREBES-WAF events.
    if [[ -n "$BREBES_WAF" ]]; then
        COUNT="$(printf '%s\n' "$BREBES_WAF" | grep -c -F 'BREBES-WAF' || true)"
        BREBES_WAF_COUNT=$((BREBES_WAF_COUNT + COUNT))
    fi

    # Count CRS and other rule events and build a Rule ID frequency summary.
    while IFS= read -r DETECTION_LINE; do
        [[ -z "$DETECTION_LINE" ]] && continue

        if [[ "$DETECTION_LINE" == *'BREBES-WAF'* ]]; then
            CATEGORY="BREBES-WAF"
        elif [[ "$DETECTION_LINE" == *'OWASP_CRS/'* ||
                "$DETECTION_LINE" == *'owasp-crs'* ||
                "$DETECTION_LINE" =~ REQUEST-[A-Z0-9_-]+\.conf ]]; then
            CATEGORY="OWASP CRS"
            CRS_COUNT=$((CRS_COUNT + 1))
        elif [[ "$DETECTION_LINE" =~ \[id[[:space:]]\"[0-9]+\"\] ]]; then
            CATEGORY="Other ModSecurity"
            OTHER_RULE_COUNT=$((OTHER_RULE_COUNT + 1))
        else
            continue
        fi

        if [[ "$DETECTION_LINE" =~ \[id[[:space:]]\"([0-9]+)\"\] ]]; then
            RULE_ID="${BASH_REMATCH[1]}"
            RULE_ID_COUNTS["$RULE_ID"]=$(( ${RULE_ID_COUNTS["$RULE_ID"]:-0} + 1 ))

            if [[ -n "${RULE_ID_CATEGORIES[$RULE_ID]:-}" ]]; then
                case "|${RULE_ID_CATEGORIES[$RULE_ID]}|" in
                    *"|${CATEGORY}|"*) ;;
                    *) RULE_ID_CATEGORIES["$RULE_ID"]+=", ${CATEGORY}" ;;
                esac
            else
                RULE_ID_CATEGORIES["$RULE_ID"]="$CATEGORY"
            fi
        else
            UNCLASSIFIED_ID_COUNT=$((UNCLASSIFIED_ID_COUNT + 1))
        fi
    done <<<"$DETECTIONS"

    # =========================================================================
    # Display detections for this audit log
    # =========================================================================

    echo "============================================================"
    echo " Log File : ${LOG}"
    echo " Domain   : ${REQUEST_HOST}"
    echo "============================================================"

    if [[ -n "$BREBES_WAF" ]]; then
        echo
        echo "===== BREBES-WAF ====="
        printf '%s\n' "$BREBES_WAF"
    fi

    if [[ -n "$CRS" ]]; then
        echo
        echo "===== OWASP CRS ====="
        printf '%s\n' "$CRS"
    fi

    if [[ -n "$OTHER_RULES" ]]; then
        echo
        echo "===== OTHER MODSECURITY RULES ====="
        printf '%s\n' "$OTHER_RULES"
    fi

    echo
done

# =============================================================================
# Summary
# =============================================================================

echo "============================================================"
echo " Detection Analysis Summary"
echo "============================================================"
echo
echo "Domain                       : ${DOMAIN}"
echo "Date                         : ${DATE}"
echo "Total audit log files        : ${TOTAL_LOGS}"
echo "Readable audit log files     : ${READABLE_LOGS}"
echo "Domain matched audit logs    : ${MATCHED_DOMAIN_LOGS}"
echo "Logs containing detections  : ${DETECTION_LOGS}"
echo "BREBES-WAF detection events  : ${BREBES_WAF_COUNT}"
echo "OWASP CRS detection events   : ${CRS_COUNT}"
echo "Other ModSecurity events     : ${OTHER_RULE_COUNT}"
echo "Rule events without ID       : ${UNCLASSIFIED_ID_COUNT}"
echo

# Rule ID summary, sorted numerically by Rule ID.
echo "============================================================"
echo " Rule ID Summary"
echo "============================================================"

if [[ "${#RULE_ID_COUNTS[@]}" -eq 0 ]]; then
    echo "No Rule ID events found."
else
    printf '%-12s %-24s %s\n' "RULE ID" "CATEGORY" "EVENT COUNT"
    printf '%-12s %-24s %s\n' "------------" "------------------------" "-----------"

    while IFS= read -r RULE_ID; do
        printf '%-12s %-24s %s\n' \
            "$RULE_ID" \
            "${RULE_ID_CATEGORIES[$RULE_ID]}" \
            "${RULE_ID_COUNTS[$RULE_ID]}"
    done < <(printf '%s\n' "${!RULE_ID_COUNTS[@]}" | sort -n)
fi

echo

if [[ "$DETECTION_LOGS" -eq 0 ]]; then
    echo "No BREBES-WAF/OWASP CRS/other ModSecurity rule detection found."
fi

echo "============================================================"
echo " Detection Analysis Completed"
echo "============================================================"
echo

exit 0
