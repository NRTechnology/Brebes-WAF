#!/usr/bin/env bash
#
# add-exclusion.sh
# Create one narrowly-scoped ModSecurity target exclusion for BREBES-WAF.
#
# Usage:
#   ./add-exclusion.sh --url https://app.example.com/path?id=1 \
#       --method POST --rule-id 933210 --target 'ARGS:parameter' \
#       --description "False positive description"
#
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_VERSION="1.1.0"

# Resolve BREBES-WAF root from this script location:
# /opt/Brebes-WAF/scripts/add-exclusion.sh -> /opt/Brebes-WAF
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BREBES_WAF_HOME="${BREBES_WAF_HOME:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"
RULES_DIR="${BREBES_WAF_HOME}/rules"
CUSTOM_DIR="${RULES_DIR}/99-custom-exclusions"
REGISTRY="${CUSTOM_DIR}/RULE-ID.txt"

# First ID considered for newly-created local exclusions. Override if needed:
# CUSTOM_ID_START=9900001 ./add-exclusion.sh ...
CUSTOM_ID_START="${CUSTOM_ID_START:-9900001}"

URL=""
METHOD=""
SOURCE_RULE_ID=""
TARGET=""
NAME=""
DESCRIPTION=""
DRY_RUN=0
FORCE=0

TMP_DIR=""
CREATED_FILE=""
REGISTRY_UPDATED=0
REGISTRY_BACKUP=""

log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
add-exclusion.sh - Add one BREBES-WAF custom target exclusion

Required:
  --url URL              Full endpoint URL (query string is ignored for URI match)
  --method METHODS       HTTP method(s), comma-separated, e.g. GET,POST
  --rule-id ID           Existing ModSecurity rule ID to exclude
  --target TARGETS       Optional comma-separated targets, e.g. ARGS:a,ARGS:b
                         If omitted, exclude the entire source rule in this scope

Optional:
  --name NAME            Descriptive application/file name
  --description TEXT     Reason for the exclusion
  --dry-run              Validate and display the proposed rule without changes
  --force                Skip interactive confirmation (does not skip validation)
  -h, --help             Show this help

Environment:
  BREBES_WAF_HOME        Override BREBES-WAF root (default: parent of scripts/)
  CUSTOM_ID_START        First candidate custom ID (default: 9900001)

Example:
  ./scripts/add-exclusion.sh \
    --url 'https://app.example.com/user/process?id=123' \
    --method POST \
    --rule-id 933210 \
    --target 'ARGS:document_type,ARGS:other_field' \
    --description 'False positive pada parameter document_type'

This script creates a custom exclusion only. It does not run nginx -t or reload Nginx.
Use deploy.sh to validate and deploy the resulting configuration.
EOF
}

need_value() {
    [[ $# -ge 2 && -n "${2}" ]] || die "Argumen $1 membutuhkan nilai."
}

while (($#)); do
    case "$1" in
        --url) need_value "$@"; URL="$2"; shift 2 ;;
        --method) need_value "$@"; METHOD="$2"; shift 2 ;;
        --rule-id) need_value "$@"; SOURCE_RULE_ID="$2"; shift 2 ;;
        --target) need_value "$@"; TARGET="$2"; shift 2 ;;
        --name) need_value "$@"; NAME="$2"; shift 2 ;;
        --description) need_value "$@"; DESCRIPTION="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; (($# == 0)) || die "Argumen setelah -- tidak didukung."; break ;;
        *) die "Argumen tidak dikenal: $1 (gunakan --help)." ;;
    esac
done

[[ -n "$URL" ]] || die "--url wajib diisi."
[[ -n "$METHOD" ]] || die "--method wajib diisi."
[[ -n "$SOURCE_RULE_ID" ]] || die "--rule-id wajib diisi."

command -v python3 >/dev/null 2>&1 || die "python3 tidak ditemukan."
command -v find >/dev/null 2>&1 || die "find tidak ditemukan."
command -v awk >/dev/null 2>&1 || die "awk tidak ditemukan."
command -v sort >/dev/null 2>&1 || die "sort tidak ditemukan."

