[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Verify", "ManualQa", "Playtest")]
    [string]$Task,

    [string]$TesterId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "build\windows"))
$guiExecutable = Join-Path $buildRoot "ProjectJARJAR.exe"
$consoleExecutable = Join-Path $buildRoot "ProjectJARJAR.console.exe"
$pckPath = Join-Path $buildRoot "ProjectJARJAR.pck"
$releaseArtifactRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "artifacts\release-tests"))
$playtestArtifactRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "artifacts\playtest"))
$packManifestPath = Join-Path $releaseArtifactRoot "pack-manifest.txt"
$playtestTargetPath = Join-Path $playtestArtifactRoot "target.txt"
$utf8 = [System.Text.UTF8Encoding]::new($false)


function Assert-ArtifactPathSafe {
    param([Parameter(Mandatory = $true)][string]$Path)

    $repositoryFull = $repositoryRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $artifactsFull = [System.IO.Path]::GetFullPath((Join-Path $repositoryFull "artifacts"))
    $targetFull = [System.IO.Path]::GetFullPath($Path)
    $artifactsPrefix = $artifactsFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not [string]::Equals($targetFull, $artifactsFull, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $targetFull.StartsWith($artifactsPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must be inside the repository artifacts directory: $targetFull"
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
            throw "Artifact path contains a reparse point: $current"
        }
        if ($index -lt ($segments.Count - 1) -and -not $item.PSIsContainer) {
            throw "Artifact path segment is not a directory: $current"
        }
    }
    return $targetFull
}


function Initialize-ArtifactDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $safePath = Assert-ArtifactPathSafe -Path $Path
    if ((Test-Path -LiteralPath $safePath) -and -not (Test-Path -LiteralPath $safePath -PathType Container)) {
        throw "Artifact directory path is not a directory: $safePath"
    }
    New-Item -ItemType Directory -Force -Path $safePath | Out-Null
    [void](Assert-ArtifactPathSafe -Path $safePath)
}


function ConvertTo-WindowsArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashCount = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashCount * 2) + 1)))
            [void]$builder.Append('"')
        } else {
            if ($backslashCount -gt 0) {
                [void]$builder.Append(('\' * $backslashCount))
            }
            [void]$builder.Append($character)
        }
        $backslashCount = 0
    }
    if ($backslashCount -gt 0) {
        [void]$builder.Append(('\' * ($backslashCount * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}


function ConvertTo-RawLines {
    param([AllowEmptyString()][string]$Text)

    if ($Text.Length -eq 0) {
        return [string[]]@()
    }
    $lines = [System.Text.RegularExpressions.Regex]::Split($Text, "`r`n|`n|`r")
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
        if ($lines.Count -eq 1) {
            return [string[]]@()
        }
        return [string[]]$lines[0..($lines.Count - 2)]
    }
    return [string[]]$lines
}


function Invoke-LoggedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [int[]]$ExpectedExitCodes = @(0),
        [string[]]$RequiredMarkers = @(),
        [bool]$CreateNoWindow = $true
    )

    if ($Label -cnotmatch '^[a-z0-9_-]+$') {
        throw "Invalid process label: $Label"
    }
    $resolvedExecutable = (Resolve-Path -LiteralPath $Executable -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf)) {
        throw "Executable is not a file: $resolvedExecutable"
    }
    $resolvedLog = Assert-ArtifactPathSafe -Path $LogPath
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $resolvedLog) -PathType Container)) {
        throw "Log parent directory is missing: $resolvedLog"
    }

    $encodedArguments = @($Arguments | ForEach-Object { ConvertTo-WindowsArgument -Value $_ })
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $resolvedExecutable
    $startInfo.Arguments = $encodedArguments -join ' '
    $startInfo.WorkingDirectory = $repositoryRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $CreateNoWindow
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Failed to start process: $Label"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
    } finally {
        $process.Dispose()
    }

    $commandLine = (@(ConvertTo-WindowsArgument -Value $resolvedExecutable) + $encodedArguments) -join ' '
    $logLines = [System.Collections.Generic.List[string]]::new()
    $logLines.Add("@@ label $Label")
    $logLines.Add("@@ command $commandLine")
    $logLines.Add("@@ stdout begin")
    foreach ($line in @(ConvertTo-RawLines -Text $stdout)) {
        $logLines.Add($line)
    }
    $logLines.Add("@@ stdout end")
    $logLines.Add("@@ stderr begin")
    foreach ($line in @(ConvertTo-RawLines -Text $stderr)) {
        $logLines.Add($line)
    }
    $logLines.Add("@@ stderr end")
    $logLines.Add("@@ exit_code $exitCode")
    $serialized = ($logLines.ToArray() -join [System.Environment]::NewLine) + [System.Environment]::NewLine
    [void](Assert-ArtifactPathSafe -Path $resolvedLog)
    [System.IO.File]::AppendAllText($resolvedLog, $serialized, $utf8)
    foreach ($line in $logLines) {
        [System.Console]::Out.WriteLine($line)
    }

    foreach ($failureMarker in @(
        "SCRIPT ERROR",
        "PARSE ERROR",
        "ERROR:",
        "PUSH_ERROR",
        "ORPHAN NODE",
        "OBJECTDB INSTANCES LEAKED",
        "RESOURCE LEAK"
    )) {
        if ($serialized.IndexOf($failureMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Process output contained failure marker '$failureMarker': $Label"
        }
    }
    if ($exitCode -notin $ExpectedExitCodes) {
        throw "Unexpected exit code $exitCode for $Label; expected $($ExpectedExitCodes -join ', ')"
    }

    $combinedLines = @((ConvertTo-RawLines -Text $stdout) + (ConvertTo-RawLines -Text $stderr))
    foreach ($requiredMarker in $RequiredMarkers) {
        $markerCount = @($combinedLines | Where-Object { $_ -ceq $requiredMarker }).Count
        if ($markerCount -ne 1) {
            throw "Required marker count for '$requiredMarker' was $markerCount in $Label"
        }
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = $stdout
        Stderr = $stderr
        Lines = [string[]]$combinedLines
    }
}


