#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$PowerShellFiles = @(
    "windows/bootstrap-wsl.ps1",
    "windows/apply-host-theme.ps1",
    "scripts/legacy/windows-profile-reader.ps1"
)

foreach ($relativePath in $PowerShellFiles) {
    $path = Join-Path $RepositoryRoot $relativePath
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failure in ${relativePath}: $($errors.Message -join '; ')"
    }
}

$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("j3w1zsh-host-theme-" + [Guid]::NewGuid().ToString("N"))
try {
    $Fragments = Join-Path $TestRoot "fragments"
    $FormerDirectory = Join-Path $Fragments "BloodyWriter"
    $Recovery = Join-Path $TestRoot "recovery"
    New-Item -ItemType Directory -Force -Path $FormerDirectory, $Recovery | Out-Null
    $OldGuid = "{12345678-1234-4567-89ab-1234567890ab}"
    $FormerFragment = [ordered]@{ profiles = @([ordered]@{ guid = $OldGuid; name = "former profile" }) }
    [IO.File]::WriteAllText(
        (Join-Path $FormerDirectory "bloody-writer.json"),
        ($FormerFragment | ConvertTo-Json -Depth 6),
        [Text.UTF8Encoding]::new($false)
    )
    $Theme = [ordered]@{
        name = "j3w1zsh"; background = "#000000"; foreground = "#FFF1F1";
        black = "#000000"; red = "#B00020"; green = "#B00020"; yellow = "#FF8A00";
        blue = "#5E9CFF"; purple = "#AA70FF"; cyan = "#44D7D7"; white = "#FFF1F1";
        brightBlack = "#4B171E"; brightRed = "#FF334D"; brightGreen = "#FF334D";
        brightYellow = "#FFB020"; brightBlue = "#86B7FF"; brightPurple = "#C79BFF";
        brightCyan = "#78FFFF"; brightWhite = "#FFFFFF"
    }
    $ThemePath = Join-Path $TestRoot "theme.json"
    [IO.File]::WriteAllText($ThemePath, ($Theme | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

    & (Join-Path $RepositoryRoot "windows/apply-host-theme.ps1") `
        -ThemePath $ThemePath -OutputRoot $Fragments -MigrationRecoveryPath $Recovery -SkipFontInstall | Out-Null

    $FragmentPath = Join-Path $Fragments "j3w1zsh/j3w1zsh.json"
    $FragmentBytes = [IO.File]::ReadAllBytes($FragmentPath)
    if ($FragmentBytes.Length -ge 3 -and $FragmentBytes[0] -eq 0xEF -and $FragmentBytes[1] -eq 0xBB -and $FragmentBytes[2] -eq 0xBF) {
        throw "Generated Windows Terminal JSON unexpectedly contains a UTF-8 BOM."
    }
    $Fragment = Get-Content -Raw -LiteralPath $FragmentPath | ConvertFrom-Json
    if ($Fragment.profiles.Count -ne 1 -or $Fragment.profiles[0].guid -ne $OldGuid -or
        $Fragment.profiles[0].name -cne "j3w1zsh - arch wsl" -or
        $Fragment.schemes.Count -ne 1 -or $Fragment.schemes[0].name -cne "j3w1zsh") {
        throw "Stable GUID, lowercase profile, or unique scheme verification failed."
    }
    if (Test-Path -LiteralPath (Join-Path $FormerDirectory "bloody-writer.json")) {
        throw "Former host fragment remained active after migration fixture."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Recovery "windows-terminal-former-fragment.json") -PathType Leaf)) {
        throw "Former host fragment was not preserved in recovery."
    }
} finally {
    if (Test-Path -LiteralPath $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}

Write-Host "PowerShell syntax, stable GUID, profile uniqueness, UTF-8 JSON, path, and recovery tests passed."
