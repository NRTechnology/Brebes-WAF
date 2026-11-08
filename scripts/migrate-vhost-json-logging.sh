#!/usr/bin/env bash
# =============================================================================
# BREBES-WAF - Migrate active Nginx virtual-host access logs: reverser -> JSON
# Version: 1.0.0
#
# Safe by default: run without arguments for a dry-run.
# Apply changes only with: --apply
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="${0##*/}"
TARGET_FORMAT="brebes_waf_json"
SOURCE_FORMAT="reverser"
BACKUP_ROOT="/opt/Brebes-WAF/backup/vhost-log-migration"
NGINX_BIN="$(command -v nginx || true)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
ok(){ printf "${GREEN}[ OK ]${NC} %s\n" "$*"; }
warn(){ printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err(){ printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die(){ err "$*"; exit 1; }

usage(){
    cat <<USAGE
Usage:
  sudo ${SCRIPT_NAME}            # dry-run, no files changed
  sudo ${SCRIPT_NAME} --dry-run  # explicit dry-run
  sudo ${SCRIPT_NAME} --apply    # backup, migrate, validate, rollback on error

Only active configuration files reported by 'nginx -T' are examined.
Only access_log directives whose format argument is exactly '${SOURCE_FORMAT}'
are changed. Log paths, options, access_log off, and other formats are preserved.
USAGE
}

MODE="dry-run"
case "${1:-}" in
    "") ;;
    --dry-run) MODE="dry-run" ;;
    --apply) MODE="apply" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "Argumen tidak dikenal: $1" ;;
esac
[[ "$#" -le 1 ]] || { usage; die "Terlalu banyak argumen."; }
[[ "${EUID}" -eq 0 ]] || die "Jalankan sebagai root: sudo $0 [--dry-run|--apply]"
[[ -n "${NGINX_BIN}" ]] || die "nginx tidak ditemukan."
command -v python3 >/dev/null 2>&1 || die "python3 tidak ditemukan."

TMP_DIR="$(mktemp -d /tmp/brebes-waf-log-migrate.XXXXXX)"
cleanup(){ rm -rf "$TMP_DIR"; }
trap cleanup EXIT

info "Memeriksa konfigurasi aktif menggunakan nginx -T ..."
if ! "$NGINX_BIN" -T >"${TMP_DIR}/nginx-T.txt" 2>"${TMP_DIR}/nginx-T.err"; then
    cat "${TMP_DIR}/nginx-T.err" >&2
    die "nginx -T gagal. Tidak ada file yang diubah."
fi

# The embedded parser reads nginx -T output, identifies active source files,
# lexes Nginx directives (comments/quotes/braces aware), and creates a plan.
python3 - "${TMP_DIR}/nginx-T.txt" "${TMP_DIR}/plan.tsv" "${SOURCE_FORMAT}" "${TARGET_FORMAT}" <<'PY'
import os, re, sys, shlex

source_file, plan_file, old_fmt, new_fmt = sys.argv[1:]
text = open(source_file, encoding='utf-8', errors='replace').read()
marker = re.compile(r'^# configuration file (.+):\s*$', re.M)
matches = list(marker.finditer(text))
if not matches:
    raise SystemExit('Tidak menemukan blok file dari output nginx -T.')

files = {}
for i, m in enumerate(matches):
    path = m.group(1).strip()
    end = matches[i+1].start() if i+1 < len(matches) else len(text)
    if path.startswith('/') and os.path.isfile(path):
        # Read the real source file so byte offsets map exactly when applying edits.
        real = os.path.realpath(path)
        if real not in files:
            with open(real, encoding='utf-8', errors='surrogateescape') as fh:
                files[real] = fh.read()

if not files:
    raise SystemExit('Tidak ada file konfigurasi aktif yang dapat dibaca.')

def statements(src):
    """Yield (statement_start, statement_end_without_semicolon, raw_statement).
       Tracks quotes, escapes and comments; braces only affect context, not parsing."""
    start = 0; quote = None; esc = False; comment = False
    for i, ch in enumerate(src):
        if comment:
            if ch == '\n': comment = False
            continue
        if quote:
            if esc: esc = False
            elif ch == '\\': esc = True
            elif ch == quote: quote = None
            continue
        if ch in ('"', "'"):
            quote = ch
        elif ch == '#':
            comment = True
        elif ch == ';':
            yield start, i, src[start:i]
            start = i + 1
        elif ch in '{}':
            # A block opener/closer cannot contain an access_log directive.
            start = i + 1

def token_spans(s):
    """Nginx-style token spans; enough to identify directive and format token."""
    out=[]; i=0; n=len(s)
    while i<n:
        while i<n and s[i].isspace(): i+=1
        if i<n and s[i]=='#':
            while i<n and s[i]!='\n': i+=1
            continue
        if i>=n: break
        a=i; quote=None; esc=False
        while i<n:
            c=s[i]
            if quote:
                if esc: esc=False
                elif c=='\\': esc=True
                elif c==quote: quote=None
                i+=1; continue
            if c in ('"', "'"): quote=c; i+=1; continue
            if c.isspace(): break
            i+=1
        out.append((a,i,s[a:i]))
    return out

