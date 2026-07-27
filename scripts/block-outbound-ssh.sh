#!/bin/bash

# ============================================================
# BLOCK OUTBOUND SSH
# Mencegah server melakukan SSH/jumping ke server lain TCP/22
# SSH inbound ke server tetap diperbolehkan.
# ============================================================

set -e

echo "=============================================="
echo " Block Outbound SSH - nftables"
echo "=============================================="

# Harus dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Jalankan script sebagai root."
    exit 1
fi

# ------------------------------------------------------------
# 1. Pastikan nft tersedia
# ------------------------------------------------------------

if ! command -v nft >/dev/null 2>&1; then
    echo "[INFO] nftables belum terinstall."
    apt-get update
    apt-get install -y nftables
fi

echo "[OK] nftables tersedia."

# ------------------------------------------------------------
# 2. Backup konfigurasi lama
# ------------------------------------------------------------

if [ -f /etc/nftables.conf ]; then
    BACKUP="/etc/nftables.conf.backup-$(date +%Y%m%d-%H%M%S)"
    cp -a /etc/nftables.conf "$BACKUP"
    echo "[OK] Backup: $BACKUP"
fi

# ------------------------------------------------------------
# 3. Buat table inet filter jika belum ada
# ------------------------------------------------------------

if ! nft list table inet filter >/dev/null 2>&1; then
    nft add table inet filter
    echo "[OK] Table inet filter dibuat."
else
    echo "[OK] Table inet filter sudah ada."
fi

# ------------------------------------------------------------
# 4. Buat chain output jika belum ada
# ------------------------------------------------------------

if ! nft list chain inet filter output >/dev/null 2>&1; then
    nft 'add chain inet filter output { type filter hook output priority filter; policy accept; }'
    echo "[OK] Chain output dibuat."
else
    echo "[OK] Chain output sudah ada."
fi

# ------------------------------------------------------------
# 5. Tambahkan rule jika belum ada
# ------------------------------------------------------------

if nft list chain inet filter output | grep -qE 'tcp dport 22 reject'; then
    echo "[OK] Rule block outbound SSH sudah ada."
else
    nft add rule inet filter output tcp dport 22 reject
    echo "[OK] Outbound SSH TCP/22 berhasil diblokir."
fi

# ------------------------------------------------------------
# 6. Simpan konfigurasi
# ------------------------------------------------------------

nft list ruleset > /etc/nftables.conf

echo "[OK] Ruleset disimpan ke /etc/nftables.conf"

# ------------------------------------------------------------
# 7. Aktifkan nftables saat boot
# ------------------------------------------------------------

systemctl enable nftables >/dev/null 2>&1

echo "[OK] nftables diaktifkan saat boot."

# ------------------------------------------------------------
# 8. Tampilkan hasil
# ------------------------------------------------------------

echo
echo "=============================================="
echo " KONFIGURASI OUTPUT"
echo "=============================================="

nft list chain inet filter output

echo
echo "=============================================="
echo " STATUS"
echo "=============================================="

echo "SSH INBOUND  TCP/22 : TIDAK DIUBAH"
echo "SSH OUTBOUND TCP/22 : BLOCKED"
echo
echo "Server tidak dapat digunakan untuk jumping"
echo "melalui SSH TCP port 22."
echo "=============================================="