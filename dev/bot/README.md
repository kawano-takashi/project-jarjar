# 開発用プレイbot

同じGodotプロジェクトの戦闘処理・カメラ・画面を利用する開発用ツールです。ゲーム本体からは参照せず、配布時は `dev/` 全体を除外します。

リポジトリのルートから起動します。

```powershell
godot --headless --path . --script res://dev/bot/run.gd -- --bot=fast --run-seed=1 --runs=100
godot --path . --script res://dev/bot/run.gd -- --bot=watch --run-seed=1 --bot-speed=4
```

seedとプレイ数の既定値は1、観戦速度は1倍です。観戦は1プレイで、1・4・16倍に対応します。`--bot-view=1920x1080` で観測する画面サイズを指定できます。ウィンドウを拡縮しても指定した画角を保ちます。

結果と集計は標準出力に表示します。高速実行の終了コードは全勝が0、敗北・時間切れが1、実行不備が2です。観戦は結果画面を残します。設定は既存の一時設定を使用します。

bot専用の回帰は次のコマンドで実行します。検査・一時設定の隔離・失敗検出はゲーム側のテストランナーを共有します。

```powershell
godot --headless --path . --script res://dev/bot/test_runner.gd
```

共有するゲーム側の処理を変更した場合は、通常の `res://tests/test_runner.gd` も実行します。100条件の全プレイ評価は短い回帰から分離し、必要な評価条件を高速実行に指定します。