function Get-SettingsSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; Length = [int64]0; Sha256 = ""; MtimeTicks = [int64]0 }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Settings path is not a file: $Path"
    }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return [pscustomobject]@{
        Exists = $true
        Length = [int64]$item.Length
        Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
        MtimeTicks = [int64]$item.LastWriteTimeUtc.Ticks
    }
}


function Assert-SettingsSnapshotEqual {
    param(
        [Parameter(Mandatory = $true)][psobject]$Expected,
        [Parameter(Mandatory = $true)][psobject]$Actual
    )

    foreach ($field in @("Exists", "Length", "Sha256", "MtimeTicks")) {
        if ($Expected.$field -ne $Actual.$field) {
            throw "User settings restoration mismatch: $field"
        }
    }
}


function Get-NonSettingsManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ExcludedFile
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return [string[]]@()
    }
    $rootPrefix = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($item in Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction Stop) {
        if ([string]::Equals($item.FullName, $ExcludedFile, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $relative = $item.FullName.Substring($rootPrefix.Length).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        $entries.Add("$relative|$($item.Length)|$hash")
    }
    $result = $entries.ToArray()
    [System.Array]::Sort($result, [System.StringComparer]::Ordinal)
    return [string[]]$result
}


function Assert-ManifestEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Before,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$After
    )

    if ($Before.Count -ne $After.Count) {
        throw "ProjectJARJAR non-settings AppData manifest count changed: $($Before.Count) -> $($After.Count)"
    }
    for ($index = 0; $index -lt $Before.Count; $index++) {
        if ($Before[$index] -cne $After[$index]) {
            throw "ProjectJARJAR non-settings AppData manifest changed at index $index"
        }
    }
}


