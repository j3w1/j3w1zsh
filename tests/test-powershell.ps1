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

$RunningOnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if (-not $RunningOnWindows) {
    $portableRoot = Join-Path ([IO.Path]::GetTempPath()) ("j3w1zsh-powershell-portable-" + [Guid]::NewGuid().ToString("N"))
    try {
        $fragments = Join-Path $portableRoot "fragments"
        $formerDirectory = Join-Path $fragments "BloodyWriter"
        $recovery = Join-Path $portableRoot "recovery"
        New-Item -ItemType Directory -Force -Path $formerDirectory, $recovery | Out-Null
        $oldGuid = "{12345678-1234-4567-89ab-1234567890ab}"
        $formerFragment = [ordered]@{ profiles = @([ordered]@{ guid = $oldGuid; name = "former profile" }) }
        [IO.File]::WriteAllText(
            (Join-Path $formerDirectory "bloody-writer.json"),
            ($formerFragment | ConvertTo-Json -Depth 6),
            [Text.UTF8Encoding]::new($false)
        )
        $theme = [ordered]@{
            name = "j3w1zsh"; background = "#000000"; foreground = "#FFF1F1";
            black = "#000000"; red = "#B00020"; green = "#B00020"; yellow = "#FF8A00";
            blue = "#5E9CFF"; purple = "#AA70FF"; cyan = "#44D7D7"; white = "#FFF1F1";
            brightBlack = "#4B171E"; brightRed = "#FF334D"; brightGreen = "#FF334D";
            brightYellow = "#FFB020"; brightBlue = "#86B7FF"; brightPurple = "#C79BFF";
            brightCyan = "#78FFFF"; brightWhite = "#FFFFFF"
        }
        $themePath = Join-Path $portableRoot "theme.json"
        [IO.File]::WriteAllText($themePath, ($theme | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
        & (Join-Path $RepositoryRoot "windows/apply-host-theme.ps1") `
            -ThemePath $themePath -OutputRoot $fragments `
            -MigrationRecoveryPath $recovery -SkipFontInstall | Out-Null
        $fragmentPath = Join-Path $fragments "j3w1zsh/j3w1zsh.json"
        $fragment = Get-Content -Raw -LiteralPath $fragmentPath | ConvertFrom-Json
        if ($fragment.profiles.Count -ne 1 -or $fragment.profiles[0].guid -ne $oldGuid -or
            $fragment.profiles[0].name -cne "j3w1zsh - arch wsl" -or
            $fragment.schemes.Count -ne 1 -or $fragment.schemes[0].name -cne "j3w1zsh") {
            throw "Portable PowerShell GUID, profile, or scheme verification failed."
        }
        if (Test-Path -LiteralPath (Join-Path $formerDirectory "bloody-writer.json")) {
            throw "Portable PowerShell fixture left the former host fragment active."
        }
        if (-not (Test-Path -LiteralPath (Join-Path $recovery "windows-terminal-former-fragment.json") -PathType Leaf)) {
            throw "Portable PowerShell fixture did not preserve the former fragment."
        }
    } finally {
        if (Test-Path -LiteralPath $portableRoot) {
            Remove-Item -LiteralPath $portableRoot -Recurse -Force
        }
    }
    Write-Host "PowerShell parsing and portable fragment, GUID, path, and recovery tests passed; native Windows owns font and registry tests."
    exit 0
}

function Get-PinnedValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $line = Get-Content -LiteralPath (Join-Path $RepositoryRoot "versions.env") |
        Where-Object { $_ -match "^$([Regex]::Escape($Name))=" } |
        Select-Object -First 1
    if (-not $line -or $line -notmatch '^[A-Z0-9_]+="([^"]+)"$') {
        throw "Unable to read test pin $Name."
    }
    return $Matches[1]
}

function New-CaseContext {
    param([Parameter(Mandatory = $true)][string]$Name)
    $root = Join-Path $TestRoot $Name
    $fontDirectory = Join-Path $root "fonts"
    $fragments = Join-Path $root "fragments"
    $temporary = Join-Path $root "temporary"
    New-Item -ItemType Directory -Force -Path $fontDirectory, $fragments, $temporary | Out-Null
    $registryPath = "HKCU:\Software\j3w1zsh-tests\$TestId-$Name"
    $script:RegistryPaths += $registryPath
    return [pscustomobject]@{
        Name = $Name
        Root = $root
        FontDirectory = $fontDirectory
        Fragments = $fragments
        Temporary = $temporary
        RegistryPath = $registryPath
        LegacyFont = Join-Path $fontDirectory $FontFileName
        ContentFont = Join-Path $fontDirectory "$FontStem-$ExpectedChecksum.ttf"
        Fragment = Join-Path $fragments "j3w1zsh/j3w1zsh.json"
    }
}

function Invoke-HostThemeCase {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [string]$SourcePath = $PinnedFontSource,
        [string]$MigrationRecoveryPath = ""
    )
    $arguments = @{
        ThemePath = $ThemePath
        OutputRoot = $Context.Fragments
        TestFontDirectory = $Context.FontDirectory
        TestFontRegistryPath = $Context.RegistryPath
        TestFontSourcePath = $SourcePath
        TestTemporaryRoot = $Context.Temporary
        TestSkipNativeFontRegistration = $true
    }
    if ($MigrationRecoveryPath) {
        $arguments.MigrationRecoveryPath = $MigrationRecoveryPath
    }
    & $HostThemeScript @arguments | Out-Null
}

