# Project JARJAR

Godot 4.7.2-stable Standard / GDScript / Compatibility renderer / Windows x86_64。

## Build & Test

```powershell
$env:JARJAR_GODOT = (Resolve-Path -LiteralPath (Get-Command godot.exe -CommandType Application -ErrorAction Stop).Source).Path
$jarjarVersion = ((& $env:JARJAR_GODOT --version 2>&1) -join "`n").Trim()
if (-not $jarjarVersion.StartsWith("4.7.2.stable.official")) { throw "Godot 4.7.2-stable Standard is required." }

# GDScriptのPython構文混入検査
python.exe .\.codex\skills\godot-gdscript-guard\scripts\gdscript_guard.py --project .

# 全回帰テスト（期待値: TEST_SUMMARY passed=105 failed=0）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run_gate_checks.ps1 -GateNumber 6 -Suite all

# Windows Release export。ユーザー最終調整完了後だけ正式buildとして実行する。
New-Item -ItemType Directory -Force -Path .\build\windows | Out-Null
& $env:JARJAR_GODOT --headless --path . --export-release "Windows Desktop" .\build\windows\ProjectJARJAR.exe
```

## Workflow

- 作業前に `docs/project-status.md` を読む。そこだけを現在フェーズの正とする。
- 正式playtest対象が未固定なら、`docs/playtest-protocol.md`を実施・集計しない。
- ユーザー最終調整後は、全回帰、GDScript検査、性能試験、Release export、pack audit、smoke、手動QA、新identity固定の順で完了させてから5人×3runへ進む。
- EXE、PCK、`balance_revision`、候補HEADのいずれかが変わったら、旧playtestデータを流用しない。
- 人間の参加・回答・計測値を生成または補完しない。

## Constraints

- 承認済みのbalance、確率、score係数、受入閾値を、ユーザーの明示承認なしに変更しない。
- QAとplaytestは `tests/run_gate_checks.ps1` または `tests/run_with_clean_settings.ps1` を使い、実ユーザー設定を汚さない。
- `tests/`、`src/debug/`、`scenes/debug/`、`src/release/` は最終調整後の検証用であり、5人×3run完了までは未使用扱いで削除しない。
- GDScriptを変更する前に `.codex/skills/godot-gdscript-guard/SKILL.md` を読み、Python構文を持ち込まない。
- `build/`、`artifacts/`、`.godot/`、`.codex/`、`work/` をコミットしない。
- fetch、pull、push、rebase、amend、tag作成は、ユーザーの明示指示なしに実行しない。

## Export Templates

- ScoopのGodotはself-contained構成とし、`C:\Users\konop\scoop\apps\godot\current\._sc_` を維持する。
- `export_presets.cfg` の `custom_template/debug` と `custom_template/release` は空に保ち、Godotの標準探索で `C:\Users\konop\scoop\apps\godot\current\editor_data\export_templates\4.7.2.stable\` を使う。
- repo内に `tools/` やExport Templatesを再作成しない。
- 対象4ファイルのSHA-256を使用前に照合する。他platform用templateの同居は許可する。
  - `windows_debug_x86_64_console.exe`: `5514C7645EE897A01F540D3CF22EDE5BADF92394521A08BFAB66A54D7369E6E6`
  - `windows_debug_x86_64.exe`: `51498B72B3A237F882EBD7D1787F06A4BC1EAF0572DAAB93837ADCFD3CFDC107`
  - `windows_release_x86_64_console.exe`: `52BDCAE9068E8D23B840E5C63B0C1798FFE2CB66144E5C4BC7AF11FB8C8600DF`
  - `windows_release_x86_64.exe`: `D34D36F3BE1A6C49C56525AE86469B92E4F417DDF0B43CF00DD80C385C4B0562`
