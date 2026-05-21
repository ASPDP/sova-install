# SOVA On-Prem bootstrap.
# - Verifies Windows PowerShell 5.1
# - Downloads the latest install.ps1 from sova-on-prem master via git
#   (so private-repo auth is handled by the user's existing git creds)
# - Dot-sources it (so Set-Location and other state changes persist in
#   the user's interactive shell, enabling Phase 1 folder alignment)
# Everything else lives in install.ps1.

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    Write-Host ""
    Write-Host "[ERROR] Requires Windows PowerShell 5.1" -ForegroundColor Red
    Write-Host "  Current: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor Yellow
    Write-Host "  Open 'Windows PowerShell' (not 'PowerShell 7') and re-run." -ForegroundColor Gray
    Write-Host ""
    return
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "[ERROR] 'git' not found. Install Git for Windows and re-run." -ForegroundColor Red
    Write-Host ""
    return
}

$repoUrl     = "https://github.com/ASPDP/sova-on-prem.git"
$installPath = Join-Path $env:TEMP "sova-install.ps1"
$tempClone   = Join-Path $env:TEMP ("sova-bootstrap-" + [Guid]::NewGuid().ToString("N"))

Write-Host ""
Write-Host "Downloading latest install.ps1 via git..." -ForegroundColor Cyan

try {
    git clone --depth=1 --no-checkout --quiet $repoUrl $tempClone
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed (private repo - is your git authenticated?)"
    }
    git -C $tempClone checkout HEAD -- install.ps1
    if ($LASTEXITCODE -ne 0) {
        throw "git checkout install.ps1 failed"
    }
    $sourcePath = Join-Path $tempClone "install.ps1"
    if (-not (Test-Path $sourcePath)) {
        throw "install.ps1 not found in clone"
    }
    Copy-Item $sourcePath $installPath -Force
    Write-Host "  [OK] Saved to $installPath" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
    if (Test-Path $tempClone) { Remove-Item $tempClone -Recurse -Force -ErrorAction SilentlyContinue }
    return
}

# Cleanup the temp clone (we only needed install.ps1)
Remove-Item $tempClone -Recurse -Force -ErrorAction SilentlyContinue

. $installPath