function Assert-FragmentContract {
    param([Parameter(Mandatory = $true)]$Context)
    $fragmentBytes = [IO.File]::ReadAllBytes($Context.Fragment)
    if ($fragmentBytes.Length -ge 3 -and $fragmentBytes[0] -eq 0xEF -and
        $fragmentBytes[1] -eq 0xBB -and $fragmentBytes[2] -eq 0xBF) {
        throw "Generated Windows Terminal JSON unexpectedly contains a UTF-8 BOM."
    }
    $fragment = Get-Content -Raw -LiteralPath $Context.Fragment | ConvertFrom-Json
    if ($fragment.profiles.Count -ne 1 -or
        $fragment.profiles[0].name -cne "j3w1zsh - arch wsl" -or
        $fragment.profiles[0].colorScheme -cne "j3w1zsh" -or
        $fragment.profiles[0].font.face -cne "JetBrainsMono Nerd Font Mono" -or
        $fragment.schemes.Count -ne 1 -or
        $fragment.schemes[0].name -cne "j3w1zsh") {
        throw "Lowercase unique Windows Terminal profile or scheme verification failed."
    }
}

function Get-RegisteredFontPath {
    param([Parameter(Mandatory = $true)]$Context)
    return Get-ItemPropertyValue -LiteralPath $Context.RegistryPath -Name $FontRegistryName
}

function Assert-NoOwnedTemporaryDirectories {
    param([Parameter(Mandatory = $true)]$Context)
    if (Get-ChildItem -LiteralPath $Context.Temporary -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "j3w1zsh-host-theme-*" } | Select-Object -First 1) {
        throw "A process-owned host-theme temporary directory was not cleaned."
    }
}

$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("j3w1zsh-powershell-" + [Guid]::NewGuid().ToString("N"))
$TestId = [Guid]::NewGuid().ToString("N")
$RegistryPaths = @()
$OriginalTestMode = $env:J3W1ZSH_TEST_MODE
$HostThemeScript = Join-Path $RepositoryRoot "windows/apply-host-theme.ps1"
$FontFileName = "JetBrainsMonoNerdFontMono-Regular.ttf"
$FontStem = [IO.Path]::GetFileNameWithoutExtension($FontFileName)
$FontRegistryName = "JetBrainsMono Nerd Font Mono (TrueType)"
$ExpectedChecksum = (Get-PinnedValue -Name "NERD_FONT_SHA256").ToLowerInvariant()
$FontVersion = Get-PinnedValue -Name "NERD_FONT_VERSION"
$PinnedFontSource = Join-Path $TestRoot "pinned-font.ttf"
$ThemePath = Join-Path $TestRoot "theme.json"

