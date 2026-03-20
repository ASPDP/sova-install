param([string]$InstallDir = ".", [switch]$Force)

$repoUrl = "https://github.com/ASPDP/sova-on-prem.git"
$target  = Join-Path $InstallDir "sova-on-prem"

if (-not (Test-Path "$target\.git")) {
    Write-Host "Cloning sova-on-prem..." -ForegroundColor Yellow
    git clone $repoUrl $target
    if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] git clone failed" -ForegroundColor Red; exit 1 }
}

& "$target\install.ps1" -Force:$Force