function Invoke-WithCleanSettings {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactRoot,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Initialize-ArtifactDirectory -Path $ArtifactRoot
    $appDataRoot = [Environment]::GetFolderPath("ApplicationData")
    if ([string]::IsNullOrWhiteSpace($appDataRoot) -or -not [System.IO.Path]::IsPathRooted($appDataRoot)) {
        throw "ApplicationData root is not an absolute path."
    }
    $userRoot = [System.IO.Path]::GetFullPath((Join-Path $appDataRoot "ProjectJARJAR"))
    $settingsPath = Join-Path $userRoot "settings.cfg"
    $before = Get-SettingsSnapshot -Path $settingsPath
    $manifestBefore = @(Get-NonSettingsManifest -Root $userRoot -ExcludedFile $settingsPath)
    $backupDirectory = ""
    $backupPath = ""
    $failure = $null
    $restoreSucceeded = $false

    try {
        if ($before.Exists) {
            $backupDirectory = Join-Path $ArtifactRoot ("settings-backup-" + [guid]::NewGuid().ToString("N"))
            [void](Assert-ArtifactPathSafe -Path $backupDirectory)
            New-Item -ItemType Directory -Path $backupDirectory -ErrorAction Stop | Out-Null
            $backupPath = Join-Path $backupDirectory "settings.cfg"
            [void](Assert-ArtifactPathSafe -Path $backupPath)
            Copy-Item -LiteralPath $settingsPath -Destination $backupPath -ErrorAction Stop
            $backupSnapshot = Get-SettingsSnapshot -Path $backupPath
            if (-not $backupSnapshot.Exists -or $backupSnapshot.Length -ne $before.Length -or $backupSnapshot.Sha256 -cne $before.Sha256) {
                throw "User settings backup verification failed."
            }
            Remove-Item -LiteralPath $settingsPath -Force -ErrorAction Stop
        }
        & $Action
    } catch {
        $failure = $_.Exception
    } finally {
        try {
            $manifestAfter = @(Get-NonSettingsManifest -Root $userRoot -ExcludedFile $settingsPath)
            Assert-ManifestEqual -Before ([string[]]$manifestBefore) -After ([string[]]$manifestAfter)
            [System.Console]::Out.WriteLine("APPDATA_NONSETTINGS_OK files=$($manifestAfter.Count)")
        } catch {
            if ($null -eq $failure) {
                $failure = $_.Exception
            }
        }

        try {
            if ($before.Exists) {
                if ((Test-Path -LiteralPath $settingsPath) -and -not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
                    throw "User settings path became a non-file; backup retained at $backupPath"
                }
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null
                Copy-Item -LiteralPath $backupPath -Destination $settingsPath -Force -ErrorAction Stop
                [System.IO.File]::SetLastWriteTimeUtc(
                    $settingsPath,
                    [datetime]::new($before.MtimeTicks, [System.DateTimeKind]::Utc)
                )
            } else {
                if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
                    Remove-Item -LiteralPath $settingsPath -Force -ErrorAction Stop
                } elseif (Test-Path -LiteralPath $settingsPath) {
                    throw "User settings path became a non-file."
                }
            }
            Assert-SettingsSnapshotEqual -Expected $before -Actual (Get-SettingsSnapshot -Path $settingsPath)
            $restoreSucceeded = $true
            [System.Console]::Out.WriteLine("USER_SETTINGS_RESTORED exists=$($before.Exists.ToString().ToLowerInvariant())")
        } catch {
            if ($null -eq $failure) {
                $failure = $_.Exception
            }
        }

        if ($restoreSucceeded -and -not [string]::IsNullOrEmpty($backupPath)) {
            try {
                [void](Assert-ArtifactPathSafe -Path $backupPath)
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
                [void](Assert-ArtifactPathSafe -Path $backupDirectory)
                Remove-Item -LiteralPath $backupDirectory -Force -ErrorAction Stop
            } catch {
                if ($null -eq $failure) {
                    $failure = $_.Exception
                }
            }
        }
    }
    if ($null -ne $failure) {
        throw $failure
    }
}


function Assert-BuildArtifactsReady {
    foreach ($path in @($guiExecutable, $consoleExecutable, $pckPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Release artifact is missing. Export Windows Release first: $path"
        }
        if ((Get-Item -LiteralPath $path -ErrorAction Stop).Length -le 0) {
            throw "Release artifact is empty: $path"
        }
    }

    $inputFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($relativeFile in @("project.godot", "export_presets.cfg")) {
        $inputFiles.Add((Get-Item -LiteralPath (Join-Path $repositoryRoot $relativeFile) -ErrorAction Stop))
    }
    foreach ($relativeDirectory in @("src", "scenes", "data")) {
        foreach ($item in Get-ChildItem -LiteralPath (Join-Path $repositoryRoot $relativeDirectory) -File -Recurse -Force -ErrorAction Stop) {
            $inputFiles.Add($item)
        }
    }
    $newestInput = $inputFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    foreach ($path in @($guiExecutable, $consoleExecutable, $pckPath)) {
        $artifact = Get-Item -LiteralPath $path -ErrorAction Stop
        if ($artifact.LastWriteTimeUtc -lt $newestInput.LastWriteTimeUtc) {
            throw "Release artifact is stale: $($artifact.Name) is older than $($newestInput.FullName)"
        }
    }
}


