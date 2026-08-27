Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Exit-JarjarArgumentRejected {
    param([string]$Name)

    [System.Console]::Error.WriteLine("GATE_ARGUMENT_REJECTED name=" + $Name)
    exit 2
}

function Assert-JarjarArtifactPathSafe {
    param(
        [string]$Path,
        [string]$RepositoryRoot
    )

    $repositoryFull = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $artifactsFull = [System.IO.Path]::GetFullPath((Join-Path $repositoryFull "artifacts"))
    $targetFull = [System.IO.Path]::GetFullPath($Path)
    $artifactsPrefix = $artifactsFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not [string]::Equals($targetFull, $artifactsFull, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $targetFull.StartsWith($artifactsPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must be inside the repository artifacts directory."
    }

    $repositoryItem = Get-Item -LiteralPath $repositoryFull -Force -ErrorAction Stop
    if (($repositoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Repository root must not be a reparse point."
    }

    $repositoryPrefix = $repositoryFull + [System.IO.Path]::DirectorySeparatorChar
    $relativeTarget = $targetFull.Substring($repositoryPrefix.Length)
    $segments = @($relativeTarget -split '[\\/]')
    $current = $repositoryFull
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $current = Join-Path $current $segments[$index]
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            break
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ("Artifact path contains a reparse point: " + $current)
        }
        if ($index -lt ($segments.Count - 1) -and -not $item.PSIsContainer) {
            throw ("Artifact path segment is not a directory: " + $current)
        }
    }
    return $targetFull
}

$rawArguments = @($args)
$gateText = $null
$suiteValue = $null
for ($argumentIndex = 0; $argumentIndex -lt $rawArguments.Count; $argumentIndex++) {
    $option = $rawArguments[$argumentIndex]
    if ($option -isnot [string]) {
        Exit-JarjarArgumentRejected -Name "extra"
    }
    switch -CaseSensitive ([string]$option) {
        "-GateNumber" {
            if ($null -ne $gateText) {
                Exit-JarjarArgumentRejected -Name "GateNumber"
            }
            if (($argumentIndex + 1) -ge $rawArguments.Count -or
                $rawArguments[$argumentIndex + 1] -isnot [string] -or
                @("-GateNumber", "-Suite") -ccontains [string]$rawArguments[$argumentIndex + 1]) {
                Exit-JarjarArgumentRejected -Name "GateNumber"
            }
            $argumentIndex++
            $gateText = [string]$rawArguments[$argumentIndex]
        }
        "-Suite" {
            if ($null -ne $suiteValue) {
                Exit-JarjarArgumentRejected -Name "Suite"
            }
            if (($argumentIndex + 1) -ge $rawArguments.Count -or
                $rawArguments[$argumentIndex + 1] -isnot [string] -or
                @("-GateNumber", "-Suite") -ccontains [string]$rawArguments[$argumentIndex + 1]) {
                Exit-JarjarArgumentRejected -Name "Suite"
            }
            $argumentIndex++
            $suiteValue = [string]$rawArguments[$argumentIndex]
        }
        default {
            Exit-JarjarArgumentRejected -Name "unknown"
        }
    }
}
if ($null -eq $gateText -or $gateText -cnotmatch '^[1-6]$') {
    Exit-JarjarArgumentRejected -Name "GateNumber"
}
if ($null -eq $suiteValue -or @("unit", "scenario", "simulation", "all") -cnotcontains $suiteValue) {
    Exit-JarjarArgumentRejected -Name "Suite"
}
$gateValue = [int]$gateText

$repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot ("artifacts\gate-{0:D2}" -f $gateValue)))
$logPath = Join-Path $artifactRoot "tests.txt"
$settingsPath = [System.IO.Path]::GetFullPath((Join-Path $artifactRoot "test-user\runner\settings.cfg"))
$mainInvalidSettingsPath = [System.IO.Path]::GetFullPath((Join-Path $artifactRoot "test-user\main-invalid\settings.cfg"))
$appDataRoot = [Environment]::GetFolderPath("ApplicationData")
$realSettingsPath = if ([string]::IsNullOrWhiteSpace($appDataRoot)) { "" } else { [System.IO.Path]::GetFullPath((Join-Path $appDataRoot "ProjectJARJAR\settings.cfg")) }
$godotPath = ""
$processLogPath = Join-Path $PSScriptRoot "process_log.ps1"

