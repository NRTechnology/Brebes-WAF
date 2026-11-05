#!/usr/bin/env bash
#
# BREBES-WAF - Remove Custom ModSecurity Exclusion
# File: scripts/remove-exclusions.sh
#
# Usage:
#   ./scripts/remove-exclusions.sh --rule-id 9900001
#   ./scripts/remove-exclusions.sh --rule-id 9900001 --dry-run
#   ./scripts/remove-exclusions.sh --rule-id 9900001 --force
#
# Only removes a custom exclusion .conf and its exact ID entry in RULE-ID.txt.
# Does not run nginx -t, reload Nginx, or deploy changes.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BREBES_WAF_HOME="${BREBES_WAF_HOME:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}"

EXCLUSIONS_DIR="${BREBES_WAF_HOME}/rules/99-custom-exclusions"
REGISTRY_FILE="${EXCLUSIONS_DIR}/RULE-ID.txt"
BACKUP_ROOT="${BREBES_WAF_HOME}/backup/remove-exclusions"

RULE_ID=""
DRY_RUN=false
FORCE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { printf '%b[INFO]%b %s\n' "${BLUE}" "${NC}" "$*"; }
log_ok()    { printf '%b[ OK ]%b %s\n' "${GREEN}" "${NC}" "$*"; }
log_warn()  { printf '%b[WARN]%b %s\n' "${YELLOW}" "${NC}" "$*"; }
log_error() { printf '%b[ERROR]%b %s\n' "${RED}" "${NC}" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

usage() {
    cat <<EOF
BREBES-WAF - Remove Custom Exclusion

Usage:
  $0 --rule-id ID [options]

Required:
  --rule-id ID    Custom Rule ID yang akan dihapus.

Options:
  --dry-run       Tampilkan rencana penghapusan tanpa mengubah file.
  --force         Hapus tanpa meminta konfirmasi.
  -h, --help      Tampilkan bantuan.

Example:
  $0 --rule-id 9900001
  $0 --rule-id 9900001 --dry-run
  $0 --rule-id 9900001 --force

Yang dihapus:
  - File .conf dari ${EXCLUSIONS_DIR}
  - Entry Rule ID dari ${REGISTRY_FILE}

Backup:
  ${BACKUP_ROOT}

Script ini tidak menjalankan nginx -t, reload Nginx, atau deploy.
Jalankan scripts/deploy.sh setelah perubahan diperiksa.
EOF
}

while (($#)); do
    case "$1" in
        --rule-id)
            (($# >= 2)) || die "Opsi --rule-id membutuhkan nilai."
            [[ -z "${RULE_ID}" ]] || die "Opsi --rule-id hanya boleh diberikan satu kali."
            RULE_ID="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Parameter tidak dikenal: $1. Gunakan --help."
            ;;
    esac
done

[[ "${EUID}" -eq 0 ]] || die "Script harus dijalankan sebagai root."
[[ -n "${RULE_ID}" ]] || die "Parameter --rule-id wajib diberikan."
[[ "${RULE_ID}" =~ ^[0-9]+$ ]] ||
    die "Format Rule ID tidak valid: '${RULE_ID}'. Gunakan angka saja."

[[ -d "${BREBES_WAF_HOME}" ]] ||
    die "BREBES-WAF repository tidak ditemukan: ${BREBES_WAF_HOME}"
[[ -d "${EXCLUSIONS_DIR}" ]] ||
    die "Direktori custom exclusions tidak ditemukan: ${EXCLUSIONS_DIR}"
[[ -f "${REGISTRY_FILE}" && ! -L "${REGISTRY_FILE}" ]] ||
    die "Registry tidak ditemukan atau berupa symbolic link: ${REGISTRY_FILE}"

command -v flock >/dev/null 2>&1 || die "Perintah flock tidak ditemukan."
exec 9>"${EXCLUSIONS_DIR}/.remove-exclusions.lock"
flock -n 9 || die "Operasi add/remove lain sedang berjalan. Coba lagi nanti."

# Registry format: one custom numeric Rule ID per line.
REGISTRY_MATCHES="$(awk -v id="${RULE_ID}" '
    {
        value=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value == id) count++
    }
    END { print count+0 }
' "${REGISTRY_FILE}")"

[[ "${REGISTRY_MATCHES}" -eq 1 ]] ||
    die "Rule ID ${RULE_ID} harus tercatat tepat satu kali di RULE-ID.txt (ditemukan: ${REGISTRY_MATCHES}). Registry tidak diubah."

# Only regular files directly inside custom-exclusions are eligible.
mapfile -d '' RULE_FILES < <(
    find "${EXCLUSIONS_DIR}" -maxdepth 1 -type f \
        \( -name "${RULE_ID}-*.conf" -o -name "${RULE_ID}.conf" \) \
        -print0
)

[[ "${#RULE_FILES[@]}" -eq 1 ]] ||
    die "File rule untuk ID ${RULE_ID} harus ditemukan tepat satu (ditemukan: ${#RULE_FILES[@]}). Registry tidak diubah."

RULE_FILE="${RULE_FILES[0]}"
RULE_REAL="$(realpath -e -- "${RULE_FILE}")"
EXCLUSIONS_REAL="$(realpath -e -- "${EXCLUSIONS_DIR}")"
[[ "$(dirname -- "${RULE_REAL}")" == "${EXCLUSIONS_REAL}" ]] ||
    die "File rule berada di luar direktori custom exclusions."
[[ -r "${RULE_FILE}" && -w "${EXCLUSIONS_DIR}" ]] ||
    die "File rule tidak dapat dibaca atau direktori tidak dapat ditulisi."
[[ -w "${REGISTRY_FILE}" ]] || die "Registry tidak dapat ditulisi."

printf '\n'
printf '%s\n' "============================================================"
printf '%s\n' " BREBES-WAF Custom Exclusion Removal"
printf '%s\n' "============================================================"
printf 'BREBES-WAF : %s\n' "${BREBES_WAF_HOME}"
printf 'Rule ID    : %s\n' "${RULE_ID}"
printf 'Rule file  : %s\n' "${RULE_FILE}"
printf 'Registry   : %s\n' "${REGISTRY_FILE}"
printf '\n%s\n' "--- Informasi rule ---"
sed -n '1,20p' "${RULE_FILE}"
printf '\n'

if [[ "${DRY_RUN}" == true ]]; then
    log_warn "DRY-RUN: tidak ada file atau registry yang diubah."
    log_info "File yang akan dihapus : ${RULE_FILE}"
    log_info "Entry registry         : ${RULE_ID}"
    exit 0
fi

if [[ "${FORCE}" != true ]]; then
    [[ -t 0 ]] ||
        die "Tidak ada terminal untuk konfirmasi. Gunakan --force jika penghapusan memang diinginkan."
    read -r -p "Yakin menghapus exclusion ${RULE_ID}? [y/N] " answer
    case "${answer}" in
        y|Y|yes|YES|Yes) ;;
        *) log_warn "Penghapusan dibatalkan."; exit 0 ;;
    esac
fi

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}-${RULE_ID}"
mkdir -p -- "${BACKUP_DIR}"

