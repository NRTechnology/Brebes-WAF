
$ErrorActionPreference = "Stop"

$ProjectDirectory = $PSScriptRoot
$VenvDirectory = Join-Path $ProjectDirectory ".venv"
$ActivateScript = Join-Path $VenvDirectory "Scripts\Activate.ps1"

if (-not (Test-Path (Join-Path $ProjectDirectory "exploit.py"))) {
    throw "exploit.py tidak ditemukan di folder ini."
}

if (-not (Test-Path $ActivateScript)) {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 -m venv $VenvDirectory
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        & python -m venv $VenvDirectory
    } else {
        throw "Python 3 tidak ditemukan."
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Gagal membuat virtual environment."
    }
}

. $ActivateScript

Write-Host "Virtual environment aktif." -ForegroundColor Green
python --version
