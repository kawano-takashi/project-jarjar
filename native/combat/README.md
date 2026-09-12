# 戦闘用C++拡張

`JarjarCombatWorld` が敵・弾・XP・破壊可能オブジェクトの数値状態を保持し、移動、位置補正、空間検索、追尾、貫通、命中履歴、爆発、HP、死亡集計、XP生成・吸引・回収を処理します。ゲーム、通常テスト、開発用botのすべてでこの拡張が必要です。

GDScriptは出現スケジュール、武器の発動時刻・パターン・クールダウン、ボスの行動進行、成長・勝敗、UI・音・VFXを担当します。対象ごとの抽選には武器自身の `RandomNumberGenerator` を渡し、出現・成長などの乱数ストリームと分離します。個体のGDScriptオブジェクトは数値状態をコピーせず、必要時にC++のスロットを参照する操作・観測用のビューです。

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

`JarjarCombatWorld` と幾何計算用 `JarjarCombatKernel` はRefCountedで、APIバージョン3を起動時に検査します。位置・半径の単位はメートル、時間は整数tick（60tick/秒）です。敵IDは64bit整数、弾一覧は `[slot, generation, slot, generation, …]` の `PackedInt64Array` です。単体の検査では2要素の配列を渡します。一覧はtick開始時に独立して作成し、その後の出現・解放によって変更しません。奇数長の一覧は処理せず、不正・古いハンドルはスキップします。解放・再利用・容量変更後も以前のハンドルで新しい弾を操作できません。プールの設定値はmanifest内の `CombatBalanceDefinition` から読み込み、描画容量は実際の個体数に合わせて拡張します。

戦闘更新は単一スレッドの固定60tickです。段階ごとのハンドル・攻撃要求をまとめて渡し、C++内で現在のHPを見て順に処理します。命中ごとのGDScriptコールバックはありません。ダメージは発生源別、撃破は発生源・種類別に集計し、重要な撃破と制限内の演出要求を返します。死亡確定は当tickの接触と特殊行動の後です。演出の上限に達しても撃破数とXPを減らしません。

`advance_enemies()` は敵の移動・位置補正を行います。`EnemySystem` がボスの境界補正を終えた後、当tickの出現処理より前に `rebuild_grid()` を呼びます。位置補正用の検索は補正開始時の座標を使うため別に保持します。グリッドのセルと戦闘用の一時配列はワールド単位で再利用し、返却済みのスナップショットやイベントを上書きしません。放物線弾は最初の交点だけを選び、通常弾は交点までの割合と敵IDの順に、貫通残数に必要な命中を処理します。

`CombatSimulation.advance_tick()` と `build_snapshot()` は独立しています。GameAppとbotの画面表示は描画フレームごとに最大1回スナップショットを作成し、種類別の `MultiMesh.buffer` へ一括反映します。イベントは `take_events()` で別に取り出してください。描画用スナップショットを読んでもイベントは消費されず、複数tickのイベントは取り出すまで順に保持されます。画面を持たない利用側もイベントを定期的に取り出します。`step()` は検査用に更新・描画スナップショット・イベント取得をまとめた入口です。

botへは位置・形状などの描画用幾何情報をまとめて渡します。bot側で画面内を判定し、HP・乱数状態・行動時刻・将来の行動を判断材料として公開しません。

## 任意の負荷計測

```powershell
godot --path . -- --performance=full_hd_500_2000 --run-seed=5002000
godot --path . -- --performance=full_hd_3000_6000 --run-seed=5002000
```

前者は既存条件（敵500体・弾1200発）、後者は敵3000体・弾6000発です。いずれもVFX800個・XP1024個・武器5種、1920×1080、120秒間（最初の30秒はウォームアップ）で計測します。専用に深く複製したmanifestへ容量を設定し、本番のResourceを変更しません。固定tickごとに不足分を補充し、敵の移動・位置補正・弾の移動と命中・武器発動を継続します。

標準出力へ実際の個体数、平均fps、p95・最遅フレーム、戦闘更新・描画データ作成時間、Godot管理のメモリを表示します。C++標準コンテナやドライバーの確保分を含むプロセス全体のメモリはOS側でも確認してください。60fpsなどの参考値を満たさない場合は計測だけが非0で終了します。この計測は通常テスト、export、ゲーム起動の必須条件ではありません。

責務分離と一括描画の設計はGodot公式の[CPU最適化](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html)と[MultiMesh最適化](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html)を参照しています。
