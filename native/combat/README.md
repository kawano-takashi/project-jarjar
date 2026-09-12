# 戦闘用C++拡張

敵同士の位置補正、空間検索、弾の線分と敵の円との交差候補を計算します。HP、乱数、貫通、命中履歴、爆発と死亡の順序はGDScript側で管理します。ゲーム、通常テスト、開発用botのすべてでこの拡張が必要です。

## ビルド

Windows x64、Godot 4.7.2-stable Standard、Visual Studio 2022 C++ツールセット **14.40.33807**、CMake 3.24以上、Python 3を使用します。リポジトリのルートから、初回とC++変更後に実行します。

```powershell
./native/combat/build.ps1
```

godot-cppはbotと同じ `godot-4.5-stable` のコミット `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` とアーカイブのSHA-256に固定しています。4.5のAPIを4.7.2 Standardで使用します。`/O2 /fp:strict`、静的MSVCランタイムでビルドし、GDScriptの64bit実数と32bit Vectorの演算順を保ちます。

SDK・中間生成物は `build/combat-native/`、DLL・拡張定義・ライセンスは `native/combat/runtime/` に生成します。いずれもGit管理外です。DLLの名前は内容に基づくため、実行中の版があってもビルドできます。変更後はゲームとGodotエディタを再起動してください。拡張の動的な再読み込みは無効です。

未ビルド・DLL欠落・API不一致・読み込み失敗の場合、ゲームとbotは理由を表示して終了コード2で停止し、テストは非0で失敗します。GDScriptによる代替実行はありません。

## 検証と配布

```powershell
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --script res://dev/bot/test_runner.gd
```

各コマンドの `$LASTEXITCODE` を確認してから次に進みます。export前はビルドした拡張をインポートします。

```powershell
godot --headless --editor --path . --import
godot --headless --path . --export-debug 'Windows Desktop' build/windows-debug/ProjectJARJAR.exe
godot --headless --path . --export-release 'Windows Desktop' build/windows-release/ProjectJARJAR.exe
```

出力先ディレクトリは事前に作成してください。Export TemplatesはGodotのユーザーデータ側にインストールした4.7.2-stable Standardを使用します。プロジェクト内への配置は不要です。

Godotは `.gdextension` が参照するDLLを配布先へコピーします。`LICENSE.txt` はexportのinclude_filterによりPCKへ同梱します。exeだけでなく、生成されたPCKとDLLを含むディレクトリ全体を配布してください。`dev/` と `build/` 内のSDKやbot専用DLLは配布に含めません。

## 計算境界

`JarjarCombatKernel` はRefCountedで、APIバージョンを起動時に検査します。配列の長さは対応する入力間で一致させます。IDはPackedInt64、位置はPackedVector2、半径と交差パラメータはPackedFloat64で受け渡します。半径と位置の単位はメートル、交差パラメータは0〜1です。

弾の交差結果は、各弾の区間を表すPackedInt32 offsetsと、それに対応する敵ID・交差パラメータです。候補は元のセル走査順で返します。GDScriptが弾ごとに現在のHPと命中履歴を確認し、その後に既存の比較規則で並べ替えます。索引は出現・移動の既存の更新境界で再構築し、数値スナップショットを別のtickへ持ち越しません。
