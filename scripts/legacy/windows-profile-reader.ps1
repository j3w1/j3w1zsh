#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RecoveryDirectory = "",
    [string]$FragmentsRoot = "",
    [switch]$Deactivate
)

$ErrorActionPreference = "Stop"
$root = if ($FragmentsRoot) { $FragmentsRoot } else { Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments" }
$formerDirectory = Join-Path $root "BloodyWriter"
$formerFragment = Join-Path $formerDirectory "bloody-writer.json"
if (-not (Test-Path -LiteralPath $formerFragment -PathType Leaf)) {
    exit 0
}
$document = Get-Content -Raw -LiteralPath $formerFragment | ConvertFrom-Json
$guid = @($document.profiles)[0].guid
if ($guid -notmatch '^\{[0-9a-fA-F-]{36}\}$') {
    throw "Former Windows Terminal profile has an invalid GUID."
}
if ($RecoveryDirectory) {
    New-Item -ItemType Directory -Force -Path $RecoveryDirectory | Out-Null
    Copy-Item -LiteralPath $formerFragment -Destination (Join-Path $RecoveryDirectory "windows-terminal-former-fragment.json")
}
if ($Deactivate) {
    if (-not $RecoveryDirectory) {
        throw "Deactivation requires a recovery directory."
    }
    Remove-Item -LiteralPath $formerFragment -Force
    if (@(Get-ChildItem -LiteralPath $formerDirectory -Force).Count -eq 0) {
        Remove-Item -LiteralPath $formerDirectory -Force
    }
}
$guid
