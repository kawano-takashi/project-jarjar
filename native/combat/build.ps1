$ErrorActionPreference = 'Stop'
$combatProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$combatBuild = Join-Path $combatProject 'build/combat-native'
$combatRuntime = Join-Path $PSScriptRoot 'runtime'
$combatRevision = 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'
$combatArchiveHash = '579AF30C5F62C1084EDB28216788188227D80A583F0114463699AC4EDD22140F'
$combatArchive = Join-Path $combatBuild 'godot-cpp.zip'
$combatSdk = Join-Path $combatBuild "sdk/godot-cpp-$combatRevision"
New-Item -ItemType Directory -Path $combatBuild -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $combatBuild '.gdignore'), '')
if (-not (Test-Path -LiteralPath $combatArchive)) {
    Invoke-WebRequest -Uri "https://codeload.github.com/godotengine/godot-cpp/zip/$combatRevision" -OutFile $combatArchive
}
if ((Get-FileHash -LiteralPath $combatArchive -Algorithm SHA256).Hash -ne $combatArchiveHash) {
    throw 'godot-cpp archive checksum mismatch'
}
if (-not (Test-Path -LiteralPath (Join-Path $combatSdk 'CMakeLists.txt'))) {
    Expand-Archive -LiteralPath $combatArchive -DestinationPath (Join-Path $combatBuild 'sdk')
}
cmake -S $PSScriptRoot -B $combatBuild -G 'Visual Studio 17 2022' -A x64 -T v143 '-DCMAKE_VS_GLOBALS=VCToolsVersion=14.40.33807' "-DCOMBAT_SDK_DIR=$combatSdk"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build $combatBuild --config Release --target jarjar_combat --parallel 4
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
New-Item -ItemType Directory -Path $combatRuntime -Force | Out-Null
$combatLibrary = Join-Path $combatBuild 'bin/jarjar_combat.dll'
$combatLibraryHash = (Get-FileHash -LiteralPath $combatLibrary -Algorithm SHA256).Hash.Substring(0, 16).ToLowerInvariant()
$combatLibraryName = "jarjar_combat-$combatLibraryHash.dll"
if (-not (Test-Path -LiteralPath (Join-Path $combatRuntime $combatLibraryName))) {
    Copy-Item -LiteralPath $combatLibrary -Destination (Join-Path $combatRuntime $combatLibraryName)
}
Copy-Item -LiteralPath (Join-Path $combatSdk 'LICENSE.md') -Destination (Join-Path $combatRuntime 'LICENSE.txt')
$combatExtension = @"
[configuration]
entry_symbol = "jarjar_combat_init"
compatibility_minimum = "4.5"
reloadable = false
[libraries]
windows.x86_64 = "$combatLibraryName"
"@
[IO.File]::WriteAllText(
    (Join-Path $combatRuntime 'jarjar_combat.gdextension'),
    $combatExtension + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)
Write-Output 'COMBAT_NATIVE_BUILD_OK'
