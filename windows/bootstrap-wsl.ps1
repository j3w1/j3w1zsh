#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DistroName = "archlinux"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    throw "Open PowerShell as Administrator, then run this script again."
}

Write-Host "j3w1zsh - WSL bootstrap" -ForegroundColor Red

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($null -eq $wslCommand) {
    throw "wsl.exe is unavailable. Install current Windows updates and try again."
}

& wsl.exe --status | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing the WSL platform. Windows may request a restart." -ForegroundColor Yellow
    & wsl.exe --install --no-distribution
    if ($LASTEXITCODE -ne 0) {
        throw "WSL platform installation failed with exit code $LASTEXITCODE."
    }
    Write-Host "Restart Windows if requested, then rerun this same script." -ForegroundColor Yellow
    exit 20
}

$installed = @(& wsl.exe --list --quiet) -replace "`0", "" | ForEach-Object { $_.Trim() }
if ($installed -notcontains $DistroName) {
    Write-Host "Installing the official Arch Linux WSL distribution." -ForegroundColor Yellow
    & wsl.exe --install --distribution $DistroName
    if ($LASTEXITCODE -ne 0) {
        throw "Arch Linux installation failed with exit code $LASTEXITCODE."
    }
    Write-Host "If Windows requests a restart, restart and rerun this same script." -ForegroundColor Yellow
}
else {
    Write-Host "Arch Linux is already installed." -ForegroundColor Green
}

Write-Host ""
Write-Host "Open Arch Linux, then run:" -ForegroundColor White
Write-Host "  pacman -Syu --needed git"
Write-Host "  git clone https://github.com/j3w1/j3w1zsh.git ~/j3w1zsh"
Write-Host "  cd ~/j3w1zsh"
Write-Host "  ./install.sh"
