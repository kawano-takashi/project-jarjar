Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Exit-JarjarWrapperArgumentRejected {
    param([string]$Name)

    [System.Console]::Error.WriteLine("CLEAN_SETTINGS_ARGUMENT_REJECTED name=" + $Name)
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

function Add-JarjarFlattenedRawValue {
    param(
        [AllowNull()][object]$Value,
        [System.Collections.Generic.List[object]]$Target
    )

    if ($Value -is [array]) {
        foreach ($innerValue in $Value) {
            Add-JarjarFlattenedRawValue -Value $innerValue -Target $Target
        }
        return
    }
    $Target.Add($Value)
}

$knownOptions = @("-Executable", "-Arguments", "-Label", "-ExpectedExitCodes", "-WorkingDirectory")
$seenOptions = @{}
$rawArguments = @($args)
$executableValue = $null
$argumentValues = [System.Collections.Generic.List[string]]::new()
$labelValue = $null
$expectedExitCodeValues = [System.Collections.Generic.List[int]]::new()
$workingDirectoryValue = $null
$expectedExitCodesProvided = $false

for ($argumentIndex = 0; $argumentIndex -lt $rawArguments.Count; $argumentIndex++) {
    if ($rawArguments[$argumentIndex] -isnot [string]) {
        Exit-JarjarWrapperArgumentRejected -Name "unknown"
    }
    $option = [string]$rawArguments[$argumentIndex]
    if ($knownOptions -cnotcontains $option) {
        Exit-JarjarWrapperArgumentRejected -Name "unknown"
    }
    if ($seenOptions.ContainsKey($option)) {
        Exit-JarjarWrapperArgumentRejected -Name $option.TrimStart('-')
    }
    $seenOptions[$option] = $true

    $collected = [System.Collections.Generic.List[object]]::new()
    while (($argumentIndex + 1) -lt $rawArguments.Count) {
        $nextRawValue = $rawArguments[$argumentIndex + 1]
        if ($nextRawValue -is [string] -and $knownOptions -ccontains [string]$nextRawValue) {
            break
        }
        $argumentIndex++
        Add-JarjarFlattenedRawValue -Value $rawArguments[$argumentIndex] -Target $collected
        if ($option -cne "-Arguments" -and $option -cne "-ExpectedExitCodes") {
            break
        }
    }

    switch -CaseSensitive ($option) {
        "-Executable" {
            if ($collected.Count -ne 1 -or $null -eq $collected[0]) {
                Exit-JarjarWrapperArgumentRejected -Name "Executable"
            }
            $executableValue = [string]$collected[0]
        }
        "-Arguments" {
            foreach ($value in $collected) {
                if ($null -eq $value) {
                    Exit-JarjarWrapperArgumentRejected -Name "Arguments"
                }
                $argumentValues.Add([string]$value)
            }
        }
        "-Label" {
            if ($collected.Count -ne 1 -or $null -eq $collected[0]) {
                Exit-JarjarWrapperArgumentRejected -Name "Label"
            }
            $labelValue = [string]$collected[0]
        }
        "-ExpectedExitCodes" {
            if ($collected.Count -eq 0) {
                Exit-JarjarWrapperArgumentRejected -Name "ExpectedExitCodes"
            }
            $expectedExitCodesProvided = $true
            foreach ($value in $collected) {
                if ($null -eq $value) {
                    Exit-JarjarWrapperArgumentRejected -Name "ExpectedExitCodes"
                }
                $exitCodeText = [System.Convert]::ToString($value, [System.Globalization.CultureInfo]::InvariantCulture)
                $parsedExitCode = 0
                if ($exitCodeText -cnotmatch '^-?[0-9]+$' -or -not [int]::TryParse($exitCodeText, [ref]$parsedExitCode)) {
                    Exit-JarjarWrapperArgumentRejected -Name "ExpectedExitCodes"
                }
                $expectedExitCodeValues.Add($parsedExitCode)
            }
        }
        "-WorkingDirectory" {
            if ($collected.Count -ne 1 -or $null -eq $collected[0]) {
                Exit-JarjarWrapperArgumentRejected -Name "WorkingDirectory"
            }
            $workingDirectoryValue = [string]$collected[0]
        }
    }
}

foreach ($requiredOption in @("-Executable", "-Arguments", "-Label", "-WorkingDirectory")) {
    if (-not $seenOptions.ContainsKey($requiredOption)) {
        Exit-JarjarWrapperArgumentRejected -Name $requiredOption.TrimStart('-')
    }
}
if (-not $expectedExitCodesProvided) {
    $expectedExitCodeValues.Add(0)
}
if ($labelValue -cnotmatch '^[a-z0-9_-]+$') {
    Exit-JarjarWrapperArgumentRejected -Name "Label"
}

function Invoke-JarjarCleanSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [int[]]$ExpectedExitCodes = @(0),

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    try {
        $resolvedExecutable = (Resolve-Path -LiteralPath $Executable -ErrorAction Stop).Path
        $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory -ErrorAction Stop).Path
    } catch {
        Exit-JarjarWrapperArgumentRejected -Name "path"
    }
    if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf)) {
        Exit-JarjarWrapperArgumentRejected -Name "Executable"
    }
    if (-not (Test-Path -LiteralPath $resolvedWorkingDirectory -PathType Container)) {
        Exit-JarjarWrapperArgumentRejected -Name "WorkingDirectory"
    }

$repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "artifacts\gate-06"))
$logPath = Join-Path $artifactRoot "tests.txt"
$processLogPath = Join-Path $PSScriptRoot "process_log.ps1"
$appDataRoot = [Environment]::GetFolderPath("ApplicationData")
$userRoot = if ([string]::IsNullOrWhiteSpace($appDataRoot)) { "" } else { [System.IO.Path]::GetFullPath((Join-Path $appDataRoot "ProjectJARJAR")) }
$realSettingsPath = if ([string]::IsNullOrWhiteSpace($userRoot)) { "" } else { Join-Path $userRoot "settings.cfg" }
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Get-JarjarNonSettingsManifest {
    param(
        [string]$Root,
        [string]$ExcludedFile
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return [string[]]@()
    }

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($item in Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction Stop) {
        if ([string]::Equals($item.FullName, $ExcludedFile, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $relative = $item.FullName.Substring($rootFull.Length).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        $entries.Add($relative + "|" + $hash)
    }
    $result = $entries.ToArray()
    [System.Array]::Sort($result, [System.StringComparer]::Ordinal)
    return [string[]]$result
}

function Test-JarjarManifestEqual {
    param(
        [string[]]$Before,
        [string[]]$After
    )

    if ($Before.Count -ne $After.Count) {
        return $false
    }
    for ($index = 0; $index -lt $Before.Count; $index++) {
        if ($Before[$index] -cne $After[$index]) {
            return $false
        }
    }
    return $true
}

function Write-JarjarWrapperStatus {
    param([string]$Message)

    $null = Assert-JarjarArtifactPathSafe -Path $logPath -RepositoryRoot $repositoryRoot
    [System.IO.File]::AppendAllText($logPath, $Message + [System.Environment]::NewLine, $utf8)
    [System.Console]::Out.WriteLine($Message)
}

$wrapperFailure = $null
$originalSettingsExisted = $false
$originalSettingsSha = ""
$originalSettingsMtimeTicks = [int64]0
$settingsBackup = ""
$manifestBefore = $null
$settingsStateCaptured = $false

try {
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
    . $processLogPath

    $originalSettingsExisted = Test-Path -LiteralPath $realSettingsPath -PathType Leaf
    if ($originalSettingsExisted) {
        $originalItem = Get-Item -LiteralPath $realSettingsPath -ErrorAction Stop
        $originalSettingsMtimeTicks = [int64]$originalItem.LastWriteTimeUtc.Ticks
        $originalSettingsSha = (Get-FileHash -LiteralPath $realSettingsPath -Algorithm SHA256 -ErrorAction Stop).Hash
    }
    $settingsStateCaptured = $true
    if ($originalSettingsExisted) {
        $backupName = "user-settings-backup-{0}-{1}" -f ([datetime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)), [guid]::NewGuid().ToString("N")
        $backupRoot = Join-Path $artifactRoot $backupName
        $null = Assert-JarjarArtifactPathSafe -Path $backupRoot -RepositoryRoot $repositoryRoot
        New-Item -ItemType Directory -Path $backupRoot -ErrorAction Stop | Out-Null
        $null = Assert-JarjarArtifactPathSafe -Path $backupRoot -RepositoryRoot $repositoryRoot
        $settingsBackup = Join-Path $backupRoot "settings.cfg"
        $null = Assert-JarjarArtifactPathSafe -Path $settingsBackup -RepositoryRoot $repositoryRoot
        Copy-Item -LiteralPath $realSettingsPath -Destination $settingsBackup -ErrorAction Stop
        $null = Assert-JarjarArtifactPathSafe -Path $settingsBackup -RepositoryRoot $repositoryRoot
        $backupSha = (Get-FileHash -LiteralPath $settingsBackup -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($backupSha -ne $originalSettingsSha) {
            throw "Settings backup verification failed."
        }
        Remove-Item -LiteralPath $realSettingsPath -Force -ErrorAction Stop
    }

    $manifestBefore = @(Get-JarjarNonSettingsManifest -Root $userRoot -ExcludedFile $realSettingsPath)
    try {
        Push-Location -LiteralPath $resolvedWorkingDirectory
        try {
            $null = Invoke-JarjarLoggedProcess -LogPath $logPath -Label $Label -FilePath $resolvedExecutable -Arguments $Arguments -ExpectedExitCodes $ExpectedExitCodes
        } finally {
            Pop-Location
        }
    } catch {
        $wrapperFailure = $_.Exception
    }
} catch {
    $wrapperFailure = $_.Exception
} finally {
    if ($null -ne $manifestBefore) {
        try {
            $manifestAfter = @(Get-JarjarNonSettingsManifest -Root $userRoot -ExcludedFile $realSettingsPath)
            $manifestMatches = Test-JarjarManifestEqual -Before $manifestBefore -After $manifestAfter
            Write-JarjarWrapperStatus -Message ("@@ appdata_nonsettings before={0} after={1} match={2}" -f $manifestBefore.Count, $manifestAfter.Count, $manifestMatches.ToString().ToLowerInvariant())
            if (-not $manifestMatches -and $null -eq $wrapperFailure) {
                $wrapperFailure = [System.InvalidOperationException]::new("ProjectJARJAR non-settings manifest changed.")
            }
        } catch {
            if ($null -eq $wrapperFailure) {
                $wrapperFailure = $_.Exception
            }
        }
    }

    try {
        if ($settingsStateCaptured) {
            if ($originalSettingsExisted) {
                $currentIsFile = Test-Path -LiteralPath $realSettingsPath -PathType Leaf
                if ((Test-Path -LiteralPath $realSettingsPath) -and -not $currentIsFile) {
                    throw "Real settings path became a non-file; refusing destructive recovery."
                }
                $currentSha = if ($currentIsFile) { (Get-FileHash -LiteralPath $realSettingsPath -Algorithm SHA256 -ErrorAction Stop).Hash } else { "" }
                if (-not $currentIsFile -or $currentSha -ne $originalSettingsSha) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $realSettingsPath) | Out-Null
                    $null = Assert-JarjarArtifactPathSafe -Path $settingsBackup -RepositoryRoot $repositoryRoot
                    Copy-Item -LiteralPath $settingsBackup -Destination $realSettingsPath -Force -ErrorAction Stop
                }
                [System.IO.File]::SetLastWriteTimeUtc($realSettingsPath, [datetime]::new($originalSettingsMtimeTicks, [System.DateTimeKind]::Utc))
                $restoredSha = (Get-FileHash -LiteralPath $realSettingsPath -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($restoredSha -ne $originalSettingsSha) {
                    throw "Settings restore hash mismatch."
                }
            } else {
                if (Test-Path -LiteralPath $realSettingsPath -PathType Leaf) {
                    Remove-Item -LiteralPath $realSettingsPath -Force -ErrorAction Stop
                } elseif (Test-Path -LiteralPath $realSettingsPath) {
                    throw "Real settings path became a non-file; refusing destructive recovery."
                }
            }
        }
    } catch {
        if ($null -eq $wrapperFailure) {
            $wrapperFailure = $_.Exception
        }
    }
}

if ($null -ne $wrapperFailure) {
    [System.Console]::Error.WriteLine("Clean settings wrapper failed: " + $wrapperFailure.Message)
    exit 1
}
exit 0
}

Invoke-JarjarCleanSettings `
    -Executable $executableValue `
    -Arguments ([string[]]$argumentValues.ToArray()) `
    -Label $labelValue `
    -ExpectedExitCodes ([int[]]$expectedExitCodeValues.ToArray()) `
    -WorkingDirectory $workingDirectoryValue
