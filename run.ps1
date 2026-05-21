param([string]$InstallDir = ".", [switch]$Force)

$repoUrl = "https://github.com/ASPDP/sova-on-prem.git"

function Find-GitRoot($startPath) {
    $path = $startPath
    while ($path) {
        if (Test-Path (Join-Path $path ".git")) { return $path }
        $parent = Split-Path $path -Parent
        if ($parent -eq $path) { break }
        $path = $parent
    }
    return $null
}

# Refresh install.ps1 directly from raw.githubusercontent.com so a broken
# on-disk copy (e.g. older version without UTF-8 BOM that PS 5.1 cannot
# parse) cannot block the bootstrap. Invoke-WebRequest -OutFile writes
# response bytes byte-for-byte, preserving the BOM and Cyrillic literals.
# Doesn't depend on the local git state being healthy.
function Refresh-InstallScript($repoDir) {
    $installPath = Join-Path $repoDir "install.ps1"
    $rawUrl = "https://raw.githubusercontent.com/ASPDP/sova-on-prem/master/install.ps1"
    try {
        Invoke-WebRequest -Uri $rawUrl -OutFile $installPath -UseBasicParsing -ErrorAction Stop
        Write-Host "  [OK] Refreshed install.ps1 from $rawUrl" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNING] Could not download install.ps1: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  [INFO] Falling back to on-disk copy" -ForegroundColor Gray
    }
}

# When run via irm|iex $PSScriptRoot is empty - fall back to $PWD
$startPath = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$gitRoot   = Find-GitRoot $startPath

# Resolve install dir + would-be sibling clone path
$resolvedDir  = Resolve-Path $InstallDir -ErrorAction SilentlyContinue
$targetDir    = if ($resolvedDir) { [string]$resolvedDir.ProviderPath } else { $PWD.Path }
$siblingClone = Join-Path $targetDir "sova-on-prem"

if ($gitRoot -and (Test-Path (Join-Path $gitRoot "install.ps1"))) {
    # Inside an existing sova-on-prem clone - refresh + delegate as update
    Refresh-InstallScript $gitRoot
    & (Join-Path $gitRoot "install.ps1") -Force:$Force
}
elseif (Test-Path (Join-Path $siblingClone ".git")) {
    # Sibling sova-on-prem already cloned next to the .env / certs - refresh + delegate as update
    Write-Host ""
    Write-Host "Found existing clone at $siblingClone - running update..." -ForegroundColor Cyan
    Refresh-InstallScript $siblingClone
    & (Join-Path $siblingClone "install.ps1") -Force:$Force
}
else {
    # No existing clone anywhere - fresh install
    Write-Host ""
    Write-Host "Cloning sova-on-prem..." -ForegroundColor Yellow
    git clone $repoUrl $siblingClone
    if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] git clone failed" -ForegroundColor Red; exit 1 }

    & (Join-Path $siblingClone "install.ps1") -Force:$Force -InstallDir $targetDir -FreshInstall
}
