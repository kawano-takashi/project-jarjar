function Invoke-JarjarLoggedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,

        [int[]]$ExpectedExitCodes = @(0)
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    function ConvertTo-JarjarWindowsArgument {
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

    function ConvertTo-JarjarRawLines {
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

    if ($Label -cnotmatch '^[a-z0-9_-]+$') {
        throw "Invalid process label."
    }
    if ($null -eq $ExpectedExitCodes -or $ExpectedExitCodes.Count -eq 0) {
        throw "ExpectedExitCodes must contain at least one value."
    }

    $resolvedFile = (Resolve-Path -LiteralPath $FilePath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedFile -PathType Leaf)) {
        throw "FilePath must resolve to an existing file."
    }

    $repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    $artifactsRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "artifacts"))
    $resolvedLog = Assert-JarjarArtifactPathSafe -Path $LogPath -RepositoryRoot $repositoryRoot
    $artifactsPrefix = $artifactsRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedLog.StartsWith($artifactsPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "LogPath must be inside the repository artifacts directory."
    }

    $relativeLog = $resolvedLog.Substring($artifactsPrefix.Length).Replace('/', '\')
    if ($relativeLog -cnotmatch '^gate-[0-9]{2}\\.+') {
        throw "LogPath must be inside artifacts/gate-NN."
    }
    $logDirectory = Split-Path -Parent $resolvedLog
    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        throw "LogPath parent directory must already exist."
    }

    $encodedArguments = @($Arguments | ForEach-Object { ConvertTo-JarjarWindowsArgument -Value $_ })
    $encodedFile = ConvertTo-JarjarWindowsArgument -Value $resolvedFile
    $commandLine = (@($encodedFile) + $encodedArguments) -join ' '

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $resolvedFile
    $startInfo.Arguments = $encodedArguments -join ' '
    $startInfo.WorkingDirectory = (Get-Location).Path
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Failed to start process."
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

    $logLines = [System.Collections.Generic.List[string]]::new()
    $logLines.Add("@@ label " + $Label)
    $logLines.Add("@@ command " + $commandLine)
    $logLines.Add("@@ stdout begin")
    foreach ($line in @(ConvertTo-JarjarRawLines -Text $stdout)) {
        $logLines.Add($line)
    }
    $logLines.Add("@@ stdout end")
    $logLines.Add("@@ stderr begin")
    foreach ($line in @(ConvertTo-JarjarRawLines -Text $stderr)) {
        $logLines.Add($line)
    }
    $logLines.Add("@@ stderr end")
    $logLines.Add("@@ exit_code " + $exitCode)

    $serializedLog = ($logLines.ToArray() -join [System.Environment]::NewLine) + [System.Environment]::NewLine
    $null = Assert-JarjarArtifactPathSafe -Path $resolvedLog -RepositoryRoot $repositoryRoot
    [System.IO.File]::AppendAllText($resolvedLog, $serializedLog, $utf8)
    foreach ($line in $logLines) {
        [System.Console]::Out.WriteLine($line)
    }

    $failureMarkers = @(
        "SCRIPT ERROR",
        "PARSE ERROR",
        "ERROR:",
        "PUSH_ERROR",
        "ORPHAN NODE",
        "OBJECTDB INSTANCES LEAKED",
        "RESOURCE LEAK"
    )
    foreach ($marker in $failureMarkers) {
        if ($serializedLog.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw ("Process output contained failure marker: " + $marker)
        }
    }
    if ($exitCode -notin $ExpectedExitCodes) {
        throw ("Unexpected exit code {0}; expected one of: {1}" -f $exitCode, ($ExpectedExitCodes -join ", "))
    }

    return $exitCode
}
