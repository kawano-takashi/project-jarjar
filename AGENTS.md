# Project JARJAR

Godot 4.7.2-stable Standard / GDScript / Compatibility renderer / Windows x86_64。

## Build & Test

```powershell
$env:JARJAR_GODOT = (Resolve-Path -LiteralPath (Get-Command godot.exe -CommandType Application -ErrorAction Stop).Source).Path
$jarjarVersion = ((& $env:JARJAR_GODOT --version 2>&1) -join "`n").Trim()
if (-not $jarjarVersion.StartsWith("4.7.2.stable.official")) { throw "Godot 4.7.2-stable Standard is required." }

# 通常のコード変更: GDScript全回帰と全.gd/.tscn/.tresのロード検査
& $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd

# 任意: 論理テスト名の完全一致で1件だけ実行する（preflightと全テスト発見は維持する）
$env:JARJAR_TEST_FILTER = "performance_fixture_contract"
try { & $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd } finally { Remove-Item Env:JARJAR_TEST_FILTER -ErrorAction SilentlyContinue }

# 任意: 各テストと成功したASSERTも含む詳細を画面に表示する
$env:JARJAR_TEST_VERBOSE = "1"
try { & $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd } finally { Remove-Item Env:JARJAR_TEST_VERBOSE -ErrorAction SilentlyContinue }

# ユーザーが最終調整完了を明示した後だけ、以下を上から実行する。
& $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd
New-Item -ItemType Directory -Force -Path .\build\windows | Out-Null
& $env:JARJAR_GODOT --headless --path . --export-release "Windows Desktop" .\build\windows\ProjectJARJAR.exe
```

## Workflow

- 人間による成功基準は、5人以上×各3runの全回答の70%以上が「また遊びたい」と答えることとする。人間による評価へ進む前に、会話内でユーザーが最終調整完了を明示していることを確認する。
- 実装仕様はコードとテストを正とし、進捗や変更履歴の別文書を維持しない。
- バランス調整は、人間によるテストへ渡す直前に一度だけ実施する。仕様策定中は数値調整や自動calibrationを行わず、仕様の確定に留める。調整後も成功を確認できない場合は反復調整せず、測定結果や本人の感想を報告して次の判断を待つ。自動難易度測定は調整の参考資料とし、プレイ開始や成功判定の必須条件にしない。
- `tests/test_runner.gd` は `tests/**/*_test.gd` を再帰検出する。`unit/`、`scenario/`、`simulation/` は整理用であり、登録簿も実行順契約もない。
- テスト・性能試験・難易度測定は結果を標準出力へ返し、自動ログ・CSV・検証一覧をファイルへ保存しない。エージェントも実行結果をファイルへリダイレクトしない。
- 通常テストは集計と失敗したASSERTだけを表示する。詳しく調べる場合は `JARJAR_TEST_FILTER` で対象を絞り、`JARJAR_TEST_VERBOSE=1` を使う。性能試験・難易度測定の詳細表示も同じ環境変数を使う。
- GDScriptテスト用設定は実行ごとにOSの一時ディレクトリへ作成し、終了時に削除する。
- 自動検証はGDScriptテスト、配布物の生成はGodot標準exportを使う。性能試験・難易度測定は必要な場合の参考測定とし、exportの必須手順にしない。
- 回答・感想はユーザーから会話で受け取り、専用の試遊コマンド・記録文書・参加者ID管理を維持しない。
- EXE、PCK、候補HEADが異なる対象の回答を混ぜて成功判定しない。
- 人間の参加・回答・計測値を生成または補完しない。

## Constraints

- 承認済みのbalance値、確率、進化時刻、受入閾値を、ユーザーの明示承認なしに変更しない。
- 自動テストは実ユーザー設定を書き換えない。
- `build/windows/ProjectJARJAR.exe`、`.console.exe`、`.pck`を手動で差し替えない。
- GDScriptを変更する前に `.codex/skills/godot-gdscript-guard/SKILL.md` を読み、Python構文を持ち込まない。
- `build/`、`artifacts/`、`.godot/`、`.codex/`、`work/` をコミットしない。
- fetch、pull、push、rebase、amend、tag作成は、ユーザーの明示指示なしに実行しない。

## Balance

- 調整値の正本は `data/balance/` の `.tres` とし、`survival_content_manifest.tres` を唯一の読み込み入口にする。コードに本番値や代替の既定値を持たせない。
- 数値調整の依頼では、指定されたデータと項目だけを変更する。現在値との一致を要求する検証を追加しない。
- 計算式・公開項目の追加・データ形式の変更は、数値調整とは別の構造変更として扱う。
- 定義Resourceを実行状態の保存先にしない。変更するテスト入力は外部参照まで `duplicate_deep(Resource.DEEP_DUPLICATE_ALL)` で複製する。
- 公開項目には意味・単位・有効範囲・成立条件をドキュメントコメントとInspectorヒントで示す。時間は整数tick、1秒＝60tickとする。
- テストを通す目的で、DPS比率・評価ボットの判断・受入閾値・人間の成功基準を無断変更しない。
- 完了報告には変更項目・変更前後の実効値・変更理由・実行した検証・未確認事項を記載する。人間による評価の開始条件は既存のWorkflowに従う。
- バランスに関わる作業では docs/balance-intent.md を参照し、設計意図と判断理由を確認する。

## Export Templates

- ScoopのGodotはself-contained構成とし、`C:\Users\konop\scoop\apps\godot\current\._sc_` を維持する。
- `export_presets.cfg` の `custom_template/debug` と `custom_template/release` は空に保ち、Godotの標準探索で `C:\Users\konop\scoop\apps\godot\current\editor_data\export_templates\4.7.2.stable\` を使う。
- repo内に `tools/` やExport Templatesを再作成しない。
- 対象4ファイルのSHA-256を使用前に照合する。他platform用templateの同居は許可する。
  - `windows_debug_x86_64_console.exe`: `5514C7645EE897A01F540D3CF22EDE5BADF92394521A08BFAB66A54D7369E6E6`
  - `windows_debug_x86_64.exe`: `51498B72B3A237F882EBD7D1787F06A4BC1EAF0572DAAB93837ADCFD3CFDC107`
  - `windows_release_x86_64_console.exe`: `52BDCAE9068E8D23B840E5C63B0C1798FFE2CB66144E5C4BC7AF11FB8C8600DF`
  - `windows_release_x86_64.exe`: `D34D36F3BE1A6C49C56525AE86469B92E4F417DDF0B43CF00DD80C385C4B0562`