BACKUP_RULE="${BACKUP_DIR}/$(basename -- "${RULE_FILE}")"
BACKUP_REGISTRY="${BACKUP_DIR}/RULE-ID.txt"
TEMP_REGISTRY="${EXCLUSIONS_DIR}/.RULE-ID.txt.tmp.$$"

cleanup() {
    rm -f -- "${TEMP_REGISTRY}"
}
trap cleanup EXIT

# Back up both files before changing either one.
cp -a -- "${RULE_FILE}" "${BACKUP_RULE}"
cp -a -- "${REGISTRY_FILE}" "${BACKUP_REGISTRY}"
log_ok "Backup rule dan registry dibuat: ${BACKUP_DIR}"

# Prepare replacement registry in the same filesystem.
awk -v id="${RULE_ID}" '
    {
        value=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value != id) print $0
    }
' "${REGISTRY_FILE}" > "${TEMP_REGISTRY}"

chmod --reference="${REGISTRY_FILE}" "${TEMP_REGISTRY}"
chown --reference="${REGISTRY_FILE}" "${TEMP_REGISTRY}"

# Remove rule first. If registry replacement fails, restore both backups.
if ! rm -- "${RULE_FILE}"; then
    die "Gagal menghapus file rule. Registry tidak diubah."
fi

if ! mv -f -- "${TEMP_REGISTRY}" "${REGISTRY_FILE}"; then
    log_error "Gagal memperbarui registry. Melakukan rollback..."
    cp -a -- "${BACKUP_RULE}" "${RULE_FILE}" ||
        log_error "Pemulihan file rule gagal. Pulihkan manual dari ${BACKUP_RULE}"
    cp -a -- "${BACKUP_REGISTRY}" "${REGISTRY_FILE}" ||
        log_error "Pemulihan registry gagal. Pulihkan manual dari ${BACKUP_REGISTRY}"
    die "Penghapusan dibatalkan karena registry gagal diperbarui."
fi

# Verify final state.
if [[ -e "${RULE_FILE}" ]]; then
    log_error "File rule masih ditemukan. Melakukan rollback..."
    cp -a -- "${BACKUP_RULE}" "${RULE_FILE}" || true
    cp -a -- "${BACKUP_REGISTRY}" "${REGISTRY_FILE}" || true
    die "Verifikasi penghapusan file gagal."
fi

REMAINING_MATCHES="$(awk -v id="${RULE_ID}" '
    {
        value=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value == id) count++
    }
    END { print count+0 }
' "${REGISTRY_FILE}")"

if [[ "${REMAINING_MATCHES}" -ne 0 ]]; then
    log_error "Rule ID masih tercatat. Melakukan rollback..."
    cp -a -- "${BACKUP_RULE}" "${RULE_FILE}" || true
    cp -a -- "${BACKUP_REGISTRY}" "${REGISTRY_FILE}" || true
    die "Verifikasi registry gagal."
fi

printf '\n'
log_ok "Custom exclusion berhasil dihapus."
log_ok "File rule dihapus : ${RULE_FILE}"
log_ok "Rule ID dihapus   : ${RULE_ID}"
log_ok "Backup tersedia   : ${BACKUP_DIR}"
printf '\n'
log_warn "Perubahan belum diterapkan ke runtime Nginx."
log_info "Jalankan scripts/deploy.sh setelah memastikan penghapusan sudah benar."
