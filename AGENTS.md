# Project JARJAR

Godot 4.7.2-stable Standard / GDScript / Compatibility renderer / Windows x86_64。

## Build & Test

```powershell
$env:JARJAR_GODOT = (Resolve-Path -LiteralPath (Get-Command godot.exe -CommandType Application -ErrorAction Stop).Source).Path
$jarjarVersion = ((& $env:JARJAR_GODOT --version 2>&1) -join "`n").Trim()
if (-not $jarjarVersion.StartsWith("4.7.2.stable.official")) { throw "Godot 4.7.2-stable Standard is required." }

# 通常のコード変更: GDScript全回帰と全.gd/.tscn/.tresのロード検査
& $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd

# ユーザーが最終調整完了を明示した後だけ、以下を上から実行する。
& $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd
& $env:JARJAR_GODOT --headless --path . -- --performance=full_hd_500_2000 --run-seed=5002000
New-Item -ItemType Directory -Force -Path .\build\windows | Out-Null
& $env:JARJAR_GODOT --headless --path . --export-release "Windows Desktop" .\build\windows\ProjectJARJAR.exe
.\tests\release.ps1 -Task Verify
.\tests\release.ps1 -Task ManualQa

# 手動QA合格後に対象identityを artifacts/playtest/target.txt へ手入力してから実施する。
.\tests\release.ps1 -Task Playtest -TesterId T01
```

## Workflow

- 作業前に `docs/project-status.md` を読む。そこだけを現在フェーズの正とする。
- バランス調整は、人間によるテストへ渡す直前に一度だけ実施する。仕様策定中は数値調整や自動calibrationを行わず、仕様と受入基準の確定に留める。その一度の調整で受入基準に届かない場合も反復調整せず、測定結果を報告して次の判断を待つ。
- `tests/test_runner.gd` は `tests/**/*_test.gd` を再帰検出する。`unit/`、`scenario/`、`simulation/` は整理用であり、登録簿も実行順契約もない。
- PowerShellテストは既存のWindows Release buildだけを検証する。コード変更だけならGDScriptテストを使い、buildまで検証するときだけ性能試験・export・`tests/release.ps1` を使う。
- `Verify` はpack audit、Release smoke、代表的なRelease引数拒否、build鮮度、identityを検証する。buildやsource testは実行しない。
- `ManualQa` のexit 0はセッション終了だけを表し、QA合格ではない。人間が `docs/final-qa.md` に判定を記録する。
- 正式playtest対象が未固定なら `docs/playtest-protocol.md` を実施・集計しない。
- 手動QA合格後、`Verify` が表示した4値を `artifacts/playtest/target.txt` に `candidate_head`、`exe_sha256`、`pck_sha256`、`balance_revision` として手入力する。自動固定しない。
- EXE、PCK、`balance_revision`、候補HEADのいずれかが変わったら旧playtestデータを流用しない。
- 人間の参加・回答・計測値を生成または補完しない。

## Constraints

- 承認済みのbalance値、確率、進化時刻、受入閾値を、ユーザーの明示承認なしに変更しない。
- QAとplaytestは `tests/release.ps1` を使い、実ユーザー設定を汚さない。
- `build/windows/ProjectJARJAR.exe`、`.console.exe`、`.pck`を手動で差し替えない。
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
