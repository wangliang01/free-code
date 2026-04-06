# free-code installer for Windows
# Usage: iwr -useb https://raw.githubusercontent.com/wangliang01/free-code/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$REPO = "https://github.com/wangliang01/free-code.git"
$INSTALL_DIR = "$env:USERPROFILE\free-code"
$BUN_MIN_VERSION = "1.3.11"

function Write-Info($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }

function Header {
    Write-Host ""
    Write-Host "    ___                            _" -ForegroundColor Cyan
    Write-Host "   / _|_ __ ___  ___        ___ __| | ___" -ForegroundColor Cyan
    Write-Host "  | |_| '__/ _ \/ _ \_____ / __/ _` |/ _ \" -ForegroundColor Cyan
    Write-Host "  |  _| | |  __/  __/_____| (_| (_| |  __/" -ForegroundColor Cyan
    Write-Host "  |_| |_|  \___|\___|      \___\__,_|\___|" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  The free build of Claude Code" -ForegroundColor DarkGray
    Write-Host ""
}

function Check-OS {
    $os = $env:OS
    if ($os -ne "Windows_NT") {
        Write-Fail "Unsupported OS: $os. Windows required."
    }
    $arch = $env:PROCESSOR_ARCHITECTURE
    Write-Ok "OS: Windows ($arch)"
}

function Check-Git {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Fail "git is not installed. Install it from: https://git-scm.com"
    }
    $ver = git --version
    Write-Ok "git: $ver"
}

function Version-Gte($v1, $v2) {
    $v1Parts = $v1.Split('.')
    $v2Parts = $v2.Split('.')
    for ($i = 0; $i -lt 3; $i++) {
        $p1 = if ($i -lt $v1Parts.Count) { [int]$v1Parts[$i] } else { 0 }
        $p2 = if ($i -lt $v2Parts.Count) { [int]$v2Parts[$i] } else { 0 }
        if ($p1 -gt $p2) { return $true }
        if ($p1 -lt $p2) { return $false }
    }
    return $true
}

function Check-Bun {
    $bun = Get-Command bun -ErrorAction SilentlyContinue
    if ($bun) {
        $ver = bun --version
        if (Version-Gte $ver $BUN_MIN_VERSION) {
            Write-Ok "bun: v$ver"
            return
        }
        Write-Warn "bun v$ver found but v$BUN_MIN_VERSION+ required. Upgrading..."
    } else {
        Write-Info "bun not found. Installing..."
    }
    Install-Bun
}

function Install-Bun {
    $bun = Get-Command bun -ErrorAction SilentlyContinue
    if ($bun) {
        $ver = bun --version
        if (Version-Gte $ver $BUN_MIN_VERSION) {
            Write-Ok "bun: v$ver"
            return
        }
        Write-Warn "bun v$ver found but v$BUN_MIN_VERSION+ required. Upgrading..."
    } else {
        Write-Info "bun not found. Installing..."
    }
    
    # Download and install bun manually (avoid bash script issues)
    $tempDir = [System.IO.Path]::GetTempPath()
    $bunZip = Join-Path $tempDir "bun-windows-x64.zip"
    
    # Detect architecture
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64") { "x64" } else { "aarch64" }
    
    Invoke-WebRequest -Uri "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_MIN_VERSION/bun-windows-x64.zip" -OutFile $bunZip -UseBasicParsing
    
    # Extract
    $bunDir = "$env:USERPROFILE\.bun"
    if (Test-Path $bunDir) { Remove-Item $bunDir -Recurse -Force }
    Expand-Archive -Path $bunZip -DestinationPath $bunDir -Force
    
    $env:BUN_INSTALL = $bunDir
    $env:PATH = "$bunDir\bin;$env:PATH"
    
    $bun = Get-Command bun -ErrorAction SilentlyContinue
    if (-not $bun) {
        Write-Fail "bun installation failed. Add $bunDir\bin to your PATH."
    }
    Write-Ok "bun: v$(bun --version) (just installed)"
}

function Clone-Repo {
    if (Test-Path $INSTALL_DIR) {
        Write-Warn "$INSTALL_DIR already exists"
        if (Test-Path "$INSTALL_DIR\.git") {
            Write-Info "Pulling latest changes..."
            Set-Location $INSTALL_DIR
            git pull --ff-only origin main 2>$null
            if ($LASTEXITCODE -ne 0) { Write-Warn "Pull failed, continuing with existing copy" }
        }
    } else {
        Write-Info "Cloning repository..."
        git clone --depth 1 $REPO $INSTALL_DIR
    }
    Write-Ok "Source: $INSTALL_DIR"
}

function Install-Deps {
    Write-Info "Installing dependencies..."
    Set-Location $INSTALL_DIR
    bun install --frozen-lockfile 2>$null
    if ($LASTEXITCODE -ne 0) { bun install }
    Write-Ok "Dependencies installed"
}

function Build-Binary {
    Write-Info "Building free-code (all experimental features enabled)..."
    Set-Location $INSTALL_DIR
    
    # Ensure output directory exists
    $outDir = if ($IsWindows) { ".\cli-dev" } else { "./cli-dev" }
    $outDir = Split-Path $outDir
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    
    bun run build:dev:full
    $binaryPath = Join-Path $INSTALL_DIR "cli-dev"
    if (Test-Path $binaryPath) {
        Write-Ok "Binary built: $binaryPath"
    } else {
        Write-Fail "Build failed: cli-dev not found"
    }
}

function Link-Binary {
    $linkDir = "$env:USERPROFILE\.local\bin"
    if (-not (Test-Path $linkDir)) {
        New-Item -ItemType Directory -Path $linkDir -Force | Out-Null
    }
    
    $linkPath = Join-Path $linkDir "free-code.exe"
    $sourcePath = Join-Path $INSTALL_DIR "cli-dev"
    
    if (Test-Path $linkPath) {
        Remove-Item $linkPath -Force
    }
    Copy-Item $sourcePath $linkPath
    Write-Ok "Copied: $linkPath"
    
    $pathAdded = $env:PATH -split ';' -contains $linkDir
    if (-not $pathAdded) {
        Write-Warn "$linkDir is not on your PATH"
        Write-Host ""
        Write-Host "  Add this to your PowerShell profile (`$PROFILE):" -ForegroundColor Yellow
        Write-Host "    `$env:PATH += `";$linkDir`"" -ForegroundColor Yellow
        Write-Host ""
    }
}

# Main
Header
Write-Info "Starting installation..."
Write-Host ""

Check-OS
Check-Git
Check-Bun
Write-Host ""

Clone-Repo
Install-Deps
Build-Binary
Link-Binary

Write-Host ""
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Run it:"
Write-Host "    free-code.exe                          # interactive REPL"
Write-Host "    free-code.exe -p `"your prompt`"        # one-shot mode"
Write-Host ""
Write-Host "  Set your API key:"
Write-Host "    `$env:ANTHROPIC_API_KEY=`"sk-ant-...`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Or log in with Claude.ai:"
Write-Host "    free-code.exe /login"
Write-Host ""
Write-Host "  Source: $INSTALL_DIR" -ForegroundColor DarkGray
Write-Host "  Binary: $INSTALL_DIR\cli-dev" -ForegroundColor DarkGray