function Get-CandidateHead {
    $headOutput = @(& git -C $repositoryRoot rev-parse HEAD 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve candidate HEAD: $($headOutput -join ' ')"
    }
    $head = (($headOutput | ForEach-Object { [string]$_ }) -join "").Trim().ToLowerInvariant()
    if ($head -cnotmatch '^[0-9a-f]{40}$') {
        throw "Candidate HEAD is not a 40-character SHA."
    }
    return $head
}


function Get-SourceBalanceRevision {
    $balancePath = Join-Path $repositoryRoot "data\balance\balance_manifest.tres"
    $contents = [System.IO.File]::ReadAllText($balancePath)
    $matches = [System.Text.RegularExpressions.Regex]::Matches(
        $contents,
        '(?m)^\s*balance_revision\s*=\s*([0-9]+)\s*$'
    )
    if ($matches.Count -ne 1) {
        throw "balance_revision must occur exactly once in balance_manifest.tres."
    }
    return [int]$matches[0].Groups[1].Value
}


function Get-BuildIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateHead,
        [Parameter(Mandatory = $true)][int]$BalanceRevision
    )

    return [pscustomobject]@{
        CandidateHead = $CandidateHead
        ExeSha256 = (Get-FileHash -LiteralPath $guiExecutable -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        ConsoleSha256 = (Get-FileHash -LiteralPath $consoleExecutable -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        PckSha256 = (Get-FileHash -LiteralPath $pckPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        BalanceRevision = $BalanceRevision
    }
}


function Write-BuildIdentity {
    param([Parameter(Mandatory = $true)][psobject]$Identity)

    [System.Console]::Out.WriteLine(
        "BUILD_IDENTITY candidate_head=$($Identity.CandidateHead) exe_sha256=$($Identity.ExeSha256) pck_sha256=$($Identity.PckSha256) balance_revision=$($Identity.BalanceRevision)"
    )
    [System.Console]::Out.WriteLine("BUILD_CONSOLE_SHA256 $($Identity.ConsoleSha256)")
}


function Invoke-PackAudit {
    param([Parameter(Mandatory = $true)][string]$LogPath)

    Initialize-ArtifactDirectory -Path $releaseArtifactRoot
    [void](Assert-ArtifactPathSafe -Path $packManifestPath)
    $result = Invoke-LoggedProcess `
        -LogPath $LogPath `
        -Label "pack_audit" `
        -Executable $consoleExecutable `
        -Arguments @("--headless", "--", "--release-pack-audit=$packManifestPath")
    if (-not (Test-Path -LiteralPath $packManifestPath -PathType Leaf)) {
        throw "Pack audit did not create its manifest."
    }
    $auditLines = @($result.Lines | Where-Object { $_ -cmatch '^PACK_AUDIT_OK paths=([0-9]+) required=2 forbidden=0 balance_revision=([0-9]+)$' })
    if ($auditLines.Count -ne 1) {
        throw "Pack audit success marker count was $($auditLines.Count)."
    }
    $match = [System.Text.RegularExpressions.Regex]::Match(
        $auditLines[0],
        '^PACK_AUDIT_OK paths=([0-9]+) required=2 forbidden=0 balance_revision=([0-9]+)$'
    )
    $manifestLines = @([System.IO.File]::ReadAllLines($packManifestPath) | Where-Object { -not [string]::IsNullOrEmpty($_) })
    if ($manifestLines.Count -ne [int]$match.Groups[1].Value) {
        throw "Pack manifest path count does not match the audit marker."
    }
    foreach ($requiredPath in @("res://scenes/main.tscn", "res://data/balance/balance_manifest.tres")) {
        if ($manifestLines -cnotcontains $requiredPath) {
            throw "Pack manifest is missing $requiredPath"
        }
    }
    foreach ($path in $manifestLines) {
        foreach ($prefix in @("res://tests/", "res://src/debug/", "res://scenes/debug/", "res://outputs/", "res://docs/")) {
            if ($path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Pack manifest contains forbidden path: $path"
            }
        }
    }
    return [int]$match.Groups[2].Value
}


function Assert-RepresentativeReleaseArgumentRejections {
    param([Parameter(Mandatory = $true)][string]$LogPath)

    [void](Invoke-LoggedProcess -LogPath $LogPath -Label "reject_debug_only" -Executable $consoleExecutable -Arguments @("--headless", "--", "--qa-scenario=weapon_bow") -ExpectedExitCodes @(2) -RequiredMarkers @("RELEASE_ARGUMENT_REJECTED name=--qa-scenario"))
    [void](Invoke-LoggedProcess -LogPath $LogPath -Label "reject_unknown" -Executable $consoleExecutable -Arguments @("--headless", "--", "--unknown-release-option") -ExpectedExitCodes @(2) -RequiredMarkers @("RELEASE_ARGUMENT_REJECTED name=--unknown-release-option"))
    [void](Invoke-LoggedProcess -LogPath $LogPath -Label "reject_duplicate" -Executable $consoleExecutable -Arguments @("--headless", "--", "--smoke-run", "--smoke-run") -ExpectedExitCodes @(2) -RequiredMarkers @("RELEASE_ARGUMENT_REJECTED name=--smoke-run"))
    [void](Invoke-LoggedProcess -LogPath $LogPath -Label "reject_invalid_combination" -Executable $consoleExecutable -Arguments @("--headless", "--", "--smoke-run", "--release-pack-audit=$packManifestPath") -ExpectedExitCodes @(2) -RequiredMarkers @("RELEASE_ARGUMENT_REJECTED name=--smoke-run"))
}


function Read-PlaytestTarget {
    if (-not (Test-Path -LiteralPath $playtestTargetPath -PathType Leaf)) {
        throw "Playtest target is missing. Create artifacts/playtest/target.txt after human QA."
    }
    $values = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($playtestTargetPath)) {
        $lineMatch = [System.Text.RegularExpressions.Regex]::Match(
            $line,
            '^([a-z0-9_]+)=([^\r\n]+)$'
        )
        if ([string]::IsNullOrWhiteSpace($line) -or -not $lineMatch.Success) {
            throw "Playtest target contains a malformed line."
        }
        $key = $lineMatch.Groups[1].Value
        $value = $lineMatch.Groups[2].Value
        if ($values.ContainsKey($key)) {
            throw "Playtest target contains duplicate key: $key"
        }
        $values[$key] = $value
    }
    $requiredKeys = @("candidate_head", "exe_sha256", "pck_sha256", "balance_revision")
    if ($values.Count -ne $requiredKeys.Count) {
        throw "Playtest target must contain exactly four keys."
    }
    foreach ($key in $requiredKeys) {
        if (-not $values.ContainsKey($key)) {
            throw "Playtest target is missing key: $key"
        }
    }
    if ([string]$values.candidate_head -cnotmatch '^[0-9a-f]{40}$') {
        throw "Playtest target candidate_head is invalid."
    }
    if ([string]$values.exe_sha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or [string]$values.pck_sha256 -cnotmatch '^[0-9a-fA-F]{64}$') {
        throw "Playtest target contains an invalid SHA-256."
    }
    $balanceRevision = 0
    if ([string]$values.balance_revision -cnotmatch '^[0-9]+$' -or -not [int]::TryParse([string]$values.balance_revision, [ref]$balanceRevision)) {
        throw "Playtest target balance_revision is invalid."
    }
    return [pscustomobject]@{
        CandidateHead = [string]$values.candidate_head
        ExeSha256 = ([string]$values.exe_sha256).ToLowerInvariant()
        PckSha256 = ([string]$values.pck_sha256).ToLowerInvariant()
        BalanceRevision = $balanceRevision
    }
}


function Assert-TargetMatchesIdentity {
    param(
        [Parameter(Mandatory = $true)][psobject]$TargetIdentity,
        [Parameter(Mandatory = $true)][psobject]$CurrentIdentity
    )

    foreach ($field in @("CandidateHead", "ExeSha256", "PckSha256", "BalanceRevision")) {
        if ($TargetIdentity.$field -cne $CurrentIdentity.$field) {
            throw "Playtest target does not match current build identity: $field"
        }
    }
}


$taskFailure = $null
try {
    if ($Task -ne "Playtest" -and -not [string]::IsNullOrEmpty($TesterId)) {
        throw "-TesterId is only valid with -Task Playtest."
    }
    if ($Task -eq "Playtest" -and $TesterId -cnotmatch '^T[0-9]{2}$') {
        throw "-TesterId is required for Playtest and must use T01-style format."
    }
    Assert-BuildArtifactsReady
    $candidateHead = Get-CandidateHead
    $sourceBalanceRevision = Get-SourceBalanceRevision

    switch ($Task) {
        "Verify" {
            Initialize-ArtifactDirectory -Path $releaseArtifactRoot
            $logPath = Join-Path $releaseArtifactRoot "verify.log"
            [void](Assert-ArtifactPathSafe -Path $logPath)
            [System.IO.File]::WriteAllText($logPath, "", $utf8)
            Invoke-WithCleanSettings -ArtifactRoot $releaseArtifactRoot -Action {
                $builtBalanceRevision = Invoke-PackAudit -LogPath $logPath
                if ($builtBalanceRevision -ne $sourceBalanceRevision) {
                    throw "Built balance revision $builtBalanceRevision does not match source revision $sourceBalanceRevision."
                }
                Assert-RepresentativeReleaseArgumentRejections -LogPath $logPath
                [void](Invoke-LoggedProcess -LogPath $logPath -Label "release_smoke" -Executable $consoleExecutable -Arguments @("--headless", "--", "--smoke-run") -RequiredMarkers @("RELEASE_SMOKE_OK seed=20260827 failures=2"))
            }
            $identity = Get-BuildIdentity -CandidateHead $candidateHead -BalanceRevision $sourceBalanceRevision
            Write-BuildIdentity -Identity $identity
            [System.Console]::Out.WriteLine("RELEASE_VERIFY_OK")
        }
        "ManualQa" {
            Initialize-ArtifactDirectory -Path $releaseArtifactRoot
            $logPath = Join-Path $releaseArtifactRoot "manual-qa.log"
            [void](Assert-ArtifactPathSafe -Path $logPath)
            [System.IO.File]::WriteAllText($logPath, "", $utf8)
            $identity = Get-BuildIdentity -CandidateHead $candidateHead -BalanceRevision $sourceBalanceRevision
            Write-BuildIdentity -Identity $identity
            Invoke-WithCleanSettings -ArtifactRoot $releaseArtifactRoot -Action {
                [void](Invoke-LoggedProcess -LogPath $logPath -Label "manual_qa" -Executable $consoleExecutable -Arguments @() -CreateNoWindow $false)
            }
            [System.Console]::Out.WriteLine("MANUAL_QA_SESSION_COMPLETED record_result=docs/final-qa.md")
        }
        "Playtest" {
            Initialize-ArtifactDirectory -Path $playtestArtifactRoot
            $targetIdentity = Read-PlaytestTarget
            $currentIdentity = Get-BuildIdentity -CandidateHead $candidateHead -BalanceRevision $sourceBalanceRevision
            Assert-TargetMatchesIdentity -TargetIdentity $targetIdentity -CurrentIdentity $currentIdentity
            $safeTesterId = $TesterId.ToLowerInvariant()
            $logPath = Join-Path $playtestArtifactRoot ("playtest-$safeTesterId.log")
            [void](Assert-ArtifactPathSafe -Path $logPath)
            [System.IO.File]::WriteAllText($logPath, "", $utf8)
            Write-BuildIdentity -Identity $currentIdentity
            Invoke-WithCleanSettings -ArtifactRoot $playtestArtifactRoot -Action {
                [void](Invoke-LoggedProcess -LogPath $logPath -Label ("playtest_" + $safeTesterId) -Executable $guiExecutable -Arguments @() -CreateNoWindow $false)
            }
            [System.Console]::Out.WriteLine("PLAYTEST_SESSION_COMPLETED tester_id=$TesterId")
        }
    }
} catch {
    $taskFailure = $_.Exception
}

if ($null -ne $taskFailure) {
    [System.Console]::Error.WriteLine("Release task failed: " + $taskFailure.Message)
    exit 1
}
exit 0
