# Project JARJAR

Godot 4.7.2-stable Standard / GDScript / Compatibility renderer / Windows x86_64。

## 日常の検証

- 通常のコード・Resource変更では、リポジトリのルートで以下の全回帰を実行する。

```powershell
$env:JARJAR_GODOT = (Resolve-Path -LiteralPath (Get-Command godot.exe -CommandType Application -ErrorAction Stop).Source).Path
$jarjarVersion = ((& $env:JARJAR_GODOT --version 2>&1) -join "`n").Trim()
if ($LASTEXITCODE -ne 0 -or -not $jarjarVersion.StartsWith("4.7.2.stable.official.")) { throw "Godot 4.7.2-stable Standard is required." }
Remove-Item Env:JARJAR_TEST_FILTER, Env:JARJAR_TEST_VERBOSE -ErrorAction SilentlyContinue
& $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd
if ($LASTEXITCODE -ne 0) { throw "GDScript tests failed: $LASTEXITCODE" }
```

- 自動テストは主要操作（開始・戦闘・強化・宝箱・勝敗・再開・設定保存）と重要なゲームルールの破綻を検出する。追加は新しい重要ルールか具体的な不具合の再発防止に絞り、同じ保証を重複させない。
- 実装の書き方・過去に削除した機能名・表示文言の完全一致を固定する検査、内部処理を再実装する検査、難易度やDPS比率の合否判定を追加しない。見た目・音の印象・難易度・爽快感は試遊で判断する。
- `tests/**/*_test.gd` は `RefCounted` を継承し、`test_名前(assertions, context)` を定義する。関数を自動発見するため登録簿は不要。ディレクトリや実行順に依存させない。
- ランナーは生成物などの除外先を除き、`.gd`・`.gdshader`・`.tscn`・`.tres`をロード検査する。絞り込み時もロード検査と全テストの発見を行う。
- 失敗調査時だけ `JARJAR_TEST_FILTER` に関数名の `test_` を除いた名前を完全一致で指定し、`JARJAR_TEST_VERBOSE=1` で詳細を表示する。全回帰の代わりにはしない。

```powershell
$env:JARJAR_TEST_FILTER = "runner_settings_are_isolated_and_removed"
$env:JARJAR_TEST_VERBOSE = "1"
try {
    & $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd
    if ($LASTEXITCODE -ne 0) { throw "GDScript tests failed: $LASTEXITCODE" }
} finally {
    Remove-Item Env:JARJAR_TEST_FILTER, Env:JARJAR_TEST_VERBOSE -ErrorAction SilentlyContinue
}
```

- 検証結果は標準出力へ表示する。ログ・CSV・検証一覧のファイル保存や出力リダイレクトを行わない。通常テストは集計と失敗だけを表示する。
- 自動テストは実ユーザー設定を書き換えない。設定は実行ごとにOSの一時ディレクトリへ隔離し、終了時に削除する。
- 任意の性能測定は調査用の参考資料とし、通常検証・export・プレイ開始・試遊の成功判定の必須条件にしない。

## 作業上の制約

- GDScript変更前に[godot-gdscript-guard](.codex/skills/godot-gdscript-guard/SKILL.md)を読み、検証手順に従う。GDScriptをPythonとして扱わない。
- 実装仕様はコードとテストを正とする。進捗・変更履歴・検証記録の別文書を維持しない。
- `build/`、`.godot/`、`.codex/`、`work/`をコミットしない。
- fetch・pull・push・rebase・amend・tag作成は、ユーザーの明示指示がある場合だけ行う。
- 配布物はGodot標準exportで生成する。`build/windows/ProjectJARJAR.exe`・`ProjectJARJAR.console.exe`・`ProjectJARJAR.pck`を手動で差し替えない。
- リポジトリ内に`tools/`やExport Templatesを再作成しない。

## バランスに関わる変更

- 着手前に[バランス調整の意図と補足](docs/balance-intent.md)を読む。この文書は人間が編集するため、修正案は会話で提示する。検討案・仮説を変更承認と扱わず、【確定】事項に抵触する依頼は実装せず、矛盾を報告する。
- 調整値の正本は`data/balance/`の`.tres`、唯一の読み込み入口は`data/balance/survival_content_manifest.tres`。コードに本番値や代替の既定値を持たせない。
- 承認済みの値・確率・進化時刻・受入閾値は、ユーザーの明示承認なしに変更しない。
- 数値調整では指定されたデータと項目だけを変更する。現在の本番値との一致を要求する検証を追加しない。計算式・公開項目の追加・データ形式の変更は別の構造変更として扱う。
- 定義Resourceを実行状態の保存先にしない。変更するテスト入力は外部参照も含め`duplicate_deep(Resource.DEEP_DUPLICATE_ALL)`で複製する。`BalanceTestFixtures.manifest()`はこの用途、`BalanceTestFixtures.catalog()`は共有の読み取り専用。
- 公開項目には意味・単位・有効範囲・成立条件をドキュメントコメントとInspectorヒントで示す。時間は整数tick、1秒＝60tick。
- 仕様策定中は数値調整を行わない。バランス調整は本人の試遊へ渡す直前に一度だけ実施し、成功を確認できなくても反復調整せず、結果・本人の感想を報告して次の判断を待つ。
- バランス変更の完了報告には、変更項目・変更前後の実効値・理由・実行した検証・未確認事項を記載する。

## 配布と試遊

- バランスの良し悪しと次の調整は、まず本人が遊んだ感想で判断する。他の人の感想は必要に応じて集め、固定の参加人数・run回数・合格率は設けない。
- 回答・感想は会話で受け取り、人間の参加・回答・計測値を生成・補完しない。専用の試遊コマンド・記録文書・参加者ID管理を維持しない。
- exportは、会話内でユーザーが最終調整完了を明示した後に進める。
- ScoopのGodotはself-contained構成を維持する。`export_presets.cfg`の`custom_template/debug`と`custom_template/release`は空に保ち、Godot実行ファイルと同じ場所の`editor_data/export_templates/4.7.2.stable/`に配置した公式テンプレートを標準探索で使う。他platform用templateの同居は許可する。
- 以下は「日常の検証」でGodotを特定した同じPowerShellで実行する。全回帰が成功した場合だけexportする。

```powershell
$jarjarGodotRoot = 'C:\Users\konop\scoop\apps\godot\current'
if (-not (Test-Path -LiteralPath "$jarjarGodotRoot\._sc_")) { throw "Godot self-contained marker is missing." }
Remove-Item Env:JARJAR_TEST_FILTER, Env:JARJAR_TEST_VERBOSE -ErrorAction SilentlyContinue
& $env:JARJAR_GODOT --headless --path . --script res://tests/test_runner.gd
if ($LASTEXITCODE -ne 0) { throw "Export cancelled: GDScript tests failed ($LASTEXITCODE)." }
New-Item -ItemType Directory -Force -Path .\build\windows -ErrorAction Stop | Out-Null
& $env:JARJAR_GODOT --headless --path . --export-release "Windows Desktop" .\build\windows\ProjectJARJAR.exe
if ($LASTEXITCODE -ne 0) { throw "Godot export failed: $LASTEXITCODE" }
```