function Get-JarjarSettingsSnapshot {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Length = [int64]0; Sha256 = ""; MtimeTicks = [int64]0 }
    }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return [pscustomobject]@{
        Exists = $true
        Length = [int64]$item.Length
        Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
        MtimeTicks = [int64]$item.LastWriteTimeUtc.Ticks
    }
}

function Assert-JarjarSettingsSnapshotEqual {
    param(
        [psobject]$Expected,
        [psobject]$Actual,
        [string]$Context
    )

    foreach ($field in @("Exists", "Length", "Sha256", "MtimeTicks")) {
        if ($Expected.$field -ne $Actual.$field) {
            throw ($Context + ": " + $field)
        }
    }
}

$gateFailure = $null
try {
    $pathGodotCommands = @(Get-Command -Name "godot.exe" -CommandType Application -All -ErrorAction SilentlyContinue)
    if ($pathGodotCommands.Count -eq 0) {
        throw "PATH does not contain a Standard godot.exe application."
    }
    $firstPathGodotSource = [string]$pathGodotCommands[0].Source
    if ([string]::IsNullOrWhiteSpace($firstPathGodotSource)) {
        throw "The first PATH godot.exe application has no filesystem source."
    }
    $expectedGodotPath = (Resolve-Path -LiteralPath $firstPathGodotSource -ErrorAction Stop).Path
    $expectedGodotName = [System.IO.Path]::GetFileName($expectedGodotPath)
    if (-not [string]::Equals($expectedGodotName, "godot.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($expectedGodotName, "godot-mono.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $expectedGodotPath -PathType Leaf)) {
        throw "The first PATH Godot application must be Standard godot.exe, not godot-mono."
    }
    if ([string]::IsNullOrWhiteSpace($env:JARJAR_GODOT) -or -not [System.IO.Path]::IsPathRooted($env:JARJAR_GODOT)) {
        throw "JARJAR_GODOT must be the absolute first PATH godot.exe path."
    }
    $godotPath = (Resolve-Path -LiteralPath $env:JARJAR_GODOT -ErrorAction Stop).Path
    if (-not [string]::Equals($godotPath, $expectedGodotPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $godotPath -PathType Leaf)) {
        throw "JARJAR_GODOT does not match the first PATH Standard godot.exe application."
    }
    $godotVersionOutput = @(& $godotPath --version 2>&1)
    $godotVersionExitCode = $LASTEXITCODE
    $godotVersion = (($godotVersionOutput | ForEach-Object { [string]$_ }) -join [System.Environment]::NewLine).Trim()
    if ($godotVersionExitCode -ne 0 -or
        -not $godotVersion.StartsWith("4.7.2.stable.official", [System.StringComparison]::Ordinal)) {
        throw ("Godot version mismatch: " + $godotVersion)
    }
    if (-not (Test-Path -LiteralPath $processLogPath -PathType Leaf)) {
        throw "process_log.ps1 is missing."
    }
    if ([string]::IsNullOrWhiteSpace($appDataRoot) -or -not [System.IO.Path]::IsPathRooted($appDataRoot)) {
        throw "ApplicationData root is not an absolute path."
    }
    if ((Test-Path -LiteralPath $realSettingsPath) -and -not (Test-Path -LiteralPath $realSettingsPath -PathType Leaf)) {
        throw "Real settings path is not a file."
    }

    $null = Assert-JarjarArtifactPathSafe -Path $artifactRoot -RepositoryRoot $repositoryRoot
    New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
    $null = Assert-JarjarArtifactPathSafe -Path $artifactRoot -RepositoryRoot $repositoryRoot
    $null = Assert-JarjarArtifactPathSafe -Path $logPath -RepositoryRoot $repositoryRoot
    [System.IO.File]::WriteAllText($logPath, "", [System.Text.UTF8Encoding]::new($false))
    $null = Assert-JarjarArtifactPathSafe -Path $logPath -RepositoryRoot $repositoryRoot
    . $processLogPath

    $testUserRoot = [System.IO.Path]::GetFullPath((Join-Path $artifactRoot "test-user")) + [System.IO.Path]::DirectorySeparatorChar
    foreach ($isolatedPath in @($settingsPath, $mainInvalidSettingsPath)) {
        if (-not $isolatedPath.StartsWith($testUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Isolated settings path escaped test-user."
        }
        $null = Assert-JarjarArtifactPathSafe -Path $isolatedPath -RepositoryRoot $repositoryRoot
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $isolatedPath) | Out-Null
        $null = Assert-JarjarArtifactPathSafe -Path $isolatedPath -RepositoryRoot $repositoryRoot
        if (Test-Path -LiteralPath $isolatedPath -PathType Leaf) {
            $null = Assert-JarjarArtifactPathSafe -Path $isolatedPath -RepositoryRoot $repositoryRoot
            Remove-Item -LiteralPath $isolatedPath -Force -ErrorAction Stop
        } elseif (Test-Path -LiteralPath $isolatedPath) {
            throw "Isolated settings path is not a file."
        }
    }

    $realSettingsBefore = Get-JarjarSettingsSnapshot -Path $realSettingsPath
    $realSettingsBackup = ""
    if ($realSettingsBefore.Exists) {
        $backupRoot = Join-Path $artifactRoot ("real-settings-backup-" + [guid]::NewGuid().ToString("N"))
        $null = Assert-JarjarArtifactPathSafe -Path $backupRoot -RepositoryRoot $repositoryRoot
        New-Item -ItemType Directory -Path $backupRoot -ErrorAction Stop | Out-Null
        $null = Assert-JarjarArtifactPathSafe -Path $backupRoot -RepositoryRoot $repositoryRoot
        $realSettingsBackup = Join-Path $backupRoot "settings.cfg"
        $null = Assert-JarjarArtifactPathSafe -Path $realSettingsBackup -RepositoryRoot $repositoryRoot
        Copy-Item -LiteralPath $realSettingsPath -Destination $realSettingsBackup -ErrorAction Stop
        $null = Assert-JarjarArtifactPathSafe -Path $realSettingsBackup -RepositoryRoot $repositoryRoot
        $backupSnapshot = Get-JarjarSettingsSnapshot -Path $realSettingsBackup
        if (-not $backupSnapshot.Exists -or $backupSnapshot.Length -ne $realSettingsBefore.Length -or $backupSnapshot.Sha256 -ne $realSettingsBefore.Sha256) {
            throw "Real settings backup verification failed."
        }
    }

    try {
        Push-Location -LiteralPath $repositoryRoot
        try {
            $null = Invoke-JarjarLoggedProcess -LogPath $logPath -Label "import" -FilePath $godotPath -Arguments @("--headless", "--path", ".", "--import")
            $null = Invoke-JarjarLoggedProcess -LogPath $logPath -Label "tests" -FilePath $godotPath -Arguments @("--headless", "--path", ".", "--script", "res://tests/test_runner.gd", "--", "--suite", $suiteValue, ("--settings-path=" + $settingsPath))

            if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
                $null = Assert-JarjarArtifactPathSafe -Path $settingsPath -RepositoryRoot $repositoryRoot
                Remove-Item -LiteralPath $settingsPath -Force -ErrorAction Stop
            } elseif (Test-Path -LiteralPath $settingsPath) {
                throw "Runner settings path is not a file."
            }
            $null = Invoke-JarjarLoggedProcess -LogPath $logPath -Label "runner_invalid_missing_settings" -FilePath $godotPath -Arguments @("--headless", "--path", ".", "--script", "res://tests/test_runner.gd", "--", "--suite", "unit") -ExpectedExitCodes @(2)
            if (Test-Path -LiteralPath $settingsPath) {
                throw "Invalid runner created bootstrap settings."
            }
            $rejectCount = @((Get-Content -LiteralPath $logPath) | Where-Object { $_ -ceq "RUNNER_ARGUMENT_REJECTED name=missing" }).Count
            if ($rejectCount -ne 1) {
                throw ("Runner rejection marker count: " + $rejectCount)
            }

            if (Test-Path -LiteralPath $mainInvalidSettingsPath -PathType Leaf) {
                $null = Assert-JarjarArtifactPathSafe -Path $mainInvalidSettingsPath -RepositoryRoot $repositoryRoot
                Remove-Item -LiteralPath $mainInvalidSettingsPath -Force -ErrorAction Stop
            } elseif (Test-Path -LiteralPath $mainInvalidSettingsPath) {
                throw "Invalid main settings path is not a file."
            }
            $null = Invoke-JarjarLoggedProcess -LogPath $logPath -Label "main_invalid_settings_only" -FilePath $godotPath -Arguments @("--headless", "--path", ".", "--", ("--settings-path=" + $mainInvalidSettingsPath)) -ExpectedExitCodes @(2)
            if (Test-Path -LiteralPath $mainInvalidSettingsPath) {
                throw "Invalid main created settings."
            }
            $mainRejectCount = @((Get-Content -LiteralPath $logPath) | Where-Object { $_ -ceq "DEBUG_ARGUMENT_REJECTED name=--settings-path child_nodes=0 run_state=0" }).Count
            if ($mainRejectCount -ne 1) {
                throw ("Debug rejection marker count: " + $mainRejectCount)
            }

            $null = Invoke-JarjarLoggedProcess -LogPath $logPath -Label "editor_quit" -FilePath $godotPath -Arguments @("--headless", "--path", ".", "--editor", "--quit-after", "2")
        } finally {
            Pop-Location
        }

        $realSettingsAfter = Get-JarjarSettingsSnapshot -Path $realSettingsPath
        Assert-JarjarSettingsSnapshotEqual -Expected $realSettingsBefore -Actual $realSettingsAfter -Context "Real settings changed"
    } catch {
        $gateFailure = $_.Exception
    } finally {
        try {
            $current = Get-JarjarSettingsSnapshot -Path $realSettingsPath
            if ($realSettingsBefore.Exists) {
                $mustRestore = ($current.Exists -ne $true) -or ($current.Length -ne $realSettingsBefore.Length) -or ($current.Sha256 -ne $realSettingsBefore.Sha256) -or ($current.MtimeTicks -ne $realSettingsBefore.MtimeTicks)
                if ($mustRestore) {
                    if ((Test-Path -LiteralPath $realSettingsPath) -and -not (Test-Path -LiteralPath $realSettingsPath -PathType Leaf)) {
                        throw "Real settings path became a non-file; refusing destructive recovery."
                    }
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $realSettingsPath) | Out-Null
                    $null = Assert-JarjarArtifactPathSafe -Path $realSettingsBackup -RepositoryRoot $repositoryRoot
                    Copy-Item -LiteralPath $realSettingsBackup -Destination $realSettingsPath -Force -ErrorAction Stop
                    [System.IO.File]::SetLastWriteTimeUtc($realSettingsPath, [datetime]::new($realSettingsBefore.MtimeTicks, [System.DateTimeKind]::Utc))
                }
            } elseif ($current.Exists) {
                Remove-Item -LiteralPath $realSettingsPath -Force -ErrorAction Stop
            } elseif (Test-Path -LiteralPath $realSettingsPath) {
                throw "Real settings path became a non-file; refusing destructive recovery."
            }
            $restored = Get-JarjarSettingsSnapshot -Path $realSettingsPath
            Assert-JarjarSettingsSnapshotEqual -Expected $realSettingsBefore -Actual $restored -Context "Real settings restore failed"
        } catch {
            if ($null -eq $gateFailure) {
                $gateFailure = $_.Exception
            }
        }
    }
} catch {
    if ($null -eq $gateFailure) {
        $gateFailure = $_.Exception
    }
}

if ($null -ne $gateFailure) {
    [System.Console]::Error.WriteLine("Gate checks failed: " + $gateFailure.Message)
    exit 1
}
exit 0
