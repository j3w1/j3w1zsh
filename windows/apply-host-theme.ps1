#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DistroName = "archlinux",
    [Parameter(Mandatory = $true)][string]$ThemePath,
    [string]$MigrationRecoveryPath = "",
    [string]$OutputRoot = "",
    [switch]$SkipFontInstall,
    [string]$TestFontDirectory = "",
    [string]$TestFontRegistryPath = "",
    [string]$TestFontSourcePath = "",
    [string]$TestTemporaryRoot = "",
    [switch]$TestSkipNativeFontRegistration
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

function Test-PathWithinBoundary {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Boundary
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullBoundary = [IO.Path]::GetFullPath($Boundary).TrimEnd([char[]]@('\', '/'))
    if ($fullPath.Equals($fullBoundary, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $fullPath.StartsWith(
        $fullBoundary + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-SafeDirectoryTree {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Boundary,
        [switch]$Create
    )
    if (-not (Test-PathWithinBoundary -Path $Path -Boundary $Boundary)) {
        throw "Refusing a directory outside its approved boundary: $Path"
    }
    if ($Create -and -not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    $current = [IO.Path]::GetFullPath($Path)
    $fullBoundary = [IO.Path]::GetFullPath($Boundary).TrimEnd([char[]]@('\', '/'))
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or
            (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "Refusing a non-directory or reparse-point directory: $current"
        }
        if ($current.Equals($fullBoundary, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent -or
            -not (Test-PathWithinBoundary -Path $parent.FullName -Boundary $fullBoundary)) {
            throw "Directory validation escaped its approved boundary: $Path"
        }
        $current = $parent.FullName
    }
}

function Get-SafeRegularFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return ""
    }
    if ($item.PSIsContainer -or
        (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Refusing a non-regular or reparse-point font path: $Path"
    }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Remove-OwnedTemporaryDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Token
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullParent = [IO.Path]::GetFullPath($Parent).TrimEnd([char[]]@('\', '/'))
    $expectedLeaf = "j3w1zsh-host-theme-$PID-$Token"
    if (-not ([IO.Directory]::GetParent($fullPath).FullName.Equals(
                $fullParent, [StringComparison]::OrdinalIgnoreCase)) -or
        -not ([IO.Path]::GetFileName($fullPath).Equals(
                $expectedLeaf, [StringComparison]::Ordinal))) {
        throw "Refusing to clean an unrecognized host-theme temporary directory."
    }
    $directory = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer -or
        (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Refusing to clean a non-directory or reparse-point temporary path."
    }
    $markerPath = Join-Path $fullPath ".j3w1zsh-owned"
    $marker = Get-Item -LiteralPath $markerPath -Force -ErrorAction Stop
    if ($marker.PSIsContainer -or
        (($marker.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
        ([IO.File]::ReadAllText($markerPath) -ne $Token)) {
        throw "Refusing to clean a temporary directory without its exact ownership marker."
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function Install-VerifiedFontContent {
    param(
        [Parameter(Mandatory = $true)][string]$VerifiedSource,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$FontDirectory
    )
    $pendingName = ".j3w1zsh-font-$PID-$([Guid]::NewGuid().ToString('N')).pending"
    $pendingPath = Join-Path $FontDirectory $pendingName
    if (-not (Test-PathWithinBoundary -Path $pendingPath -Boundary $FontDirectory)) {
        throw "Refusing an invalid pending font path."
    }
    try {
        [IO.File]::Copy($VerifiedSource, $pendingPath, $false)
        if ((Get-SafeRegularFileSha256 -Path $pendingPath) -ne $ExpectedSha256) {
            throw "Pending Nerd Font bytes changed before installation."
        }
        try {
            [IO.File]::Move($pendingPath, $Destination)
        } catch [IO.IOException] {
            if ((Get-SafeRegularFileSha256 -Path $Destination) -ne $ExpectedSha256) {
                throw
            }
        }
    } finally {
        $pending = Get-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $pending) {
            if ($pending.PSIsContainer -or
                (($pending.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
                -not ([IO.Directory]::GetParent($pending.FullName).FullName.Equals(
                        [IO.Path]::GetFullPath($FontDirectory), [StringComparison]::OrdinalIgnoreCase)) -or
                -not $pending.Name.StartsWith(".j3w1zsh-font-$PID-", [StringComparison]::Ordinal)) {
                throw "Refusing to clean an unrecognized pending font path."
            }
            Remove-Item -LiteralPath $pending.FullName -Force
        }
    }
}

$testHooksRequested = $TestFontDirectory -or $TestFontRegistryPath -or
    $TestFontSourcePath -or $TestTemporaryRoot -or $TestSkipNativeFontRegistration
if ($testHooksRequested -and $env:J3W1ZSH_TEST_MODE -ne "1") {
    throw "Host-theme test paths are accepted only in explicit test mode."
}
if ($TestFontRegistryPath -and
    $TestFontRegistryPath -notmatch '^HKCU:\\Software\\j3w1zsh-tests\\[A-Za-z0-9-]+$') {
    throw "The test font registry path must stay under HKCU:\\Software\\j3w1zsh-tests."
}
$systemTemporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
foreach ($testPath in @($TestFontDirectory, $TestFontSourcePath, $TestTemporaryRoot)) {
    if ($testPath -and -not (Test-PathWithinBoundary -Path $testPath -Boundary $systemTemporaryRoot)) {
        throw "Host-theme test filesystem paths must stay under the system temporary directory."
    }
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
    $fontChecksum = (Get-PinnedValue -Name "NERD_FONT_SHA256").ToLowerInvariant()
    if ($fontVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$' -or
        $fontChecksum -notmatch '^[0-9a-f]{64}$') {
        throw "Invalid pinned Nerd Font version or SHA-256."
    }
    $fontUrl = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v$fontVersion/patched-fonts/JetBrainsMono/Ligatures/Regular/$fontFileName"
    $userFontDirectory = if ($TestFontDirectory) {
        [IO.Path]::GetFullPath($TestFontDirectory)
    } else {
        Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    }
    $fontBoundary = if ($TestFontDirectory) { $systemTemporaryRoot } else { $env:LOCALAPPDATA }
    Assert-SafeDirectoryTree -Path $userFontDirectory -Boundary $fontBoundary -Create

    $legacyFontPath = Join-Path $userFontDirectory $fontFileName
    $fontStem = [IO.Path]::GetFileNameWithoutExtension($fontFileName)
    $contentFontPath = Join-Path $userFontDirectory "$fontStem-$fontChecksum.ttf"
    $legacyChecksum = Get-SafeRegularFileSha256 -Path $legacyFontPath
    $contentChecksum = Get-SafeRegularFileSha256 -Path $contentFontPath
    if ($contentChecksum -and $contentChecksum -ne $fontChecksum) {
        throw "Refusing to overwrite a mismatched content-addressed Nerd Font file: $contentFontPath"
    }

    if ($legacyChecksum -eq $fontChecksum) {
        $installedFontPath = $legacyFontPath
    } elseif ($contentChecksum -eq $fontChecksum) {
        $installedFontPath = $contentFontPath
    } else {
        $temporaryParent = if ($TestTemporaryRoot) {
            [IO.Path]::GetFullPath($TestTemporaryRoot)
        } else {
            $systemTemporaryRoot
        }
        Assert-SafeDirectoryTree -Path $temporaryParent -Boundary $systemTemporaryRoot -Create
        $temporaryToken = [Guid]::NewGuid().ToString("N")
        $temporaryDirectory = Join-Path $temporaryParent "j3w1zsh-host-theme-$PID-$temporaryToken"
        New-Item -ItemType Directory -Path $temporaryDirectory -ErrorAction Stop | Out-Null
        Assert-SafeDirectoryTree -Path $temporaryDirectory -Boundary $temporaryParent
        [IO.File]::WriteAllText(
            (Join-Path $temporaryDirectory ".j3w1zsh-owned"),
            $temporaryToken,
            [Text.UTF8Encoding]::new($false)
        )
        try {
            $downloadPath = Join-Path $temporaryDirectory $fontFileName
            if ($TestFontSourcePath) {
                if ((Get-SafeRegularFileSha256 -Path $TestFontSourcePath) -eq "") {
                    throw "Test font source is missing."
                }
                [IO.File]::Copy($TestFontSourcePath, $downloadPath, $false)
            } else {
                Invoke-WebRequest -Uri $fontUrl -OutFile $downloadPath -UseBasicParsing
            }
            if ((Get-SafeRegularFileSha256 -Path $downloadPath) -ne $fontChecksum) {
                throw "Nerd Font checksum verification failed."
            }
            Install-VerifiedFontContent -VerifiedSource $downloadPath `
                -Destination $contentFontPath -ExpectedSha256 $fontChecksum `
                -FontDirectory $userFontDirectory
        } finally {
            Remove-OwnedTemporaryDirectory -Path $temporaryDirectory `
                -Parent $temporaryParent -Token $temporaryToken
        }
        if ((Get-SafeRegularFileSha256 -Path $contentFontPath) -ne $fontChecksum) {
            throw "Installed Nerd Font verification failed."
        }
        $installedFontPath = $contentFontPath
    }

    $fontRegistryPath = if ($TestFontRegistryPath) {
        $TestFontRegistryPath
    } else {
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
    }
    New-Item -Path $fontRegistryPath -Force | Out-Null
    $fontRegistryName = "JetBrainsMono Nerd Font Mono (TrueType)"
    $fontRegistryItem = Get-ItemProperty -LiteralPath $fontRegistryPath
    $registeredFontProperty = $fontRegistryItem.PSObject.Properties[$fontRegistryName]
    $registeredFontPath = if ($null -eq $registeredFontProperty) {
        ""
    } else {
        [string]$registeredFontProperty.Value
    }
    if ($registeredFontPath -ne $installedFontPath) {
        New-ItemProperty -Path $fontRegistryPath -Name $fontRegistryName `
            -Value $installedFontPath -PropertyType String -Force | Out-Null
    }
    if (-not $TestSkipNativeFontRegistration) {
        if (-not ("J3W1ZSH.NativeFont" -as [type])) {
            Add-Type -Namespace J3W1ZSH -Name NativeFont -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResourceEx(string fileName, uint flags, System.IntPtr reserved);
'@
        }
        [J3W1ZSH.NativeFont]::AddFontResourceEx($installedFontPath, 0x10, [IntPtr]::Zero) | Out-Null
    }
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
