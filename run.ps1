# SOVA On-Prem bootstrap.
# - Verifies Windows PowerShell 5.1
# - Force-downloads the latest install.ps1 from sova-on-prem master
# - Dot-sources it (so Set-Location and other state changes persist in the
#   user's interactive shell, enabling Phase 1 folder alignment)
# Everything else lives in install.ps1.

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    Write-Host ""
    Write-Host "[ERROR] Requires Windows PowerShell 5.1" -ForegroundColor Red
    Write-Host "  Current: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor Yellow
    Write-Host "  Open 'Windows PowerShell' (not 'PowerShell 7') and re-run." -ForegroundColor Gray
    Write-Host ""
    return
}

$installUrl  = "https://raw.githubusercontent.com/ASPDP/sova-on-prem/master/install.ps1"
$installPath = Join-Path $env:TEMP "sova-install.ps1"

Write-Host ""
Write-Host "Downloading latest install.ps1..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $installUrl -OutFile $installPath -UseBasicParsing -ErrorAction Stop
    Write-Host "  [OK] Saved to $installPath" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

. $installPath
