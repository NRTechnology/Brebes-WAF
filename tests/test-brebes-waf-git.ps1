# =============================================================================
# BREBES-WAF Git Protection Test
# Rule ID : 6001001
# Purpose : Test whether exposed Git repository paths are blocked
# =============================================================================

$BaseUrl = "https://csirtlab.brebeskab.go.id/brebes-waf-git-test"

$Tests = @(
    "/.git/",
    "/.git/config",
    "/.git/HEAD",
    "/.git/index",
    "/.git/logs/",
    "/.git/logs/HEAD",
    "/.git/objects/",
    "/.git/refs/",
    "/.git/refs/heads/main"
)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " BREBES-WAF Git Protection Test" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Target : $BaseUrl"
Write-Host "Rule   : 6001001"
Write-Host ""

$Results = @()

foreach ($Path in $Tests) {

    $Url = "$BaseUrl$Path"

    try {

        $Response = Invoke-WebRequest `
            -Uri $Url `
            -Method GET `
            -MaximumRedirection 0 `
            -ErrorAction Stop

        $StatusCode = [int]$Response.StatusCode

    }
    catch {

        if ($_.Exception.Response) {
            $StatusCode = [int]$_.Exception.Response.StatusCode
        }
        else {
            $StatusCode = "ERROR"
        }
    }

    if ($StatusCode -eq 403) {

        $Result = "BLOCKED"

        Write-Host ("{0,-35} HTTP {1,-5} {2}" -f $Path, $StatusCode, $Result) `
            -ForegroundColor Green

    }
    elseif ($StatusCode -eq 200) {

        $Result = "VULNERABLE"

        Write-Host ("{0,-35} HTTP {1,-5} {2}" -f $Path, $StatusCode, $Result) `
            -ForegroundColor Red

    }
    elseif ($StatusCode -eq 404) {

        $Result = "NOT FOUND"

        Write-Host ("{0,-35} HTTP {1,-5} {2}" -f $Path, $StatusCode, $Result) `
            -ForegroundColor Yellow

    }
    else {

        $Result = "CHECK"

        Write-Host ("{0,-35} HTTP {1,-5} {2}" -f $Path, $StatusCode, $Result) `
            -ForegroundColor Yellow
    }

    $Results += [PSCustomObject]@{
        Path   = $Path
        Status = $StatusCode
        Result = $Result
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Summary" -ForegroundColor Cyan
Write-Host "============================================================"

$Results | Format-Table -AutoSize

$Blocked = ($Results | Where-Object { $_.Result -eq "BLOCKED" }).Count
$Vulnerable = ($Results | Where-Object { $_.Result -eq "VULNERABLE" }).Count

Write-Host ""
Write-Host "Blocked    : $Blocked" -ForegroundColor Green
Write-Host "Vulnerable : $Vulnerable" -ForegroundColor Red
Write-Host ""

if ($Vulnerable -gt 0) {

    Write-Host "[WARNING] Ada path .git yang masih dapat diakses." `
        -ForegroundColor Red

}
elseif ($Blocked -eq $Tests.Count) {

    Write-Host "[PASS] Seluruh path .git berhasil diblokir." `
        -ForegroundColor Green

}
else {

    Write-Host "[CHECK] Tidak semua path menghasilkan HTTP 403." `
        -ForegroundColor Yellow
}

Write-Host ""