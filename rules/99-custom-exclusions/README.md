# Custom Exclusions

## Overview

Direktori `99-custom-exclusions` digunakan untuk menyimpan konfigurasi pengecualian (*custom exclusions*) terhadap rule keamanan BREBES-WAF dan OWASP Core Rule Set (CRS).

Pengecualian diperlukan ketika suatu rule mendeteksi aktivitas aplikasi yang sah sebagai ancaman (*false positive*), sehingga request normal terblokir oleh WAF.

Direktori ini ditujukan untuk konfigurasi lokal yang dikelola oleh administrator pada masing-masing server instalasi BREBES-WAF.

## Purpose

- Menyediakan tempat khusus untuk konfigurasi pengecualian rule.
- Memisahkan konfigurasi lokal dari rule proteksi bawaan BREBES-WAF.
- Memisahkan konfigurasi lokal dari rule OWASP CRS.
- Mempertahankan konfigurasi pengecualian ketika repository diperbarui melalui Git.
- Memungkinkan setiap instalasi memiliki konfigurasi pengecualian sesuai kebutuhan aplikasi masing-masing.

## Directory Structure

```text
rules/
└── 99-custom-exclusions/
    ├── README.md
    ├── 9900001-exclude-application-a.conf
    ├── 9900002-exclude-application-b.conf
    └── ...
```

## Configuration Management

File konfigurasi di dalam direktori ini bersifat lokal dan tidak dikelola melalui repository Git.

Administrator dapat menambahkan, mengubah, atau menghapus konfigurasi pengecualian sesuai kebutuhan masing-masing instalasi.

Pastikan direktori ini tercantum dalam `.gitignore`:

```gitignore
# Local custom exclusions - not tracked by Git
/rules/99-custom-exclusions/*
!/rules/99-custom-exclusions/README.md
```

Dengan konfigurasi tersebut:

- `README.md` tetap dikelola melalui Git.
- File konfigurasi `.conf` tidak ikut di-commit ke repository.
- File pengecualian yang sudah ada di server tetap tersedia ketika menjalankan `git pull`.

**Important:** Hindari penggunaan `git clean -fdx` pada proses deployment karena perintah tersebut dapat menghapus file lokal yang diabaikan oleh Git.

## Rule ID Convention

Gunakan namespace ID khusus untuk konfigurasi pengecualian lokal.

| Prefix | Description |
|---|---|
| `990xxxx` | Local custom exclusion rules |

Contoh:

```apache
SecRule ... \\
    "id:9900001,phase:1,pass,nolog"
```

Pastikan setiap Rule ID unik dan tidak bertabrakan dengan Rule ID BREBES-WAF, OWASP CRS, maupun rule lokal lainnya.

## Exclusion Guidelines

Pengecualian harus dibuat secara spesifik dan terbatas.

1. Terapkan pengecualian hanya setelah dilakukan analisis terhadap audit log.
2. Pastikan deteksi merupakan false positive, bukan serangan yang sebenarnya.
3. Batasi pengecualian berdasarkan hostname, HTTP method, URI, dan parameter jika memungkinkan.
4. Hindari menonaktifkan rule secara global.
5. Hindari mengecualikan seluruh parameter atau seluruh request apabila tidak diperlukan.
6. Pertahankan pemeriksaan keamanan terhadap parameter dan rule lainnya.
7. Dokumentasikan alasan dan ruang lingkup setiap pengecualian.

## Deployment Considerations

Konfigurasi dalam direktori ini harus tetap dipertahankan selama proses deployment dan pembaruan BREBES-WAF.

Deployment script tidak boleh:

- Menghapus direktori `99-custom-exclusions`.
- Menghapus file konfigurasi lokal di dalamnya.
- Menimpa konfigurasi lokal dengan file dari repository.
- Menjalankan perintah pembersihan Git yang menghapus ignored files.

Pastikan konfigurasi pengecualian dimuat oleh ModSecurity setelah rule yang menjadi target pengecualian tersedia, dengan memperhatikan fase eksekusi rule.

Setelah perubahan konfigurasi, lakukan validasi:

```bash
nginx -t
```

Reload Nginx hanya jika validasi berhasil:

```bash
systemctl reload nginx
```

## Security Notice

Custom exclusions mengurangi cakupan pemeriksaan terhadap bagian tertentu dari request. Kesalahan dalam membuat pengecualian dapat membuka peluang serangan terhadap aplikasi.

Setiap perubahan harus melalui analisis, pengujian, dan evaluasi keamanan.

**Custom exclusions are intended for controlled, application-specific security tuning. They must not be used as a general mechanism to bypass WAF protection.**
