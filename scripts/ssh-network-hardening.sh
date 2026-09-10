#!/bin/bash

# ============================================================
# SSH NETWORK HARDENING - nftables
#
# Fungsi:
# 1. SSH INBOUND hanya dari network VPN
# 2. SSH OUTBOUND TCP/22 diblokir
#
# PENTING:
# Ubah VPN_NETWORK sebelum menjalankan script.
# ============================================================

set -e

# ============================================================
# KONFIGURASI
# ============================================================

VPN_NETWORK="10.10.10.0/24"

# ============================================================
# CEK ROOT
# ============================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Script harus dijalankan sebagai root."
    exit 1
fi

echo "================================================"
echo " SSH NETWORK HARDENING"
echo "================================================"
echo
echo "VPN Network : $VPN_NETWORK"
echo
echo "Kebijakan:"
echo "  INBOUND  TCP/22 dari VPN  : ALLOW"
echo "  INBOUND  TCP/22 selain VPN: REJECT"
echo "  OUTBOUND TCP/22           : REJECT"
echo

# ============================================================
# KONFIRMASI
# ============================================================

read -p "Apakah VPN_NETWORK sudah benar? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo
    echo "[CANCEL] Tidak ada perubahan firewall."
    exit 0
fi

# ============================================================
# INSTALL NFTABLES JIKA BELUM TERSEDIA
# ============================================================

if ! command -v nft >/dev/null 2>&1; then

    echo "[INFO] nftables belum tersedia."
    echo "[INFO] Menginstall nftables..."

    apt-get update
    apt-get install -y nftables

fi

echo "[OK] nftables tersedia."

# ============================================================
# VALIDASI VPN NETWORK
# ============================================================

if ! echo "$VPN_NETWORK" | grep -Eq \
'^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then

    echo "[ERROR] Format VPN_NETWORK tidak valid."
    echo "Contoh: 10.10.10.0/24"
    exit 1

fi

# ============================================================
# BACKUP NFTABLES
# ============================================================

if [ -f /etc/nftables.conf ]; then

    BACKUP="/etc/nftables.conf.backup-$(date +%Y%m%d-%H%M%S)"

    cp -a /etc/nftables.conf "$BACKUP"

    echo "[OK] Backup dibuat:"
    echo "     $BACKUP"

fi

# ============================================================
# TABLE inet filter
# ============================================================

if ! nft list table inet filter >/dev/null 2>&1; then

    nft add table inet filter

    echo "[OK] Table inet filter dibuat."

else

    echo "[OK] Table inet filter sudah ada."

fi

# ============================================================
# CHAIN INPUT
# ============================================================

if ! nft list chain inet filter input >/dev/null 2>&1; then

    nft 'add chain inet filter input {
        type filter hook input priority filter;
        policy accept;
    }'

    echo "[OK] Chain input dibuat."

else

    echo "[OK] Chain input sudah ada."

fi

# ============================================================
# CHAIN OUTPUT
# ============================================================

if ! nft list chain inet filter output >/dev/null 2>&1; then

    nft 'add chain inet filter output {
        type filter hook output priority filter;
        policy accept;
    }'

    echo "[OK] Chain output dibuat."

else

    echo "[OK] Chain output sudah ada."

fi

# ============================================================
# SSH INBOUND DARI VPN
# ============================================================

if nft list chain inet filter input | \
grep -Fq "SSH_FROM_VPN"; then

    echo "[OK] Rule SSH_FROM_VPN sudah ada."

else

    nft add rule inet filter input \
        ip saddr "$VPN_NETWORK" \
        tcp dport 22 \
        accept \
        comment \"SSH_FROM_VPN\"

    echo "[OK] SSH dari VPN diizinkan."

fi

# ============================================================
# BLOCK SSH INBOUND NON-VPN
# ============================================================

if nft list chain inet filter input | \
grep -Fq "BLOCK_SSH_NON_VPN"; then

    echo "[OK] Rule BLOCK_SSH_NON_VPN sudah ada."

else

    nft add rule inet filter input \
        tcp dport 22 \
        reject \
        comment \"BLOCK_SSH_NON_VPN\"

    echo "[OK] SSH dari luar VPN diblokir."

fi

# ============================================================
# BLOCK SSH OUTBOUND
# ============================================================

if nft list chain inet filter output | \
grep -Fq "BLOCK_SSH_OUTBOUND"; then

    echo "[OK] Rule BLOCK_SSH_OUTBOUND sudah ada."

else

    nft add rule inet filter output \
        tcp dport 22 \
        reject \
        comment \"BLOCK_SSH_OUTBOUND\"

    echo "[OK] SSH outbound TCP/22 diblokir."

fi

# ============================================================
# SIMPAN RULESET
# ============================================================

nft list ruleset > /etc/nftables.conf

echo "[OK] Ruleset disimpan ke /etc/nftables.conf"

# ============================================================
# ENABLE NFTABLES
# ============================================================

systemctl enable nftables >/dev/null 2>&1

echo "[OK] nftables diaktifkan saat boot."

# ============================================================
# TAMPILKAN HASIL
# ============================================================

echo
echo "================================================"
echo " CHAIN INPUT"
echo "================================================"

nft list chain inet filter input

echo
echo "================================================"
echo " CHAIN OUTPUT"
echo "================================================"

nft list chain inet filter output

echo
echo "================================================"
echo " HASIL HARDENING"
echo "================================================"
echo
echo "VPN NETWORK:"
echo "  $VPN_NETWORK"
echo
echo "SSH INBOUND:"
echo "  VPN       -> Server TCP/22 : ALLOW"
echo "  NON-VPN   -> Server TCP/22 : REJECT"
echo
echo "SSH OUTBOUND:"
echo "  Server -> TCP/22           : REJECT"
echo
echo "================================================"
echo " PERINGATAN"
echo "================================================"
echo
echo "JANGAN logout dari SSH saat ini."
echo
echo "Buka terminal kedua melalui VPN dan pastikan"
echo "SSH ke server berhasil sebelum menutup sesi ini."
echo
echo "================================================"