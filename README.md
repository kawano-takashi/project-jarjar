# Project JARJAR

Godot 4.7.2-stable で開発する、見下ろし型3DローグライトのMVPです。

## Gate 1

工程1では、PATH上のStandard Godot 4.7.2、固定Export Templates、プロジェクト設定、SettingsStore、起動引数の安全な検証、タイトル画面、独自テストrunner、Windows Debug exportを固定しています。ゲーム本編のenumとドメインモデルは工程2以降で実装します。

```powershell
$env:JARJAR_GODOT = (Resolve-Path -LiteralPath (Get-Command godot.exe -CommandType Application -ErrorAction Stop).Source).Path
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\tests\run_gate_checks.ps1' -GateNumber 1 -Suite all
```
