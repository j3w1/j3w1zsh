#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DistroName = "archlinux",
    [Parameter(Mandatory = $true)][string]$ThemePath,
    [string]$MigrationRecoveryPath = "",
    [string]$OutputRoot = "",
    [switch]$SkipFontInstall
)

$ErrorActionPreference = "Stop"
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$VersionsFile = Join-Path $RepositoryRoot "versions.env"
$BrandPng = Join-Path $RepositoryRoot "assets/brand/j3w1zsh.png"

function Get-PinnedValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $line = Get-Content -LiteralPath $VersionsFile |
        Where-Object { $_ -match "^$([Regex]::Escape($Name))=" } |
        Select-Object -First 1
    if (-not $line -or $line -notmatch '^[A-Z0-9_]+="([^"]+)"$') {
        throw "Unable to read $Name from versions.env."
    }
    return $Matches[1]
}

if (-not (Test-Path -LiteralPath $ThemePath -PathType Leaf)) {
    throw "Rendered declarative theme is missing: $ThemePath"
}
if (-not (Test-Path -LiteralPath $BrandPng -PathType Leaf)) {
    throw "Rendered brand PNG is missing: $BrandPng"
}
$theme = Get-Content -Raw -LiteralPath $ThemePath | ConvertFrom-Json
if ($theme.name -ne "j3w1zsh") {
    throw "Rendered Windows Terminal theme must be lowercase j3w1zsh."
}

Write-Host "j3w1zsh - Windows host theme" -ForegroundColor Red

$fontFileName = "JetBrainsMonoNerdFontMono-Regular.ttf"
if (-not $SkipFontInstall) {
    $fontVersion = Get-PinnedValue -Name "NERD_FONT_VERSION"
    $fontChecksum = Get-PinnedValue -Name "NERD_FONT_SHA256"
    $fontUrl = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v$fontVersion/patched-fonts/JetBrainsMono/Ligatures/Regular/$fontFileName"
    $downloadPath = Join-Path $env:TEMP "j3w1zsh-$fontFileName"
    Invoke-WebRequest -Uri $fontUrl -OutFile $downloadPath -UseBasicParsing
    $actualChecksum = (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadPath).Hash.ToLowerInvariant()
    if ($actualChecksum -ne $fontChecksum.ToLowerInvariant()) {
        throw "Nerd Font checksum verification failed."
    }
    $userFontDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    New-Item -ItemType Directory -Force -Path $userFontDirectory | Out-Null
    $installedFontPath = Join-Path $userFontDirectory $fontFileName
    Copy-Item -LiteralPath $downloadPath -Destination $installedFontPath -Force
    $fontRegistryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    New-Item -Path $fontRegistryPath -Force | Out-Null
    New-ItemProperty -Path $fontRegistryPath -Name "JetBrainsMono Nerd Font Mono (TrueType)" `
        -Value $installedFontPath -PropertyType String -Force | Out-Null
    if (-not ("J3W1ZSH.NativeFont" -as [type])) {
        Add-Type -Namespace J3W1ZSH -Name NativeFont -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResourceEx(string fileName, uint flags, System.IntPtr reserved);
'@
    }
    [J3W1ZSH.NativeFont]::AddFontResourceEx($installedFontPath, 0x10, [IntPtr]::Zero) | Out-Null
    Remove-Item -LiteralPath $downloadPath -Force
} else {
    Write-Warning "Package-free mode did not acquire or update the pinned Windows font."
}

$fragmentBase = if ($OutputRoot) { $OutputRoot } else { Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments" }
$fragmentDirectory = Join-Path $fragmentBase "j3w1zsh"
New-Item -ItemType Directory -Force -Path $fragmentDirectory | Out-Null
$iconPath = Join-Path $fragmentDirectory "j3w1zsh.png"
Copy-Item -LiteralPath $BrandPng -Destination $iconPath -Force

$profileGuid = "{8f916408-9c85-48e2-a01f-b02188433b83}"
$legacyReader = Join-Path $RepositoryRoot "scripts\legacy\windows-profile-reader.ps1"
if (Test-Path -LiteralPath $legacyReader -PathType Leaf) {
    $legacyArguments = @{}
    if ($MigrationRecoveryPath) {
        $legacyArguments.RecoveryDirectory = $MigrationRecoveryPath
        $legacyArguments.Deactivate = $true
    }
    if ($OutputRoot) {
        $legacyArguments.FragmentsRoot = $OutputRoot
    }
    $discoveredGuid = & $legacyReader @legacyArguments
    if ($discoveredGuid -and $discoveredGuid.Trim() -match '^\{[0-9a-fA-F-]{36}\}$') {
        $profileGuid = $discoveredGuid.Trim()
    }
}

$profile = [ordered]@{
    guid = $profileGuid
    name = "j3w1zsh - arch wsl"
    commandline = "wsl.exe -d $DistroName"
    startingDirectory = "~"
    colorScheme = "j3w1zsh"
    icon = $iconPath
    font = [ordered]@{ face = "JetBrainsMono Nerd Font Mono"; size = 13 }
}
$scheme = [ordered]@{}
foreach ($property in $theme.PSObject.Properties) {
    $scheme[$property.Name] = $property.Value
}
$fragment = [ordered]@{ profiles = @($profile); schemes = @($scheme) }
$fragmentPath = Join-Path $fragmentDirectory "j3w1zsh.json"
$json = $fragment | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($fragmentPath, $json, [Text.UTF8Encoding]::new($false))

Write-Host "Windows host theme installed. Reopen Windows Terminal and select:"
Write-Host "  j3w1zsh - arch wsl" -ForegroundColor White