try {
    New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null
    $env:J3W1ZSH_TEST_MODE = "1"
    $fontUrl = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v$FontVersion/patched-fonts/JetBrainsMono/Ligatures/Regular/$FontFileName"
    Invoke-WebRequest -Uri $fontUrl -OutFile $PinnedFontSource -UseBasicParsing
    if ((Get-FileHash -LiteralPath $PinnedFontSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne
        $ExpectedChecksum) {
        throw "Downloaded PowerShell fixture does not match the pinned Nerd Font SHA-256."
    }

    $theme = [ordered]@{
        name = "j3w1zsh"; background = "#000000"; foreground = "#FFF1F1";
        black = "#000000"; red = "#B00020"; green = "#B00020"; yellow = "#FF8A00";
        blue = "#5E9CFF"; purple = "#AA70FF"; cyan = "#44D7D7"; white = "#FFF1F1";
        brightBlack = "#4B171E"; brightRed = "#FF334D"; brightGreen = "#FF334D";
        brightYellow = "#FFB020"; brightBlue = "#86B7FF"; brightPurple = "#C79BFF";
        brightCyan = "#78FFFF"; brightWhite = "#FFFFFF"
    }
    [IO.File]::WriteAllText($ThemePath, ($theme | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

    # Font absent: install verified bytes under a content-addressed filename,
    # reconcile the one owned registry value, and generate one profile/scheme.
    $absent = New-CaseContext -Name "absent"
    Invoke-HostThemeCase -Context $absent
    if (-not (Test-Path -LiteralPath $absent.ContentFont -PathType Leaf) -or
        (Test-Path -LiteralPath $absent.LegacyFont) -or
        (Get-FileHash -LiteralPath $absent.ContentFont -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedChecksum -or
        (Get-RegisteredFontPath -Context $absent) -ne $absent.ContentFont) {
        throw "Absent-font installation did not produce the verified content-addressed registration."
    }
    Assert-FragmentContract -Context $absent
    Assert-NoOwnedTemporaryDirectories -Context $absent

    # Exact legacy file, unlocked: do not rewrite or migrate it merely because
    # the new installer supports content-addressed filenames.
    $exact = New-CaseContext -Name "exact"
    [IO.File]::Copy($PinnedFontSource, $exact.LegacyFont, $false)
    $exactTimestamp = [DateTime]::SpecifyKind([DateTime]::Parse("2001-02-03T04:05:06"), [DateTimeKind]::Utc)
    [IO.File]::SetLastWriteTimeUtc($exact.LegacyFont, $exactTimestamp)
    Invoke-HostThemeCase -Context $exact
    if ((Get-Item -LiteralPath $exact.LegacyFont).LastWriteTimeUtc -ne $exactTimestamp -or
        (Test-Path -LiteralPath $exact.ContentFont) -or
        (Get-RegisteredFontPath -Context $exact) -ne $exact.LegacyFont) {
        throw "Exact installed font was unnecessarily rewritten or relocated."
    }

    # Exact legacy file, locked against writes: hashing and host reconciliation
    # must succeed without any replacement attempt.
    $locked = New-CaseContext -Name "locked"
    [IO.File]::Copy($PinnedFontSource, $locked.LegacyFont, $false)
    $lockedTimestamp = [DateTime]::SpecifyKind([DateTime]::Parse("2002-03-04T05:06:07"), [DateTimeKind]::Utc)
    [IO.File]::SetLastWriteTimeUtc($locked.LegacyFont, $lockedTimestamp)
    $lockedHandle = [IO.File]::Open($locked.LegacyFont, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Invoke-HostThemeCase -Context $locked
    } finally {
        $lockedHandle.Dispose()
    }
    if ((Get-Item -LiteralPath $locked.LegacyFont).LastWriteTimeUtc -ne $lockedTimestamp -or
        (Test-Path -LiteralPath $locked.ContentFont) -or
        (Get-RegisteredFontPath -Context $locked) -ne $locked.LegacyFont) {
        throw "Locked exact font was rewritten instead of being treated as satisfied."
    }

    # A different locked legacy file is preserved. Verified new bytes install
    # beside it and only the owned registry value advances to the new file.
    $upgrade = New-CaseContext -Name "upgrade"
    [IO.File]::WriteAllText($upgrade.LegacyFont, "older reviewed font bytes", [Text.UTF8Encoding]::new($false))
    $oldChecksum = (Get-FileHash -LiteralPath $upgrade.LegacyFont -Algorithm SHA256).Hash
    $upgradeHandle = [IO.File]::Open($upgrade.LegacyFont, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        Invoke-HostThemeCase -Context $upgrade
    } finally {
        $upgradeHandle.Dispose()
    }
    if ((Get-FileHash -LiteralPath $upgrade.LegacyFont -Algorithm SHA256).Hash -ne $oldChecksum -or
        -not (Test-Path -LiteralPath $upgrade.ContentFont -PathType Leaf) -or
        (Get-RegisteredFontPath -Context $upgrade) -ne $upgrade.ContentFont) {
        throw "Safe font upgrade overwrote the legacy file or failed to select verified side-by-side bytes."
    }

    # A stale registry value is repaired without touching exact legacy bytes.
    $stale = New-CaseContext -Name "stale"
    [IO.File]::Copy($PinnedFontSource, $stale.LegacyFont, $false)
    $staleTimestamp = [DateTime]::SpecifyKind([DateTime]::Parse("2003-04-05T06:07:08"), [DateTimeKind]::Utc)
    [IO.File]::SetLastWriteTimeUtc($stale.LegacyFont, $staleTimestamp)
    New-Item -Path $stale.RegistryPath -Force | Out-Null
    New-ItemProperty -Path $stale.RegistryPath -Name $FontRegistryName `
        -Value (Join-Path $stale.Root "stale.ttf") -PropertyType String -Force | Out-Null
    Invoke-HostThemeCase -Context $stale
    if ((Get-Item -LiteralPath $stale.LegacyFont).LastWriteTimeUtc -ne $staleTimestamp -or
        (Get-RegisteredFontPath -Context $stale) -ne $stale.LegacyFont) {
        throw "Registry reconciliation rewrote an exact installed font."
    }

    # Repetition keeps one content file, one owned registry value, and one
    # profile/scheme without replacing verified installed bytes.
    $repeat = New-CaseContext -Name "repeat"
    Invoke-HostThemeCase -Context $repeat
    $repeatTimestamp = (Get-Item -LiteralPath $repeat.ContentFont).LastWriteTimeUtc
    Invoke-HostThemeCase -Context $repeat
    $ownedValues = @((Get-ItemProperty -LiteralPath $repeat.RegistryPath).PSObject.Properties |
        Where-Object { $_.Name -eq $FontRegistryName })
    $repeatCurrentTimestamp = (Get-Item -LiteralPath $repeat.ContentFont).LastWriteTimeUtc
    $ownedValueCount = @($ownedValues).Count
    $installedContentCount = @(Get-ChildItem -LiteralPath $repeat.FontDirectory `
        -Filter "$FontStem-*.ttf" -File).Count
    if ($repeatCurrentTimestamp -ne $repeatTimestamp -or
        $ownedValueCount -ne 1 -or $installedContentCount -ne 1) {
        throw "Repeated host-theme application was not idempotent: timestamp=$repeatCurrentTimestamp/$repeatTimestamp registry=$ownedValueCount files=$installedContentCount"
    }
    Assert-FragmentContract -Context $repeat
    Assert-NoOwnedTemporaryDirectories -Context $repeat

    # A mismatched file occupying the exact content-addressed destination is
    # ambiguous and must never be overwritten, even when locked.
    $collision = New-CaseContext -Name "collision"
    [IO.File]::WriteAllText($collision.ContentFont, "unexpected occupant", [Text.UTF8Encoding]::new($false))
    $collisionChecksum = (Get-FileHash -LiteralPath $collision.ContentFont -Algorithm SHA256).Hash
    $collisionHandle = [IO.File]::Open($collision.ContentFont, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $collisionFailed = $false
    try {
        try {
            Invoke-HostThemeCase -Context $collision
        } catch {
            $collisionFailed = $_.Exception.Message -like "*Refusing to overwrite a mismatched content-addressed*"
        }
    } finally {
        $collisionHandle.Dispose()
    }
    if (-not $collisionFailed -or
        (Get-FileHash -LiteralPath $collision.ContentFont -Algorithm SHA256).Hash -ne $collisionChecksum) {
        throw "Mismatched content-addressed font was not preserved fail-closed."
    }

    # Failed checksum verification cleans only its unique marker-owned staging
    # directory and creates no installed font or registry value.
    $checksumFailure = New-CaseContext -Name "checksum-failure"
    $wrongSource = Join-Path $checksumFailure.Root "wrong.ttf"
    [IO.File]::WriteAllText($wrongSource, "wrong font bytes", [Text.UTF8Encoding]::new($false))
    $checksumFailed = $false
    try {
        Invoke-HostThemeCase -Context $checksumFailure -SourcePath $wrongSource
    } catch {
        $checksumFailed = $_.Exception.Message -like "*checksum verification failed*"
    }
    if (-not $checksumFailed -or (Test-Path -LiteralPath $checksumFailure.ContentFont)) {
        throw "Checksum failure did not stop before font installation."
    }
    Assert-NoOwnedTemporaryDirectories -Context $checksumFailure

    # Reparse-point font directories are rejected before download or registry
    # mutation. Junctions are available without developer-mode symlink rights.
    $reparse = New-CaseContext -Name "reparse"
    $realFontDirectory = Join-Path $reparse.Root "real-fonts"
    Remove-Item -LiteralPath $reparse.FontDirectory -Force
    New-Item -ItemType Directory -Path $realFontDirectory | Out-Null
    New-Item -ItemType Junction -Path $reparse.FontDirectory -Target $realFontDirectory | Out-Null
    $reparseFailed = $false
    try {
        Invoke-HostThemeCase -Context $reparse
    } catch {
        $reparseFailed = $_.Exception.Message -like "*reparse-point directory*"
    }
    if (-not $reparseFailed -or (Test-Path -LiteralPath $reparse.RegistryPath)) {
        throw "Reparse-point installed destination was not rejected before registry mutation."
    }

    # Test-only path injection remains unavailable during normal execution.
    $guard = New-CaseContext -Name "guard"
    $env:J3W1ZSH_TEST_MODE = $null
    $guardFailed = $false
    try {
        Invoke-HostThemeCase -Context $guard
    } catch {
        $guardFailed = $_.Exception.Message -like "*accepted only in explicit test mode*"
    } finally {
        $env:J3W1ZSH_TEST_MODE = "1"
    }
    if (-not $guardFailed) {
        throw "Production execution accepted host-theme test path injection."
    }

    # Migration preserves the discovered GUID, deactivates only the bounded
    # former fragment, and still emits one lowercase profile and one scheme.
    $migration = New-CaseContext -Name "migration"
    $formerDirectory = Join-Path $migration.Fragments "BloodyWriter"
    $recovery = Join-Path $migration.Root "recovery"
    New-Item -ItemType Directory -Force -Path $formerDirectory, $recovery | Out-Null
    $oldGuid = "{12345678-1234-4567-89ab-1234567890ab}"
    $formerFragment = [ordered]@{ profiles = @([ordered]@{ guid = $oldGuid; name = "former profile" }) }
    [IO.File]::WriteAllText(
        (Join-Path $formerDirectory "bloody-writer.json"),
        ($formerFragment | ConvertTo-Json -Depth 6),
        [Text.UTF8Encoding]::new($false)
    )
    & $HostThemeScript -ThemePath $ThemePath -OutputRoot $migration.Fragments `
        -MigrationRecoveryPath $recovery -SkipFontInstall | Out-Null
    $migrationFragment = Get-Content -Raw -LiteralPath $migration.Fragment | ConvertFrom-Json
    if ($migrationFragment.profiles.Count -ne 1 -or
        $migrationFragment.profiles[0].guid -ne $oldGuid -or
        $migrationFragment.profiles[0].name -cne "j3w1zsh - arch wsl" -or
        $migrationFragment.schemes.Count -ne 1 -or
        $migrationFragment.schemes[0].name -cne "j3w1zsh") {
        throw "Stable GUID, lowercase profile, or unique scheme verification failed."
    }
    if (Test-Path -LiteralPath (Join-Path $formerDirectory "bloody-writer.json")) {
        throw "Former host fragment remained active after migration fixture."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $recovery "windows-terminal-former-fragment.json") -PathType Leaf)) {
        throw "Former host fragment was not preserved in recovery."
    }
} finally {
    foreach ($registryPath in $RegistryPaths) {
        if (Test-Path -LiteralPath $registryPath) {
            Remove-Item -LiteralPath $registryPath -Recurse -Force
        }
    }
    if ($null -eq $OriginalTestMode) {
        $env:J3W1ZSH_TEST_MODE = $null
    } else {
        $env:J3W1ZSH_TEST_MODE = $OriginalTestMode
    }
    if (Test-Path -LiteralPath $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}

Write-Host "PowerShell parsing, locked-font idempotency, side-by-side upgrades, guarded staging, registry, GUID, profile, and recovery tests passed."
