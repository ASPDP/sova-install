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

# When run via irm|iex $PSScriptRoot is empty — fall back to $PWD
$startPath = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$gitRoot   = Find-GitRoot $startPath

if ($gitRoot) {
    # Already inside an existing repo — delegate entirely to install.ps1
    & (Join-Path $gitRoot "install.ps1") -Force:$Force
} else {
    # Not inside a repo — clone first, then delegate to install.ps1
    $resolvedDir = Resolve-Path $InstallDir -ErrorAction SilentlyContinue
    $targetDir   = if ($resolvedDir) { [string]$resolvedDir.ProviderPath } else { $PWD.Path }
    $target      = Join-Path $targetDir "sova-on-prem"

    Write-Host ""
    Write-Host "Cloning sova-on-prem..." -ForegroundColor Yellow
    git clone $repoUrl $target
    if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] git clone failed" -ForegroundColor Red; exit 1 }

    & (Join-Path $target "install.ps1") -Force:$Force -InstallDir $targetDir
}
