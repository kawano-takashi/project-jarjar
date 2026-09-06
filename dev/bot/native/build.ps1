$ErrorActionPreference = 'Stop'
$botProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$botBuild = Join-Path $botProject 'build/bot-native'
$botRevision = 'e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77'
$botArchiveHash = '579AF30C5F62C1084EDB28216788188227D80A583F0114463699AC4EDD22140F'
$botArchive = Join-Path $botBuild 'godot-cpp.zip'
$botSdk = Join-Path $botBuild "sdk/godot-cpp-$botRevision"
$botToolset = 'v143'
New-Item -ItemType Directory -Path $botBuild -Force | Out-Null
Set-Content -LiteralPath (Join-Path $botBuild '.gdignore') -Value ''
if (-not (Test-Path -LiteralPath $botArchive)) {
    Invoke-WebRequest -Uri "https://codeload.github.com/godotengine/godot-cpp/zip/$botRevision" -OutFile $botArchive
}
if ((Get-FileHash -LiteralPath $botArchive -Algorithm SHA256).Hash -ne $botArchiveHash) {
    throw 'godot-cpp archive checksum mismatch'
}
if (-not (Test-Path -LiteralPath (Join-Path $botSdk 'CMakeLists.txt'))) {
    Expand-Archive -LiteralPath $botArchive -DestinationPath (Join-Path $botBuild 'sdk')
}
$botConfigure = @('-S', $PSScriptRoot, '-B', $botBuild, '-G', 'Visual Studio 17 2022', '-A', 'x64', '-T', $botToolset, '-DCMAKE_VS_GLOBALS=VCToolsVersion=14.40.33807', "-DBOT_SDK_DIR=$botSdk")
$botCache = Join-Path $botBuild 'CMakeCache.txt'
if ((Test-Path -LiteralPath $botCache) -and ((Get-Content -LiteralPath $botCache) -notcontains "CMAKE_GENERATOR_TOOLSET:INTERNAL=$botToolset")) {
    $botConfigure += '--fresh'
}
cmake @botConfigure
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build $botBuild --config Release --target jarjar_bot --parallel 4
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$botLibraryHash = (Get-FileHash -LiteralPath (Join-Path $botBuild 'bin/jarjar_bot.dll') -Algorithm SHA256).Hash.Substring(0, 16).ToLowerInvariant()
$botLibraryName = "jarjar_bot-$botLibraryHash.dll"
$botRuntime = Join-Path $botBuild 'runtime'
New-Item -ItemType Directory -Path $botRuntime -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $botRuntime $botLibraryName))) {
    Copy-Item -LiteralPath (Join-Path $botBuild 'bin/jarjar_bot.dll') -Destination (Join-Path $botRuntime $botLibraryName)
}
@"
[configuration]
entry_symbol = "jarjar_bot_init"
compatibility_minimum = "4.5"
reloadable = false
[libraries]
windows.x86_64 = "runtime/$botLibraryName"
"@ | Set-Content -LiteralPath (Join-Path $botBuild 'jarjar_bot.gdextension') -Encoding utf8
Write-Output 'BOT_NATIVE_BUILD_OK'
