##########################################################################
#                                                                        #
#                         SOVA ON-PREM INSTALLER                        #
#   Fresh install OR upgrade — auto-detected based on environment        #
#                                                                        #
#   Fresh install:  irm https://raw.githubusercontent.com/ASPDP/sova-on-prem/master/install.ps1 | iex
#   Upgrade:        Run from the root of the cloned repo                 #
#                                                                        #
##########################################################################

param(
    [switch]$Force,
    [string]$InstallDir = "."
)

# ── Pre-checks ───────────────────────────────────────────────────────────────
foreach ($cmd in @("git", "node", "npm")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] '$cmd' не найден. Установите его и повторите." -ForegroundColor Red
        exit 1
    }
}

# ── Detect scenario ───────────────────────────────────────────────────────────
# $PSScriptRoot = папка скрипта (корень репо), даже когда npm запускает из src/
# При irm|iex $PSScriptRoot пуст — тогда используем $PWD
$_checkRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$isInsideRepo = (Test-Path (Join-Path $_checkRoot "src\package.json")) -or
                (Test-Path (Join-Path $_checkRoot ".git"))

if ($isInsideRepo) {
    # ════════════════════════════════════════════════════════════════════════
    #  SCENARIO B — Update existing installation
    # ════════════════════════════════════════════════════════════════════════

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SOVA On-Prem — Update" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Resolve repo root — $PSScriptRoot надёжнее $PWD (npm меняет $PWD на src/)
    $repoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
    if (-not (Test-Path (Join-Path $repoRoot ".git"))) {
        $repoRoot = Split-Path $repoRoot -Parent
    }
    $srcDir = Join-Path $repoRoot "src"

    # Env file paths (all live in src/)
    $envPath              = Join-Path $srcDir ".env"
    $envExamplePath       = Join-Path $srcDir ".env.example"
    $envBackupPath        = Join-Path $srcDir ".env.backup"
    $envExampleBackupPath = Join-Path $srcDir ".env.example.backup"

    # ── Step 1: Check for new commits ────────────────────────────────────
    Write-Host "[Step 1/6] Checking for updates..." -ForegroundColor Yellow

    Set-Location $repoRoot
    $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { $currentBranch = "master" }

    git fetch origin --tags --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [WARNING] Could not reach remote — continuing with local state" -ForegroundColor Yellow
        $newCommitCount = 0
    } else {
        $localHash  = git rev-parse HEAD 2>$null
        $remoteHash = git rev-parse "origin/$currentBranch" 2>$null
        $countStr = git rev-list --count "HEAD..origin/$currentBranch" 2>$null
        $newCommitCount = if ($countStr -match '^\d+$') { [int]$countStr } else { 0 }

        if ($localHash -eq $remoteHash -or $newCommitCount -eq 0) {
            Write-Host "  [OK] Already up to date (branch: $currentBranch)" -ForegroundColor Green
            if (-not $Force) {
                Write-Host ""
                Write-Host "  No updates available. Use -Force to reinstall anyway." -ForegroundColor Gray
                Write-Host ""
                exit 0
            }
            Write-Host "  [INFO] -Force specified — proceeding anyway" -ForegroundColor Gray
        } else {
            Write-Host "  [INFO] Branch: $currentBranch" -ForegroundColor Gray
            Write-Host "  [UPDATE] $newCommitCount new commit(s) available:" -ForegroundColor Cyan
            Write-Host ""
            git log --oneline "HEAD..origin/$currentBranch" | ForEach-Object {
                Write-Host "    • $_" -ForegroundColor White
            }
            Write-Host ""
        }
    }

    # ── Step 2: Backup .env and .env.example ─────────────────────────────
    Write-Host "[Step 2/6] Preserving current environment files..." -ForegroundColor Yellow

    $hadEnv        = $false
    $hadEnvExample = $false

    if (Test-Path $envPath) {
        Copy-Item -Path $envPath -Destination $envBackupPath -Force
        Write-Host "  [OK] Backed up .env to .env.backup" -ForegroundColor Green
        $hadEnv = $true
    } else {
        Write-Host "  [INFO] No .env file found (will use .env.example after upgrade)" -ForegroundColor Gray
    }

    if (Test-Path $envExamplePath) {
        Copy-Item -Path $envExamplePath -Destination $envExampleBackupPath -Force
        Write-Host "  [OK] Backed up .env.example to .env.example.backup" -ForegroundColor Green
        $hadEnvExample = $true
    } else {
        Write-Host "  [INFO] No .env.example file found" -ForegroundColor Gray
    }

    # ── Step 3: Confirm ───────────────────────────────────────────────────
    Write-Host "[Step 3/6] Confirming update..." -ForegroundColor Yellow

    if (-not $Force) {
        Write-Host "  [WARNING] This will discard all local changes!" -ForegroundColor Red
        $confirm = Read-Host "  Continue? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "  [CANCELLED] Update cancelled by user" -ForegroundColor Yellow
            # Restore backups
            if ($hadEnv)        { Copy-Item $envBackupPath        $envPath        -Force; Remove-Item $envBackupPath        -Force }
            if ($hadEnvExample) { Copy-Item $envExampleBackupPath $envExamplePath -Force; Remove-Item $envExampleBackupPath -Force }
            exit 0
        }
    }

    # ── Step 4: git reset / clean ────────────────────────────────────────
    Write-Host ""
    Write-Host "[Step 4/6] Updating repository..." -ForegroundColor Yellow

    try {
        Set-Location $repoRoot

        Write-Host "  [INFO] Current branch: $currentBranch" -ForegroundColor Gray

        git reset --hard "origin/$currentBranch"
        if ($LASTEXITCODE -ne 0) { throw "git reset failed" }
        Write-Host "  [OK] Repository updated to latest remote version" -ForegroundColor Green

        git clean -fd -e ".env" -e "*.backup"
        Write-Host "  [OK] Cleaned untracked files" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] Git operation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  [INFO] Restoring backed up files..." -ForegroundColor Yellow
        if ($hadEnv        -and (Test-Path $envBackupPath))        { Copy-Item $envBackupPath        $envPath        -Force; Remove-Item $envBackupPath        -Force; Write-Host "  [OK] Restored .env" -ForegroundColor Green }
        if ($hadEnvExample -and (Test-Path $envExampleBackupPath)) { Copy-Item $envExampleBackupPath $envExamplePath -Force; Remove-Item $envExampleBackupPath -Force; Write-Host "  [OK] Restored .env.example" -ForegroundColor Green }
        exit 1
    }

    # ── Step 5: Restore .env ─────────────────────────────────────────────
    Write-Host ""
    Write-Host "[Step 5/6] Restoring preserved .env file..." -ForegroundColor Yellow

    if ($hadEnv -and (Test-Path $envBackupPath)) {
        Copy-Item -Path $envBackupPath -Destination $envPath -Force
        Write-Host "  [OK] Restored .env from backup" -ForegroundColor Green
    }

    # ── Step 6: Compare env variables ────────────────────────────────────
    Write-Host ""
    Write-Host "[Step 6/6] Comparing environment variables..." -ForegroundColor Yellow

    $newEnvExamplePath = Join-Path $srcDir ".env.example"

    if ((Test-Path $newEnvExamplePath) -and $hadEnv) {
        Write-Host ""
        Write-Host "  Analyzing environment variables..." -ForegroundColor Cyan

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

        $newExample  = Parse-EnvFile $newEnvExamplePath
        $currentEnv  = Parse-EnvFile $envBackupPath

        $missingVars    = $newExample.Keys  | Where-Object { -not $currentEnv.ContainsKey($_)  } | ForEach-Object { @{ Key = $_; DefaultValue = $newExample[$_] } }
        $deprecatedVars = $currentEnv.Keys  | Where-Object { -not $newExample.ContainsKey($_)  }

        if ($missingVars.Count -gt 0) {
            Write-Host ""
            Write-Host "  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
            Write-Host "  │  MISSING VARIABLES - Add these to your .env file:      │" -ForegroundColor Yellow
            Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
            Write-Host ""
            foreach ($var in $missingVars) {
                $def = if ($var.DefaultValue) { " (default: $($var.DefaultValue))" } else { "" }
                Write-Host "    → $($var.Key)$def" -ForegroundColor Red
            }
            Write-Host ""
            Write-Host "  [ACTION REQUIRED] Please add the above variables to your .env file" -ForegroundColor Yellow
            Write-Host "  You can copy default values from .env.example" -ForegroundColor Gray
            Write-Host ""
            $appendConfirm = Read-Host "  Would you like to append missing variables with default values to .env? (y/N)"
            if ($appendConfirm -eq 'y' -or $appendConfirm -eq 'Y') {
                Add-Content -Path $envPath -Value ""
                Add-Content -Path $envPath -Value "# === Added by install.ps1 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
                foreach ($var in $missingVars) {
                    Add-Content -Path $envPath -Value "$($var.Key)=$($var.DefaultValue)"
                    Write-Host "    [ADDED] $($var.Key)" -ForegroundColor Green
                }
                Write-Host ""
                Write-Host "  [OK] Missing variables appended to .env with default values" -ForegroundColor Green
                Write-Host "  [ACTION] Please review and update the values as needed!" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [OK] No missing variables — your .env is up to date!" -ForegroundColor Green
        }

        if ($deprecatedVars.Count -gt 0) {
            Write-Host ""
            Write-Host "  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
            Write-Host "  │  DEPRECATED VARIABLES - May no longer be needed:        │" -ForegroundColor Cyan
            Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
            Write-Host ""
            foreach ($var in $deprecatedVars) { Write-Host "    → $var" -ForegroundColor Cyan }
            Write-Host ""
            Write-Host "  [INFO] These variables exist in your .env but not in .env.example" -ForegroundColor Gray
            Write-Host "  [INFO] They may be custom or deprecated — review if needed" -ForegroundColor Gray
        }
    } elseif (-not (Test-Path $newEnvExamplePath)) {
        Write-Host "  [WARNING] No .env.example found in updated repository" -ForegroundColor Yellow
    } elseif (-not $hadEnv) {
        Write-Host "  [INFO] No previous .env to compare — please create one from .env.example" -ForegroundColor Yellow
        if (Test-Path $newEnvExamplePath) { Write-Host "  [TIP] Run: Copy-Item src\.env.example src\.env" -ForegroundColor Gray }
    }

    # ── Install deps & compile ────────────────────────────────────────────
    Write-Host ""
    Write-Host "Installing dependencies..." -ForegroundColor Yellow
    Set-Location $srcDir
    npm install xlsx@file:vendor/xlsx-0.20.3.tgz --save
    npm install
    if ($LASTEXITCODE -ne 0) { Write-Host "  [ERROR] npm install failed" -ForegroundColor Red; exit 1 }

    Write-Host ""
    Write-Host "Compiling TypeScript..." -ForegroundColor Yellow
    npx tsc -p tsconfig.json
    if ($LASTEXITCODE -ne 0) { Write-Host "  [WARNING] TypeScript compilation reported errors" -ForegroundColor Yellow }

    # ── Cleanup backups ───────────────────────────────────────────────────
    Write-Host ""
    Write-Host "Cleaning up backup files..." -ForegroundColor Yellow
    if (Test-Path $envBackupPath)        { Remove-Item $envBackupPath        -Force; Write-Host "  [OK] Removed .env.backup"         -ForegroundColor Green }
    if (Test-Path $envExampleBackupPath) { Remove-Item $envExampleBackupPath -Force; Write-Host "  [OK] Removed .env.example.backup" -ForegroundColor Green }

    # ── Done ──────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Update completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Review any missing/deprecated variables above" -ForegroundColor White
    Write-Host "  2. Start the server: cd src && npm start" -ForegroundColor White
    Write-Host ""

} else {
    # ════════════════════════════════════════════════════════════════════════
    #  SCENARIO A — Fresh install (repo not yet cloned)
    # ════════════════════════════════════════════════════════════════════════

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SOVA On-Prem — Fresh Install" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Resolve install directory (ensure string, not PathInfo)
    $resolvedDir = Resolve-Path $InstallDir -ErrorAction SilentlyContinue
    $targetDir = if ($resolvedDir) { [string]$resolvedDir.ProviderPath } else { $InstallDir }

    # ── Determine clone destination ───────────────────────────────────────
    $defaultCloneName = "sova-on-prem"
    $cloneDest = Join-Path $targetDir $defaultCloneName

    # Check if destination already exists and is non-empty
    if ((Test-Path $cloneDest) -and (Get-ChildItem $cloneDest -Force | Select-Object -First 1)) {
        Write-Host "  [WARNING] Папка '$cloneDest' уже существует и не пуста." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Выберите действие:" -ForegroundColor Cyan
        Write-Host "  [1] Создать новую папку (введите имя, Enter = $defaultCloneName-new)" -ForegroundColor White
        Write-Host "  [2] Установить в текущую папку '$cloneDest' (git clone внутрь)" -ForegroundColor White
        Write-Host "  [Q] Отмена" -ForegroundColor White
        Write-Host ""
        $choice = Read-Host "  Ваш выбор"

        switch -Regex ($choice.Trim()) {
            '^[Qq]$' {
                Write-Host "  [CANCELLED] Установка отменена" -ForegroundColor Yellow
                exit 0
            }
            '^2$' {
                if (Test-Path (Join-Path $cloneDest ".git")) {
                    # Already a git repo → direct user to run from there
                    Write-Host "  [INFO] '$cloneDest' уже является git-репозиторием." -ForegroundColor Cyan
                    Write-Host "  Для обновления запустите скрипт из этой папки:" -ForegroundColor Yellow
                    Write-Host "  cd '$cloneDest'" -ForegroundColor White
                    Write-Host "  .\install.ps1" -ForegroundColor White
                    Write-Host ""
                    exit 0
                } else {
                    # Non-empty, not a git repo — git clone will fail; ask for a new name
                    Write-Host "  [WARNING] Папка '$cloneDest' не является git-репозиторием и не пуста." -ForegroundColor Red
                    Write-Host "  git clone не может работать с непустой папкой. Укажите новое имя." -ForegroundColor Red
                    Write-Host ""
                    $altName = Read-Host "  Имя новой папки (Enter = $defaultCloneName-new, Q = отмена)"
                    if ($altName -match '^[Qq]$') { Write-Host "  [CANCELLED]" -ForegroundColor Yellow; exit 0 }
                    $newName = if ([string]::IsNullOrWhiteSpace($altName)) { "$defaultCloneName-new" } else { $altName.Trim() }
                    $cloneDest = Join-Path $targetDir $newName
                    Write-Host "  [INFO] Папка установки: '$cloneDest'" -ForegroundColor Gray
                }
            }
            default {
                # Use entered name or fallback
                $newName = $choice.Trim()
                if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq '1') {
                    $newName = "$defaultCloneName-new"
                }
                $cloneDest = Join-Path $targetDir $newName
                Write-Host "  [INFO] Папка установки: '$cloneDest'" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    # ── Step 1: Clone ─────────────────────────────────────────────────────
    Write-Host "[Step 1/4] Cloning repository..." -ForegroundColor Yellow
    git clone https://github.com/ASPDP/sova-on-prem.git $cloneDest
    if ($LASTEXITCODE -ne 0) { Write-Host "  [ERROR] git clone failed" -ForegroundColor Red; exit 1 }
    Write-Host "  [OK] Repository cloned" -ForegroundColor Green

    $repoDir = $cloneDest
    $srcDir  = Join-Path $repoDir "src"

    # ── Step 2: Copy .env ─────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[Step 2/4] Looking for .env file..." -ForegroundColor Yellow

    # Check for .env alongside the repo directory (i.e. in $targetDir)
    $envSource = Join-Path $targetDir ".env"
    $envDest   = Join-Path $srcDir ".env"

    if (Test-Path $envSource) {
        Copy-Item -Path $envSource -Destination $envDest -Force
        Write-Host "  [OK] .env скопирован из $envSource" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] Нужно создать .env (пример: src/.env.example)" -ForegroundColor Red
        Write-Host "  Поместите файл .env рядом с папкой sova-on-prem и запустите скрипт снова," -ForegroundColor Yellow
        Write-Host "  или скопируйте вручную: cp sova-on-prem/src/.env.example sova-on-prem/src/.env" -ForegroundColor Yellow
        exit 1
    }

    # ── Step 3: Install deps & compile ───────────────────────────────────
    Write-Host ""
    Write-Host "[Step 3/4] Installing dependencies..." -ForegroundColor Yellow
    Set-Location $srcDir
    npm install xlsx@file:vendor/xlsx-0.20.3.tgz --save
    npm install
    if ($LASTEXITCODE -ne 0) { Write-Host "  [ERROR] npm install failed" -ForegroundColor Red; exit 1 }

    Write-Host ""
    Write-Host "Compiling TypeScript..." -ForegroundColor Yellow
    npx tsc -p tsconfig.json
    if ($LASTEXITCODE -ne 0) { Write-Host "  [WARNING] TypeScript compilation reported errors" -ForegroundColor Yellow }

    # ── Step 4: Start ─────────────────────────────────────────────────────
    Write-Host ""
    Write-Host "[Step 4/4] Starting server..." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Installation complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    npm start
}
