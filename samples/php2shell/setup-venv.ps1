$ErrorActionPreference = "Stop"

$ProjectDir = $PSScriptRoot
$VenvDir = Join-Path $ProjectDir ".venv"
$Requirements = Join-Path $ProjectDir "requirements.txt"
$Python = "py"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host " BREBES-WAF - Python Virtual Environment"
Write-Host "======================================" -ForegroundColor Cyan

Set-Location $ProjectDir

# Check Python
try {
    & $Python --version
    if ($LASTEXITCODE -ne 0) {
        throw "Python launcher gagal dijalankan."
    }
} catch {
    Write-Error "Python tidak ditemukan. Pastikan Python sudah terpasang."
    exit 1
}

# Create virtual environment if absent
if (-not (Test-Path $VenvDir)) {
    Write-Host "`nMembuat virtual environment..." -ForegroundColor Yellow
    & $Python -m venv $VenvDir

    if ($LASTEXITCODE -ne 0) {
        throw "Gagal membuat virtual environment."
    }
} else {
    Write-Host "`nVirtual environment sudah tersedia." -ForegroundColor Green
}

# Activate virtual environment
$ActivateScript = Join-Path $VenvDir "Scripts\Activate.ps1"

if (-not (Test-Path $ActivateScript)) {
    throw "File aktivasi tidak ditemukan: $ActivateScript"
}

. $ActivateScript

Write-Host "`nPython aktif:" -ForegroundColor Green
python --version
Write-Host "Lokasi Python: $((Get-Command python).Source)"

# Install dependencies if requirements.txt exists
if (Test-Path $Requirements) {
    Write-Host "`nMemasang dependensi requirements.txt..." -ForegroundColor Yellow
    python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) {
        throw "Gagal memperbarui pip."
    }

    python -m pip install -r $Requirements
    if ($LASTEXITCODE -ne 0) {
        throw "Gagal memasang dependensi."
    }
} else {
    Write-Host "`nrequirements.txt tidak ditemukan; melewati instalasi dependensi." -ForegroundColor DarkYellow
}

Write-Host "`nVirtual environment siap digunakan." -ForegroundColor Green
Write-Host "Untuk mengaktifkan kembali pada sesi berikutnya:"
Write-Host "  .\.venv\Scripts\Activate.ps1"