plan=[]
for path, body in files.items():
    for a,b,stmt in statements(body):
        spans=token_spans(stmt)
        if len(spans) < 3: continue
        if spans[0][2] != 'access_log': continue
        # access_log syntax: access_log path format [parameters...];
        fmt = spans[2][2]
        # Remove matching outer quotes only for comparison; preserve original token otherwise.
        unquoted = fmt[1:-1] if len(fmt)>=2 and fmt[0]==fmt[-1] and fmt[0] in ('"', "'") else fmt
        if unquoted == old_fmt:
            fmt_start, fmt_end, _ = spans[2]
            plan.append((path, a+fmt_start, a+fmt_end, fmt))

# Stable, machine-readable TSV; paths with tabs/newlines are rejected.
with open(plan_file, 'w', encoding='utf-8') as f:
    for path,a,b,token in plan:
        if any(c in path for c in '\t\r\n'):
            raise SystemExit('Nama file konfigurasi mengandung karakter yang tidak didukung.')
        f.write(f'{path}\t{a}\t{b}\t{token}\n')

print(f'File konfigurasi aktif diperiksa : {len(files)}')
print(f'Deklarasi access_log reverser   : {len(plan)}')
for path,a,b,token in plan:
    print(f'  {path}')
PY

PLAN_COUNT="$(wc -l < "${TMP_DIR}/plan.tsv" | tr -d ' ')"
if [[ "${MODE}" == "dry-run" ]]; then
    echo
    info "MODE DRY-RUN: tidak ada file yang diubah."
    if [[ "${PLAN_COUNT}" -eq 0 ]]; then
        ok "Tidak ditemukan access_log dengan format reverser pada konfigurasi aktif."
    else
        printf '%s\n' "Rencana migrasi: ${PLAN_COUNT} deklarasi reverser -> ${TARGET_FORMAT}."
        info "Jalankan dengan --apply untuk menerapkan perubahan."
    fi
    exit 0
fi

if [[ "${PLAN_COUNT}" -eq 0 ]]; then
    ok "Tidak ada migrasi diperlukan."
    exit 0
fi

STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}"
mkdir -p "${BACKUP_DIR}/files"
chmod 0700 "${BACKUP_DIR}"

info "Membuat backup konfigurasi yang akan diubah: ${BACKUP_DIR}"
python3 - "${TMP_DIR}/plan.tsv" "${BACKUP_DIR}" <<'PY'
import os, sys, shutil, hashlib
plan, backup = sys.argv[1:]
seen=set(); manifest=[]
for line in open(plan, encoding='utf-8'):
    path=line.rstrip('\n').split('\t',1)[0]
    real=os.path.realpath(path)
    if real in seen: continue
    seen.add(real)
    if not os.path.isfile(real): raise SystemExit(f'File target tidak ditemukan: {real}')
    digest=hashlib.sha256(real.encode()).hexdigest()[:16]
    dest=os.path.join(backup,'files',digest+'-'+os.path.basename(real))
    shutil.copy2(real,dest)
    manifest.append((real,dest))
with open(os.path.join(backup,'MANIFEST.tsv'),'w') as f:
    for src,dst in manifest: f.write(src+'\t'+dst+'\n')
print(f'Backup dibuat untuk {len(manifest)} file.')
PY

# Apply edits in-place to resolved targets so sites-enabled symlinks remain intact.
if ! python3 - "${TMP_DIR}/plan.tsv" "${SOURCE_FORMAT}" "${TARGET_FORMAT}" <<'PY'
import os, sys, tempfile
plan, old, new = sys.argv[1:]
changes={}
for line in open(plan, encoding='utf-8'):
    path,a,b,token=line.rstrip('\n').split('\t',3)
    real=os.path.realpath(path)
    changes.setdefault(real,[]).append((int(a),int(b),token))