[[ "$SOURCE_RULE_ID" =~ ^[0-9]+$ ]] || die "Rule ID sumber harus berupa angka."
[[ "$CUSTOM_ID_START" =~ ^[0-9]+$ ]] || die "CUSTOM_ID_START harus berupa angka."
(( CUSTOM_ID_START > 0 )) || die "CUSTOM_ID_START harus lebih besar dari 0."

# Parse and validate comma-separated HTTP methods.
METHODS=()
IFS=',' read -r -a METHOD_INPUTS <<< "$METHOD"
for item in "${METHOD_INPUTS[@]}"; do
    item="${item//[[:space:]]/}"
    item="${item^^}"
    [[ "$item" =~ ^[A-Z][A-Z0-9_-]*$ ]] || die "HTTP method tidak valid: $item"
    for existing in "${METHODS[@]:-}"; do
        [[ "$existing" != "$item" ]] || die "HTTP method duplikat: $item"
    done
    METHODS+=("$item")
done
((${#METHODS[@]} > 0)) || die "--method wajib diisi."
METHOD_DISPLAY="$(IFS=','; printf '%s' "${METHODS[*]}")"
METHOD_REGEX="^("
for i in "${!METHODS[@]}"; do
    (( i == 0 )) || METHOD_REGEX+="|"
    METHOD_REGEX+="${METHODS[$i]}"
done
METHOD_REGEX+=")$"

# --target is optional. If supplied, validate a comma-separated target list.
TARGETS=()
if [[ -n "$TARGET" ]]; then
    IFS=',' read -r -a TARGET_INPUTS <<< "$TARGET"
    for item in "${TARGET_INPUTS[@]}"; do
        item="${item//[[:space:]]/}"
        [[ "$item" =~ ^(ARGS|ARGS_NAMES|REQUEST_HEADERS|REQUEST_COOKIES|FILES|XML)(:[A-Za-z0-9_.:-]+)?$ ]] \
            || die "Format target tidak didukung: $item. Contoh: ARGS:uttp_type"
        for existing in "${TARGETS[@]:-}"; do
            [[ "$existing" != "$item" ]] || die "Target duplikat: $item"
        done
        TARGETS+=("$item")
    done
fi
if ((${#TARGETS[@]} == 0)); then
    TARGET_DISPLAY="ALL (seluruh source rule)"
else
    TARGET_DISPLAY="$(IFS=,; printf '%s' "${TARGETS[*]}")"
fi

[[ -d "$BREBES_WAF_HOME" ]] || die "Direktori BREBES-WAF tidak ditemukan: $BREBES_WAF_HOME"
[[ -d "$RULES_DIR" ]] || die "Direktori rules tidak ditemukan: $RULES_DIR"
[[ -d "$CUSTOM_DIR" ]] || die "Direktori custom exclusions tidak ditemukan: $CUSTOM_DIR"
[[ -f "$REGISTRY" ]] || die "Registry tidak ditemukan: $REGISTRY (buat RULE-ID.txt terlebih dahulu)."

# Parse URL safely. Query and fragment are intentionally excluded from URI matching.
URL_PARTS="$(python3 - "$URL" <<'PY'
import sys
from urllib.parse import urlsplit
try:
    u = urlsplit(sys.argv[1])
    if u.scheme.lower() not in ("http", "https"):
        raise ValueError("scheme harus http atau https")
    if not u.hostname:
        raise ValueError("hostname tidak ditemukan")
    if u.username or u.password:
        raise ValueError("URL tidak boleh berisi username/password")
    host = u.hostname.encode("idna").decode("ascii").lower()
    path = u.path or "/"
    if any(ord(c) < 32 for c in host + path):
        raise ValueError("URL mengandung karakter kontrol")
    # URL path is kept as supplied; ModSecurity REQUEST_URI is path plus query,
    # so exact path matching below uses REQUEST_URI with a query-stripping regex.
    print(host)
    print(path)
except Exception as e:
    print(f"URL tidak valid: {e}", file=sys.stderr)
    sys.exit(2)
PY
)" || die "Gagal mem-parsing URL."
HOST="$(printf '%s\n' "$URL_PARTS" | sed -n '1p')"
URI_PATH="$(printf '%s\n' "$URL_PARTS" | sed -n '2p')"
[[ -n "$HOST" && "$URI_PATH" == /* ]] || die "Hostname atau path URL tidak valid."

# Escape strings for ModSecurity quoted string/regex contexts.
escape_re() {
    sed -e 's/[.[\*^$()+?{|]/\\&/g' -e 's#/#\\/#g' <<<"$1" | tr -d '\n'
}
HOST_RE="$(escape_re "$HOST")"
PATH_RE="$(escape_re "$URI_PATH")"

# Extract actual rule IDs from ModSecurity config files. Comments are stripped
# before scanning. This is a practical text-based scan, not a full SecLang parser.
extract_ids() {
    local file="$1"
    awk '
      {
        sub(/[[:space:]]+#.*/, "")
        if ($0 ~ /^[[:space:]]*#/) next
        line = $0
        while (match(line, /id:[[:space:]]*[0-9]+/)) {
          token = substr(line, RSTART, RLENGTH)
          gsub(/[^0-9]/, "", token)
          if (token != "") print token
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$file"
}

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brebes-exclusion.XXXXXX")"
cleanup() {
    local status=$?
    if (( status != 0 )); then
        if [[ -n "$CREATED_FILE" && -f "$CREATED_FILE" ]]; then
            rm -f -- "$CREATED_FILE"
        fi
        if (( REGISTRY_UPDATED == 1 )) && [[ -n "$REGISTRY_BACKUP" && -f "$REGISTRY_BACKUP" ]]; then
            cp -f -- "$REGISTRY_BACKUP" "$REGISTRY"
        fi
    fi
    [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
    exit "$status"
}
trap cleanup EXIT

REGISTRY_IDS="$TMP_DIR/registry.ids"
ALL_IDS="$TMP_DIR/all.ids"
CUSTOM_IDS="$TMP_DIR/custom.ids"
OTHER_IDS="$TMP_DIR/other.ids"
CRS_IDS="$TMP_DIR/crs.ids"
USED_IDS="$TMP_DIR/used.ids"

# Validate registry: comments and blank lines are allowed; every other line numeric.
awk '
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*#/ { next }
  {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "")
    if ($0 !~ /^[0-9]+$/) {
      printf "Format ID tidak valid pada %s:%d: %s\n", FILENAME, FNR, $0 > "/dev/stderr"
      bad=1
      next
    }
    print $0
  }
  END { exit bad }
' "$REGISTRY" > "$REGISTRY_IDS" || die "Format RULE-ID.txt tidak valid."

sort -n "$REGISTRY_IDS" | uniq -d > "$TMP_DIR/registry.duplicates"
[[ ! -s "$TMP_DIR/registry.duplicates" ]] || {
    die "ID duplikat dalam registry: $(paste -sd ', ' "$TMP_DIR/registry.duplicates")"
}

# Collect BREBES-WAF rule files excluding the local custom-exclusions directory.
: > "$OTHER_IDS"
while IFS= read -r -d '' file; do
    [[ "$file" == "$CUSTOM_DIR/"* ]] && continue
    extract_ids "$file" >> "$OTHER_IDS"
done < <(find "$RULES_DIR" -type f -name '*.conf' -print0)

# Collect custom exclusion IDs from the .conf files.
: > "$CUSTOM_IDS"
while IFS= read -r -d '' file; do
    extract_ids "$file" >> "$CUSTOM_IDS"
done < <(find "$CUSTOM_DIR" -type f -name '*.conf' -print0)

# Discover installed CRS/config rule IDs in common locations.
# BREBES_WAF_CRS_DIRS can add or replace locations (colon-separated).
CRS_DIRS="${BREBES_WAF_CRS_DIRS:-/etc/nginx/modsecurity:/usr/share/modsecurity-crs:/etc/modsecurity}"
: > "$CRS_IDS"
IFS=':' read -r -a CRS_PATHS <<< "$CRS_DIRS"
for dir in "${CRS_PATHS[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' file; do
        # Avoid counting BREBES-WAF local rule files twice.
        [[ "$file" == "$BREBES_WAF_HOME/"* ]] && continue
        extract_ids "$file" >> "$CRS_IDS"
    done < <(find "$dir" -type f -name '*.conf' -print0)
done

# The source rule must exist in BREBES-WAF rules or installed ModSecurity/CRS configs.
cat "$OTHER_IDS" "$CUSTOM_IDS" "$CRS_IDS" | sort -nu > "$ALL_IDS"
grep -Fxq "$SOURCE_RULE_ID" "$ALL_IDS" \
    || die "Rule ID sumber $SOURCE_RULE_ID tidak ditemukan pada rule BREBES-WAF/konfigurasi ModSecurity/CRS yang dipindai."

# Existing custom exclusion IDs must be in registry, and registry must correspond to files.
sort -nu "$CUSTOM_IDS" > "$TMP_DIR/custom.unique"
sort -nu "$REGISTRY_IDS" > "$TMP_DIR/registry.unique"
comm -23 "$TMP_DIR/custom.unique" "$TMP_DIR/registry.unique" > "$TMP_DIR/custom.unregistered"
comm -13 "$TMP_DIR/custom.unique" "$TMP_DIR/registry.unique" > "$TMP_DIR/registry.orphan"
[[ ! -s "$TMP_DIR/custom.unregistered" ]] || die "ID custom .conf belum terdaftar: $(paste -sd ', ' "$TMP_DIR/custom.unregistered")"
[[ ! -s "$TMP_DIR/registry.orphan" ]] || die "ID terdaftar tetapi file .conf tidak ditemukan: $(paste -sd ', ' "$TMP_DIR/registry.orphan")"

# Detect duplicates across custom exclusion files.
while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    count=0
    files=()
    while IFS= read -r -d '' file; do
        if extract_ids "$file" | grep -Fxq "$id"; then
            ((count+=1))
            files+=("$file")
        fi
    done < <(find "$CUSTOM_DIR" -type f -name '*.conf' -print0)
    (( count <= 1 )) || die "ID duplikat antar-file custom exclusion: $id (${files[*]})"
done < "$TMP_DIR/custom.unique"

# Find first unused ID from CUSTOM_ID_START, checking every scanned rule source.
cat "$OTHER_IDS" "$CUSTOM_IDS" "$CRS_IDS" "$REGISTRY_IDS" | sort -nu > "$USED_IDS"
NEW_ID="$CUSTOM_ID_START"
while grep -Fxq "$NEW_ID" "$USED_IDS"; do
    ((NEW_ID+=1))
    (( NEW_ID <= 999999999 )) || die "Tidak menemukan ID custom yang tersedia."
done

slug_source="${NAME:-${HOST%%.*}}-${URI_PATH}"
SLUG="$(printf '%s' "$slug_source" | tr '[:upper:]' '[:lower:]' | sed -E 's#^https?://##; s#[^a-z0-9]+#-#g; s#^-+|-+$##; s#-+#-#g' | cut -c1-70)"
[[ -n "$SLUG" ]] || SLUG="application-endpoint"
OUT_FILE="${CUSTOM_DIR}/${NEW_ID}-${SLUG}.conf"
[[ ! -e "$OUT_FILE" ]] || die "File tujuan sudah ada: $OUT_FILE"

# REQUEST_URI includes the query string. Match the path only, regardless of query.
# The escaped path is anchored and followed by end-of-string or '?'.
# Build a readable BREBES-WAF audit message; escape quotes/backslashes for SecLang.
LOG_RAW="BREBES-WAF custom exclusion matched: host=${HOST} methods=${METHOD_DISPLAY} uri=${URI_PATH} source_rule=${SOURCE_RULE_ID} custom_rule=${NEW_ID}"
LOG_MESSAGE="$(printf '%s' "$LOG_RAW" | tr "\\\'" "__")"

# Build the final ctl action. With no target, remove the whole source rule;
# otherwise remove only the listed targets from that source rule.
CTL_ACTIONS=()
if ((${#TARGETS[@]} == 0)); then
    CTL_ACTIONS+=("ctl:ruleRemoveById=${SOURCE_RULE_ID}")
else
    for target_item in "${TARGETS[@]}"; do
        CTL_ACTIONS+=("ctl:ruleRemoveTargetById=${SOURCE_RULE_ID};${target_item}")
    done
fi
CTL_ACTION="$(IFS=','; printf '%s' "${CTL_ACTIONS[*]}")"

RULE_CONTENT=$(cat <<EOF
# Application : ${NAME:-${HOST}}
# Host        : ${HOST}
# Endpoint    : ${URI_PATH}
# Methods     : ${METHOD_DISPLAY}
# Source Rule : ${SOURCE_RULE_ID}
# Target      : ${TARGET_DISPLAY}
# Description : ${DESCRIPTION:-Not specified}
# Generated   : $(date '+%Y-%m-%d %H:%M:%S %z')
#
# BREBES-WAF scoped exclusion. The audit event is logged when this chain matches.

SecRule REQUEST_HEADERS:Host "@streq ${HOST}" \
    "id:${NEW_ID},phase:1,pass,log,msg:'${LOG_MESSAGE}',tag:'BREBES-WAF/EXCLUSION',chain"
    SecRule REQUEST_METHOD "@rx ${METHOD_REGEX}" "chain"
    SecRule REQUEST_URI "@rx ^${PATH_RE}(?:\\?.*)?$" \
        "${CTL_ACTION}"
EOF
)


printf '%s\n' "$RULE_CONTENT" > "$TMP_DIR/proposed.conf"

log "Ringkasan exclusion:"
printf '  Host             : %s\n' "$HOST"
printf '  URI path         : %s\n' "$URI_PATH"
printf '  HTTP methods     : %s\n' "$METHOD_DISPLAY"
printf '  Source Rule ID   : %s\n' "$SOURCE_RULE_ID"
printf '  Target           : %s\n' "$TARGET_DISPLAY"
printf '  New custom ID    : %s\n' "$NEW_ID"
printf '  Output           : %s\n' "$OUT_FILE"
printf '\n'
cat "$TMP_DIR/proposed.conf"
printf '\n'

if (( DRY_RUN == 1 )); then
    log "DRY-RUN: tidak ada file atau registry yang diubah."
    exit 0
fi

if (( FORCE == 0 )); then
    [[ -t 0 ]] || die "Mode non-interaktif: gunakan --force untuk menyetujui pembuatan."
    read -r -p "Buat file exclusion dan daftarkan ID ${NEW_ID}? [y/N] " answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Dibatalkan pengguna."
fi

# Atomic-ish update: stage both files, preserve registry backup for rollback.
REGISTRY_BACKUP="$TMP_DIR/RULE-ID.txt.backup"
cp -p -- "$REGISTRY" "$REGISTRY_BACKUP"
REGISTRY_TMP="${REGISTRY}.tmp.$$"
trap 'rm -f -- "$REGISTRY_TMP"; cleanup' EXIT

# Preserve existing registry comments/order and append the new ID.
cat "$REGISTRY" > "$REGISTRY_TMP"
printf '%s\n' "$NEW_ID" >> "$REGISTRY_TMP"

# Create config first, then replace registry. On failure cleanup removes config
# and restores registry from backup.
install -m 0640 "$TMP_DIR/proposed.conf" "$OUT_FILE"
CREATED_FILE="$OUT_FILE"
mv -f -- "$REGISTRY_TMP" "$REGISTRY"
REGISTRY_UPDATED=1

# Post-write consistency check.
grep -Fxq "$NEW_ID" "$REGISTRY" || die "Gagal memverifikasi ID pada registry."
extract_ids "$OUT_FILE" | grep -Fxq "$NEW_ID" || die "Gagal memverifikasi ID pada file exclusion."

log "Exclusion berhasil dibuat."
log "File       : $OUT_FILE"
log "Registry   : $REGISTRY"
log "Custom ID  : $NEW_ID"
log "Langkah berikutnya: jalankan deploy.sh untuk validasi konfigurasi dan deployment."
