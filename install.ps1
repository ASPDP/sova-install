param([string]$InstallDir = ".", [switch]$Force)

$repoUrl = "https://github.com/ASPDP/sova-on-prem.git"

# Walk up from $startPath to find the nearest .git folder
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
    # Already inside an existing repo — use it directly
    $target    = $gitRoot
    $targetDir = Split-Path $gitRoot -Parent   # folder that contains sova-on-prem/
} else {
    # Not inside a repo — resolve fresh-install destination
    $resolvedDir = Resolve-Path $InstallDir -ErrorAction SilentlyContinue
    $targetDir   = if ($resolvedDir) { [string]$resolvedDir.ProviderPath } else { $PWD.Path }
    $target      = Join-Path $targetDir "sova-on-prem"
}

if (-not (Test-Path (Join-Path $target ".git"))) {

    # ════════════════════════════════════════════════════════════════════════
    #  FRESH INSTALL — clone, then delegate to the freshly-cloned install.ps1
    #  (it was just downloaded from GitHub, so it is always up-to-date)
    # ════════════════════════════════════════════════════════════════════════

    Write-Host ""
    Write-Host "Cloning sova-on-prem..." -ForegroundColor Yellow
    git clone $repoUrl $target
    if ($LASTEXITCODE -ne 0) { Write-Host "[ERROR] git clone failed" -ForegroundColor Red; exit 1 }

    & (Join-Path $target "install.ps1") -Force:$Force -InstallDir $targetDir

} else {

    # ════════════════════════════════════════════════════════════════════════
    #  UPDATE — fully inline so it is always driven by the freshly-downloaded
    #  sova-install script, never by the potentially-stale local install.ps1
    # ════════════════════════════════════════════════════════════════════════

    $srcDir         = Join-Path $target "src"
    $envPath        = Join-Path $srcDir ".env"
    $envBakPath     = Join-Path $srcDir ".env.backup"
    $envExamplePath = Join-Path $srcDir ".env.example"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SOVA On-Prem — Update" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # ── Step 1: Check for updates ────────────────────────────────────────
    Write-Host "[Step 1/5] Checking for updates..." -ForegroundColor Yellow

    Set-Location $target
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch) { $branch = "master" }

    git fetch origin --tags --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARNING] Could not reach remote — continuing with local state" -ForegroundColor Yellow
    }

    $countStr = git rev-list --count "HEAD..origin/$branch" 2>$null
    $newCount = if ($countStr -match '^\d+$') { [int]$countStr } else { 0 }

    if ($newCount -eq 0 -and -not $Force) {
        Write-Host "  [OK] Already up to date (branch: $branch)" -ForegroundColor Green
        if (-not (Test-Path (Join-Path $srcDir "node_modules"))) {
            Write-Host "  [INFO] node_modules missing — running setup..." -ForegroundColor Cyan
        } else {
            Write-Host ""
            Write-Host "  No updates available. Use -Force to reinstall." -ForegroundColor Gray
            Write-Host ""
            exit 0
        }
    } elseif ($newCount -gt 0) {
        Write-Host "  [UPDATE] $newCount new commit(s) on '$branch':" -ForegroundColor Cyan
        Write-Host ""
        git log --oneline "HEAD..origin/$branch" | ForEach-Object { Write-Host "    • $_" -ForegroundColor White }
        Write-Host ""
    }

    # ── Step 2: Backup .env ──────────────────────────────────────────────
    Write-Host "[Step 2/5] Preserving .env..." -ForegroundColor Yellow

    $hadEnv = Test-Path $envPath
    if ($hadEnv) {
        Copy-Item $envPath $envBakPath -Force
        Write-Host "  [OK] Backed up .env" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] No .env found — create one from .env.example after update" -ForegroundColor Gray
    }

    # ── Step 3: Confirm ──────────────────────────────────────────────────
    Write-Host "[Step 3/5] Confirming update..." -ForegroundColor Yellow

    if (-not $Force) {
        Write-Host "  [WARNING] This will discard all local changes!" -ForegroundColor Red
        $confirm = Read-Host "  Continue? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            if ($hadEnv -and (Test-Path $envBakPath)) {
                Copy-Item $envBakPath $envPath -Force
                Remove-Item $envBakPath -Force
            }
            Write-Host "  [CANCELLED]" -ForegroundColor Yellow
            exit 0
        }
    }

    # ── Step 4: git reset + restore .env ─────────────────────────────────
    Write-Host ""
    Write-Host "[Step 4/5] Updating repository..." -ForegroundColor Yellow

    git reset --hard "origin/$branch"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] git reset failed" -ForegroundColor Red
        if ($hadEnv -and (Test-Path $envBakPath)) {
            Copy-Item $envBakPath $envPath -Force
            Remove-Item $envBakPath -Force
            Write-Host "  [OK] Restored .env" -ForegroundColor Green
        }
        exit 1
    }
    git clean -fd
    Write-Host "  [OK] Repository updated" -ForegroundColor Green

    if ($hadEnv -and (Test-Path $envBakPath)) {
        Copy-Item $envBakPath $envPath -Force
        Remove-Item $envBakPath -Force
        Write-Host "  [OK] Restored .env" -ForegroundColor Green
    }

    # Copy SSL certificates from $targetDir if not already present in src/
    foreach ($certFile in @("cert.pem", "key.pem")) {
        $certSrc  = Join-Path $targetDir $certFile
        $certDest = Join-Path $srcDir $certFile
        if (-not (Test-Path $certDest)) {
            if (Test-Path $certSrc) {
                Copy-Item $certSrc $certDest -Force
                Write-Host "  [OK] Copied $certFile from $targetDir" -ForegroundColor Green
            } else {
                Write-Host "  [WARNING] $certFile not found in $targetDir — place it there before starting the server" -ForegroundColor Yellow
            }
        }
    }

    # ── Step 5: Compare env vars, install deps, compile ──────────────────
    Write-Host ""
    Write-Host "[Step 5/5] Checking environment and installing dependencies..." -ForegroundColor Yellow

    if ($hadEnv -and (Test-Path $envExamplePath)) {
        function Parse-EnvFile($path) {
            $map = @{}
            foreach ($line in (Get-Content $path -ErrorAction SilentlyContinue)) {
                $t = $line.Trim()
                if ($t -and -not $t.StartsWith('#') -and $t.Contains('=')) {
                    $parts = $t -split '=', 2
                    $map[$parts[0].Trim()] = if ($parts.Length -gt 1) { $parts[1].Trim() } else { "" }
                }
            }
            return $map
        }

        $newExample     = Parse-EnvFile $envExamplePath
        $currentEnv     = Parse-EnvFile $envPath
        $missingVars    = $newExample.Keys | Where-Object { -not $currentEnv.ContainsKey($_) } |
                              ForEach-Object { @{ Key = $_; DefaultValue = $newExample[$_] } }
        $deprecatedVars = $currentEnv.Keys | Where-Object { -not $newExample.ContainsKey($_) }

        if ($missingVars.Count -gt 0) {
            Write-Host ""
            Write-Host "  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
            Write-Host "  │  MISSING VARIABLES — Add these to your .env:           │" -ForegroundColor Yellow
            Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
            foreach ($v in $missingVars) {
                $def = if ($v.DefaultValue) { " (default: $($v.DefaultValue))" } else { "" }
                Write-Host "    → $($v.Key)$def" -ForegroundColor Red
            }
            Write-Host ""
            $appendConfirm = Read-Host "  Append missing variables with defaults to .env? (y/N)"
            if ($appendConfirm -eq 'y' -or $appendConfirm -eq 'Y') {
                Add-Content $envPath ""
                Add-Content $envPath "# === Added by install.ps1 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
                foreach ($v in $missingVars) {
                    Add-Content $envPath "$($v.Key)=$($v.DefaultValue)"
                    Write-Host "    [ADDED] $($v.Key)" -ForegroundColor Green
                }
            }
        } else {
            Write-Host "  [OK] No missing variables" -ForegroundColor Green
        }

        if ($deprecatedVars.Count -gt 0) {
            Write-Host ""
            Write-Host "  DEPRECATED (in .env but not in .env.example):" -ForegroundColor Cyan
            foreach ($v in $deprecatedVars) { Write-Host "    → $v" -ForegroundColor Cyan }
            Write-Host "  [INFO] Review and remove if no longer needed" -ForegroundColor Gray
        }
    } elseif (-not $hadEnv) {
        Write-Host "  [INFO] No .env — copy src\.env.example to src\.env and fill in values" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Installing dependencies..." -ForegroundColor Yellow
    Set-Location $srcDir
    npm install xlsx@file:vendor/xlsx-0.20.3.tgz --save
    npm install
    if ($LASTEXITCODE -ne 0) { Write-Host "  [ERROR] npm install failed" -ForegroundColor Red; exit 1 }

    Write-Host ""
    Write-Host "  Compiling TypeScript..." -ForegroundColor Yellow
    npx tsc -p tsconfig.json
    if ($LASTEXITCODE -ne 0) { Write-Host "  [WARNING] TypeScript compilation reported errors" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Update complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next: cd src && npm start" -ForegroundColor Cyan
    Write-Host ""
}