for path, edits in changes.items():
    with open(path,'r',encoding='utf-8',errors='surrogateescape') as f: data=f.read()
    for a,b,token in sorted(edits, key=lambda x:x[0], reverse=True):
        if data[a:b] != token:
            raise SystemExit(f'File berubah sejak pemeriksaan; batal: {path}')
        data=data[:a]+new+data[b:]
    st=os.stat(path)
    fd,tmp=tempfile.mkstemp(prefix='.brebes-waf-',dir=os.path.dirname(path))
    try:
        with os.fdopen(fd,'w',encoding='utf-8',errors='surrogateescape') as f:
            f.write(data); f.flush(); os.fsync(f.fileno())
        os.chmod(tmp, st.st_mode & 0o7777)
        os.chown(tmp, st.st_uid, st.st_gid)
        os.replace(tmp,path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise
    print(f'Migrated: {path} ({len(edits)} directive(s))')
PY
then
    err "Migrasi gagal saat menulis konfigurasi. Memulihkan backup."
    python3 - "${BACKUP_DIR}/MANIFEST.tsv" <<'PY'
import sys,shutil
for line in open(sys.argv[1]):
    src,dst=line.rstrip('\n').split('\t',1); shutil.copy2(dst,src)
PY
    die "Perubahan dibatalkan dan backup dipulihkan."
fi

# Validate Nginx. On failure, restore every changed file and re-test.
if ! "$NGINX_BIN" -t; then
    err "nginx -t gagal setelah migrasi. Melakukan rollback otomatis."
    python3 - "${BACKUP_DIR}/MANIFEST.tsv" <<'PY'
import sys,shutil
for line in open(sys.argv[1]):
    src,dst=line.rstrip('\n').split('\t',1); shutil.copy2(dst,src)
PY
    "$NGINX_BIN" -t || warn "Konfigurasi tetap gagal setelah rollback; periksa konfigurasi dan backup."
    die "Migrasi di-rollback. Backup: ${BACKUP_DIR}"
fi

# Re-read active config and verify all access_log directives are migrated.
"$NGINX_BIN" -T >"${TMP_DIR}/nginx-T-after.txt" 2>"${TMP_DIR}/nginx-T-after.err" || {
    err "nginx -T gagal saat verifikasi. Rollback."
    python3 - "${BACKUP_DIR}/MANIFEST.tsv" <<'PY'
import sys,shutil
for line in open(sys.argv[1]):
    src,dst=line.rstrip('\n').split('\t',1); shutil.copy2(dst,src)
PY
    die "Verifikasi gagal; backup dipulihkan: ${BACKUP_DIR}"
}
python3 - "${TMP_DIR}/nginx-T-after.txt" "${SOURCE_FORMAT}" "${TARGET_FORMAT}" "${PLAN_COUNT}" <<'PY'
import os,re,sys,shlex
srcfile,old,new,expected=sys.argv[1:]
txt=open(srcfile,encoding='utf-8',errors='replace').read()
marker=re.compile(r'^# configuration file (.+):\s*$',re.M)
ms=list(marker.finditer(txt)); files={}
for m in ms:
    p=m.group(1).strip()
    if p.startswith('/') and os.path.isfile(p):
        real=os.path.realpath(p)
        if real not in files:
            with open(real,encoding='utf-8',errors='replace') as f: files[real]=f.read()
def scan(s):
    start=0; q=None; esc=False; comment=False
    for i,c in enumerate(s):
        if comment:
            if c=='\n': comment=False
            continue
        if q:
            if esc: esc=False
            elif c=='\\': esc=True
            elif c==q: q=None
            continue
        if c in ('"',"'"): q=c
        elif c=='#': comment=True
        elif c==';':
            yield s[start:i]; start=i+1
        elif c in '{}': start=i+1
def toks(s):
    # Remove comments outside quoted strings before tokenizing.
    out=[]; q=None; esc=False; comment=False
    for c in s:
        if comment:
            if c=='\n': comment=False; out.append(c)
            continue
        if q:
            out.append(c)
            if esc: esc=False
            elif c=='\\': esc=True
            elif c==q: q=None
            continue
        if c in ('\"', "'"): q=c; out.append(c)
        elif c=='#': comment=True
        else: out.append(c)
    try: return shlex.split(''.join(out), comments=False, posix=True)
    except ValueError: return []
remaining=[]; migrated=0
for p,s in files.items():
    for st in scan(s):
        t=toks(st)
        if len(t)>=3 and t[0]=='access_log':
            if t[2]==old: remaining.append((p,st.strip()))
            if t[2]==new: migrated+=1
print(f'Active config files checked : {len(files)}')
print(f'JSON access_log directives  : {migrated}')
print(f'Remaining reverser directives: {len(remaining)}')
if remaining:
    for p,st in remaining: print(f'  UNMIGRATED {p}: {st}')
    raise SystemExit(2)
if migrated < int(expected):
    print(f'WARNING: jumlah JSON ({migrated}) lebih kecil dari target migrasi ({expected}).')
    raise SystemExit(3)
print('Verification: PASS')
PY
VERIFY_STATUS=$?
if [[ "$VERIFY_STATUS" -ne 0 ]]; then
    err "Verifikasi migrasi gagal (status ${VERIFY_STATUS}); rollback otomatis."
    python3 - "${BACKUP_DIR}/MANIFEST.tsv" <<'PY'
import sys,shutil
for line in open(sys.argv[1]):
    src,dst=line.rstrip('\n').split('\t',1); shutil.copy2(dst,src)
PY
    "$NGINX_BIN" -t || warn "Periksa konfigurasi setelah rollback."
    die "Migrasi di-rollback. Backup: ${BACKUP_DIR}"
fi

ok "Migrasi selesai: ${PLAN_COUNT} deklarasi access_log reverser diubah menjadi ${TARGET_FORMAT}."
ok "Konfigurasi Nginx valid; tidak ada access_log reverser tersisa pada konfigurasi aktif."
info "Backup: ${BACKUP_DIR}"
info "Belum dilakukan reload/restart Nginx. Perubahan baru aktif setelah reload."
info "Jika hasil validasi sudah sesuai, jalankan: systemctl reload nginx"
