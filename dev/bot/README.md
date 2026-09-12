# 開発用プレイbot

同じGodotプロジェクトの戦闘処理・カメラ・画面を利用する開発用ツールです。ゲーム本体からは参照せず、配布時は `dev/` 全体を除外します。

リポジトリのルートから起動します。

ゲーム本体が使う戦闘用GDExtensionも必要です。初回・`native/combat/` のC++変更後は `./native/combat/build.ps1` を実行してください。ビルド・配布の詳細は [戦闘拡張のREADME](../../native/combat/README.md) を参照してください。

初回と `dev/bot/native/` の変更後は、先にbot専用のGDExtensionをビルドします。Windows x64、Visual Studio 2022のC++ツールセット **14.40.33807**、CMake 3.24以上、Python 3が必要です。このPCではCMake 3.27.9 / Python 3.13.0で確認しています。

```powershell
./dev/bot/native/build.ps1
```

godot-cppは `godot-4.5-stable` のコミット `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` に固定し、取得アーカイブのSHA-256を検査します。4.5のGDExtension APIをGodot 4.7.2 Standardで使用します。依存・DLL・拡張定義はすべて `build/bot-native/` に生成します。ビルド後のDLLを内容別の名前で保持するため、実行中のbotを止めずに次の版をビルドできます。

bot専用DLLはbot起動時に読み込みます。未ビルド・DLL欠落・API不一致・読み込み失敗は理由を表示し、終了コード2で停止します。ゲーム本体の配布にbot専用DLLは含めません。

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

処理別の計測は `--bot-profile=1` で有効になります。終了時の `BOT_PROFILE` は子処理を含む時間なので、行同士を加算しないでください。計測用のラッパーはこの指定時だけ使用します。速度評価では指定せず、単独プロセスの起動から `BOT_SUMMARY` までを測ります。通常の `wall_seconds` はセッション初期化後の時間です。

```powershell
godot --headless --path . --script res://dev/bot/run.gd -- --bot=fast --run-seed=1 --bot-profile=1
```

C++はメッシュの可視判定、観測済みの値による追跡・記憶・経路・移動候補評価を担当します。ゲーム状態や乱数を判断処理へ渡しません。GDScriptの実数は64bit、標準Vectorは32bitとして演算順を保ち、MSVCの `/fp:strict` でビルドします。`ArenaView` の投影行列から視錐台の6面を求め、境界では描画メッシュの三角形をクリッピングします。部分表示・リングの穴・近遠クリップを扱い、記憶の消去にも同じ透視投影と画面端24pxの余白を使います。
