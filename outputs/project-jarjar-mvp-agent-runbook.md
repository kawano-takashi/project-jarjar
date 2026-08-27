# Project JARJAR（仮題）— MVP コーディングエージェント作業手順書

文書版: 1.1  
対象: Windows PC / Steam 向けローカル・シングルプレイ MVP  
実装基盤: Godot 4.7.2-stable Standard / GDScript / Compatibility renderer

## 1. この手順書の目的

この文書は、空の作業領域から Project JARJAR のプレイ可能な MVP を作るコーディングエージェント向けの実行仕様である。実装者は、ゲーム仕様や技術方針を独自に補完・変更しない。数値、状態遷移、乱数、UI、テスト、証跡、コミット条件は本書を正とする。

MVP の完成条件は、Windows x86_64 の Release ビルドで、タイトルから8ウェーブ完走、失敗、報酬開封、装備整理、合成、最終結果、同じ seed での再挑戦、終了までを操作でき、後述する自動テスト、性能試験、人間プレイテストをすべて満たすことである。

本書内の「箱」は宝箱を、「主武器」は装備枠 MAIN_WEAPON を、「現在タイプ」は装備中の主武器が持つ BOW / STAFF / SWORD のいずれかを指す。初期装備の木の棒は UNCLASSIFIED である。

## 2. 作業上の絶対ルール

### 2.1 作業場所と既知の初期状態

- コーディングエージェントに割り当てられた作業ディレクトリそのものをリポジトリルートとする。入れ子のプロジェクトディレクトリは作らない。
- project.godot、src、scenes、data、tests はリポジトリルート直下へ置く。
- 開始時点では Godot 4.7-stable が PATH 上にあり、Git 2.47.1 以上が使用でき、Git リポジトリはまだ初期化されていない。
- ローカルのコーディング支援用として`.codex/skills/godot-gdscript-guard/`が存在してよい。許可内容は6.2のexact whitelistだけとし、他の`.codex`内容は想定外として停止する。`.codex`は製品sourceではなくGit管理外とする。
- outputs/project-jarjar-game-proposal.md と本書は、ゲート1の初回コミットへ含める。
- 実装開始前に、必ず本書と outputs/project-jarjar-game-proposal.md を最後まで読む。両者が食い違う場合は本書の内部契約を実装上の正とし、食い違いを人間へ報告して停止する。

### 2.2 禁止事項

- Godot 以外のゲームエンジン、C#、GDExtension、ネイティブ DLL を使わない。
- 外部アドオン、Asset Library、外部画像、外部3Dモデル、外部フォント、外部音源、Steamworks を使わない。
- 敵または飛翔物1体ごとに Node3D、CharacterBody3D、RigidBody3D、Area3D を生成しない。
- 戦闘、loot、名前生成で同じ RandomNumberGenerator インスタンスを共有しない。
- 報酬開封時に loot を再抽選しない。
- テストを無効化、期待値を緩和、失敗ケースを削除してゲートを通過させない。
- 未確定欄、曖昧な裁量指定、仮実装、先送り事項を残さない。
- ビルド、テスト結果、スクリーンショット、ローカル Godot 本体を Git にコミットしない。
- 未承認の次工程へ進まない。

### 2.3 変更とコミットの規律

各工程の開始時に git status --short --branch を記録する。ゲート1では `git init --object-format=sha1 -b main` を実行し、commit hashを40文字へ固定する。各工程では、その工程に必要な変更だけを行い、すべての必須検証が成功した後に初回の基準コミットを1つ作る。人間の承認前に修正依頼を受けた場合だけ、後述する追補コミットを追加する。各コミット後の git status --short は空でなければならない。

- Gate 1の初回preflightで既存の`.git`、想定外の追跡候補、またはremote相当の既存repository状態が見つかった場合は上書きせず、状態を報告して停止する。`git init`は本書どおりの空の非Git作業領域でだけ実行する。Gate 2以降を新規開始するときは逆に`.git`が存在し、object formatがsha1、branchが`main`、remoteが0件、開始時working treeがclean、HEADが直前Gateの承認済み40文字HEADであることを要求し、満たさなければ停止する。同一Gateの明示再開時だけ2.3末尾の再開規則を適用する。
- `git config --get user.name` と `git config --get user.email` のどちらかが空なら、globalまたはlocal設定を勝手に変更せず、人間へ設定を依頼して停止する。
- `git commit --amend`、rebase、push、force push、タグ作成は行わない。

コミットメッセージは次の文字列へ固定する。

1. chore: bootstrap Godot 4.7.2 project
2. feat: add deterministic run domain model
3. feat: implement arena combat and wave flow
4. feat: add deterministic chest rewards
5. feat: implement inventory skills and scoring
6. feat: polish and export MVP

承認前のレビュー修正に使う追補コミットメッセージは `fix: address Gate N review` に固定し、Nを対象Gate番号へ置換する。複数回の修正でも同じ文字列を使い、amendはしない。検証失敗時はコミットしない。原因、再現コマンド、関連ログの絶対パスを報告して停止する。

同じ工程を再開できるのは、人間が本項の固定文言で明示した場合だけとする。Gate 1が`git init`より前に停止した場合は、人間が「Gate 1の修正を再開」と指示し、原因を解消した後に初回preflightから再実行する。`git init`後かつGate 1基準コミット前に停止した場合も同じ文言を使い、初回preflightと`git init`を再実行せず6.2の無コミット再開監査を使う。

Gate 2〜6が基準コミット前に停止した場合は、人間が「Gate Nの修正を再開 H」と指示する。Nは対象番号、Hは直前Gateの承認済み40文字HEADである。再開時はbranch=`main`、remote=0件、`git rev-parse HEAD`がHと完全一致し、H以後のcommitがなく、working treeがcleanまたは中断前からの当該Gate変更だけを含むことを確認する。別Gateの変更、未知の生成物、別HEADがあれば停止する。合格時は未コミット成果を削除せず、最初に失敗した、または完了を証明できないコマンドから続ける。Gate 6の人間プレイテスト待ちはこの経路のまま基準コミット前に停止し、集計再開指示だけは「Gate 6のプレイテスト集計を再開 H」に固定する。

基準コミット作成後から承認までのHEADを「候補HEAD」と呼ぶ。候補HEADの報告後に修正依頼を受けた場合は、人間が「Gate Nの修正を再開 H」と指示する。ここでHは最後に報告した40文字の候補HEADである。再開時にbranch=`main`、remote=0件、`git rev-parse HEAD`がHと完全一致することを確認する。Gate 2〜6では直前の承認済みHEADが祖先であり、その後のsubjectが対象Gateの基準message 1件と`fix: address Gate N review`だけであることも確認する。Gate 1には直前承認済みHEADがないため、root commitのsubjectが`chore: bootstrap Godot 4.7.2 project`であり、その後のsubjectが`fix: address Gate 1 review`だけであることを確認する。working treeはclean、または中断前からの当該Gate修正だけを含む状態でなければ停止する。修正後は当該Gateの全必須検証を再実行し、成功時だけ `fix: address Gate N review` で新しい追補コミットを作り、新しい候補HEADとして再報告する。候補コミット作成後・報告前に中断した場合もHへその候補HEADを指定して再開し、全検証を再実行して既存HEADを報告する。変更がないのに空コミットを作らない。Gateの承認は、直前の承認済みHEADより後にある当該Gateの基準コミットと全追補コミットを、現在の候補HEADまで一括して承認する。Gate 1ではrootから候補HEADまでを承認する。次Gateはその承認済みHEADからだけ開始できる。

### 2.4 人間承認ゲート

各工程の最後に、次の順序で報告し、その場で停止する。

1. 工程番号と完了内容
2. 変更ファイルの要約
3. 実行した検証コマンド、終了コード、合格件数
4. 合格条件のチェックリスト
5. PNG スクリーンショットの絶対パス
6. 直前の承認済みHEAD以後に作った当該Gateの全コミット hash と、現在の候補HEAD。Gate 1はroot commitから列挙する
7. git status --short の結果
8. 既知の問題。問題がなければ「なし」と明記
9. 「次工程は未着手。人間の明示承認を待つ」と明記

承認とは、人間が「ゲートN承認 H。工程N+1へ進んでよい」と明示することをいう。Nは完了Gate、Hは報告された40文字の候補HEADであり、エージェントは`git rev-parse HEAD`との完全一致を確認する。Gate 6の最終承認は「ゲート6承認 H。MVP完了」とする。単なる質問、感想、修正依頼、hashなしの承認文は承認ではない。

## 3. MVP の固定仕様

### 3.1 製品範囲

- 日本語のみ、ローカル1人用、買い切りを想定した Windows PC MVP。
- 操作は WASD、矢印キー、左スティックによる移動だけ。攻撃、照準、スキルは完全自動。ダッシュ、手動攻撃、手動スキル発動は存在しない。
- 斜め見下ろし3D。障害物のない30m×18mのアリーナ。
- 1ランは60秒×8ウェーブ。戦闘と報酬整理を合わせた目標時間は約15分。
- 恒久能力強化、恒久コンテンツ解禁、オンライン通信、ランキング、実績、多言語、マルチプレイ、ラン途中保存、日替り seed、高難度は MVP に含めない。
- 設定値と「チュートリアル確認済み」だけ user://settings.cfg に保存する。ラン、スコア、プレイログは保存も外部送信もしない。Godot既定のdesktop file logも`debug/file_logging/enable_file_logging=false`と`debug/file_logging/enable_file_logging.pc=false`の両方で無効化する。

### 3.2 ウェーブ進行

キルノルマは順に 40、60、85、115、150、190、240、300。各ウェーブ開始時に HP を最大まで回復する。

各ウェーブ開始時はプレイヤーをXZ=(0,0)へ戻し、前ウェーブの敵、味方／敵飛翔物、VFX、世界箱表示、ScheduledProcReplay、recent_damage_samplesを全消去し、spawn_credit=0、time_remaining=60、wave_kills=0、wave_chests=0、wave_cleared=false、coward_stationary_elapsed=0へ戻す。主武器の攻撃準備値は実効攻撃間隔まで満たした状態にする。entity_idの次値、inventory、overflow、装備、スキルtrigger_progress / pending_queue、同じ反響の手甲itemを装備し続けている場合のecho_primary_attack_progress、peak_dps、wild、確定済み累計scoreは保持する。血塗れの短剣のウェーブ内kill bonusだけは3.9どおり0へ戻す。

ノルマと画面の総撃破数は、通常敵、ボス召喚、エリート、ボスの死亡をすべて1体として数える。スコアでは通常敵とボス召喚を1体10点、ELITEを300点、BOSSを1,500点として排他的に数える。wave_cleared後の撃破には敵種を問わず追加10点を与える。

物理 tick 内の判定順は、攻撃解決、死亡とキルイベント、箱獲得、ノルマ成立のラッチ、プレイヤー死亡、残り時間更新、時間切れ判定とする。残り時間更新は4.1のTimerMath countdownを使い、0へ正規化したtickで時間切れを判定する。同じ tick でノルマ到達とプレイヤー死亡または時間切れが起きた場合、ノルマ到達を成功として扱う。

COMBATの各physics tickは次の全体順へ固定する。W1初回チュートリアルでtimer / spawn停止中はプレイヤー移動とチュートリアル累積だけを行い、下記処理とphysics_tick加算を行わない。

1. RunState.physics_tickを1増やし、tick開始時点のactive enemy entity_id集合と味方／敵projectileの`(pool_index, generation)`集合をsnapshotする。
2. プレイヤーを移動・clampする。snapshot内の敵だけをentity_id昇順で移動・clampし、全移動後に4.1のuniform gridを再構築する。接触timer、RANGED射撃timer、ELITE予告開始timerと進行中予告timer、BOSS弾幕timerと召喚timerを進め、readyになった行動を種類別に記録する。この時点では行動を生成・解決しない。snapshot内projectileだけをpool index昇順で移動し、命中候補を固定する。同時にspawn_creditを加算する。
3. snapshot内の生存BOSSで召喚timerがreadyならentity_id昇順で召喚を先に解決し、その後に通常spawn loopを解決する。したがって同tickのW8残りnon_boss枠、敵pool枠、combat RNG、next_entity_idはBOSS召喚が先に使う。生成した全敵へ`born_physics_tick=current physics_tick`を持たせる。
4. 3.10の攻撃解決順を実行する。tick開始snapshotに含まれ、まだ生存する敵とprojectileだけを移動、対象選定、接触、命中の候補にできる。手順3で生成した敵と、このtickに生成したprojectileは表示には加えるが、次physics tickまで移動せず、攻撃せず、接触せず、攻撃対象にもならない。
5. 手順4で各event直後に確定済みの死亡・キルから、保持していたloot候補を死亡entity_id昇順で処理してquotaをラッチし、続いてプレイヤー死亡を判定する。
6. time_remainingを必ず1 physics delta減らす。手順5で死亡遷移が確定済みなら死亡側の遷移を優先し、時間切れ判定と特殊敵生成は行わない。死亡遷移がなければ時間切れを判定する。W4ではこの更新で経過時間が初めて30.0秒へ達し、かつCOMBAT継続中なら、通常spawnより後のnext_entity_idを使ってELITEを1体生成し、born_physics_tickをcurrentへ設定する。ELITEは次tickから更新・対象選定される。
7. REWARD_REVEALまたはFAILEDへの遷移が成立した場合は戦闘配列をそれ以上更新せず、3.2の成功／失敗処理へ進む。

- ノルマ前に HP が0以下: ラン失敗。そのウェーブで得た箱と報酬だけを破棄する。
- 残り時間が0になった時点でノルマ未達: ラン失敗。そのウェーブで得た箱と報酬だけを破棄する。
- W1〜W7のノルマ到達: wave_cleared を true に固定し、その後ノルマを下回る状態へ戻さない。
- W8の成功: `wave_kills >= 300 and boss_defeated == true` を同時に満たしたときだけ wave_cleared を true にする。
- ノルマ到達後かつ残り時間あり: 戦闘を継続し、追加キルと箱を獲得できる。
- ノルマ到達後に死亡: その tick のイベント解決後に戦闘を終了し、報酬開封へ進む。
- ノルマ到達後に時間切れ: 報酬開封へ進む。
- W4: 経過30秒でエリートを1体出す。
- W8: 開始時にボスを1体出す。ボス生存中に生成できる非ボス敵は、通常スポーンとボス召喚を合計299体までとする。生存中の非ボス敵をすべて倒しても299キルなので、ボス撃破なしに300キルへ到達できない。ボス召喚もノルマへ1体1キルとして加算し、通常敵と同じ3%で箱を抽選する。ボスを早期撃破した場合は通常スポーンを継続し、299体を先に生成した場合はボス撃破まで通常スポーンを停止する。ボス撃破後は通常スポーン上限を解除する。
- ボス召喚1回の実生成数`n`は`min(8, 299 - non_boss_spawned, 敵pool空き数)`。n=0なら何も生成せずcombat RNGも消費しない。n>0ならcombat RNGの`randf_range(0.0, TAU)`を1回だけ使って開始角を決め、その後slot index 0..n-1の順に、W8 WaveDefinition.enemy_weights（TRACKER 20% / FAST 30% / ARMORED 25% / RANGED 25%）と4.5のweighted selectorで敵種類を1回ずつ抽選する。候補位置はBOSS中心から2.0m、角度`開始角 + TAU × slot_index / n`の等間隔円上とし、最終位置は3.5の敵中心clampを適用する。位置ごとのRNGは使わず、clampで同一点になった個体もそのまま別entityとして生成する。召喚雑魚は選ばれた通常敵と同じAIへW8のHP / damage倍率を適用し、spawn_creditを使わず、実生成ごとにnon_boss_spawnedを1増やす。上限またはpoolで省略した分の種類RNGは消費しない。次の召喚判定は通常どおり6秒後で、取り戻すための即時再試行は行わない。

W4エリートは経過30秒のtickに、内周四隅`(14.25,8.25), (-14.25,8.25), (-14.25,-8.25), (14.25,-8.25)`からプレイヤーとの距離が最大の点へ出す。同距離はこの列の先頭を選ぶ。W8ボスはウェーブ開始reset直後に`(14.25,8.25)`へ出す。いずれも位置決定でcombat RNGを消費しない。

### 3.3 アリーナ、プレイヤー、カメラ

- 論理座標は地面の XZ 平面。境界は X=-15..15、Z=-9..9。
- プレイヤー半径0.45m、最大HP100、基本移動速度5.0m/s、基本ダメージ軽減0%。
- 入力は Input.get_vector("move_left", "move_right", "move_up", "move_down", 0.2)。斜め入力を正規化し、加速なしで即時に速度へ反映する。
- プレイヤーを境界内へ clamp する。敵との物理押し合いは行わない。
- Camera3D は orthographic、size=13.0、方位角45度、俯角55度、near=0.1、far=100.0。16:9で地面へ投影した1画面の面積は`(13×16/9) × (13/sin(55°)) ≒ 366.8m²`で、30m×18mのアリーナは約1.47画面分、すなわち目標の約1.5画面分となる。追従目標はプレイヤーXZをX=-9..9、Z=-4.5..4.5へclampしY=0とした座標で、smoothed_targetは毎physics tickに`alpha=1-exp(-physics_delta/0.18)`を使って`lerp(previous, target, alpha)`する。Camera3D位置は`smoothed_target + Vector3(8.912187, 18.0, 8.912187)`、注視点はsmoothed_target、upはVector3.UPへ固定する。このoffsetは水平距離12.603736mで俯角55度となり、高さと回転をプレイ中に変えない。
- アリーナ床、境界、キャラクター、敵、攻撃、箱は PrimitiveMesh、StandardMaterial3D、GPUParticles3D だけで表現する。重要情報を色だけで伝えず、形、アイコン、文字、動きのうち2つ以上を併用する。

### 3.4 主武器

| 武器 | タイプ | 基礎ダメージ | 基礎間隔 | 射程 / 形状 | 固定挙動 |
|---|---|---:|---:|---|---|
| 木の棒 | UNCLASSIFIED | 10 | 0.80秒 | 1.8m | 最も近い1体へ即時打撃 |
| 弓 | BOW | 12 | 0.75秒 | 14m | 速度24m/s、半径0.20mの矢。基本追加貫通0 |
| 杖 | STAFF | 18 | 1.50秒 | 13m、弾半径0.25m、着弾半径2.25m | 最も近い敵の位置へ速度16m/sの弾を飛ばし、着弾時に範囲内を1回攻撃 |
| 剣 | SWORD | 14 | 0.90秒 | 2.4m、120度 | 最も近い敵方向を中心とする扇形内の全敵を1回攻撃 |

攻撃準備値は4.1のTimerMathでphysics deltaを加え、実効攻撃間隔まででclampする。敵が射程内にいない間は満タンで保持し、射程内へ入った最初の physics tick に1回だけ攻撃して0へ戻す。待機時間を蓄積した連射は行わない。攻撃間隔の実効下限は0.05秒。追加貫通値 N は、最初の1体に加えて N 体を通過できることを意味する。値が現在生存する全敵数以上なら全敵を貫通する。

最寄り対象の同距離判定は entity_id の小さい敵を優先する。弓と杖は発射 tick の対象位置へ向けた非追尾弾で、射程距離を進んだ時点で消える。飛翔物の各tickはprevious_positionから、そのtickの速度移動または残距離でclampしたnext_positionまでのXZ線分と、敵中心・半径`enemy_body_radius + projectile_radius`の円との最初の交差を連続判定する。同じ線分上の候補は交差parameter t昇順、同tはentity_id昇順とするため、高速弾のすり抜けを許さない。弓は同じ entity_id へ1発で2回命中せず、この順で命中し、命中可能回数を使い切るか14m進むまで直進する。杖は最初の敵交差点、保存した対象位置への到達点、13mの射程端点のうち線分上で最初の点を爆発中心とし、中心距離が`2.25m × effective_area_multiplier + enemy_body_radius`以下の各敵へentity_id昇順で1回だけ当てる。敵と同時に対象位置へ達した場合は敵交差を優先する。敵弾もprevious→next線分とプレイヤー半径+弾半径で連続判定し、最初の交差で1回命中して消える。剣と木の棒は発生 tick に即時解決する。

木の棒は初期装備で、Common、通常特性なし、ユニークなし、固定名「木の棒」とする。別の主武器を装備した時点で通常の Common 装備としてインベントリへ戻り、再装備と合成素材化を許可する。

### 3.5 敵

| 種類 | 基礎HP | 速度 | 接触 / 弾ダメージ | 挙動 |
|---|---:|---:|---:|---|
| TRACKER | 10 | 2.2m/s | 8 | 常にプレイヤーへ直進。接触判定は敵ごとに0.75秒間隔 |
| FAST | 12 | 3.8m/s | 6 | 常にプレイヤーへ直進。接触判定は敵ごとに0.60秒間隔 |
| ARMORED | 65 | 1.35m/s | 14 | 常にプレイヤーへ直進。半径0.65m、接触判定は1.00秒間隔 |
| RANGED | 28 | 1.8m/s | 接触9 / 弾9 | 7mを保つよう接近・後退し、接触判定は0.75秒間隔、1.80秒ごとに速度10m/sの弾を撃つ |
| ELITE | 650 | 1.6m/s | 接触18 / 範囲25 | 接触判定は1.00秒間隔、4秒ごとに半径2.5mを1.2秒予告して攻撃 |
| BOSS | 4500 | 1.1m/s | 接触24 / 弾12 | 接触判定は1.00秒間隔、3秒ごとに12方向弾、6秒ごとに8体召喚 |

当たり半径は TRACKER=0.45m、FAST=0.32m、ARMORED=0.65m、RANGED=0.45m、ELITE=0.90m、BOSS=1.25m。接触はプレイヤー半径との和以下で成立する。RANGED は距離7.25m超で直進、6.75m未満で後退、その間は停止し、発射時のプレイヤー位置へ半径0.20m、寿命4秒の非追尾弾を撃つ。ELITE は予告中も直進し、予告開始時のプレイヤー位置を攻撃中心として固定する。BOSS は常に直進し、12方向弾を30度間隔で撃つ。弾幕ごとに角度を15度交互にずらし、弾半径0.25m、速度8m/s、寿命5秒とする。召喚の実生成数、開始角、slot位置、種類抽選は3.2の固定順に従う。

敵生成時は接触elapsedを0にし、毎physics tickで4.1の`TimerMath.advance_clamped`へ渡す。接触中かつ`TimerMath.is_ready(elapsed, contact_interval)`なら1回だけDamageServiceへ渡して0へ戻す。非接触中もintervalまで蓄積するため、生成からinterval以上経過後の初接触はそのtickに当たる。RANGEDの射撃、ELITEの予告開始、BOSSの弾幕、BOSSの召喚はそれぞれ独立elapsedを生成時0にし、1.80 / 4.00 / 3.00 / 6.00秒へ同じTimerMath加算を行い、readyとなったtickで1回実行して0へ戻す。したがって初回は生成直後でなく各interval経過後である。ELITEは予告開始から1.20秒後に1回解決し、BOSS弾幕の15度offsetは最初を0度、次を15度として交互にする。召喚数n=0でも召喚elapsedは0へ戻す。

通常敵のウェーブ別構成比、HP倍率、ダメージ倍率、毎秒スポーン数は次で固定する。毎physics tickの手順2開始時、countdown更新前のtime_remainingから`elapsed_at_tick_start=60.0-time_remaining`を求め、`current_spawn_rate=lerp(spawn_rate_start, spawn_rate_end, clamp(elapsed_at_tick_start / 60.0, 0.0, 1.0))`とする。そのtickではこの値を変えず、`spawn_credit += current_spawn_rate × physics_delta`へ使う。W1初回チュートリアル停止中はこの計算と加算を行わない。

| W | TRACKER | FAST | ARMORED | RANGED | HP倍率 | ダメージ倍率 | spawn/s 開始→終了 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 100% | 0% | 0% | 0% | 1.00 | 1.00 | 1.4→2.0 |
| 2 | 75% | 25% | 0% | 0% | 1.15 | 1.10 | 2.0→2.8 |
| 3 | 55% | 30% | 15% | 0% | 1.35 | 1.20 | 2.7→3.8 |
| 4 | 45% | 25% | 20% | 10% | 1.60 | 1.35 | 3.6→5.0 |
| 5 | 35% | 30% | 20% | 15% | 1.90 | 1.50 | 4.5→6.0 |
| 6 | 30% | 30% | 22% | 18% | 2.25 | 1.70 | 5.6→7.4 |
| 7 | 25% | 30% | 25% | 20% | 2.65 | 1.90 | 7.0→9.2 |
| 8 | 20% | 30% | 25% | 25% | 3.10 | 2.20 | 9.0→12.0 |

通常敵を実生成するときは、最初にwave weightsからenemy typeを1回抽選し、次に位置を最大16試行する。各位置試行はcombat RNGを`randi_range(0, 3)`、`randf()`の順にちょうど2回使う。edge 0はX=-14.25でZを-8.25..8.25、edge 1はX=14.25でZを同範囲、edge 2はZ=-8.25でXを-14.25..14.25、edge 3はZ=8.25でXを同範囲とし、randf値を区間の線形補間へ使う。プレイヤーから8m以上ならその位置を採用して残り試行のRNGは消費しない。16試行すべてが不合格なら`(14.25,8.25), (-14.25,8.25), (-14.25,-8.25), (14.25,-8.25)`から距離最大を選び、同距離は列の先頭、追加RNGなしとする。エリートとボスへウェーブ倍率は適用しない。

通常敵、召喚敵、ELITE、BOSSは生成直後と各移動後に、体半径とは無関係に中心座標をX=-15..15、Z=-9..9へclampする。BOSS召喚は等間隔円の候補位置を作った後、slot index順にこのclampを適用する。敵の体が境界外へ一部はみ出すことは許容し、半径分を内側へ寄せない。敵飛翔物は境界でclampや反射を行わず、命中、寿命切れ、またはpool解放まで直進する。

通常スポーンは spawn_credit に current_spawn_rate×physics_delta を加算し、8.0でclampする。1以上の間、敵poolに空きがありW8の299制限外なら1を引いて1体を実生成する。敵容量が満杯、またはW8の299制限中はcreditを減らさず、combat RNGも消費せず、そのtickの通常spawn loopを終える。pool slotは再利用してよいが、entity_idはラン開始から単調増加し再利用しない。

プレイヤーが受ける最終ダメージは raw_damage × (1 - clamp(damage_reduction_pct, 0, 100) / 100)。100%軽減ではHPを減らさないが、攻撃が命中して DamageService に受理された時点で「被弾判定」を1回加算する。敵接触は敵ごとの再ヒット間隔を守り、敵弾は命中後に消える。

### 3.6 箱、loot、レアリティ

各ウェーブ開始時、装備中の MainWeaponType を保証抽選用 snapshot として固定する。そのウェーブで最初に自然獲得した箱は、元の内容抽選を行わず保証主武器へ置き換える。さらにノルマ成立をラッチした時点で自然獲得箱が0個なら、プレイヤー位置へ保証箱を1個生成して即時獲得させる。このフォールバックは通常箱抽選を行わず、成功ウェーブの箱が0個になる経路をなくす。保証主武器がすでに存在する場合は追加しない。失敗時は保証を含む当該ウェーブの全 RewardRoll を破棄する。

同じphysics tickに複数の敵が死亡した場合はentity_id昇順でlootを処理する。通常敵とボス召喚は各死亡につきloot RNGの`randf()`を1回だけ消費し、値が当該waveの箱率未満なら箱1個を生成する。ELITEとBOSSは箱率判定のrandfを消費せず、それぞれ3個・8個をreward_id順に生成する。最初に生成された1個だけを保証内容へ置換し、箱総数は変えない。

- W1 の保証主武器: BOW / STAFF / SWORD を各1/3。
- W2以降の保証主武器: ウェーブ開始時 snapshot のタイプ50%、他2タイプを各25%。
- W2以降も snapshot が UNCLASSIFIED の場合: 3タイプを各1/3。
- 保証枠以外: 装備90%、スキル10%。
- スキル報酬になった場合: 星落とし、千刃陣、魂の連鎖、報復の鐘を各25%。
- 通常敵の箱率 W1..W8: 30%、22%、16%、10%、9%、7.5%、6%、3%。
- エリート撃破: 箱3個。
- ボス撃破: 箱8個。

装備レアリティ抽選:

| W | Common | Rare | Epic | Legendary |
|---|---:|---:|---:|---:|
| 1–2 | 88% | 11% | 1% | 0% |
| 3–4 | 80% | 17% | 2.5% | 0.5% |
| 5–6 | 72% | 23% | 4% | 1% |
| 7–8 | 64% | 27% | 7% | 2% |

RNG消費順を次に固定する。

1. 保証箱は内容種別を装備、部位を MAIN_WEAPON、unique_idを空に固定し、「当該ウェーブのレアリティ → snapshotを用いた保証タイプ → 通常特性 → 名前」の順で生成する。
2. 通常箱は最初に装備90%／スキル10%を抽選する。スキルなら4種を各25%で抽選し、以後のレアリティ・ユニーク・部位抽選は行わない。
3. 通常装備なら当該ウェーブのレアリティを抽選した後、loot RNGの`randf()`を正確に1回消費し、値が`< 0.04`ならユニーク、`>= 0.04`なら非ユニークとする。当選時はIDのordinal辞書順`bloodied_dagger, broken_clock, coward_boots, echo_gauntlet, hollow_crown, immortal_breastplate`から各1/6で選ぶ。この選択は4.5のweighted selectorへ等重み6件を渡してloot RNGの`randf()`をさらに正確に1回消費し、選ばれた固定品の部位へ確定する。部位と主武器タイプの抽選は行わない。
4. ユニーク非当選時だけ6部位を各1/6で抽選し、MAIN_WEAPONならBOW / STAFF / SWORDを各1/3で抽選する。通常箱の主武器タイプにはsnapshotの50% / 25% / 25%を使わない。
5. 最後に通常特性と名前を生成する。

したがって「ユニーク4%」の母集団は、保証主武器を除く全装備であり、通常箱の装備と合成出力の最終ユニーク率はそれぞれ4%である。ユニーク当選が部位を固定するため、6部位均等は非ユニーク品だけに対する条件付き仕様とする。エリート3箱とボス8箱は保証ではない通常箱として同じ手順を使う。スキル報酬は開封表示上SKILLと記す。

報酬内容は箱のドロップが成立した死亡 tick に「論理獲得」され、RewardRoll として完全確定する。0.25秒の跳ねと HUD 吸収は獲得済み箱の表示だけであり、内容確定を遅らせない。箱の表示、開封速度、長押し、全開封、画面遷移は RNG を消費しない。成功で戦闘が終了する時は残っている箱表示を即時に HUD へ吸収してから REWARD_REVEAL へ遷移する。失敗時は表示を消し、そのウェーブの RewardRoll を破棄する。箱は死亡地点で0.25秒跳ね、同一メッシュ、同一マテリアル、同一色のまま HUD へ吸収される。接近操作は不要。表示用箱プールは128個で、枯渇時は最古の箱を直ちに吸収して再利用し、報酬を失わない。

開封:

- 開封順は acquired_tick 昇順、同tickなら reward_id 昇順。
- 「すべて開ける」でも報酬の状態反映はこの順序で行い、同時表示だけを行う。
- 通常自動開封は1箱0.35秒間隔。
- 決定ボタンまたはマウス左ボタン長押し中は4倍速、すなわち平均0.0875秒間隔。4.1の剰余保持repeating timerを使うため、60Hzでも4件を21tick=0.35秒で公開し、frame丸めをカードごとに累積させない。
- Epic / Legendary は公開前に0.75秒の震動、上昇音、段階点灯、設定有効時のコントローラー振動を必ず行う。Epic振動は弱0.30/強0.50を0.30秒、Legendaryは弱0.50/強0.80を0.50秒。偽予告は行わない。
- 「すべて開ける」は、Epic以上が1個でもあれば0.75秒の集約先バレを1回出す。その間、該当する未公開カードをすべて個別に震動・段階点灯させ、文字「EPIC以上」を表示し、最上位レアリティの上昇音と振動設定を1回だけ再生してから全カードを同時公開する。これを各Epic / Legendaryに対する公開前予告として扱う。Epic以上がなければ即時公開する。
- Reduce Motion 有効時は位置の震動を2%拡縮パルスへ置換する。Reduce Flashes 有効時は白フラッシュを輪郭太さの変化へ置換する。重要度は文字「EPIC」「LEGENDARY」と形状でも示す。
- Reduce Flashes が無効でも全画面フラッシュは禁止し、同一画面領域の点滅は毎秒3回未満、連続1秒未満とする。

通常／4倍の連続開封で次のカードがEpic以上なら、そのカードを公開せず0.75秒の個別先バレへ入り、reward_open accumulatorを0へ戻して予告中は加算しない。予告完了時にその1件を公開してaccumulator=0から連続開封を再開する。「すべて開ける」の集約先バレは通常／4倍timerを破棄して別経路で全件を公開する。

### 3.7 装備、特性、名前

装備枠は MAIN_WEAPON、SUB_WEAPON、HEAD、BODY、HANDS、FEET の6つ。SUB_WEAPON は通常攻撃を行わず、特性とユニーク効果だけを提供する。

レアリティごとの通常特性数は Common=1、Rare=2、Epic=3、Legendary=4。ユニーク品は floor(通常特性数 / 2) とし、順に0、1、1、2。木の棒だけは Common かつ0特性の例外とする。同一アイテム内で同じ特性IDを重複させない。アイテムレベル、必要レベル、耐久度、売却価格は存在しない。

各特性スロットは、75%で部位固有プール、25%で共通プールから選ぶ。現在の主武器と好相性の特性は候補重みを2倍にする。loot生成では`wave_main_weapon_type` snapshot、合成では確定ボタンを押した時点の装備タイプを「現在」とする。好相性は BOW=attack_speed_pct / pierce、STAFF=cooldown_reduction_pct / area_pct、SWORD=area_pct / attack_speed_pct、UNCLASSIFIED=重み増加なし。

特性は affixes 配列の先頭から順に生成する。各枠で部位固有 / 共通を抽選し、すでに選ばれた affix_id を候補から除く。選んだ側の候補が空なら反対側へフォールバックする。候補は affix_id の辞書順に並べ、通常重み1、好相性重み2の累積重み抽選を行う。主要特性は affixes[0]、副特性は affixes[1] とする。

部位固有プール:

- MAIN_WEAPON: damage_pct、attack_speed_pct、cooldown_reduction_pct、area_pct、pierce
- SUB_WEAPON: damage_pct、max_hp、move_speed_pct、skill_power_pct
- HEAD: skill_power_pct、cooldown_reduction_pct、area_pct
- BODY: max_hp、damage_reduction_pct
- HANDS: damage_pct、attack_speed_pct、pierce、area_pct
- FEET: move_speed_pct、max_hp、damage_reduction_pct
- 共通: damage_pct、attack_speed_pct、cooldown_reduction_pct、area_pct、max_hp、damage_reduction_pct、move_speed_pct、skill_power_pct

特性値:

| 特性ID | Common | Rare | Epic | Legendary |
|---|---:|---:|---:|---:|
| damage_pct | +8% | +14% | +24% | +40% |
| attack_speed_pct | +8% | +14% | +24% | +40% |
| cooldown_reduction_pct | +6% | +10% | +16% | +24% |
| area_pct | +10% | +18% | +30% | +48% |
| pierce | +1 | +1 | +2 | +3 |
| max_hp | +10 | +18 | +30 | +50 |
| damage_reduction_pct | +5% | +9% | +15% | +25% |
| move_speed_pct | +6% | +10% | +16% | +25% |
| skill_power_pct | +10% | +18% | +30% | +50% |

ステータス演算順:

1. 武器、プレイヤー、スキルの基礎値
2. 装備特性の加算合計
3. ユニーク固有の乗算または条件変換を unique_id の昇順で適用
4. ダメージ軽減だけ0..100%へ clamp
5. 通常攻撃間隔を0.05秒以上、時間型スキル間隔を0.25秒以上へ clamp

派生値の式:

- damage_multiplier = (1 + damage_pct / 100) × 装備中ユニークの与ダメージ乗算。damage_pct は主攻撃、追加攻撃、スキルの全与ダメージへ適用し、スキルだけさらに (1 + skill_power_pct / 100) を掛ける。
- effective_attack_interval は、木の棒・弓・剣では `base_interval / max(0.01, 1 + attack_speed_pct / 100)`、杖では `base_interval × max(0, 1 - cooldown_reduction_pct / 100) / max(0.01, 1 + attack_speed_pct / 100)` とする。血塗れの短剣のキル加算は attack_speed_pct へ加え、臆病者の靴の停止時×2は分母へ最後に掛け、全武器で0.05秒へ clamp する。これにより杖はクールダウンと攻撃速度の両方、他武器は攻撃速度だけで通常攻撃間隔を短縮する。
- effective_move_speed = 5.0 × max(0, 1 + move_speed_pct / 100)。
- effective_max_hp = 100 + max_hp。装備は戦闘中に変更できず、各ウェーブ開始時にこの値まで全回復する。
- effective_area_multiplier = max(0.01, 1 + area_pct / 100)。杖の爆発半径、剣の射程、剣の角度、全スキルの半径へ掛ける。剣の角度だけ幾何上の上限360度へ clamp する。弓と杖の索敵射程、木の棒には適用しない。
- effective_pierce = pierce の整数合計。弓にだけ適用する。
- effective_time_skill_interval = base_interval × max(0, 1 - cooldown_reduction_pct / 100) に壊れた時計を適用し、最後に0.25秒へ clamp する。
- effective_damage_reduction_pct は不死者の胸当て以外の装備分を同品装備時だけ2倍にし、同品自身の通常特性分と合算して0..100へ clamp する。

クリティカル、回避、lifesteal、状態異常、ノックバック、乗算 area、距離による減衰は MVP に存在しない。

通常名は「主要特性の接頭辞 + 素材語 + 固定部位 / 武器種 + 副名」で作る。名前抽選は item_seed から派生した name RNG だけを使う。unique_idが空でない場合は生成名を作らず、3.9の固定名をdisplay_nameへ入れる。

- 接頭辞: damage_pct=猛撃の、attack_speed_pct=疾風の、cooldown_reduction_pct=時詠みの、area_pct=広天の、pierce=穿孔の、max_hp=巨命の、damage_reduction_pct=不落の、move_speed_pct=俊足の、skill_power_pct=星導の
- 素材語: 木、鉄、黒曜石、琥珀、白銀、竜骨、星晶、深紅鋼
- 固定語: UNCLASSIFIED=棒、BOW=弓、STAFF=杖、SWORD=剣、SUB_WEAPON=触媒、HEAD=兜、BODY=鎧、HANDS=手甲、FEET=靴
- 副名: 2番目の特性があれば同じ対応語から「破軍」「迅駆」「秒詠」「天蓋」「貫星」「長命」「城塞」「飛燕」「星火」を特性順に使う。2番目の特性がなければ item_seed により「萌芽」「余韻」「一閃」「静謐」から選ぶ。
- 表記例: 「疾風の白銀弓『貫星』」

Item ID は i-{run_seedの16桁小文字hex}-{waveの2桁}-{drop_serialの4桁}。Reward ID は r-{同じrun seed hex}-{waveの2桁}-{drop_serialの4桁}。drop_serial はラン全体で0から単調増加し、通常はRewardRoll生成と合成出力生成の直前に1つ確保する。装備RewardRollではreward_idとitem_idに同じ確保値を使い、スキルRewardRollではreward_idだけ、合成出力ではitem_idだけを作るため、1件で2回進めない。例外としてRunState初期化直後、W1開始前にdrop_serial=0を初期木の棒へ確保し、wave表記00の`i-{run_seed hex}-00-0000`、通常式のitem_seed、固定名「木の棒」でItemInstanceを作り、RewardRollは作らずdrop_serialを1へ進める。したがって最初の報酬または合成出力はserial 0001以降となる。スキル報酬、破棄したウェーブ報酬、廃棄品、合成消費品の番号を再利用しない。item_seed は SeedService.derive(run_seed, "item:" + item_id) で作り、loot RNGを追加消費しない。

### 3.8 インベントリと合成

- 通常インベントリは6列×6行、36枠。
- 36枠を超えた装備は無制限の一時受取欄へ置く。通常インベントリは常に最大36を守り、一時受取欄が空になるまで「次のウェーブ」または「結果へ」を無効化する。
- 装備中アイテムは6装備枠側にあり、36枠へ数えない。
- inventoryはindex 0..35の固定36要素で、空slotをnullとする。報酬反映時は公開順、すなわち acquired_tick 昇順・同tickでは reward_id 昇順で、空いているinventory indexの小さい順に入れ、残りを同じ順でoverflow末尾へ追加する。overflowはnullを持たない密な安定index列とし、全体を再ソートしない。装備交換で外れた品はドラッグ元と同じinventoryまたはoverflow indexを置換する。
- 廃棄、合成、装備、装備解除、並べ替えの各処理終了時にinventoryへ空きがありoverflowが残っていれば、overflow index 0からinventoryの最小空きindexへ自動補充し、空きまたはoverflowがなくなるまで繰り返す。overflowの品は互換装備枠へ直接装備できる。inventoryが満杯のまま任意のoverflow品をinventory品へドラッグした場合は2品の位置を交換する。overflow内の手動並べ替えはできない。
- ドラッグで互換装備枠へ装備、装備枠からインベントリへ戻す、インベントリ内で並べ替える。inventoryから装備する場合、外した装備はドラッグ元のinventory indexへ入る。overflowから装備する場合はドラッグ元のoverflow indexへ入る。空装備枠へ入れた場合、inventory元slotはnull、overflow元要素は削除して後続indexを1つ前へ詰める。SUB_WEAPON、HEAD、BODY、HANDS、FEETを単独で外す場合、inventoryの最小空きindexへ置き、空きがなければoverflow末尾へ入れる。MAIN_WEAPONはラン生成からRESULT / FAILEDまで常に非nullとし、MAIN_WEAPON同士の交換だけを許可する。主武器を単独で外す操作は状態不変で拒否し、「主武器は外せません。別の主武器と交換してください」と表示する。
- ホバーまたはフォーカスで、同じ部位の装備中アイテムとの差分を数値と上向き / 下向き形状で表示する。
- 各アイテムにロック切替を付ける。
- 自動選択は3.12のBulkSelectDialogで指定したレアリティだけを対象にし、装備中、ロック済み、ユニーク品を除外する。build_value 昇順、同値なら item_id 昇順に最大3個を`marked_item_ids`へ入れ、それ以前のmarkを置換する。候補0件なら空setにして「候補がありません」と表示する。
- build_value = rarity_index×100 + 通常特性数×20 + 現在タイプの好相性特性1つにつき10。rarity_index は Common=0、Rare=1、Epic=2、Legendary=3。
- インベントリと一時受取欄の未装備品は3.12のA1から無償廃棄できる。`marked_item_ids`が1件以上ならその全件、0件なら最後にfocusしたG/Oの1件を対象とし、どちらもなければA1をdisabledにする。装備中とロック済みは実行直前にも拒否する。対象にユニーク品が1つでもあれば対象名を全件列挙した確認を出し、「ユニークを含めて廃棄」を選んだ場合だけ実行する。成功または対象消失時はmarkを空にし、確認取消では維持する。
- 廃棄は装備、通貨、ワイルド素材、スコアを一切与えず、RNGも消費しない。廃棄済みアイテムは最終保持装備スコアに含めない。
- 合成材料は通常インベントリと一時受取欄を横断して選べる。確定時はinventory材料slotをnullにし、overflow材料はindex降順で削除する。次に合成出力をinventoryの最小空きindexへ置き、空きがなければoverflow末尾へ置く。その後だけ、残るinventory空きへoverflow index 0から順に3.8の自動補充を行う。これにより合成出力が古いoverflow品より先に、消費で生じた最小空きslotを得る。

合成規則:

- Common、Rare、Epic のいずれか同一レアリティ装備を3個消費し、1段階上の装備1個を必ず得る。
- ワイルド素材1個で、必要な装備材料のうち最大1個だけを代替できる。したがって2装備+1ワイルドは許可、1装備+2ワイルドは拒否する。
- Legendary は材料にも出力元にも指定できず、Legendary 3個の合成を拒否する。
- 出力レアリティ確定後にfusion RNGの`randf()`を正確に1回消費し、値が`< 0.04`ならユニーク、`>= 0.04`なら非ユニークとする。当選時はIDのordinal辞書順`bloodied_dagger, broken_clock, coward_boots, echo_gauntlet, hollow_crown, immortal_breastplate`を4.5のweighted selectorへ等重み6件で渡し、fusion RNGの`randf()`をさらに正確に1回消費して対応部位を出力する。非当選時だけ6部位を等確率で選び、MAIN_WEAPON のタイプは BOW / STAFF / SWORD を各1/3で選ぶ。
- 出力レアリティの特性数と名前生成を通常 loot と同じ順序で適用する。
- locked または equipped のアイテムは材料にできない。
- ユニーク品は自動選択しない。手動選択した場合は、固有効果と固定名が失われること、対象名を列挙した確認ダイアログを表示し、「ユニークを失って合成」を選んだ場合だけ消費する。
- 確定前のプレビューは材料名、出力レアリティ、「通常なら6部位ランダム／ユニーク率4%」だけを表示し、出力部位、武器タイプ、ユニークID、特性、名前は見せない。プレビュー表示にRNGを使わない。
- 材料検証とユニーク確認をすべて終えるまでfusion RNGを呼ばない。確認を取り消した場合は材料、ワイルド、drop_serial、fusion RNG stateを一切変えない。
- 合成結果は「ユニーク4% → 当選なら固定6種、非当選なら6部位 → 非ユニークMAIN_WEAPONならタイプ → 通常特性」の順でfusion RNGから確定し、名前だけはitem_seed由来のname RNGで生成する。UIアニメーションはRNGを消費しない。

### 3.9 固定ユニーク

| unique_id | 固定名 | 部位 | 固定効果 |
|---|---|---|---|
| bloodied_dagger | 血塗れの短剣 | SUB_WEAPON | 全与ダメージ×0.5。ウェーブ中のキル1回ごとに攻撃速度+1%。キル加算はウェーブ開始時0へ戻す |
| broken_clock | 壊れた時計 | SUB_WEAPON | スキル与ダメージ×0.5。時間条件×0.5、整数条件は ceil(基礎値×0.5)。6秒→3秒、8攻撃→4、15キル→8、5被弾→3 |
| coward_boots | 臆病者の靴 | FEET | `distance(previous_clamped_position, current_clamped_position) / physics_delta` で得た実移動速度が0.05m/s超の間と、実移動停止直後0.25秒は通常攻撃と全スキルの進捗・発動を停止。停止0.25秒後に与ダメージ×3、攻撃速度×2で再開し、待機分の一括発動はしない。再移動で即解除。境界へ入力し続けても座標が動かなければ停止扱い。装備の有無を問わず各wave開始時のstationary elapsedは0で、装備中なら最初の15tickも停止待機になる |
| immortal_breastplate | 不死者の胸当て | BODY | 全与ダメージ×0.5。この品自身を除く装備の damage_reduction_pct を2倍にし、最終値100%まで許可 |
| echo_gauntlet | 反響の手甲 | HANDS | 一次の主攻撃3回ごとに0.15秒後、同じ攻撃種、ダメージ snapshot、照準方向を現在のプレイヤー位置から等倍で再演 |
| hollow_crown | 空洞の王冠 | HEAD | 第2スキル枠を封印。第1スキル発動時、0.15秒後に同じ威力で再度発動。2回目は対象を再選定 |

反響の手甲をHANDSへ装備した瞬間に`echo_progress_item_id`をそのitem_id、`echo_primary_attack_progress=0`とする。装備中に生成まで成立した一次主攻撃だけを1加算し、3へ達した攻撃のsnapshotから再演を1件予約して3を減算する。空振りで主攻撃自体を生成しなかったtick、反響再演、スキル攻撃は加算しない。同じitem_idをHANDSへ装備し続ける限りウェーブ間でも0..2の値を保持する。そのitemがHANDSを離れた瞬間、別itemへ交換した瞬間、ラン終了、同seed／新seed再挑戦ではprogressを0、progress_item_idを空へ戻す。外した同じitemを後で再装備しても0から始める。反響の手甲による再演は一次主攻撃数へ加算せず、千刃陣の攻撃数条件も進めない。空洞の王冠を装備した時点で第2枠のスキルは失われず、equipped_slot=-1としてライブラリへ戻す。王冠を外しても自動再装着はせず、インベントリ画面で選び直す。王冠による2回目は当該スキルの条件を進めない。

連鎖判定では、解決する武器・スキル内容を `source_effect_id`、二次イベントを生成したprocを `proc_effect_id` として分離する。一次の主攻撃はprocが空、chainも空である。条件から通常発動したスキル攻撃は`source_effect_id=skill:<skill_id>`、`proc_effect_id=skill:<skill_id>`とし、生成時に自身のproc IDをchainへ追加する。`effect_chain`には発動済みproc IDだけを順に保持する。procが二次イベントを生成する直前に、自身のproc IDが親のeffect_chainにあれば生成を拒否し、なければコピーへ自身のIDを追加する。payloadのsource IDが履歴へ現れていることだけでは拒否しない。反響は同じ主攻撃payload、`proc_effect_id=unique:echo_gauntlet`、`is_primary=false`、空洞の王冠は同じスキルpayload、`proc_effect_id=unique:hollow_crown`、`is_primary=false`として各1回の再演を成立させる。両者の0.15秒予約は生成時に親chainをコピーして自身のproc IDを追加し、9 physics tick後までそのchainとdamage snapshotを`ScheduledProcReplay`に保持する。反響では弓と剣は元direction、杖は元directionとaim_distance、木の棒は元target_entity_idを保存する。実行時は現在のプレイヤー位置を起点とし、弓は元directionへ14m、剣は元directionの扇形、杖は現在位置から元direction×aim_distanceの点へ飛ばし、木の棒は元targetが生存かつ1.8m内なら同targetへ当て、それ以外は空振りとする。王冠は元のtarget情報を使わず実行時に通常規則で再選定する。実行時に空chainから作り直さない。異なるprocのキル・被弾条件は進むためA→Bは許可し、BからAを再度生成するA→B→AはAが履歴にあるため拒否する。技術保護としてchain_depthが16のイベントから新しい二次イベントを生成せず、debug counterを1増やす。この深度上限へ通常プレイで到達したテストは失敗とする。

王冠のScheduledProcReplayは、臆病者の靴で停止中の場合だけ3.10どおり保留し、それ以外はdue tickに1回試行して必ずqueueから除去する。星落としと魂の連鎖はdue時に有効敵0ならダメージイベントを作らず空振りとして消費する。千刃陣と報復の鐘はプレイヤー中心の範囲イベントを作り、命中0でも消費する。通常SkillStateのpending_queueへ戻したり、対象出現まで保持したりしない。

### 3.10 スキル

スキルはskill_idごとに唯一のSkillStateをラン内ライブラリへ最大4種類保持し、装着枠は2つ。ライブラリUIは装着中も含む所持SkillStateを3.10表順で常時表示し、装着枠は同じstateのskill_id参照だけを持つため、同じskillを2枠へ重複装着できない。未所持スキルを得たとき、封印されていない空き枠だけを候補にして番号の小さい枠へ自動装着し、なければ未装着でライブラリへ置く。空洞の王冠中の第2枠は空でも候補外なので、第1枠が空なら0、使用中なら-1となる。ライブラリから装着枠へ配置すると、そのskillが別枠へ装着済みなら2枠の内容を交換し、未装着なら対象枠の旧skillを未装着へ戻して置き換える。装着枠から別の装着枠への配置も2枠を交換し、自分自身への配置はno-opとする。装着枠から同じskill_idのライブラリカードへ戻すと未装着になり、別skillのライブラリカードへは配置できない。インベントリ画面でマウスドラッグまたは3.12のA持上げ／配置、B取消を使う。重複取得は装着状態にかかわらず Lv3 まで自動昇格し、Lv3 の重複はワイルド素材1個へ変換する。ワイルド素材はインベントリ枠を消費しない。

全skill操作は純粋`SkillEquipService.apply_move(source_kind, source_id, target_kind, target_id)`を通し、成功時もlevel、trigger_progress、pending_queueを変更しない。`equipped_slot`は未装着=-1、第1枠=0、第2枠=1とし、遷移を次へ固定する。catalog card自体はalias表示なので配置後も消えない。

| 持上げ元 | 配置先 | 結果 |
|---|---|---|
| 未装着catalog A | 空slot j | A=j |
| 未装着catalog A | Bが入るslot j | A=j、B=-1 |
| slot i装着済みcatalog A | 同じslot i | no-op |
| slot i装着済みcatalog A | 空の別slot j | A=j、slot iを空にする |
| slot i装着済みcatalog A | Bが入る別slot j | A=j、B=i |
| Aが入るslot i | 空の別slot j | A=j、slot iを空にする |
| Aが入るslot i | Bが入る別slot j | A=j、B=i |
| Aが入るslot i | A自身のcatalog card | A=-1、slot iを空にする |
| 空slot | 任意 | 持上げを開始せずno-op |
| 任意skill | 別skillのcatalog card、またはcatalog card同士 | 拒否して状態不変 |

B取消は持上げ開始直前の全skill `equipped_slot` snapshotへ戻す。空洞の王冠で第2枠が封印される時は、そこにいたskillを先に-1へ戻してからK1をdisabledにする。

| skill_id | 表示名 | 条件 | Lv1 | Lv2 | Lv3 |
|---|---|---|---|---|---|
| starfall | 星落とし | 6秒ごと | 最密集地点へ威力45、半径2.5m | 威力75、半径3.0m | 威力115、半径3.5m |
| thousand_blades | 千刃陣 | 一次主攻撃8回ごと | 全周威力30、半径3.0m | 威力48、半径3.5m | 威力72、半径4.0m |
| soul_chain | 魂の連鎖 | キル15回ごと | 威力24、4対象 | 威力38、6対象 | 威力56、9対象 |
| bell_of_retribution | 報復の鐘 | 被弾判定5回ごと | 周囲威力36、半径2.5m | 威力58、半径3.0m | 威力86、半径3.5m |

星落としの「最密集地点」は、そのphysics tickの開始enemy snapshotに含まれて現在も生存するtargetable enemyを1体以上含むoccupied cellだけを候補とし、そのセルと境界内の隣接8セルにいるtargetable enemy総数を比較する。最大候補が複数ならセルキー昇順を選び、勝った3×3近傍にいる全targetable enemyをentity_id昇順で加算した平均XZを照準点とする。有効対象0では3.10の予約保持規則を使うため平均を計算しない。魂の連鎖はtargetable enemyをプレイヤーに近い順、同距離なら entity_id 昇順で選ぶ。

スキルの最終威力は `表の基礎威力 × (1 + damage_pct / 100) × (1 + skill_power_pct / 100) × 装備中ユニークの全与ダメージ乗算 × スキル固有乗算` とする。壊れた時計のスキル威力×0.5は最後のスキル固有乗算で適用する。cooldown_reduction_pct は時間型の星落としと杖の主攻撃だけに適用し、星落としの実効間隔は `6 × max(0, 1-cooldown_reduction_pct/100)`。整数条件型スキルには適用しない。壊れた時計はこの演算後の時間をさらに0.5倍し、最後に0.25秒へ clamp する。

キル条件と血塗れの短剣は通常、召喚、エリート、ボスのすべての敵死亡を1回として数える。ただしCombatEventのeffect_chainに`skill:<skill_id>`が含まれる場合、そのイベントが生んだキル／被弾は同じskill_idのtrigger_progressを進めず、chainに含まれない別スキルの進捗だけを進める。血塗れの短剣は攻撃を生成するprocではないため全キルを数える。進捗を加えた後、`trigger_progress >= effective_threshold`の間は閾値を減算し、閾値を越えさせた入力ごとに`PendingSkillActivation`をFIFOへ追加する。同じ入力で複数回越えた場合はactivation_serial昇順で複数件を追加する。キル／被弾由来は原因CombatEventのeffect_chainとevent_serialを各予約へコピーし、時間／一次主攻撃由来と壊れた時計の閾値正規化由来は空chain、origin_event_serial=-1とする。予約があり有効対象もある場合は、各スキルにつき1 physics tickにFIFO先頭を最大1件だけ発動する。ここで「有効対象」はそのphysics tickの開始enemy snapshotに含まれ、現在も生存するtargetable enemy、「対象0」はその件数0を指す。手順3で当tickにspawnした敵しかいない場合はactive countが1以上でも全4種の通常PendingSkillActivationと剰余を保持し、次tickのsnapshotへ入った後から1回ずつ解決する。発動時は保持したchainを親として`skill:<skill_id>` procを追加し、成功時だけ予約を取り除く。未装着スキルは進捗を増やさないが既存値を保持し、再装着後に続行する。trigger_progressと予約FIFOはREWARD_REVEAL / INVENTORY中およびウェーブ間でも保持し、ラン終了または再挑戦時だけ空へ戻す。壊れた時計の着脱で閾値が小さくなった場合は、次COMBAT開始直前に同じwhileで剰余と空chain予約を正規化する。臆病者の靴で移動中および停止後0.25秒の待機中は、既存進捗と予約を保持したまま主攻撃、全スキルの時間加算、event加算、予約発動を停止する。0.25秒経過時に再開し、待機時間分をまとめて加算しない。

同じ進捗入力を複数スキルへ配る順は3.10表の`starfall, thousand_blades, soul_chain, bell_of_retribution`順とし、この順でactivation_serialを割り当てる。各physics tickの攻撃解決順は、(1) 時間条件の進捗加算、(2) due済みScheduledProcReplayをschedule_serial昇順で1件ずつ解決、(3) tick開始時から存在する味方飛翔物の命中をpool index・同弾内entity_id昇順で解決、(4) 準備済み主攻撃を最大1回生成して一次攻撃条件を加算し、その攻撃を解決、(5) この時点の全SkillStateのFIFO先頭をsnapshotし、activation_serial昇順で各スキル最大1件を解決、(6) 予告1.20秒を完了しsourceがまだ生存するELITE範囲攻撃をsource entity_id昇順、敵接触をsource entity_id昇順、tick開始時から存在する敵弾の命中をprojectile pool index昇順で解決し、最後に手順2でreadyになりsourceがまだ生存する非召喚特殊行動をsource entity_id昇順で生成する、とする。非召喚特殊行動はELITEなら現在のプレイヤー位置を中心に新しい予告を開始、RANGEDなら現在のプレイヤー位置へ1発、BOSSなら角度index 0..11の順に12発をpoolへ確保する。同一sourceが複数種類を持つ場合の補助順は`ELITE予告開始, RANGED射撃, BOSS弾幕`だが、現行敵定義では重複しない。BOSS召喚は手順3ですでに解決済みでここへ含めない。実行を試みたready timerはpool確保成否にかかわらず0へ戻し、確保失敗はpool overflowとして当該ゲートを不合格にする。このtickに開始したELITE予告は次tickから予告timerを進め、このtickに生成した弾は次tickまで移動・命中しない。sourceが途中で死亡した特殊行動と進行中ELITE予告は取り消し、timer resetや弾生成を行わない。各CombatEventのevent_serialはこの解決順で生成直前に割り当てる。(5)または(6)で新たにできたスキル予約は次physics tickまで発動候補にしない。各eventのdamage、死亡確定、kill条件を解決して死亡entityを除外してから次eventへ進む。loot候補だけはtick末まで保持し、3.6どおり死亡entity_id昇順で抽選した後にquotaラッチへ進む。

臆病者の靴で攻撃停止中にdueとなったScheduledProcReplayは削除せず、due順を保って停止解除後の最初のphysics tickから上記(2)で解決する。COMBATからREWARD_REVEAL、FAILED、INVENTORY、RESULT、TITLEのいずれかへ出る時は未解決のScheduledProcReplayをすべて破棄し、次waveへ持ち越さない。retryとラン終了でも必ず空へ戻す。

### 3.11 スコア

スコアは整数で、次を単純加算する。

- 通常敵とボス召喚の撃破1回10点。
- wave_cleared が true になった後の敵撃破1回につき追加10点。ELITE / BOSS も含む。
- エリート撃破300点。通常キル10点は重ねない。
- ボス撃破1,500点。通常キル10点は重ねない。
- クリアしたウェーブ1つ500点。
- W8クリア2,000点。
- 最終的に保持している装備: Common 30、Rare 105、Epic 360、Legendary 1,260点。装備中とインベントリ内を含み、破棄済みと合成消費済みは含めない。
- 保持装備のユニークタグ1つ600点。
- ライブラリに保持する全スキルのレベル合計×100点。装着・未装着を問わない。
- 未使用ワイルド素材1個100点。

W8後はoverflowを空にしてから完走スコアを確定する。FAILEDでは失敗ウェーブのRewardRollを破棄した後、過去ウェーブから保持している装備、スキル、ワイルド素材と、その時点までに確定した戦闘点だけで途中スコアを算出する。

比率検証では、キル、ノルマ後追加、エリート、ボス、ウェーブクリア、ランクリアを「戦闘由来」、装備レアリティ、ユニーク、スキル、ワイルドを「最終ビルド由来」と分類する。

検算用固定例: 通常敵100体、エリート1体、ボス1体、ノルマ後撃破20体、8ウェーブクリア、ランクリア、Common/Rare/Epic/Legendaryを各1個保持、ユニーク1個、スキルレベル合計5、ワイルド2個なら12,055点。

結果画面には seed、cleared_waves、総撃破数、ノルマ後撃破数、獲得箱数、合成回数、最高DPS、最終装備6枠、装着スキル2枠、スコア内訳、合計を表示する。RESULTとFAILEDの両方で、3.11の分類による戦闘由来小計を`combat_score`、最終ビルド由来小計を`final_build_score`として明記し、両者の和が表示合計と一致する。FAILEDはこれに失敗waveも表示する。最高DPSは敵HPを実際に減らした量だけを、physics_tickとevent_serial付きのrecent_damage_samples dequeへ記録して算出する。各damage event解決後、`sample.physics_tick < current_physics_tick - 60`の要素を先頭から除き、閉区間`[current_tick-60, current_tick]`の合計を更新してラン中のpeak_dps最大値を保持する。同tickはevent_serial昇順で加算する。overkill分は含めず、100ms丸めは行わない。COMBATから出る時点でdequeだけを空にし、peak_dpsはラン終了まで保持するため、非戦闘画面を挟んだ別waveのdamageを同じ1秒窓へ合算しない。

### 3.12 入力契約

戦闘中にゲーム結果へ作用する入力は `move_up / move_down / move_left / move_right` だけである。WASD、矢印キー、左スティックをこの4 actionへ割り当てる。戦闘中は `ui_accept`、`ui_cancel`、`item_lock`、`reward_open_all`とマウスクリックをゲーム操作として受理せず、手動攻撃、照準、スキル、ダッシュ、ポーズを実装しない。

TITLE、REWARD_REVEAL、INVENTORY、RESULT、FAILED、設定画面では次へ固定する。

- フォーカス移動: 矢印キー、方向パッド、左スティック。`ui_up / ui_down / ui_left / ui_right`を使う。
- 選択、決定、アイテムの持ち上げ／配置: Enter、ゲームパッドA、またはマウス左クリック。`ui_accept`を使う。
- 取消、持ち上げ中アイテムを元位置へ戻す: EscまたはゲームパッドB。`ui_cancel`を使う。
- フォーカス中アイテムのロック切替: LまたはゲームパッドX。`item_lock`を使う。
- 報酬の「すべて開ける」: FまたはゲームパッドY。`reward_open_all`を使う。
- マウスではアイテムを左ドラッグして配置または交換できる。コントローラーではAで持ち上げ、フォーカス移動後にAで配置または交換、Bで取消を行い、同じ結果へ到達する。
- 装備比較はアイテムをホバーまたはフォーカスした時点で自動表示する。一括選択、単品／一括廃棄、合成確定、ワイルド素材投入、次戦、結果遷移はすべてフォーカス可能なボタンとし、Aだけで実行できる。
- REWARD_REVEALで`ui_accept`を押し続けると4倍速、`reward_open_all`で全開封する。単押しで乱数や順序を変更しない。
- 設定ボタンはTITLE、REWARD_REVEAL、INVENTORY、RESULT、FAILEDに置く。設定画面は元のphaseを保持するoverlayとし、表示中は開封タイマーを停止し、閉じると同じ位置から再開する。戦闘中には設定画面を開けない。

`FocusController`を1つ置き、全focusable Controlへ固定`focus_id`と明示的な`focus_neighbor_top / bottom / left / right`を設定する。Godotの自動neighbor推定へ依存しない。新しい画面を表示したframeの末尾で表の初期要素へ`call_deferred("grab_focus")`し、設定overlayまたは確認dialogを開く直前には起点`focus_id`を保存する。閉じた後は同じ要素がvisibleかつenabledならそこへ、そうでなければ元画面の初期要素へ戻す。新phaseへ遷移した場合は復元せず、新画面の初期要素を使う。neighbor先がhiddenまたはdisabledなら同じ方向の固定neighborを最大登録数までたどり、最初の有効要素へ移る。有効要素がほかにない場合だけ自分自身へ戻す。

| 画面 | 初期focus | 固定focus順・neighbor |
|---|---|---|
| TITLE | `title_start` | 縦順`title_start, title_settings, title_exit`。上下は循環、左右は自分自身 |
| REWARD_REVEAL | `reward_speed_proxy` | 横順`reward_speed_proxy, reward_open_all, reward_settings`。左右は循環、上下は自分自身 |
| INVENTORY | `equip_0`（MAIN_WEAPON） | 下記の空間規則 |
| RESULT | `result_retry_same_seed` | 縦順`result_retry_same_seed, result_retry_new_seed, result_title, result_exit, result_settings`。上下は循環、左右は自分自身 |
| FAILED | `failed_retry_same_seed` | 縦順`failed_retry_same_seed, failed_retry_new_seed, failed_title, failed_exit, failed_settings`。上下は循環、左右は自分自身 |
| 設定overlay | `settings_master` | 縦順`settings_master, settings_music, settings_sfx, settings_reduce_motion, settings_reduce_flashes, settings_vibration, settings_tutorial_again, settings_close`。上下は循環。3 sliderは左右で1ずつ値を変えてfocusを維持し、それ以外の左右は自分自身 |
| 確認dialog | `dialog_cancel` | 横順`dialog_cancel, dialog_confirm`。左右は循環、上下は自分自身。Bはcancelと同じ |

INVENTORYでは装備枠をenum順`E0..E5`、36枠を行優先`G[row,column]`、一時受取欄を`O0..O(n-1)`、操作列を`A0..A5 = 一括選択, 廃棄, 合成, ワイルド投入, 次戦／結果へ, 設定`、スキル列を`K0..K5 = 装着slot 0, 装着slot 1, library catalogのstarfall, thousand_blades, soul_chain, bell_of_retribution`とする。K2..K5は装着状態にかかわらず所持中ならvisibleとし、装着中badgeを表示する。E、各G行、O、A、Kの左右はそれぞれ同じ列内で循環する。`E[c]`の下は`G[0,c]`、上は`K[c]`。Gの上は同列の前行、row 0だけ`E[c]`、下は同列の次行、row 5だけoverflowがあれば`O[min(c,n-1)]`、なければ`A[c]`。`O[i]`の上は`G[5,min(i,5)]`、下は`A[min(i,5)]`。`A[i]`の上はoverflowがあれば`O[min(i,n-1)]`、なければ`G[5,i]`、下は`K[i]`。`K[i]`の上は`A[i]`、下は`E[i]`とする。libraryに未所持のskillはhidden、空洞の王冠装備中のK1はdisabledとし、overflow 0件、ワイルド0個、overflow未整理による次戦disabledを含め共通のskip規則で処理する。K0/K1とvisibleなK2..K5はAでskillを持ち上げ、別Kへ移動してAで3.10どおり配置、交換、未装着化、またはno-opとし、Bで元位置へ戻す。K1が操作途中でdisabledになった場合も持上げ状態をcancelして元位置へ戻し、直前の有効focusへ復帰する。比較パネルと説明文はfocusableにしない。

O列は固定幅144px、間隔8pxのcardを横1列に置く904px幅の横ScrollContainerとし、同時に6件を完全表示する。件数に上限を置かず、Oへfocusが移るたびに同じframeのlayout後、描画前に対象cardの左右端がviewport内へ完全に入る最小scroll値へ更新する。O0で左を押すと末尾、末尾で右を押すとO0へ循環し、循環後もfocus cardを完全表示する。scrollbar自体はfocusableにせず、マウスwheelとdrag scrollは許可する。overflow 40件でO0から左右両方向に全40件へ到達し、O39→O0も含め各focused cardのglobal rectがviewport rect内に完全包含されることを固定testにする。

通常INVENTORYのA0「一括選択」はBulkSelectDialogを開く。dialogは`bulk_common, bulk_rare, bulk_epic, bulk_legendary, bulk_cancel`の縦循環、左右selfとし、初期focusは最後にfocusしたG/O itemのレアリティ、該当itemがなければ`bulk_common`とする。レアリティをAで決定すると3.8の自動選択で`marked_item_ids`を置換し、A0へ戻る。Bまたはcancelはmarkを変えずA0へ戻る。G/Oへfocusするたび`last_item_focus_id`を更新し、A1「廃棄」は3.8のmark優先規則を使う。A3「ワイルド投入」はwild 0ならdisabled、1以上なら下記FusionDialogを`use_wild=true`で開くshortcutであり、A2「合成」は`use_wild=false`で開く。dialogを開く時にbulk markを空にし、初期レアリティはlast itemがCommon / Rare / Epicならその値、それ以外はCommonとする。

FusionDialogはレアリティselector `FR`、材料slot `F0..F2`、元のG/O item群、操作`FA0..FA3 = 自動投入, ワイルド切替, 確定, 取消`で構成し、E/A/Kはmodal中focus不可にする。初期focusはFR。FRは左右でCommon→Rare→Epicを循環してfocusを維持し、上=FA3、下=F0。Fは左右循環、上=FR、下はF0/F1/F2からそれぞれG[0,0]/G[0,2]/G[0,4]。Gは通常の行内左右と上下を使うがrow 0の上を`F[min(floor(column/2),2)]`、row 5の下をoverflowありなら`O[min(column,n-1)]`、なしなら`FA[min(column,3)]`とする。Oは3.12のscroll規則を維持し、上=`G[5,min(i,5)]`、下=`FA[min(i,3)]`。FAは左右循環、上はoverflowありなら`O[min(i,n-1)]`、なしなら`G[5,min(i,5)]`、下=FR。F0..F2とFA0/FA3は常にenabled、FA1はwild 1以上、FA2は下記valid時だけenabledとし、共通skip規則を使う。

FusionDialog中、G/OのAはitem持上げではなく材料toggleになる。選択レアリティと一致し、Common / Rare / Epicで、未装備かつunlockedのitemだけをitem_idでFの最小空slotへ参照追加し、uniqueは手動なら許可する。選択済みG/Oまたは埋まったFをAで決定するとその参照を外し、item本体は確定まで元slotへ残す。レアリティ変更はFを空、`use_wild=false`へ戻し、run state、RNG、wild数を変えない。FA1はwild 1個の予約だけをtoggleし、false→trueでFが3件ならF2を外す。必要item数はwild falseで3、trueで2。FA0はFを空にして、選択レアリティのeligible非unique品をbuild_value / item_id順に必要数まで入れ、候補不足なら入る件数だけを表示して不足数を文字表示する。FA2はFが必要数ちょうど、全参照が有効、wild予約分が現存する時だけenabledにし、非RNG previewを表示する。uniqueが1件以上なら標準確認dialogへ全対象名を列挙し、取消でFA2へ戻って無変更、承認後だけFusionServiceを1回呼ぶ。成功時は材料と予約wildを消費して3.8どおり出力を置き、dialogを閉じA2へfocusする。BまたはFA3は材料参照とwild予約を破棄し、run stateと全RNGを変えずA2へ戻る。マウスはG/OからFへのdragで追加、Fからdialog内の材料外領域へのdragで解除し、同じvalidationと結果を使う。

REWARD_REVEALの`reward_speed_proxy`はButtonではないfocusable Controlとし、現在カードと「長押し4倍」ラベルを覆う1つの矩形に置く。`reward_open_all`と`reward_settings`の矩形とは重ねない。この要素だけが`ui_accept`のpress/releaseを消費し、`HOLD_THRESHOLD_SECONDS=0.25`到達後からreleaseまで4倍開封を有効にする。releaseで別操作を発火しない。`reward_open_all`と`reward_settings`にfocusがある時は0.25秒未満のA releaseだけをbutton決定として扱い、0.25秒以上保持したAは4倍化もbutton activationもせず消費する。マウス左はproxy内でpressした場合だけpointer captureし、同じ0.25秒後から4倍化し、内外どこでreleaseしても解除してclickを発火しない。2つのbutton上で始めたマウス左入力は通常clickだけを行い、保持時間にかかわらず4倍化しない。Yの全開封はREWARD_REVEAL内のどのfocusからでも受理する。これにより長押し後に設定overlayや全開封buttonが意図せず発火する競合を作らない。

## 4. 技術設計と内部契約

### 4.1 固定アーキテクチャ

- Godot 4.7.2-stable Standard、GDScript、Compatibility renderer。
- 物理 tick は60Hz。戦闘ロジックは _physics_process だけで進め、描画補間は見た目にだけ使う。
- 秒数timerは純粋`TimerMath`へ統一し、`TIME_EPSILON_SECONDS=0.000000001`を使う。武器、敵、スキル、予告、チュートリアル、臆病者停止判定の単発／満タン保持timerでは、`advance_clamped(elapsed, interval, delta)`が`next=min(interval, elapsed+delta)`を求め、`next >= interval - TIME_EPSILON_SECONDS`なら正確なinterval値、未満ならnextを返す。`is_ready(elapsed, interval)`も`elapsed >= interval - TIME_EPSILON_SECONDS`だけで判定する。発動時の0 reset、対象不在時の満タン保持は各仕様に従う。countdownは`next=max(0, remaining-delta)`とし、`next <= TIME_EPSILON_SECONDS`なら正確な0へ置換する。報酬の通常／4倍連続開封だけは`consume_repeating(accumulator, interval, delta, max_events=16)`を使う。この純粋関数はaccumulatorへdeltaを加え、`accumulator >= interval - epsilon`の間、1frame最大16回までintervalを減算してevent数と非負の剰余を返す。16回へ達しても余剰時間を捨てず、次frameへ保持する。個別先バレ開始時は3.6どおりaccumulatorを0へ戻す。全秒数counterで浮動小数の直接`==`を使わない。physics timerの固定試験は0.05=3、0.25=15、0.75=45、0.80=48、0.90=54、1.20=72、1.50=90、1.80=108、3=180、4=240、6=360、60=3,600 tickで初回readyになることを要求する。repeating timerはdelta=1/60、interval=0.35で21tickに1件・剰余0、interval=0.0875で21tickに4件・剰余0となり、1frameへ2秒を与えると16件を返して残余0.6秒を次frameへ保持することを要求する。
- 静的定義は Resource と .tres、ランタイム状態と計算サービスは RefCounted の純粋ロジック、画面と描画は Node と Scene に分離する。
- GameApp が RunState と画面遷移を所有する。SettingsStore だけを Autoload とし、ラン状態を Autoload に置かない。SettingsStoreの`_enter_tree()`と`_ready()`はfield初期化以外を行わず、fileの存在確認、作成、読込、書込を一切行わない。初期状態は`initialized=false`、`runner_safe_mode=false`、`active_settings_path=""`とする。通常main sceneではGameAppが全引数を検証した後、runnerではtest runnerがrunner-local引数を検証した後に、SettingsStoreを明示的に一度だけ初期化する。file-backedの`initialize_for_game()`、`initialize_for_runner()`と、既定値をmemoryへ入れるだけの`initialize_ephemeral()`は相互排他的で、いずれも2回目の呼出しを拒否する。
- UI は RunState のコピーを直接変更せず、GameApp の command メソッドを呼ぶ。GameApp は結果を signal で通知する。
- `debug/file_logging/enable_file_logging`とplatform overrideの`debug/file_logging/enable_file_logging.pc`をともにfalse、`rendering/shader_compiler/shader_cache/enabled`もfalseへ固定し、`user://logs/godot.log`や`user://shader_cache`内fileを含む実行時ログ／cacheを作らない。標準出力／標準エラーは5.2の外部process loggerだけがrepositoryのartifactsへ取得する。
- 通常main sceneのGameAppが受理するDebug/test専用user引数は`--evidence`、`--qa-scenario`、`--settings-path`、`--smoke-quit`、`--performance`、`--run-seed`の6種とし、`OS.is_debug_build()`がtrueの時だけ受理する。GameAppは最初の処理として`OS.get_cmdline_user_args()`を重複、値欠落、未知option、組合せまで全件検証する。通常の引数なし起動と検証済みDebug/test main sceneはSettingsStoreの`initialize_for_game(validated_settings_path)`を1回呼び、Releaseの`--smoke-run`だけは`initialize_ephemeral()`を呼んでfile I/Oなしの既定値を使い、`--release-pack-audit`はSettingsStoreを未初期化のまま実行する。`--script res://tests/test_runner.gd`で起動した独自SceneTreeではmain sceneとGameAppは生成されないが、Godot 4.7.2の起動順によりAutoloadのSettingsStoreは生成される。test runnerはtest列挙前に`OS.get_cmdline_args()`を調べ、`--script`の直後が完全一致で`res://tests/test_runner.gd`であることと、`OS.get_cmdline_user_args()`が重複なしの`--suite <unit|scenario|simulation|all>` 1組と`--settings-path=<絶対path>` 1個だけであることを検証する。解決後のsettings pathが当該Gateの`artifacts/gate-NN/test-user/`配下なら、既存の`/root/SettingsStore`へ`initialize_for_runner(validated_settings_path)`を1回だけ呼ぶ。このmethodだけが`initialized=true`、`runner_safe_mode=true`、`active_settings_path=validated_settings_path`へ変更してそのfileを唯一の設定入出力先にする。runner引数が不正ならSettingsStoreを未初期化のまま維持し、実ユーザー設定を含む全file I/Oを行わず、`RUNNER_ARGUMENT_REJECTED name=<最初の不正引数またはmissing>`を1行出して終了コード2とする。runnerはSettingsStoreを別instance化せず、GameApp parserも呼ばない。通常Debug/testのGameAppはrunner-localな`--suite`を拒否する。3つのinitialize methodの2回目呼出しはI/Oせずエラーとし、debug/testでは呼出し側を失敗させる。Windows Releaseにはtests、src/debug、scenes/debug、outputs、docsをexportしない。Releaseのuser引数parserは、引数なしの通常起動、単独の`--smoke-run`、または単独の`--release-pack-audit=<絶対manifest path>`だけを受理する。Debug/test専用引数、runner-local引数、未知引数、重複、または複数optionの組合せは、RunState生成、SettingsStore初期化、設定読書き、画面遷移より前に標準出力へ`RELEASE_ARGUMENT_REJECTED name=<引数名>`を1行出し、終了コード2で拒否する。許可された2つの保守用引数は通常UIから到達できない。pack auditはPCK内の全`res://` pathをordinal辞書順でmanifestへ書き、manifestが1件以上、禁止prefix 5種が0件、`ResourceLoader.load("res://scenes/main.tscn") is PackedScene`、かつ`ResourceLoader.load("res://data/balance/balance_manifest.tres") is BalanceManifest`の場合だけ`PACK_AUDIT_OK paths=<件数> required=2 forbidden=0`を1行出して終了0とする。manifestが空、禁止prefixが1件以上、必須resourceがnullまたは型不一致なら終了3、出力pathが不正なら終了2とする。

Debug/test main sceneで受理するuser引数の完全な組合せは次だけとし、表にない組合せ、同option重複、値欠落、未知optionは終了2とする。引数なしは通常debug起動としてuser://settings.cfgを使う。表の全自動起動は`--settings-path`必須であり、`--run-seed`はperformance専用、`--settings-path`単独は拒否する。

`scenes/main.tscn`はGameApp root 1 Nodeだけを持ち、起動時の子Nodeを置かない。GameAppは`_enter_tree()`で上記parserを実行し、有効時だけ対応するSettingsStore初期化を完了してからTITLE、driver、またはaudit用の最初の子sceneをinstantiateする。Debug/testの拒否では子Node、RunState、設定fileを0件のまま`DEBUG_ARGUMENT_REJECTED name=<最初の不正引数またはmissing> child_nodes=0 run_state=0`をexact 1行出して終了2とする。これにより子UIの`_ready()`が引数検証や設定初期化へ先行しない。

| 用途 | 許可するuser引数集合 |
|---|---|
| 通常debug | 引数なし |
| evidence | `--evidence=<gate_XX:scenario>` + `--settings-path=<絶対cfg>` |
| QA scenario | `--qa-scenario=<fixture_id>` + `--settings-path=<絶対cfg>` |
| debug exported smoke | `--smoke-quit=<1以上の整数physics frames>` + `--settings-path=<絶対cfg>` |
| performance | `--performance=full_hd_500_2000` + `--run-seed=5002000` + `--settings-path=<絶対cfg>` |

Release pack auditの出力先は任意pathにしない。`OS.get_executable_path().get_base_dir()`を正規化したdirectoryが末尾`build/windows`であることをcase-insensitiveに確認し、その2階層上をrepository rootとして、唯一の許可先を`<repository root>/artifacts/gate-06/release-pack-manifest.txt`へ算出する。user引数は絶対pathでなければならず、`simplify_path()`後にこの許可先とcase-insensitiveで完全一致し、親`artifacts/gate-06`が既存directoryである場合だけ開く。directoryは作らない。不一致、親欠落、実行位置不一致はmanifestその他のfileを開く前に`RELEASE_ARGUMENT_REJECTED name=--release-pack-audit`をexact 1行出して終了2とする。既存のexact manifest fileだけはWRITE modeで置換してよく、他fileを上書きしない。

- 戦闘中の敵、敵弾、味方弾、短命VFXは密な配列、固定容量プール、MultiMeshInstance3D で保持する。
- 味方／敵飛翔物は共有4096 slotのindex 0..4095を使い、確保時はその瞬間のinactive slotで最小indexを必ず選ぶ。各slotに0開始のgeneration counterを持ち、確保直前に1増やす。tick開始snapshotは`(pool_index, generation)`の値コピーであり、移動・命中時にactiveかつgeneration一致を再検証する。解放済みslotを同tickに再確保してよいが、新世代はsnapshotとgenerationが異なり、`born_physics_tick=current`でもあるため次tickまで処理されない。これにより古いsnapshotが新しい弾を処理しない。命中順はsnapshotのpool index昇順で、同indexに複数generationが同時存在することはない。
- 敵容量768、味方/敵飛翔物合計4096、短命VFX4096。枯渇を黙って無視せず、debug counter を増やしテストを失敗させる。
- 空間検索はセル幅2.0m、grid_width=15、grid_height=9のuniform grid。arena座標から`x_index=clamp(floor((x+15.0)/2.0),0,14)`、`z_index=clamp(floor((z+9.0)/2.0),0,8)`、`cell_key=x_index+z_index*15`とする。x=15 / z=9の境界は最終cellへ入る。一般shape queryは効果の幾何半径とbroad-phase paddingを別引数にし、円なら中心±`(effect_radius + padding)`、扇形なら中心±射程、線分／swept collisionならpreviousとnextの各軸min/maxへ`projectile_radius + max_target_body_radius`を加減したXZ AABBを先に作る。杖爆発のpaddingは全敵定義中の最大半径1.25m、敵を狙う味方飛翔物のmax target半径も1.25m、プレイヤーを狙う敵弾ではプレイヤー半径0.45mとする。中心包含だけで判定する他の円効果はpadding 0とする。AABBがarenaと交差しなければ空を返し、交差部分のmin/max indexを上式で求めてclampし、z index外側・x index内側の昇順、すなわちcell_key昇順で全cellを列挙し、各cell内はentity_id昇順とする。その後に杖なら`effect_radius + candidate.body_radius`、他の円／扇形なら各効果の定義、線分なら`projectile_radius + candidate.body_radius`という3.4の正確なshape判定を行い、境界は`<=`で含める。broad-phaseの1.25mは候補列挙だけに使い、個別命中半径へ一律加算しない。これにより14m索敵、area強化後の範囲、対象bodyが隣接cellへまたがる杖爆発、複数cellを横断する弾も3×3へ制限しない。星落としの密度集計だけは、候補cellごとにz offset=-1..1の外側loop、x offset=-1..1の内側loopでarena外indexをskipする固定3×3近傍を使う。すべての最終候補順はcell_key昇順、同cell内entity_id昇順として決定性を保つ。

### 4.2 ディレクトリ

次の構成を使用する。

~~~text
project.godot
export_presets.cfg
.godot-version
.gitattributes
.gitignore
README.md
.codex/                         # local coding support; Git ignored
  skills/godot-gdscript-guard/
    SKILL.md
    agents/openai.yaml
    references/gdscript_python_differences.md
    scripts/gdscript_guard.py
data/
  balance/
    balance_manifest.tres
  definitions/
    weapons/
    enemies/
    waves/
    rarities/
    affixes/
    skills/
    uniques/
    score.tres
scenes/
  main.tscn
  arena/arena.tscn
  ui/
  debug/evidence_scene.tscn
src/
  app/
  core/
  combat/
  loot/
  inventory/
  skills/
  ui/
  audio/
  debug/
tests/
  test_runner.gd
  process_log.ps1
  run_gate_checks.ps1
  run_with_clean_settings.ps1
  unit/
  scenario/
  simulation/
  performance/
tools/
build/windows/
artifacts/
outputs/
docs/
~~~

.codex、tools、build、artifacts、work、.godot は Git ignore 対象。data、scenes、src、tests、outputs、docs、project.godot、export_presets.cfg、.godot-version、.gitattributes、.gitignore、README.md は追跡対象。

`.gitattributes`は次へ固定する。

~~~gitattributes
* text=auto eol=lf
*.gd text eol=lf
*.tscn text eol=lf
*.tres text eol=lf
*.godot text eol=lf
*.cfg text eol=lf
*.md text eol=lf
*.csv text eol=lf
*.ps1 text eol=lf
*.png binary
*.exe binary
*.pck binary
~~~

#### 4.2.1 静的Resource契約

`DefinitionCatalog.load_and_validate()`は次の固定pathを列挙順に`ResourceLoader.load()`し、IDをStringName辞書へ登録する。ディレクトリ走査順へ依存しない。欠落、型違い、重複ID、非有限値、負の基礎値、重み検証失敗、表と件数不一致が1件でもあればBOOTからTITLEへ進まず終了コード2とする。

- `WeaponDefinition`: `weapon_id`、`main_weapon_type`、`base_damage`、`base_interval`、`range_m`、`projectile_speed`、`projectile_radius`、`aoe_radius`、`arc_degrees`。`wood_stick.tres`、`bow.tres`、`staff.tres`、`sword.tres`の4件。
- `EnemyDefinition`: `enemy_id`、`base_hp`、`move_speed`、`body_radius`、`contact_interval`、`contact_damage`、`preferred_distance_min`、`preferred_distance_max`、`special_interval`、`telegraph_seconds`、`area_radius`、`projectile_damage`、`projectile_speed`、`projectile_radius`、`projectile_lifetime`、`volley_count`、`summon_interval`、`summon_count`。`tracker.tres`、`fast.tres`、`armored.tres`、`ranged.tres`、`elite.tres`、`boss.tres`の6件。
- `WaveDefinition`: 4.4記載field。`wave_01.tres`から`wave_08.tres`の8件。
- `RarityDefinition`: `rarity`、`affix_count`。`common.tres`、`rare.tres`、`epic.tres`、`legendary.tres`の4件。保持装備scoreは`ScoreDefinition.equipment_scores`だけを正本とし、ここへ重複保持しない。
- `AffixDefinition`: `affix_id`、`values_by_rarity: PackedFloat32Array`の4値、`slot_pool: Array[EquipmentSlot]`、`in_common_pool`、`affinity_weapon_types: Array[MainWeaponType]`。3.7の9 IDと値を1 ID 1ファイル、snake_caseの`<affix_id>.tres`で9件。
- `SkillDefinition`: `skill_id`、`trigger_type`、`base_threshold`、`damage_by_level`、`radius_by_level`、`target_count_by_level`。配列はすべて3要素。`starfall.tres`、`thousand_blades.tres`、`soul_chain.tres`、`bell_of_retribution.tres`の4件。
- `UniqueDefinition`: `unique_id`、`display_name`、`equipment_slot`。`bloodied_dagger.tres`、`broken_clock.tres`、`coward_boots.tres`、`immortal_breastplate.tres`、`echo_gauntlet.tres`、`hollow_crown.tres`の6件。効果ロジックはunique_idで型付きserviceへdispatchし、表示名から分岐しない。
- `ScoreDefinition`: `normal_kill`、`post_quota_bonus`、`elite_kill`、`boss_kill`、`wave_clear`、`run_clear`、`equipment_scores: PackedInt32Array`、`unique_tag`、`skill_level`、`wild_material`。`equipment_scores`はCommon / Rare / Epic / Legendaryのenum順4値。`score.tres`1件。

`BalanceManifest`は下記の1件だけを読み、Catalogのロード後に`balance_revision>=0`を検証する。全Resourceの値は本書3章の表と一致させ、同じ数値を別のGDScript定数として二重管理しない。

WaveDefinitionの`elite_spawn_elapsed`だけは上記どおり非該当を-1で表す。それ以外の数値fieldが挙動に該当しない場合は0を格納する。SkillDefinitionでは星落とし・千刃陣・報復の鐘の`target_count_by_level`を`[0,0,0]`とし、0は半径内全敵を表す。魂の連鎖は`radius_by_level=[0,0,0]`、`target_count_by_level=[4,6,9]`とする。WeaponDefinitionとEnemyDefinitionの非該当projectile / area / arc fieldも0であり、未初期化値や追加の-1 sentinelを使わない。

`data/balance/balance_manifest.tres`は整数`balance_revision`だけを持つResourceとし、初期値を0にする。企画書、本書、Resourceまたは期待値テストに影響する承認済みバランス変更を1組適用するたびに1増やす。

### 4.3 enum

src/core/game_types.gd に次を置く。

~~~gdscript
enum EquipmentSlot { MAIN_WEAPON, SUB_WEAPON, HEAD, BODY, HANDS, FEET }
enum MainWeaponType { UNCLASSIFIED, BOW, STAFF, SWORD }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }
enum TriggerType { TIME, PRIMARY_ATTACK_COUNT, KILL_COUNT, HIT_COUNT }
enum RunPhase { BOOT, TITLE, COMBAT, REWARD_REVEAL, INVENTORY, RESULT, FAILED }
enum EnemyType { TRACKER, FAST, ARMORED, RANGED, ELITE, BOSS }
enum RewardKind { EQUIPMENT, SKILL }
~~~

enum の整数値を永続データへ書かない。設定保存は文字列キーを使う。

### 4.4 ランタイム型

以下の型名と必須フィールドを変えない。追加フィールドは派生キャッシュ、UI状態、テスト計測に限る。

**ItemInstance extends RefCounted**

- item_id: String
- item_seed: int
- slot: EquipmentSlot
- main_weapon_type: MainWeaponType。MAIN_WEAPON以外はUNCLASSIFIED
- rarity: Rarity
- affixes: Array[AffixRoll]
- unique_id: StringName。通常品は空
- display_name: String
- locked: bool

**AffixRoll extends RefCounted**

- affix_id: StringName
- value: float

**SkillState extends RefCounted**

- skill_id: StringName
- level: int。1..3
- equipped_slot: int。未装着=-1、第1=0、第2=1
- trigger_progress: float
- pending_queue: Array[PendingSkillActivation]。activation_serial昇順のFIFO

**PendingSkillActivation extends RefCounted**

- activation_serial: int。RunState.next_activation_serialから単調増加
- origin_event_serial: int。時間、一次主攻撃、閾値正規化は-1
- inherited_effect_chain: PackedStringArray。予約原因のchainの値コピー

**ScheduledProcReplay extends RefCounted**

- due_physics_tick: int。予約tick+9
- schedule_serial: int。RunState.next_activation_serialから単調増加
- source_effect_id: StringName
- proc_effect_id: StringName。`unique:echo_gauntlet`または`unique:hollow_crown`
- inherited_effect_chain: PackedStringArray。予約時点でproc_effect_id追加済み
- damage_snapshot: float
- direction: Vector2。王冠では実行時に対象再選定するためVector2.ZERO
- aim_distance: float。反響の杖だけ元発射距離、他は0
- target_entity_id: int。反響の木の棒だけ元対象、他は-1

**DamageSample extends RefCounted**

- physics_tick: int
- event_serial: int
- applied_damage: float。敵HPを実際に減らした量で0より大きい値

**RunRngStreams extends RefCounted**

- combat_seed: int。`SeedService.derive(run_seed, "combat")`
- loot_seed: int。`SeedService.derive(run_seed, "loot")`
- fusion_seed: int。`SeedService.derive(run_seed, "fusion")`
- combat_rng: RandomNumberGenerator。seedをcombat_seedへ設定したmutable stream
- loot_rng: RandomNumberGenerator。seedをloot_seedへ設定したmutable stream
- fusion_rng: RandomNumberGenerator。seedをfusion_seedへ設定したmutable stream

`RunRngStreams.create(run_seed)`だけが3 instanceを生成し、各RNGへ対応seedを設定する。3 instanceを共有、再生成、途中reseedingせず、現在位置の比較には各`RandomNumberGenerator.state`を使う。name RNGはitemごとの一時instanceなのでこの型へ入れない。

**WaveDefinition extends Resource**

- wave_number: int。1..8
- duration_seconds: float。60
- kill_quota: int
- enemy_weights: Dictionary
- hp_multiplier: float
- damage_multiplier: float
- spawn_rate_start: float
- spawn_rate_end: float
- normal_chest_rate: float
- rarity_weights: Dictionary
- elite_spawn_elapsed: float。該当なし=-1、W4=30
- boss_at_start: bool

**BalanceManifest extends Resource**

- balance_revision: int。MVP初期仕様は0

**RewardRoll extends RefCounted**

- reward_id: String
- wave_number: int
- acquired_tick: int
- is_guaranteed_main_weapon: bool
- kind: RewardKind
- equipment: ItemInstance または null
- skill_id: StringName または空
- rarity_for_presentation: int。装備報酬はRarityの0..3、スキル報酬はsentinel -1
- revealed: bool

**RunState extends RefCounted**

- run_seed: int
- rng_streams: RunRngStreams。run_seedからランfactoryが1回だけ生成し、同seed／新seed再挑戦では新しい3 instanceへ置換
- phase: RunPhase
- wave_number: int
- wave_main_weapon_type: MainWeaponType。ウェーブ開始時snapshot
- physics_tick: int
- time_remaining: float
- wave_cleared: bool
- boss_defeated: bool。W1..W7=false、W8ボス死亡時だけtrue
- current_hp: float
- max_hp: float
- equipped: Dictionary。EquipmentSlot→ItemInstance。MAIN_WEAPON keyは常に非null、他5 keyはnull可
- inventory: Array[ItemInstance]。常に36要素、空slotはnull
- overflow: Array[ItemInstance]
- skill_library: Dictionary。skill_id→SkillState
- unopened_rewards: Array[RewardRoll]
- scheduled_proc_replays: Array[ScheduledProcReplay]。due_physics_tick、同値ならschedule_serial昇順
- wild_material_count: int
- drop_serial: int
- next_entity_id: int。ラン開始・再挑戦時0、敵生成直前に現在値を割り当てて1増加し、pool slot再利用やウェーブ遷移では戻さない
- next_activation_serial: int。ラン開始・再挑戦時0、スキル予約と遅延proc予約のたびに1増加し、ウェーブ間では保持
- next_event_serial: int。ラン開始・再挑戦時0、各CombatEvent生成直前に現在値をevent_serialへ割り当てて1増加し、ウェーブ間では保持
- spawn_credit: float。各ウェーブ開始時0、3.5の通常スポーン処理で0..8.0を保持
- coward_stationary_elapsed: float。各ウェーブ開始・ラン開始・再挑戦時0、臆病者の靴の停止待機だけに使い、ウェーブ間で保持しない
- echo_progress_item_id: String。反響の手甲を装備していない時は空、装備中はそのitem_id
- echo_primary_attack_progress: int。0..2、同じ反響の手甲を継続装備中だけウェーブ間保持
- non_boss_spawned: int。W8開始時0、通常敵とボス召喚を実生成した体数だけ増やし、W1..W7では0
- wave_kills: int。ウェーブ開始時0、敵種を問わないノルマ用
- total_kills: int
- normal_kills: int。TRACKER / FAST / ARMORED / RANGEDとボス召喚の合計
- post_quota_kills: int。表示用、敵種を問わない
- elite_kills: int
- boss_kills: int
- cleared_waves: int
- wave_chests: int。そのウェーブで論理獲得した箱数、開始時0
- total_chests: int。クリア済みウェーブから確定した箱数。成功終了時にwave_chestsを加え、FAILEDでは加えない
- fusion_count: int
- peak_dps: float
- recent_damage_samples: Array[DamageSample]。physics_tick、同tickはevent_serial昇順のdeque。COMBAT退出時に空へ戻す
- score_breakdown: Dictionary

**CombatEvent extends RefCounted**

- event_serial: int
- event_type: StringName
- source_entity_id: int。敵由来eventは生成元enemyのentity_id、プレイヤーの主攻撃・スキル・装備procは-1
- source_effect_id: StringName。実際に解決する武器・スキル・攻撃payloadのID
- proc_effect_id: StringName。このイベントを生成したprocのID。一次イベントは空
- is_primary: bool
- effect_chain: PackedStringArray。発動済みproc_effect_idだけを順に保持
- chain_depth: int。一次イベント=0、派生ごとに+1、最大16
- damage_snapshot: float
- position: Vector2
- direction: Vector2

CombatEventRouterは二次生成時にだけproc循環を検査する。生成しようとするproc IDが親のeffect_chainにあれば拒否し、なければ追加した子イベントを作る。通常スキル発動も条件カウンタが生成する二次イベントとして同じ検査を通す。source_effect_idはpayload解決に使い、循環判定には使わない。`chain_depth == effect_chain.size()`を不変条件とする。

**CombatSnapshot**

- 戦闘層から描画層へ渡す読み取り専用 snapshot。
- player_position、敵/飛翔物/VFXの active count と transform、HUD用数値だけを持つ。
- 描画側から戦闘配列を変更できない。

### 4.5 seed と RNG

run seed は0以上の63bit整数。通常開始では Time.get_unix_time_from_system と Time.get_ticks_usec を文字列連結し SHA-256 化して先頭8byteを読み、符号bitを落とす。結果が0なら1へ置換する。テストと同じseed再挑戦では0を含む指定値をそのまま使う。

SeedService.derive(base_seed, stream_name) は UTF-8 の "{base_seed}|{stream_name}" を SHA-256 化し、digest.decode_u64(0) & 0x7fffffffffffffff を返す。combat、loot、fusion は run_seed を base_seed としてラン開始時に`RunRngStreams.create(run_seed)`から別々の RandomNumberGenerator を作り、RunState.rng_streamsが所有する。name はアイテムごとの独立 RNG とし、SeedService.derive(item_seed, "name") で都度作る。

- combat: 出現辺、敵タイプ、敵固有挙動
- loot: 箱ドロップ、報酬種別、部位、レアリティ、ユニーク
- name: 素材語、副名。アイテムごとの item_seed から派生
- fusion: 合成出力

重み付き抽選は、候補を固定ID昇順に並べ、重み0の候補を選択対象から除外したうえで`r = randf() × 重み合計`を作る。rが重み合計未満なら、正の重みだけを固定順に加算し、`r < 累積重み`を最初に満たす候補を返す。`randf()`が1.0を返してrが重み合計と等しい場合だけ、固定順で最後の**正の重み**を持つ候補を返す。これにより0%候補は端点でも選ばれない。先に副作用もログ出力もない純粋関数`validate_weights(candidates, weights)`で、候補1件以上、配列長一致、各重み0以上、合計が0より大きいことを検証する。falseなら呼出元は抽選を呼ばず、設定読込失敗として停止するためRNGを消費しない。抽選関数は検証済み入力だけを受けるものとし、debug assertionはプログラム不変条件の保護に限定して通常test suiteから意図的に発生させない。RNG 消費はサービス内に閉じ込め、描画、UI、音、開封演出から呼ばない。敵の見た目差分も entity_id から決定し、combat RNG を追加消費しない。RewardRoll は論理獲得時に生成し、開封では revealed を切り替えるだけとする。

### 4.6 状態遷移

許可する遷移は次だけ。

~~~text
BOOT -> TITLE
TITLE -> COMBAT
COMBAT -> REWARD_REVEAL   成功確定後の死亡または時間切れ
COMBAT -> FAILED          成功前の死亡または時間切れ
REWARD_REVEAL -> INVENTORY 全報酬公開後
INVENTORY -> COMBAT       W1..W7、overflowなし、MAIN_WEAPON非null
INVENTORY -> RESULT       W8、overflowなし、MAIN_WEAPON非null
FAILED -> COMBAT          同じseedまたは新seedで再挑戦
FAILED -> TITLE
RESULT -> COMBAT          同じseedまたは新seedで再挑戦
RESULT -> TITLE
~~~

TITLEの「開始」は4.5で新seedを作り、下記と同じRunState factoryを使って初回ランを構築する。FAILED / RESULTのどちらから再挑戦しても、新しいRunStateを同じfactoryで作り直す。「同じseed」は直前のrun_seedだけを再利用し、「新しいseed」は4.5の通常生成で置換する。いずれもHP100、W1、空inventory / overflow / skill library / reward / ScheduledProcReplay、wild 0、全score・kill・chest・fusion counter 0、physics_tick / next_entity_id / next_activation_serial / next_event_serial 0、coward_stationary_elapsed=0、echo_progress_item_id空、echo_primary_attack_progress=0、combat / loot / fusion RNGを選択seedから再派生した状態へ戻す。その後3.7の固定手順でserial 0000の木の棒だけを初期装備するため、COMBAT開始時のdrop_serialは1となる。直前ランの装備、スキル、進捗、RNG state、serial、ビルドは持ち越さない。

`can_transition(from, to)`を副作用のない純粋関数として実装する。無効な遷移を実際のtransition APIへ渡した場合は処理を続けず、debug/testではassertion failure、releaseではpush_errorを1回出して現在phaseを維持する。通常の自動suiteは拒否組合せを`can_transition`だけで全件検査し、意図したエラーログを発生させない。実transition APIの無効入力は通常suiteから呼ばず、debug手動診断だけで確認する。

## 5. 開発環境と共通コマンド

### 5.1 Godot 4.7.2 の固定

現在の PATH 上の Godot 4.7-stable は使用しない。ゲート1で公式 4.7.2-stable Standard win64 と同版 Export Templates を`tools/godot`配下へ配置する。`tools/godot/_sc_`を置くself-contained modeとし、共有`%APPDATA%`を変更しない。URL と公式Release assetのSHA-256は次に固定する。

| asset | URL | SHA-256 |
|---|---|---|
| Standard win64 zip | `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip` | `731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953` |
| Export Templates | `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz` | `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011` |

CLIは標準出力と標準エラーを取得できるconsole wrapperへ固定する。セッションごとに次で実行ファイルを指定する。HOME、home、CODEX_HOME は変更しない。

~~~powershell
$env:JARJAR_GODOT = (Resolve-Path -LiteralPath ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe").Path
$jarjarGodotVersion = (& $env:JARJAR_GODOT --version).Trim()
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$jarjarGodotVersion
if (-not $jarjarGodotVersion.StartsWith("4.7.2.stable.official")) { throw ("Godot version mismatch: " + $jarjarGodotVersion) }
~~~

バージョン出力は 4.7.2.stable.official で始まること。完全一致するまで実装へ進まない。

### 5.2 標準検証

Gate 1で`tests/process_log.ps1`と`tests/run_gate_checks.ps1`を作成し、以後の全Gateで使う。`process_log.ps1`は関数`Invoke-JarjarLoggedProcess`だけを定義し、引数を`-LogPath`、`-Label`、`-FilePath`、`-Arguments`、`-ExpectedExitCodes`へ固定する。Argumentsは`[Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$Arguments`へ固定して空配列を受理し、既定ExpectedExitCodesは`@(0)`とする。関数はコマンド行、標準出力、標準エラー、native command直後の終了コードをLogPathへUTF-8で追記し、標準出力にも同じ内容を出す。command / label / stream境界 / exit codeのmetadata行だけを`@@ `で始め、captured stdoutとstderrのpayloadは各行を文字変更、prefix、indent、timestampなしの独立したraw行としてmetadata間へ書く。これにより`*_ARGUMENT_REJECTED`と`PACK_AUDIT_OK`のexact markerはlog内でも完全一致行になる。終了コードが期待集合外なら例外を投げる。その実行で追加されたlogを大文字小文字を無視して`SCRIPT ERROR`、`PARSE ERROR`、`ERROR:`、`PUSH_ERROR`、`ORPHAN NODE`、`OBJECTDB INSTANCES LEAKED`、`RESOURCE LEAK`で検索し、1件でもあれば例外を投げる。Labelは`^[a-z0-9_-]+$`、FilePathは既存file、LogPathは解決後にrepositoryの`artifacts/gate-NN`内であることを要求する。

`run_gate_checks.ps1`の引数は`-GateNumber`の1..6と`-Suite`のunit / scenario / simulation / allだけを受け付ける。このscriptは`artifacts/gate-NN`を作り、当該実行の開始時に`tests.txt`を空にし、process_log.ps1をdot-sourceする。さらに実ユーザーの`%APPDATA%\ProjectJARJAR\settings.cfg`について、存在有無、存在時のbyte長、SHA-256、`LastWriteTimeUtc.Ticks`をprocess外でmemoryへsnapshotし、存在時は一意な`artifacts/gate-NN/real-settings-backup-<32桁GUID>/settings.cfg`へbackupする。次の5コマンドをimport、正常な独自runner、不正runner、不正Debug main、editor終了の順で`Invoke-JarjarLoggedProcess`へ渡した後、同じ4値が完全一致することを確認する。不正runnerはsettings pathを意図的に欠落させ、期待終了コード2、かつ`RUNNER_ARGUMENT_REJECTED name=missing`のexact行1件を要求する。不正Debug mainは`--settings-path`単独を渡し、期待終了コード2、`DEBUG_ARGUMENT_REJECTED name=--settings-path child_nodes=0 run_state=0`のexact行1件、指定cfg非生成を要求する。5 processと比較を`try/finally`で囲み、途中例外でも、元がfileなら内容とmtimeをbackupから復元、元が不存在なら新規作成されたexact settings.cfg 1fileだけを削除し、復元後の4値を再検証する。親directoryや他fileを削除しない。どれかのprocess、拒否marker、設定不変、復元が失敗したらscriptの終了コード1、script引数不正は2、全件成功は0とする。

script内部からprocess loggerへ渡す実行列は次へ固定する。

~~~powershell
$artifactRoot = [System.IO.Path]::GetFullPath((".\artifacts\gate-{0:D2}" -f $GateNumber))
$logPath = Join-Path $artifactRoot "tests.txt"
$settingsPath = [System.IO.Path]::GetFullPath((Join-Path $artifactRoot "test-user\runner\settings.cfg"))
$mainInvalidSettingsPath = [System.IO.Path]::GetFullPath((Join-Path $artifactRoot "test-user\main-invalid\settings.cfg"))
$realSettingsPath = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "ProjectJARJAR\settings.cfg"
function Get-JarjarSettingsSnapshot([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Length = [int64]0; Sha256 = ""; MtimeTicks = [int64]0 }
    }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return [pscustomobject]@{
        Exists = $true
        Length = [int64]$item.Length
        Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
        MtimeTicks = [int64]$item.LastWriteTimeUtc.Ticks
    }
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null
$testUserRoot = [System.IO.Path]::GetFullPath((Join-Path $artifactRoot "test-user")) + [System.IO.Path]::DirectorySeparatorChar
if (-not $settingsPath.StartsWith($testUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "runner settings path escaped test-user" }
if (-not $mainInvalidSettingsPath.StartsWith($testUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "main invalid settings path escaped test-user" }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mainInvalidSettingsPath) | Out-Null
if (Test-Path -LiteralPath $settingsPath) { Remove-Item -LiteralPath $settingsPath -Force -ErrorAction Stop }
if (Test-Path -LiteralPath $mainInvalidSettingsPath) { Remove-Item -LiteralPath $mainInvalidSettingsPath -Force -ErrorAction Stop }
if ((Test-Path -LiteralPath $realSettingsPath) -and -not (Test-Path -LiteralPath $realSettingsPath -PathType Leaf)) { throw "real settings path is not a file" }
$realSettingsBefore = Get-JarjarSettingsSnapshot -Path $realSettingsPath
$realSettingsBackup = ""
if ($realSettingsBefore.Exists) {
    $backupRoot = Join-Path $artifactRoot ("real-settings-backup-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $backupRoot -ErrorAction Stop | Out-Null
    $realSettingsBackup = Join-Path $backupRoot "settings.cfg"
    Copy-Item -LiteralPath $realSettingsPath -Destination $realSettingsBackup -ErrorAction Stop
}
$gateFailure = $null
try {
    try {
        Invoke-JarjarLoggedProcess -LogPath $logPath -Label "import" -FilePath $env:JARJAR_GODOT -Arguments @("--headless", "--path", ".", "--import")
        Invoke-JarjarLoggedProcess -LogPath $logPath -Label "tests" -FilePath $env:JARJAR_GODOT -Arguments @("--headless", "--path", ".", "--script", "res://tests/test_runner.gd", "--", "--suite", $Suite, ("--settings-path=" + $settingsPath))
        if (Test-Path -LiteralPath $settingsPath) { Remove-Item -LiteralPath $settingsPath -Force -ErrorAction Stop }
        Invoke-JarjarLoggedProcess -LogPath $logPath -Label "runner_invalid_missing_settings" -FilePath $env:JARJAR_GODOT -Arguments @("--headless", "--path", ".", "--script", "res://tests/test_runner.gd", "--", "--suite", "unit") -ExpectedExitCodes @(2)
        if (Test-Path -LiteralPath $settingsPath) { throw "invalid runner created bootstrap settings" }
        $rejectCount = @((Get-Content -LiteralPath $logPath) | Where-Object { $_ -ceq "RUNNER_ARGUMENT_REJECTED name=missing" }).Count
        if ($rejectCount -ne 1) { throw ("runner rejection marker count: " + $rejectCount) }
        Invoke-JarjarLoggedProcess -LogPath $logPath -Label "main_invalid_settings_only" -FilePath $env:JARJAR_GODOT -Arguments @("--headless", "--path", ".", "--", ("--settings-path=" + $mainInvalidSettingsPath)) -ExpectedExitCodes @(2)
        if (Test-Path -LiteralPath $mainInvalidSettingsPath) { throw "invalid main created settings" }
        $mainRejectCount = @((Get-Content -LiteralPath $logPath) | Where-Object { $_ -ceq "DEBUG_ARGUMENT_REJECTED name=--settings-path child_nodes=0 run_state=0" }).Count
        if ($mainRejectCount -ne 1) { throw ("debug rejection marker count: " + $mainRejectCount) }
        Invoke-JarjarLoggedProcess -LogPath $logPath -Label "editor_quit" -FilePath $env:JARJAR_GODOT -Arguments @("--headless", "--path", ".", "--editor", "--quit-after", "2")
        $realSettingsAfter = Get-JarjarSettingsSnapshot -Path $realSettingsPath
        foreach ($field in @("Exists", "Length", "Sha256", "MtimeTicks")) {
            if ($realSettingsBefore.$field -ne $realSettingsAfter.$field) { throw ("real settings changed: " + $field) }
        }
    } catch {
        $gateFailure = $_.Exception
    }
} finally {
    try {
        $current = Get-JarjarSettingsSnapshot -Path $realSettingsPath
        if ($realSettingsBefore.Exists) {
            $mustRestore = ($current.Exists -ne $true) -or ($current.Length -ne $realSettingsBefore.Length) -or ($current.Sha256 -ne $realSettingsBefore.Sha256) -or ($current.MtimeTicks -ne $realSettingsBefore.MtimeTicks)
            if ($mustRestore) {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $realSettingsPath) | Out-Null
                Copy-Item -LiteralPath $realSettingsBackup -Destination $realSettingsPath -Force -ErrorAction Stop
                [System.IO.File]::SetLastWriteTimeUtc($realSettingsPath, [datetime]::new($realSettingsBefore.MtimeTicks, [System.DateTimeKind]::Utc))
            }
        } elseif ($current.Exists) {
            Remove-Item -LiteralPath $realSettingsPath -Force -ErrorAction Stop
        }
        $restored = Get-JarjarSettingsSnapshot -Path $realSettingsPath
        foreach ($field in @("Exists", "Length", "Sha256", "MtimeTicks")) {
            if ($realSettingsBefore.$field -ne $restored.$field) { throw ("real settings restore failed: " + $field) }
        }
    } catch {
        if ($null -eq $gateFailure) { $gateFailure = $_.Exception }
    }
}
if ($null -ne $gateFailure) { throw $gateFailure }
~~~

呼び出しは次の形式とし、Gate 1なら1、Gate 2なら2、以後同様に現在の工程番号を渡す。

~~~powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\run_gate_checks.ps1" -GateNumber 1 -Suite all
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
~~~

NNは工程番号のゼロ埋め2桁で、工程1なら01、工程6なら06。`tests/test_runner.gd` は `extends SceneTree` とし、test列挙前に4.1のrunner引数検証と`initialize_for_runner()`を行う。直後に既存Autoload `/root/SettingsStore` の`initialized`と`runner_safe_mode`がtrue、`active_settings_path`がuser引数の解決済み`--settings-path`と完全一致することを検証する。満たさなければtestを1件も始めず`quit(2)`する。その後、検証済み`--suite`のunit、scenario、simulation、allを受け付け、`all`はunit→scenario→simulationの順に実行する。画面を必要とするperformanceは`--performance=full_hd_500_2000`の別経路で実行する。全テスト終了後に成功なら`quit(0)`、assertion failureなら`quit(1)`、runner自体の例外・無効suite・指定Suiteを展開した実行全体のテスト総数0件なら`quit(2)`を必ず呼ぶ。`all`実行時は工程未到達の空sub-suiteを許容し、unit/scenario/simulation合計が1件以上なら0件扱いにしない。`--quit-after`でテスト成功を代用しない。テスト名、期待値、実値、所要時間を標準出力へ出し、最後にpassed / failed / elapsed_msを出す。プロジェクト作成後のGodot、evidence、performance、export、export済みEXEの全実行は、意図して終了2を期待するQA引数拒否も含め、必ず同じGateの`Invoke-JarjarLoggedProcess`を通す。文書中で実行引数だけを示す箇所もこの規則を省略しない。

### 5.3 証跡スクリーンショット

src/debug/evidence_capture.gd は --evidence=gate_XX:scenario_name を受け、指定状態を構築し、RenderingServer.frame_post_draw を2回待って viewport を PNG 保存し、終了コード0で終了する。保存先は artifacts/gate-XX/{scenario_name}.png。画像は1280×720以上、UI文字が読め、マウスカーソルや別アプリを含まないこと。

実行例:

~~~powershell
. ".\tests\process_log.ps1"
$logPath = [System.IO.Path]::GetFullPath(".\artifacts\gate-03\tests.txt")
$settingsPath = [System.IO.Path]::GetFullPath(".\artifacts\gate-03\test-user\evidence_arena_combat\settings.cfg")
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null
$testUserRoot = [System.IO.Path]::GetFullPath(".\artifacts\gate-03\test-user") + [System.IO.Path]::DirectorySeparatorChar
if (-not $settingsPath.StartsWith($testUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "evidence settings path escaped test-user" }
if (Test-Path -LiteralPath $settingsPath) { Remove-Item -LiteralPath $settingsPath -Force -ErrorAction Stop }
Invoke-JarjarLoggedProcess -LogPath $logPath -Label "evidence_arena_combat" -FilePath $env:JARJAR_GODOT -Arguments @("--path", ".", "--", "--evidence=gate_03:arena_combat", ("--settings-path=" + $settingsPath))
~~~

スクリーンショットを生成できない場合、そのゲートは未完了である。OS の画面切り取りを代用しない。

### 5.4 再現可能なDebug QA状態

`src/debug/qa_scenario_factory.gd`は`--qa-scenario=<id>`をdebug buildでだけ受け付け、通常のRunStateを破棄して次の固定状態を構築する。seedはすべて`20260827`。全QA状態で設定ファイルへ書かずruntime上だけ`tutorial_seen=true`、tutorial overlay inactiveへ固定し、W1 fixtureも開始直後のphysics tickから通常pipelineへ入れる。状態構築はRunStateのmutable combat / loot / fusion RNGへ触れず、下表と後続の固定object一覧を使う。「通常規則で生成」と明記した大量itemだけは、アイテムごとに新規作成するfixture-local affix RNGとitem-local name RNGを使う。TITLEへ戻る、再挑戦する、またはプロセスを終了した時点でQA状態を破棄し、settingsやランを保存しない。Debugでの不明ID、値欠落、同時に複数指定した場合は状態変更前に終了コード2。Releaseではfactoryへ到達させず、4.1の共通parserが標準出力へ`RELEASE_ARGUMENT_REJECTED name=--qa-scenario`を1行出して終了コード2とする。

| id | 開始phaseと固定状態 |
|---|---|
| `weapon_bow` | W1 COMBAT、弓を装備、TRACKERを正面10mへ20体。敵AI、全敵timer、normal spawn、spawn_credit加算、wave countdownを停止し、弓だけを反復表示 |
| `weapon_staff` | W1 COMBAT、杖を装備、TRACKERを正面10mの半径2m内へ20体。敵AI、全敵timer、normal spawn、spawn_credit加算、wave countdownを停止 |
| `weapon_sword` | W1 COMBAT、剣を装備、TRACKERを正面2mの120度内へ20体。敵AI、全敵timer、normal spawn、spawn_credit加算、wave countdownを停止 |
| `pre_quota_death` | W1 COMBAT、wave_kills=39、wave_cleared=false、HP=1、wave_chests=1、主攻撃準備値=0、スキルなし。current-wave RewardRollとしてreward_id=`qa-reward-death`、item_id=`qa-item-death`のCommon HEADを1件保持する。接触cooldown済みTRACKER 1体を重ね、主攻撃がreadyになる前の次tickに死亡してFAILEDへ入り、そのRewardRollとwave_chestsを破棄する |
| `pre_quota_timeout` | W1 COMBAT、wave_kills=39、wave_cleared=false、残り1 physics tick、敵0、wave_chests=1。reward_id=`qa-reward-timeout`、item_id=`qa-item-timeout`のCommon HEADを1件保持し、次tickにFAILEDへ入って破棄する |
| `post_quota_death` | W1 COMBAT、wave_kills=40、wave_cleared=true、HP=1、wave_chests=1、主攻撃準備値=0、スキルなし。reward_id=`qa-reward-post-death`、item_id=`qa-item-post-death`のCommon HANDSを1件保持する。接触cooldown済みTRACKER 1体を重ね、主攻撃がreadyになる前の次tickにREWARD_REVEALへ入り、そのRewardRollを保持する |
| `reward_controls` | W3 REWARD_REVEAL。未公開順をCommon弓、Rare胴、Epic手、Legendary足の4 RewardRollへ固定し、`revealed=false`、開封timer=0、loot RNG snapshotを構築前後で同値にする |
| `inventory_controller` | W7成功後のINVENTORY。装備中6件はitem_id=`qa-equipped-00`..`05`、enum順の各部位、Common、unlocked、非uniqueで、主武器だけBOW。inventory 36件、overflow 4件、wild 1個、4スキルを保持する。inventory index 0..17はCommon、18..26はRare、27..32はEpicの非uniqueで、部位はindex mod 6、MAIN_WEAPONなら`floor(index / 6) mod 3`の0/1/2をBOW/STAFF/SWORDへ対応させる。index 0..2のaffixは`max_hp=10`、3..17は`attack_speed_pct=8`へ固定し、Common自動選択を`qa-inventory-00, 01, 02`の順にする。index 33はRareの血塗れの短剣、affix=`damage_pct=14`、34はlocked Common HANDS非unique、35はLegendary FEET非unique。item_idは`qa-inventory-00`..`35`。overflowは順にCommon非uniqueのMAIN_WEAPON/STAFF、SUB_WEAPON、HEAD、BODYで、すべてunlocked、affix=`attack_speed_pct=8`、item_id=`qa-overflow-00`..`03`。index 18..32、34、35だけはItemFactoryの通常規則で特性を生成する。星落としLv3を枠1、千刃陣Lv2を枠2、魂の連鎖Lv1と報復の鐘Lv3を未装着にする |
| `result_controller` | 固定例12,055点のRESULT。seed、全score内訳、装備6枠、スキル2枠と4つの結果導線を表示 |
| `immortal_100` | W5 COMBAT、HP100。不死者の胸当て、他装備2件にdamage_reduction_pct=25ずつ、報復の鐘Lv1を枠1・progress=4で装備。接触可能なTRACKER 1体をプレイヤー位置へ置き、敵HPを無限扱い、normal spawn、spawn_credit加算、他敵timer、wave countdownを停止する |
| `boss_299` | W8 COMBAT、残り30秒、boss_defeated=false、non_boss_spawned=299、wave_kills=299、通常敵0、BOSS 1体。通常spawn停止を表示し、QA専用の5000 damage弓でBOSS撃破後に通常spawn再開と300到達を観察できるようにする |

固定objectは次のとおり。`affix_id=value`はその順のAffixRoll、`none`はunique_id空を表す。ここにないfieldは4.4の型既定値ではなく、各phaseを成立させる通常RunState factory値を使う。

- `weapon_bow / weapon_staff / weapon_sword`: 装備item_idを順に`qa-weapon-bow / qa-weapon-staff / qa-weapon-sword`、Common MAIN_WEAPON、typeをBOW / STAFF / SWORD、affix=`max_hp=10`、none、locked=falseとする。置換された木の棒はinventory index 0へ残す。
- `pre_quota_death`: `qa-item-death`はCommon HEAD、affix=`skill_power_pct=10`、none、locked=false。RewardRollはreward_id=`qa-reward-death`、wave=1、acquired_tick=0、guaranteed=false、kind=EQUIPMENT、rarity_for_presentation=COMMON、revealed=false。
- `pre_quota_timeout`: `qa-item-timeout`はCommon HEAD、affix=`skill_power_pct=10`、none、locked=false。RewardRollはreward_id=`qa-reward-timeout`で、他fieldは直前と同じ。
- `post_quota_death`: `qa-item-post-death`はCommon HANDS、affix=`damage_pct=8`、none、locked=false。RewardRollはreward_id=`qa-reward-post-death`で、他fieldは`pre_quota_death`と同じ。
- `reward_controls`: 下表4件を表順でunopened_rewardsへ置く。すべてwave=3、guaranteed=false、kind=EQUIPMENT、unique_id空、locked=false、revealed=falseとし、rarity_for_presentationはitem rarityと同値にする。

| acquired_tick | reward_id | item_id | rarity / slot / type | affixes |
|---:|---|---|---|---|
| 0 | `qa-reward-common-bow` | `qa-item-common-bow` | Common / MAIN_WEAPON / BOW | `max_hp=10` |
| 1 | `qa-reward-rare-body` | `qa-item-rare-body` | Rare / BODY / UNCLASSIFIED | `max_hp=18, damage_reduction_pct=9` |
| 2 | `qa-reward-epic-hands` | `qa-item-epic-hands` | Epic / HANDS / UNCLASSIFIED | `damage_pct=24, attack_speed_pct=24, area_pct=30` |
| 3 | `qa-reward-legendary-feet` | `qa-item-legendary-feet` | Legendary / FEET / UNCLASSIFIED | `move_speed_pct=25, max_hp=50, damage_reduction_pct=25, skill_power_pct=50` |

- `inventory_controller`: `qa-inventory-33`だけをQaItemBuilderでRare SUB_WEAPON / UNCLASSIFIED、affix=`damage_pct=14`、unique_id=`bloodied_dagger`、locked=falseへ固定する。他の装備中、inventory、overflow itemは表のslot / rarity / type / lock条件をItemFactoryへ渡して通常規則で生成する。
- `result_controller`: run_seed=20260827、cleared_waves=8、normal_kills=100、elite_kills=1、boss_kills=1、total_kills=102、post_quota_kills=20、total_chests=160、fusion_count=12、peak_dps=999.0、wild=2。保持装備は`qa-result-common-bow`=Common MAIN_WEAPON/BOW/`max_hp=10`/none、`qa-result-rare-dagger`=Rare SUB_WEAPON/UNCLASSIFIED/`damage_pct=14`/`bloodied_dagger`、`qa-result-epic-body`=Epic BODY/UNCLASSIFIED/`max_hp=30, damage_reduction_pct=15, skill_power_pct=30`/none、`qa-result-legendary-hands`=Legendary HANDS/UNCLASSIFIED/`damage_pct=40, attack_speed_pct=40, pierce=3, area_pct=48`/noneの4件で、HEADとFEETは空、木の棒は廃棄済み。星落としLv3をslot 0、千刃陣Lv2をslot 1へ置き、他skillは未所持とする。combat_score=9,000、final_build_score=3,055、total=12,055を固定する。
- `immortal_100`: 初期木の棒に加え、`qa-immortal-body`=Common BODY/affixなし/`immortal_breastplate`、`qa-immortal-head`=Legendary HEAD/`damage_reduction_pct=25, skill_power_pct=50, cooldown_reduction_pct=24, area_pct=48`/none、`qa-immortal-hands`=Legendary HANDS/`damage_reduction_pct=25, damage_pct=40, attack_speed_pct=40, area_pct=48`/noneを装備する。不死者自身は軽減0、他2件の25+25を2倍して実効100%とする。
- `boss_299`: `qa-boss-bow`=Common MAIN_WEAPON/BOW/`max_hp=10`/noneを装備し、fixture combat stateだけに`main_weapon_damage_override=5000`を持たせる。木の棒はinventory index 0。BOSSはentity_id=0、HP=4,500、位置=(14.25,8.25)、全特殊timer=0、next_entity_id=1とする。

固定object用`QaItemBuilder`はdebug directoryだけに置き、明示されたitem_id、slot、rarity、type、affix列、unique_id、lockedを直接ItemInstanceへ設定する。item_seedは`SeedService.derive(20260827, "qa-item:" + item_id)`、通常品のdisplay_nameはそのitem_seed由来name RNG、unique表示名はUniqueDefinitionから作る。Builderは特性数、値、部位pool、unique半減数をDefinitionCatalogに照合し、不正ならQA構築を終了2で失敗させる。`inventory_controller`では`qa-inventory-33`だけをBuilderへ渡し、それ以外のitemはitem_seedを同式、特性用fixture-local RNG seedを`SeedService.derive(20260827, "qa-affix:" + item_id)`へ固定し、ItemFactoryへ表のslot / rarity / type / uniqueを渡す。1itemごとにlocal RNGを破棄し、RunStateの3つのmutable stream stateは全QA構築前後で完全一致させる。QA専用の無限HP、5000 damage、停止flagはfactory生成stateだけのoverrideで、Resource、通常ItemInstance、通常RunState factoryへ書き戻さない。

実行形式は次へ固定する。

~~~powershell
. ".\tests\process_log.ps1"
$logPath = [System.IO.Path]::GetFullPath(".\artifacts\gate-05\tests.txt")
$settingsPath = [System.IO.Path]::GetFullPath(".\artifacts\gate-05\test-user\qa_inventory_controller\settings.cfg")
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null
$testUserRoot = [System.IO.Path]::GetFullPath(".\artifacts\gate-05\test-user") + [System.IO.Path]::DirectorySeparatorChar
if (-not $settingsPath.StartsWith($testUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "QA settings path escaped test-user" }
if (Test-Path -LiteralPath $settingsPath) { Remove-Item -LiteralPath $settingsPath -Force -ErrorAction Stop }
Invoke-JarjarLoggedProcess -LogPath $logPath -Label "qa_inventory_controller" -FilePath $env:JARJAR_GODOT -Arguments @("--path", ".", "--", "--qa-scenario=inventory_controller", ("--settings-path=" + $settingsPath))
~~~

Gate 3で3 weapon IDと3 failure ID、Gate 4で`reward_controls`、Gate 5で残る4 IDを実装する。各Gateのunit testはID一覧、開始phase、主要固定値、RNG state不変、全IDのruntime tutorial inactive、設定値不変、不明IDの終了コード2を検証する。Gate 3ではW1の6 fixtureが最初のphysics tickから通常pipelineへ入ることも検証する。Gate 6ではReleaseが全IDを終了コード2で拒否し、通常起動へ混入しないことを検証する。

### 5.5 設定データの隔離

project.godotは`application/config/use_custom_user_dir=true`、`application/config/custom_user_dir_name="ProjectJARJAR"`へ固定し、Windows Releaseの設定ファイルを`%APPDATA%\ProjectJARJAR\settings.cfg`だけに限定する。SettingsStoreは自動初期化せず、4.1の引数検証後にだけ明示初期化する。通常Releaseは`initialize_for_game(user://settings.cfg)`、Debug/test main sceneは`--settings-path=<絶対cfg path>`を受け、解決後pathがrepositoryの`artifacts/gate-NN/test-user/`配下である場合だけ`initialize_for_game()`へ依存注入する。Release smokeは`initialize_ephemeral()`だけを使い、pack auditは未初期化のまま実行する。値欠落、相対path、範囲外pathは初期化と全file I/Oより前に終了コード2。Releaseはこの引数を終了コード2で拒否する。独自runner、evidence、QA scenario、performance、debug exported smokeというfile-backedの全自動Debug/test起動は専用の空`--settings-path`を必須とし、実ユーザーのsettings.cfgを読書きしない。引数なしの通常debugはuser://settings.cfgを使い、Release smokeとpack auditはsettings pathを渡さない明示例外とする。各file-backed自動プロセスの起動直前に、解決済みcfg pathが当該`artifacts/gate-NN/test-user/`直下または子孫であることをcase-insensitive比較で再検証し、そのcfgファイル1件だけが存在すれば`Remove-Item -LiteralPath ... -Force`で削除する。親directoryや他fileは削除しない。test runner起動時には`initialize_for_runner()`がGate共通の`test-user/runner/settings.cfg`をbootstrap設定先として使用する。各testは開始前に`SettingsStore.use_test_path(<test_nameの絶対cfg path>)`を1回呼び、同じ範囲検証に成功した後だけ`artifacts/gate-NN/test-user/<test_name>/settings.cfg`へ切り替え、その単一fileを削除して既定値を再読込する。各testの成功・失敗・例外にかかわらず`finally`で`SettingsStore.restore_runner_bootstrap_path()`を1回呼んでbootstrap pathの既定値へ戻し、test間で設定値を共有しない。`use_test_path()`とrestoreは`initialized=true`かつ`runner_safe_mode=true`の時だけ使用できる。範囲外pathなら切替えもI/Oもせず当該testを失敗させるため、同Gate再実行でも実ユーザー設定へ触れず常に既定値から始める。

Gate 1で`tests/run_with_clean_settings.ps1`を作る。引数は`-Executable`、`-Arguments`、`-Label`、`-ExpectedExitCodes`、`-WorkingDirectory`の5つとし、ExpectedExitCodesの既定値は`@(0)`、他4つは必須とする。Argumentsの宣言は`[Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$Arguments`へ固定し、通常起動で渡す空配列も受理する。対象設定を上記のsettings.cfg 1ファイル、logを`artifacts/gate-06/tests.txt`へ固定する。ExecutableとWorkingDirectoryは既存の絶対pathへ解決する。実行前に既存ファイルがあれば`artifacts/gate-06/user-settings-backup-<UTC yyyyMMddTHHmmssZ>-<32桁GUID>/settings.cfg`へコピーし、そのSHA-256を記録してから元ファイルだけを除去する。さらに実行前後で`%APPDATA%\ProjectJARJAR`配下の全fileからroot直下のexact path `%APPDATA%\ProjectJARJAR\settings.cfg`だけを除外し、root相対pathを`/`区切り・ordinal昇順に並べた値と各fileのSHA-256をmemory上のmanifestにする。pathやhash自体はlogへ出さず件数と一致／不一致だけを記録し、追加・削除・内容変更が1件でもあれば失敗する。rootがなければ空manifestとする。外側の`try/finally`で設定復元を保証し、内側の`try/finally`でWorkingDirectoryへPush-Locationして必ずPopする。その中で`process_log.ps1`の`Invoke-JarjarLoggedProcess`へ固定LogPathと4つのprocess parameterを渡して指定プロセスを待機実行する。終了後は既存ファイルがあった場合にbackupから復元してSHA-256一致を検証し、なかった場合はQA中に作られたsettings.cfgだけを除去する。親ディレクトリの再帰削除、他ファイルの移動、backupの上書きを禁止する。native終了値がExpectedExitCodes内、設定復元成功、非settings manifest一致のすべてを満たせばwrapper自身は明示的に`exit 0`、検証・実行・復元失敗は`exit 1`、wrapper引数不正は`exit 2`とする。Releaseのsmoke、pack audit、QA引数拒否、最終E2E、各tester起動を含む全自動・手動検証起動は必ずこのscriptを通す。

Windows exportでは`debug/export_console_wrapper=2`によりDebugとReleaseの双方へ`ProjectJARJAR.console.exe`を生成する。export済みbuildの自動smoke、pack audit、引数拒否、最終E2Eは、同じbasenameの`ProjectJARJAR.exe`と`ProjectJARJAR.pck`を起動して標準出力／標準エラーと終了コードを中継するこのconsole wrapperを`-Executable`へ渡す。配布体験を測る人間プレイテストだけはGUIの`ProjectJARJAR.exe`を渡す。console wrapperはQA補助物であり、Release build identityやSteam配布物には含めない。

## 6. 工程1 — 環境固定、Git、プロジェクト骨格

### 6.1 コピー用指示文

~~~text
Project JARJAR の工程1だけを実行してください。リポジトリルートの outputs/project-jarjar-mvp-agent-runbook.md と outputs/project-jarjar-game-proposal.md を最後まで読み、本書を内部契約の正としてください。次工程には進まないでください。

開始状態を確認し、既存の.gitや想定外のファイルがない場合だけ`git init --object-format=sha1 -b main`を実行してください。6.2のexact whitelistと一致する`.codex/skills/godot-gdscript-guard/`だけは既知のローカル支援fileとして許可し、Git管理外としてください。git user.name / user.emailが未設定なら変更せず、人間へ報告して停止してください。公式 Godot 4.7.2-stable Standard win64 と同版 Export Templates を、本書の固定URLから取得し、固定SHA-256照合後だけ導入してください。Godot 本体、`_sc_`、`editor_data/export_templates/4.7.2.stable`はすべて tools/godot 配下へ置き、tools はGit管理外とします。共有`%APPDATA%`と既存の PATH 上の4.7-stableは使用しません。

project.godot を作成し、Compatibility renderer、60Hz physics、1920×1080論理解像度、1280×720の初期ウィンドウ、canvas_items stretch、`use_custom_user_dir=true`、`custom_user_dir_name="ProjectJARJAR"`、`debug/file_logging/enable_file_logging=false`、`debug/file_logging/enable_file_logging.pc=false`、`rendering/shader_compiler/shader_cache/enabled=false`を設定してください。InputMapへ move_up=W/Up/左スティックY負、move_down=S/Down/左スティックY正、move_left=A/Left/左スティックX負、move_right=D/Right/左スティックX正、ui_up=Up/方向パッド上/左スティックY負、ui_down=Down/方向パッド下/左スティックY正、ui_left=Left/方向パッド左/左スティックX負、ui_right=Right/方向パッド右/左スティックX正、ui_accept=Enter/ゲームパッドA、ui_cancel=Escape/ゲームパッドB、item_lock=L/ゲームパッドX、reward_open_all=F/ゲームパッドY を登録してください。InputMapの追加actionはこれら以外に作らないでください。

本書のディレクトリ構成、.godot-version、.gitattributes、.gitignore、README.md、project.godot、export_presets.cfg を作ってください。.godot-versionの内容は4.7.2-stableです。.gitignoreには .codex/、.godot/、tools/、build/、artifacts/、work/、*.log、.godot/export_credentials.cfg を含めます。export preset名は Windows Desktop、対象はx86_64、出力は build/windows/ProjectJARJAR.exe、`binary_format/embed_pck=false`、`debug/export_console_wrapper=2`とし、ProjectJARJAR.pckを必ず分離生成します。値2はDebugとReleaseの双方で`ProjectJARJAR.console.exe`を生成する指定です。Release presetの除外filterへ tests/*、src/debug/*、scenes/debug/*、outputs/*、docs/* を登録してください。

SettingsStoreを唯一のAutoloadとして作り、`_enter_tree()`と`_ready()`ではfile I/Oを行わないでください。通常起動ではGameAppの引数検証成功後にだけ`initialize_for_game()`を呼び、user://settings.cfgへ master_volume=1.0、music_volume=0.8、sfx_volume=0.9、reduce_motion=false、reduce_flashes=false、controller_vibration=true、tutorial_seen=false を保存・読込できるようにしてください。存在しない設定ファイルはこの既定値で作ります。ランやスコアは保存しません。4.1どおり、`--script res://tests/test_runner.gd`でもSettingsStoreはAutoloadされる前提で`initialize_for_runner()`、runner safe mode、`active_settings_path`、`use_test_path()`、`restore_runner_bootstrap_path()`を実装してください。Release smokeだけは`initialize_ephemeral()`の既定値を使い、pack auditは未初期化のままとし、runnerと両保守modeでは実ユーザーのuser://settings.cfgを一度も開かないでください。

Main sceneはGameApp root 1 Nodeだけで作り、GameAppの`_enter_tree()`が引数検証と対応するSettingsStore初期化を完了するまで子Nodeを生成しないでください。その後にBOOTからTITLEへの遷移とタイトル画面を作ってください。タイトル画面は仮題 Project JARJAR、Godot実行バージョン、renderer名、「開始」「終了」を表示します。工程1時点の縦focus順は`title_start, title_exit`、初期focusは`title_start`、上下循環・左右selfとし、表示frame末尾にdeferred grab_focusしてください。開始はまだbootstrap確認画面へ遷移するだけで構いませんが、空画面やエラーにしないでください。`--smoke-quit=<physics frames>` を受けた場合はTITLE表示後に指定physics frame数を待って終了コード0で閉じ、値が欠落・非整数・1未満なら終了コード2にしてください。通常起動では自動終了しません。

外部アドオンを使わないtests/test_runner.gd、最小のassertion helper、本書5.2どおりのtests/process_log.ps1とtests/run_gate_checks.ps1、本書5.5どおりのtests/run_with_clean_settings.ps1を作り、unit/smoke_bootstrap_test.gdでSettingsStore既定値、test path隔離、runner起動時にもSettingsStore Autoloadが存在すること、runner_safe_mode=true、active_settings_path一致、test別path切替えとbootstrap復帰、BOOT→TITLE、TITLEの初期focusと4方向neighbor、両file logging設定=false、shader cache設定=falseを含むプロジェクト設定、検証scriptの不正GateNumber／Suite拒否を検証してください。実ユーザーsettings.cfgの存在・長さ・SHA-256・更新日時不変、不正runner引数のI/O前終了2、不正Debug mainの子Node / RunState / 指定cfg 0件・終了2は`run_gate_checks.ps1`の別process integrationとして検証してください。enumは工程2で実装します。src/debug/evidence_capture.gdとdebug evidence sceneを作り、--evidence=gate_01:bootstrapで artifacts/gate-01/bootstrap.png を自動生成して終了させてください。

Godot import、全テスト、エディタ起動終了、Windows debug exportを順に実行してください。すべて成功した後だけ、追跡対象を明示してステージし、コミットメッセージ chore: bootstrap Godot 4.7.2 project でコミットしてください。コミット後のgit statusは空にしてください。

最後に、本書2.4の形式で結果、テスト、PNG絶対パス、commit hash、clean statusを報告し、「次工程は未着手。人間の明示承認を待つ」と書いて停止してください。
~~~

### 6.2 必須検証と合格条件

工程冒頭、ファイル作成より前に次を実行する。既存の`.git`があれば必ず停止し、このコードを迂回して初期化しない。

~~~powershell
$jarjarGitName = git config --get user.name 2>$null
$jarjarGitEmail = git config --get user.email 2>$null
if ([string]::IsNullOrWhiteSpace($jarjarGitName) -or [string]::IsNullOrWhiteSpace($jarjarGitEmail)) { throw "Git author未設定。人間による設定が必要" }
$jarjarExistingRepo = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -eq 0) { throw ("現在または親ディレクトリの既存Git repositoryを検出したため停止: " + (($jarjarExistingRepo | Select-Object -First 1).Trim())) }
if (Test-Path -LiteralPath ".\.git") { throw "既存の.gitを検出したため停止" }
$jarjarUnexpected = @(Get-ChildItem -Force | Where-Object { $_.Name -notin @(".codex", "outputs", "work") })
if ($jarjarUnexpected.Count -gt 0) { throw ("git init前の想定外ファイル: " + ($jarjarUnexpected.Name -join ", ")) }
$jarjarExpectedCodexEntries = @(
    "dir:skills",
    "dir:skills/godot-gdscript-guard",
    "dir:skills/godot-gdscript-guard/agents",
    "dir:skills/godot-gdscript-guard/references",
    "dir:skills/godot-gdscript-guard/scripts",
    "file:skills/godot-gdscript-guard/SKILL.md",
    "file:skills/godot-gdscript-guard/agents/openai.yaml",
    "file:skills/godot-gdscript-guard/references/gdscript_python_differences.md",
    "file:skills/godot-gdscript-guard/scripts/gdscript_guard.py"
)
if (Test-Path -LiteralPath ".\.codex") {
    if (-not (Test-Path -LiteralPath ".\.codex" -PathType Container)) { throw ".codexはdirectoryでなければならない" }
    $jarjarCodexRoot = (Resolve-Path -LiteralPath ".\.codex").Path
    $jarjarActualCodexEntries = @(Get-ChildItem -LiteralPath ".\.codex" -Force -Recurse | ForEach-Object {
        $jarjarKind = if ($_.PSIsContainer) { "dir:" } else { "file:" }
        $jarjarKind + $_.FullName.Substring($jarjarCodexRoot.Length + 1).Replace("\", "/")
    })
    $jarjarCodexDiff = @(Compare-Object -ReferenceObject $jarjarExpectedCodexEntries -DifferenceObject $jarjarActualCodexEntries)
    if ($jarjarCodexDiff.Count -gt 0) { throw ".codexは固定のgodot-gdscript-guard支援fileだけでなければならない" }
}
$jarjarExpectedOutputs = @("project-jarjar-game-proposal.md", "project-jarjar-mvp-agent-runbook.md")
$jarjarActualOutputFiles = @(Get-ChildItem -LiteralPath ".\outputs" -File -Recurse | ForEach-Object { $_.FullName.Substring((Resolve-Path -LiteralPath ".\outputs").Path.Length + 1).Replace("\", "/") })
$jarjarOutputDirs = @(Get-ChildItem -LiteralPath ".\outputs" -Directory -Recurse)
$jarjarOutputDiff = @(Compare-Object -ReferenceObject $jarjarExpectedOutputs -DifferenceObject $jarjarActualOutputFiles)
if ($jarjarOutputDirs.Count -gt 0 -or $jarjarOutputDiff.Count -gt 0) { throw "outputsは指定Markdown 2件だけでなければならない" }
git init --object-format=sha1 -b main
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$jarjarObjectFormat = (git rev-parse --show-object-format).Trim()
if ($LASTEXITCODE -ne 0 -or $jarjarObjectFormat -ne "sha1") { throw ("Git object format mismatch: " + $jarjarObjectFormat) }

$jarjarTemp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("jarjar-bootstrap-" + [guid]::NewGuid().ToString("N")))
$engineZip = Join-Path $jarjarTemp.FullName "Godot_v4.7.2-stable_win64.exe.zip"
$templateTpz = Join-Path $jarjarTemp.FullName "Godot_v4.7.2-stable_export_templates.tpz"
$engineDir = Join-Path (Get-Location) "tools\godot"
New-Item -ItemType Directory -Force -Path $engineDir | Out-Null
Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip" -OutFile $engineZip -ErrorAction Stop
Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz" -OutFile $templateTpz -ErrorAction Stop
$expectedEngineSha = "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953"
$expectedTemplateSha = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
$actualEngineSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $engineZip).Hash.ToLowerInvariant()
$actualTemplateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $templateTpz).Hash.ToLowerInvariant()
if ($actualEngineSha -ne $expectedEngineSha) { throw ("Godot engine SHA-256 mismatch: " + $actualEngineSha) }
if ($actualTemplateSha -ne $expectedTemplateSha) { throw ("Godot templates SHA-256 mismatch: " + $actualTemplateSha) }
Expand-Archive -LiteralPath $engineZip -DestinationPath $engineDir -Force -ErrorAction Stop
New-Item -ItemType File -Force -Path (Join-Path $engineDir "_sc_") | Out-Null

$templateZip = Join-Path $jarjarTemp.FullName "Godot_v4.7.2-stable_export_templates.zip"
$templateExtract = Join-Path $jarjarTemp.FullName "templates-extracted"
Copy-Item -LiteralPath $templateTpz -Destination $templateZip -Force
New-Item -ItemType Directory -Force -Path $templateExtract | Out-Null
Expand-Archive -LiteralPath $templateZip -DestinationPath $templateExtract -Force -ErrorAction Stop
$templateDestination = Join-Path $engineDir "editor_data\export_templates\4.7.2.stable"
$requiredTemplates = @("windows_debug_x86_64.exe", "windows_debug_x86_64_console.exe", "windows_release_x86_64.exe", "windows_release_x86_64_console.exe")
if (Test-Path -LiteralPath $templateDestination) {
    $invalidTemplates = @()
    foreach ($templateName in $requiredTemplates) {
        $sourceTemplate = Join-Path $templateExtract ("templates\" + $templateName)
        $installedTemplate = Join-Path $templateDestination $templateName
        if (-not (Test-Path -LiteralPath $sourceTemplate) -or -not (Test-Path -LiteralPath $installedTemplate)) {
            $invalidTemplates += $templateName
            continue
        }
        $sourceSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceTemplate).Hash
        $installedSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedTemplate).Hash
        if ($sourceSha -ne $installedSha) { $invalidTemplates += $templateName }
    }
    if ($invalidTemplates.Count -gt 0) { throw ("既存self-contained 4.7.2 templateが公式asset内容と不一致。上書きせず停止: " + ($invalidTemplates -join ", ")) }
} else {
    New-Item -ItemType Directory -Path $templateDestination | Out-Null
    Copy-Item -Path (Join-Path $templateExtract "templates\*") -Destination $templateDestination -Recurse -ErrorAction Stop
}

$env:JARJAR_GODOT = (Resolve-Path -LiteralPath ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe").Path
$jarjarGodotVersion = (& $env:JARJAR_GODOT --version).Trim()
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$jarjarGodotVersion
if (-not $jarjarGodotVersion.StartsWith("4.7.2.stable.official")) { throw ("Godot version mismatch: " + $jarjarGodotVersion) }
~~~

初回ブロックが`git init`後に失敗した場合だけ、人間が「Gate 1の修正を再開」と明示してから次の再開監査を実行する。初回preflightと`git init`は再実行しない。

~~~powershell
$jarjarGitName = git config --get user.name 2>$null
$jarjarGitEmail = git config --get user.email 2>$null
if ([string]::IsNullOrWhiteSpace($jarjarGitName) -or [string]::IsNullOrWhiteSpace($jarjarGitEmail)) { throw "Git author未設定。人間による設定が必要" }
if (-not (Test-Path -LiteralPath ".\.git")) { throw "再開対象の.gitが存在しない" }
$jarjarRepoRootRaw = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) { throw "Gate 1対象repositoryを解決できない" }
$jarjarRepoRoot = [System.IO.Path]::GetFullPath(($jarjarRepoRootRaw | Select-Object -First 1).Trim())
$jarjarExpectedRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
if (-not [string]::Equals($jarjarRepoRoot, $jarjarExpectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "現在ディレクトリがGate 1対象repositoryではない" }
$jarjarBranch = (git branch --show-current 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $jarjarBranch -ne "main") { throw ("Gate 1再開時のbranch不一致: " + $jarjarBranch) }
$jarjarObjectFormat = (git rev-parse --show-object-format 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $jarjarObjectFormat -ne "sha1") { throw ("Gate 1再開時のobject format不一致: " + $jarjarObjectFormat) }
git rev-parse --verify HEAD 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw "既存commitを検出したためGate 1を再開できない" }
$jarjarRemotes = @(git remote 2>$null)
if ($LASTEXITCODE -ne 0 -or $jarjarRemotes.Count -gt 0) { throw "既存remoteを検出したためGate 1を再開できない" }
$jarjarExpectedCodexEntries = @(
    "dir:skills",
    "dir:skills/godot-gdscript-guard",
    "dir:skills/godot-gdscript-guard/agents",
    "dir:skills/godot-gdscript-guard/references",
    "dir:skills/godot-gdscript-guard/scripts",
    "file:skills/godot-gdscript-guard/SKILL.md",
    "file:skills/godot-gdscript-guard/agents/openai.yaml",
    "file:skills/godot-gdscript-guard/references/gdscript_python_differences.md",
    "file:skills/godot-gdscript-guard/scripts/gdscript_guard.py"
)
if (Test-Path -LiteralPath ".\.codex") {
    if (-not (Test-Path -LiteralPath ".\.codex" -PathType Container)) { throw ".codexはdirectoryでなければならない" }
    $jarjarCodexRoot = (Resolve-Path -LiteralPath ".\.codex").Path
    $jarjarActualCodexEntries = @(Get-ChildItem -LiteralPath ".\.codex" -Force -Recurse | ForEach-Object {
        $jarjarKind = if ($_.PSIsContainer) { "dir:" } else { "file:" }
        $jarjarKind + $_.FullName.Substring($jarjarCodexRoot.Length + 1).Replace("\", "/")
    })
    $jarjarCodexDiff = @(Compare-Object -ReferenceObject $jarjarExpectedCodexEntries -DifferenceObject $jarjarActualCodexEntries)
    if ($jarjarCodexDiff.Count -gt 0) { throw ".codexは固定のgodot-gdscript-guard支援fileだけでなければならない" }
}
$jarjarAllowedExact = @(".gitattributes", ".gitignore", ".godot-version", "README.md", "project.godot", "export_presets.cfg")
$jarjarAllowedPrefixes = @(".codex/", "outputs/", "scenes/main.tscn", "scenes/debug/", "scenes/ui/", "src/app/", "src/core/", "src/debug/", "src/ui/", "tests/", "tools/", "build/", "artifacts/", "work/")
$jarjarStatus = @(git status --porcelain=v1 -uall)
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
foreach ($jarjarStatusLine in $jarjarStatus) {
    $jarjarStatusCode = $jarjarStatusLine.Substring(0, 2)
    if ($jarjarStatusCode -notin @("??", "A ", "AM")) { throw ("Gate 1基準commit前の許可外status: " + $jarjarStatusLine) }
    $jarjarPath = $jarjarStatusLine.Substring(3).Replace("\", "/")
    $jarjarAllowed = ($jarjarPath -in $jarjarAllowedExact)
    if (-not $jarjarAllowed) {
        foreach ($jarjarPrefix in $jarjarAllowedPrefixes) {
            if ($jarjarPath.StartsWith($jarjarPrefix, [System.StringComparison]::Ordinal)) { $jarjarAllowed = $true; break }
        }
    }
    if (-not $jarjarAllowed) { throw ("Gate 1再開時の想定外file: " + $jarjarPath) }
}
git status --short --branch
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
~~~

再開監査に合格した場合は、未コミットの途中成果を削除せず、初回ブロック内で最初に失敗した、または完了を証明できないコマンドから再開する。ダウンロード済みファイルも固定versionと整合するものだけ再利用し、以後の実装・検証手順は通常のGate 1と同じにする。

プロジェクト、テスト、evidenceを実装した後、次を順に実行する。

~~~powershell
$env:JARJAR_GODOT = (Resolve-Path -LiteralPath ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe").Path
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\run_gate_checks.ps1" -GateNumber 1 -Suite all
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
. ".\tests\process_log.ps1"
$logPath = [System.IO.Path]::GetFullPath(".\artifacts\gate-01\tests.txt")
New-Item -ItemType Directory -Force -Path ".\build\windows" | Out-Null
Invoke-JarjarLoggedProcess -LogPath $logPath -Label "export_debug" -FilePath $env:JARJAR_GODOT -Arguments @("--headless", "--path", ".", "--export-debug", "Windows Desktop", ".\build\windows\ProjectJARJAR.exe")
$debugExe = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.exe").Path
$debugConsoleExe = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.console.exe").Path
$debugPck = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.pck").Path
$smokeSettings = [System.IO.Path]::GetFullPath(".\artifacts\gate-01\test-user\smoke_debug\settings.cfg")
$evidenceSettings = [System.IO.Path]::GetFullPath(".\artifacts\gate-01\test-user\evidence_bootstrap\settings.cfg")
$testUserRoot = [System.IO.Path]::GetFullPath(".\artifacts\gate-01\test-user") + [System.IO.Path]::DirectorySeparatorChar
foreach ($isolatedSettings in @($smokeSettings, $evidenceSettings)) {
    if (-not $isolatedSettings.StartsWith($testUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Gate 1 settings path escaped test-user" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $isolatedSettings) | Out-Null
    if (Test-Path -LiteralPath $isolatedSettings) { Remove-Item -LiteralPath $isolatedSettings -Force -ErrorAction Stop }
}
$jarjarUserRoot = Join-Path ([Environment]::GetFolderPath("ApplicationData")) "ProjectJARJAR"
$jarjarRealSettings = Join-Path $jarjarUserRoot "settings.cfg"
function Get-JarjarNonSettingsManifest([string]$Root, [string]$ExcludedFile) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return [string[]]@() }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($item in Get-ChildItem -LiteralPath $Root -File -Recurse -Force) {
        if ([string]::Equals($item.FullName, $ExcludedFile, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $relative = $item.FullName.Substring($rootFull.Length).Replace("\", "/")
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        $entries.Add($relative + "|" + $hash)
    }
    $result = $entries.ToArray()
    [System.Array]::Sort($result, [System.StringComparer]::Ordinal)
    return [string[]]$result
}
$nonSettingsBefore = @(Get-JarjarNonSettingsManifest -Root $jarjarUserRoot -ExcludedFile $jarjarRealSettings)
Invoke-JarjarLoggedProcess -LogPath $logPath -Label "smoke_debug" -FilePath $debugConsoleExe -Arguments @("--", "--smoke-quit=120", ("--settings-path=" + $smokeSettings))
Invoke-JarjarLoggedProcess -LogPath $logPath -Label "evidence_bootstrap" -FilePath $env:JARJAR_GODOT -Arguments @("--path", ".", "--", "--evidence=gate_01:bootstrap", ("--settings-path=" + $evidenceSettings))
$nonSettingsAfter = @(Get-JarjarNonSettingsManifest -Root $jarjarUserRoot -ExcludedFile $jarjarRealSettings)
if ($nonSettingsBefore.Count -ne $nonSettingsAfter.Count) { throw "ProjectJARJAR non-settings manifest count changed" }
for ($i = 0; $i -lt $nonSettingsBefore.Count; $i++) {
    if ($nonSettingsBefore[$i] -cne $nonSettingsAfter[$i]) { throw "ProjectJARJAR non-settings manifest changed" }
}
("APPDATA_NONSETTINGS_OK before={0} after={1}" -f $nonSettingsBefore.Count, $nonSettingsAfter.Count)
~~~

合格条件:

- 2 assetのSHA-256が本書の固定値と完全一致し、`tools/godot/_sc_`とself-contained Export Templates 4本が存在する。共有`%APPDATA%`は変更されていない。
- Git branchがmain、object formatがsha1、remote 0件、基準commit後のHEADが40文字である。
- Godot の version が 4.7.2.stable.official で始まる。
- rendering_method と rendering_method.mobile が gl_compatibility。
- `debug/file_logging/enable_file_logging`、`.pc` override、`rendering/shader_compiler/shader_cache/enabled`がすべてfalseで、debug smoke/evidence後も`%APPDATA%\ProjectJARJAR`へ新しい非settings fileが0件。
- Autoload は SettingsStore だけ。
- import、テスト、debug export の終了コードがすべて0。
- build/windows/ProjectJARJAR.exe、ProjectJARJAR.console.exe、ProjectJARJAR.pckが存在し、console wrapper経由の起動後にタイトルを表示して自動終了用 --smoke-quit=120 を受け付ける。
- artifacts/gate-01/bootstrap.png にタイトル、バージョン、renderer、「開始」「終了」が写る。
- Git に .codex、tools、build、artifacts、.godot が含まれない。
- コミット後の working tree が clean。

## 7. 工程2 — 決定的ドメインモデルと純粋ロジック

### 7.1 コピー用指示文

~~~text
直前の人間メッセージが本書2.4の「ゲート1承認 H。工程2へ進んでよい」と完全に対応することを確認してください。Project JARJAR の工程2だけを実行し、最初に本書を最後まで再読して、Hと現在のclean HEADの完全一致、main branch、remote 0件を確認してください。満たさなければ停止し、次工程には進まないでください。

本書4章のenum、ItemInstance、AffixRoll、SkillState、PendingSkillActivation、ScheduledProcReplay、DamageSample、RunRngStreams、WaveDefinition、BalanceManifest、RewardRoll、RunState、CombatEvent、CombatSnapshotを型付きGDScriptで実装してください。4.2.1の静的Resource class、固定`.tres`、DefinitionCatalogを実装し、ランタイム型はRefCountedにしてください。

SeedService、RunRngStreamsが所有するcombat/loot/fusionの3本のmutable run RNG stream、item_seedごとの使い捨てname RNGを本書どおり実装してください。名前生成はitem_seedだけから決まり、combat/loot/fusion RNGの消費順に影響されないことを保証してください。item_id、drop_serial、木の棒の例外も固定仕様どおりです。

TimerMath、StatCalculator、ItemFactory、NameGenerator、FusionService、ScoreService、RunStateMachineを純粋ロジックとして実装してください。TimerMathは本書4.1のepsilon、clamp、ready、countdown契約を1か所で実装します。FusionServiceは材料検証、ロック/装備中拒否、Legendary拒否、ワイルド最大1、ユニーク警告要求、出力抽選を返し、UIを参照しないでください。ScoreServiceは内訳と合計を返してください。RunStateMachineは許可遷移以外を拒否し、同tickのノルマ成立を死亡・時間切れより先にラッチしてください。

8つのWaveDefinitionを本書の表どおり.tres化し、`data/balance/balance_manifest.tres`を`balance_revision=0`で作成してください。数値をコードへ二重定義せず、プロダクションとテストが同じResourceを読むようにしてください。

unit testとして、同seed再現、stream独立、名前の独立、item_id、特性数、部位プール75%/共通25%、武器相性2倍のselector単体統計、合成成功/全拒否条件/ユニーク確認、状態遷移、W8の遷移、スコア12,055点、100%軽減、攻撃0.05秒下限、スキル0.25秒下限を実装してください。W8は `wave_kills=300/boss_defeated=false` と `299/true` の両方を失敗、`300/true`だけを成功として固定テストします。統計テストはseed `0..9999`を用います。selector単体試験では同じ候補集合に好相性1候補・非相性1候補だけを置き、観測比1.8..2.2を要求します。実生成品の最終頻度比は75%/25%の二段抽選と候補集合差の影響を受けるため、2倍判定には使いません。

debug evidence sceneへlogic_diagnostics状態を追加し、seed、combat/loot/fusionの3つのmutable run streamの先頭3値、生成アイテム例4個と各item_seed由来name RNGの先頭3値、合成例、12,055点の内訳、全unit test PASS件数を画面表示し、artifacts/gate-02/logic_diagnostics.pngを生成してください。

importと全テストを通し、警告をエラー扱いにしてparser error、orphan Node、Resource leakが0であることを確認してください。すべて成功後だけ、コミットメッセージ feat: add deterministic run domain model でコミットしてください。

最後に本書2.4の形式で報告し、「次工程は未着手。人間の明示承認を待つ」と書いて停止してください。
~~~

### 7.2 必須テスト

- game_types_test: enum の全値と文字列変換。
- seed_service_test: 同 seed・同 stream の列が一致し、異なる stream が一致しない。
- rng_isolation_test: combat を10,000回余計に消費しても loot/name/fusion の結果が不変。
- item_factory_test: 木の棒、部位、主武器タイプ、特性数、同一特性なし、ユニーク時の特性半減。
- name_generator_test: 同じitem_seedで完全一致する。固定の1特性通常品をitem_seed `0..999`で生成し、8素材語と4つの単特性副名をすべて1回以上出し、異なるdisplay_nameを28..32種類得る。2特性品では第2特性に対応する副名が全9特性で固定される。
- weighted_selector_boundary_test: 検証済み入力へ注入したrandf値0.0で最初の正重み候補、1.0で最後の正重み候補を返す。重み`[88,11,1,0]`のrandf=1.0でも末尾の0重み候補を返さず、その候補が10,000回の端点混在試験で一度も選ばれないことを検証する。候補0件、配列長不一致、負の重み、重み合計0は`validate_weights`がログなしでfalseを返し、呼出側のRNG呼出回数が0のままであることも検証する。
- affix_pool_test: seed `0..9999`。フォールバックが不要な候補集合で、部位固有pool選択率75%±1.0ポイント、共通pool25%±1.0ポイント。
- affinity_weight_test: seed `0..9999`。同一pool内の好相性1候補と非相性1候補だけを与えたweighted selector単体で観測比1.8..2.2。
- fusion_service_test: 3対1、2+wild、1+2wild拒否、rarity不一致拒否、locked拒否、equipped拒否、Legendary拒否、unique確認。
- phase_test: `can_transition`で許可遷移全件と拒否遷移全件を副作用・logなしで検証し、実transition APIでは許可遷移全件だけを検証する。ノルマ/死亡同tick、ノルマ/時間切れ同tickも含む。
- score_test: 固定例が12,055。
- stat_calculator_test: 演算順、100%軽減=0 damage、attack interval>=0.05、time skill>=0.25。
- timer_math_test: 4.1記載の全固定秒数が60Hzの指定tickより早くreadyにならず、指定tickでreadyになり、60秒countdownが3,600tickで正確な0になる。

合格証跡:

- tests suite all が全件成功。
- artifacts/gate-02/logic_diagnostics.png。
- テスト標準出力を artifacts/gate-02/tests.txt に保存。
- コミット後 clean。

## 8. 工程3 — 3Dアリーナ、戦闘、8ウェーブ

### 8.1 コピー用指示文

~~~text
直前の人間メッセージが本書2.4の「ゲート2承認 H。工程3へ進んでよい」と完全に対応することを確認してください。Project JARJAR の工程3だけを実行し、Hと現在のclean HEADの完全一致、main branch、remote 0件を確認してください。満たさなければ停止し、次工程には進まないでください。

30m×18mの障害物なし3Dアリーナ、プレイヤー移動、固定斜め見下ろしカメラ、4通常敵、W4エリート、W8ボス、木の棒/弓/杖/剣、自動照準、自動攻撃、HUD、ウェーブ状態遷移を実装してください。本書3.3から3.5の数値を変更しないでください。

工程1のbootstrap確認画面とその遷移を削除し、TITLEの「開始」から新seedのW1 COMBATへ直接進むよう置き換えてください。bootstrap用scene、script、文言を追跡ファイルとReleaseから残さず、TITLE→COMBATを自動テストしてください。

敵は容量768の密な配列とMultiMeshで、味方/敵飛翔物は合計容量4096の固定プールとMultiMeshで実装してください。敵または弾1体ごとのNodeを作らないでください。2m uniform gridで近傍検索し、entity_id順のtie-breakを守ってください。短命VFXも容量4096のプールとし、枯渇カウンタをHUDのdebug overlayへ表示してください。

入力は移動だけです。攻撃、照準、スキル、ダッシュのInput actionを作らないでください。プレイヤーは5.0m/sで境界内にclampし、カメラは本書のorthographic値と追従値を使ってください。

4主武器の対象選定、攻撃間隔、射程、形状、弾速、貫通を固定仕様どおり実装してください。本書5.4の`weapon_bow`、`weapon_staff`、`weapon_sword`を実装し、通常ゲームでは工程4以降の報酬装備まで木の棒を使います。

EnemySystemは固定ウェーブResourceを読み、線形spawn rate、敵構成比、HP/ダメージ倍率、出現位置をcombat RNGだけで決めてください。W4の経過30秒エリート、W8開始ボス、ボス生存中の非ボス生成総数299上限、ボス撃破後の通常spawn再開を実装してください。ボス召喚も299上限へ含めます。

CombatEventRouterで一次/二次、payloadを表すsource_effect_id、生成procを表すproc_effect_id、procだけを保持するeffect_chain、chain_depthを実装してください。二次生成時に同じproc_effect_idが履歴にあれば拒否し、source_effect_idの重複だけでは拒否しません。深度16からの追加生成を拒否してください。この工程ではスキルとユニークは未接続ですが、後続工程が同じrouterを使える状態にします。

HUDはウェーブ番号、残り秒、小数切上げ表示、現在キル/ノルマ、HP、主武器名、箱数0、wave_cleared後の「BONUS TIME」、debug buildだけのactive enemy/projectile/VFX/pool overflowを表示してください。工程3時点でも2スキル枠を「未装着」として表示し、工程5で進捗表示へ置換できる固定領域を確保します。W8でboss_defeated=falseなら常時「300到達にはボス撃破が必要」、さらにnon_boss_spawned=299なら「通常敵スポーン停止中」を併記し、boss_defeated=trueなら「ボス撃破済み／通常敵スポーン中」へ置換してください。

scenario testとして、Camera3Dのorthographic / size 13.0 / 方位角45度 / 俯角55度、4武器の対象/範囲/攻撃間隔、4通常敵挙動、エリート予告、ボス弾幕/召喚、W1..W8定義、初期木の棒でW1 TRACKERを1撃、連続射程内なら40体を32.0秒以内に撃破、ノルマ前死亡、時間切れ、ノルマ後死亡、同tick優先、全回復、W8ボス未撃破299停止、ボス後spawn再開を実装してください。生成直後に対象を重ねた敵の初接触は各contact interval経過tick、RANGED初弾は生成108tick後、ELITE初予告は240tick後・解決はさらに72tick後、BOSS初弾幕は180tick後、初召喚は360tick後であることを固定します。注入RNGで通常spawnのtype 1回→各位置試行edge/coordinate 2回の順、accept後の消費停止、16reject後の固定cornerと追加消費0、blocked spawnの消費0を検証します。同じtickにBOSS召喚と通常spawnがreadyで非ボス残り枠とpool空きが3なら、召喚が3枠、対応するcombat RNG、連続するentity_idを先に使い、通常spawnは0体かつspawn_creditを保持することを検証してください。その3体、このtickに撃たれた敵弾、このtickに生成された味方弾はいずれもborn tickでは移動、接触、命中、攻撃、対象選定へ参加せず、次tickから参加することを検証してください。飛翔物poolでは空きindex 2, 7, 9から2→7→9の順に確保し、tick開始snapshotのindex 2・generation Gを解放後に同tickでindex 2をgeneration G+1として再確保しても、旧snapshot処理が新世代へ命中を発生させず、次tickからだけ処理することを固定します。W4の30秒到達tickに通常spawnとELITE生成が重なれば、通常敵が小さいentity_id、ELITEが次のentity_idを得ることも固定します。シナリオは描画を不要とする固定tickシミュレーションで実行してください。

uniform gridの固定testも追加してください。中心(0,0)・半径4.1m・padding 0の円queryは3×3より外の該当cellを含み、4.1m境界上を含め4.11mを除外します。arena外へはみ出すAABBはindex範囲へclampします。(-14.9,-8.9)から(14.9,8.9)への線分queryは横断cellを欠落せず、候補をcell_key・entity_id順で正確な線分円交差へ渡します。弓14m索敵、area強化で効果半径4.5mになった杖爆発、複数cellを横断する高速弾を各1ケース検証し、いずれも固定3×3だけで候補を切らないことをassertしてください。杖fixtureでは爆発中心から5.75mにBOSS中心を置いて`4.5 + 1.25`境界を命中、5.7501mを非命中とし、BOSS中心が効果半径4.5mのAABB外かつpadding込みAABB内の別cellにあることを要求します。味方矢は線分から1.45mにあるBOSSを`0.20 + 1.25`境界で命中、1.4501mで非命中、敵弾は線分から0.70mにあるプレイヤーを`0.25 + 0.45`境界で命中、0.7001mで非命中とし、broad-phase最大半径と個体別の正確判定を混同しないことをassertしてください。

evidenceをarena_combat、weapon_shapes、boss_gateの3状態で生成してください。arena_combatはプレイヤー、4敵種、HUDと「未装着」の2スキル枠を、weapon_shapesは弓の軌道/杖範囲/剣扇形を同時に示し、boss_gateはボス、299/300表記、「300到達にはボス撃破が必要」「通常敵スポーン停止中」を示してください。

import、全テスト、debug exportを通し、すべて成功後だけ feat: implement arena combat and wave flow でコミットしてください。最後に本書2.4の形式で報告し、次工程を開始せず停止してください。
~~~

### 8.2 シナリオ合格条件

- プレイヤーはキーボードと左スティックでのみ移動し、斜め速度が増えない。
- 中央からX外周まで3.0秒±1 physics tick。
- Camera3Dがorthographic、size 13.0、方位角45度、俯角55度である。
- 木の棒、弓、杖、剣が表のダメージ、間隔、射程、形状どおり。
- 3×3を越える円・扇形・線分AABB queryがcellを欠落せず、境界包含、arena clamp、候補順、正確なshape判定が固定テストどおり。
- W1のHP10 TRACKERは木の棒1撃で倒れ、射程内へ敵を連続供給する固定試験で40体を32.0秒以内に倒せる。
- 敵タイプ選定、spawn位置、攻撃結果は同じseedと同じ入力記録で再現する。
- W4にエリートがちょうど1体、W8開始tickにボスがちょうど1体。
- ボス生存中は非ボスの生成総数が299を超えず、非ボスだけではキルが300にならない。
- W8 HUDはboss生存中、299停止中、boss撃破後の3状態で固定文言を正しく切り替え、2スキル枠は工程3時点で「未装着」と表示する。
- ノルマ前死亡/時間切れは FAILED、ノルマ後死亡/時間切れは REWARD_REVEAL。
- 次ウェーブ開始時HPが最大。
- 敵500体をdebug強制生成しても個別の敵Nodeが0で、pool overflowが0。
- artifacts/gate-03/arena_combat.png、weapon_shapes.png、boss_gate.png が存在。

## 9. 工程4 — 宝箱、loot、開封演出

### 9.1 コピー用指示文

~~~text
直前の人間メッセージが本書2.4の「ゲート3承認 H。工程4へ進んでよい」と完全に対応することを確認してください。Project JARJAR の工程4だけを実行し、Hと現在のclean HEADの完全一致、main branch、remote 0件を確認してください。満たさなければ停止し、次工程には進まないでください。

敵死亡から箱抽選、箱の物理的な跳ねと自動吸収、RewardRollの獲得時確定、報酬キュー、保証主武器、装備/スキル比率、レアリティ、4%ユニーク、報酬開封画面を本書3.6どおり実装してください。

各ウェーブで通常率または特殊敵固定ドロップから最初に自然獲得した箱を保証箱に置き換え、元の内容抽選や追加の通常抽選をしないでください。さらにノルマ成立時に自然獲得箱が0で保証主武器RewardRollが未生成なら、プレイヤー位置へ保証箱を1個生成して即時獲得するフォールバックを実装し、すでに保証済みなら重複付与しないでください。箱は全レアリティで同一メッシュ/マテリアル/色、0.25秒の跳ね後HUDへ自動吸収とします。表示プール128が埋まっても報酬を失わず、最古を即吸収して再利用してください。

RewardRollは箱ドロップ成立tickに論理獲得され、loot RNGで完全確定します。装備ならitem_id、item_seed、部位、主武器タイプ、レアリティ、特性、unique_id、名前まで確定してください。0.25秒の箱挙動は表示だけです。成功終了時は表示中の獲得済み箱を即吸収し、失敗時は当該waveのRewardRollを破棄してください。開封画面はRewardRollを読むだけでRNGを呼びません。

開封UIは未開封箱数、現在カード、獲得一覧、0.35秒自動進行、決定長押し4倍速、「すべて開ける」を備えます。本書3.12の`reward_speed_proxy`を初期focusとし、A長押しとbutton activationの優先規則、Y全開封、設定overlayからのfocus復元を固定どおり実装してください。Epic/Legendaryは公開前の真の先バレを必須とし、偽予告は禁止します。全開封時の0.75秒集約予告、対象カードごとの震動・段階点灯、Reduce Motion、Reduce Flashes、controller vibrationの設定を反映してください。色に加え、レアリティ文字と輪郭形状を使ってください。

本書5.4の`reward_controls`を実装し、固定4報酬の通常、4倍、全開封でRewardRollと全RNG stateが不変であることを検証してください。controller scenarioはpointer event 0件で、初期focusがproxy、Aを0.25秒未満で離して設定が開かない、0.25秒到達後だけ4倍になりreleaseで通常へ戻る、settingsへfocus移動後の短いAだけで開く、閉じると同位置へ復帰する、settings上のA長押しでoverlayが開かない、どのfocusからもYで全開封できることをassertします。mouse scenarioはproxy内pressから0.25秒未満／以上、proxy外release、各button上pressを分け、4倍flagとclick回数が3.12どおりであることをassertします。

loot simulation testを実装してください。箱数テストではrun seedを`0..99`、各waveの通常キル数をceil(kill_quota×1.5)とし、W4はエリート箱3、W8はボス箱8を加え、各wave平均が15以上25以下であることを確認してください。各seed・waveの最初の自然箱は保証へ置換され、箱総数を増やさない仕様をそのまま使います。実装が仕様どおりなのに範囲外なら、勝手に確率を変更せず実測を人間へ提示して停止してください。Gate 4の初回基準commit前だけを初期箱率の校正窓とし、人間が調整を承認した場合だけ通常敵箱率を0.5パーセントポイント刻みで変更し、企画書、本書、WaveDefinition、期待テストを同じ未コミット変更で更新し、balance_revisionを1増やして100 seed試験を最初から行います。レア率、固定箱数、quota、基準キル数は変更しません。Gate 4承認後は箱率を凍結し、Gate 6の回帰試験や人間プレイテストを通す目的では変更しません。

確率分布テストはsimulation RNG seed `20260827`から固定100,000抽選を行い、装備/スキル、レアリティ、保証を除く装備全体のユニーク率、ユニーク非当選品の部位、保証主武器タイプを検証してください。通常loot装備とfusion出力のユニーク／部位試験は別々に100,000回行います。固定ユニーク6種の選択比率は、4%当選後の標本へ条件付けず、UniqueSelectorへ当選済み状態を直接与える独立100,000回で検証します。保証タイプ試験はW1、W2・snapshot=BOW、W2・snapshot=STAFF、W2・snapshot=SWORD、W2・snapshot=UNCLASSIFIEDを別々に100,000回行います。確率許容差は絶対値で、90/10は0.6ポイント、レアリティは各0.5ポイント、通常loot装備とfusion出力のunique 4%は各0.3ポイント、unique非当選品の6部位各1/6は各0.6ポイント、独立UniqueSelectorの固定6種各1/6は各0.6ポイント、50/25/25および1/3ずつは各0.8ポイントです。全装備を無条件に集計した部位比率は、ユニーク品が固定部位を持つため合格判定へ使いません。

同じrun seed `0..99`と8ウェーブの報酬列でfusion progression simulationも行ってください。木の棒は装備したまま材料へ入れず、各wave後に得た未装備品のうちuniqueでない装備だけを候補へ加えます。wildは使いません。Common、Rare、Epicの順に、各rarityでitem_id昇順の先頭3個を実際のFusionServiceへ渡し、3個未満になるまで繰り返します。生成した非unique出力は対応rarityの後続材料に使え、unique出力は保持して以後の自動材料から除外します。直ドロップとfusion生成のEpic / Legendary件数、各seedでfusion由来へ初到達したかを別集計します。合格条件はfusion由来Epic到達95 seed以上、fusion由来Legendary到達90 seed以上、かつEpicとLegendaryの両方で100 seed合計のfusion生成数が直ドロップ数を上回ることです。未達時は値や期待値を変更せず、実測と原因を人間へ報告して停止します。

同じseedと同じ戦闘イベント列なら報酬全フィールドが一致し、開封順、通常/4倍/全開封の選択、Reduce設定を変えても一致するテストを作ってください。装備RewardRollの`rarity_for_presentation`が0..3で対応するレアリティ表示になり、スキル報酬は必ず-1かつ表示「スキル」となってCommon扱いされないことも検証します。FAILEDへ入った場合は当該waveのRewardRollだけが破棄され、過去waveのinventoryは維持されることも検証してください。

evidenceをchest_absorb、epic_prealert、reward_gridの3状態で生成してください。epic_prealertは公開前で内容を隠しながら「高レア予告」であることが分かる静止状態、reward_gridはCommonからLegendaryまで文字と形の差が読める状態にしてください。

import、全テスト、100 seed simulation、debug exportを通し、すべて成功後だけ feat: add deterministic chest rewards でコミットしてください。最後に本書2.4の形式で報告し、次工程を開始せず停止してください。
~~~

### 9.2 合格条件

- 各ウェーブで保証主武器がちょうど1個存在し、通常敵死亡を経ずに成功を強制したテストでもフォールバック箱が1個付与される。
- W1保証タイプは固定多数seedで1/3ずつ、W2以降は現在タイプ50%/他25%/25%へ許容差内で収束する。
- 装備90%/スキル10%、レア表、通常loot装備とfusion出力のunique 4%、unique非当選品の6部位均等、unique当選時の固定6種均等が許容差内。
- 固定100 seed、ceil(quota×1.5)キルで各wave平均15..25箱。
- 固定100 seedの貪欲3対1 simulationでfusion由来Epicへ95 seed以上、Legendaryへ90 seed以上が到達し、両rarityのfusion生成総数が直ドロップ総数を上回る。
- RewardRoll は獲得時に確定し、開封操作で全フィールドが変わらない。
- REWARD_REVEALの初期focus、A長押し4倍、button競合防止、Y全開封、設定復帰がpointer eventなしのcontroller testを通る。
- Epic以上の公開前に必ず先バレがあり、Common/Rareでは発生しない。
- 全箱の世界モデルが同色・同形。
- failure時に現在waveの箱だけが失われる。
- artifacts/gate-04/chest_absorb.png、epic_prealert.png、reward_grid.png が存在。

## 10. 工程5 — 装備、合成、スキル、ユニーク、結果

### 10.1 コピー用指示文

~~~text
直前の人間メッセージが本書2.4の「ゲート4承認 H。工程5へ進んでよい」と完全に対応することを確認してください。Project JARJAR の工程5だけを実行し、Hと現在のclean HEADの完全一致、main branch、remote 0件を確認してください。満たさなければ停止し、次工程には進まないでください。

6装備枠、6×6インベントリ、無制限一時受取欄、ドラッグ装備/並替、比較、ロック、自動低評価選択、保護付き手動廃棄、3対1合成、ワイルド素材、4スキル、6ユニーク、最終スコア、結果画面を固定仕様どおり実装してください。

報酬公開後、装備はinventoryの空きへ、超過はoverflowへ、スキルはlibraryへ、Lv3重複はwild countへ送ってからINVENTORYへ遷移してください。inventoryは最大36、MAIN_WEAPONは常に非nullという不変条件を守り、overflowが空であり、かつ主武器が非nullになるまで次wave/結果ボタンを無効にして、残り処理数または主武器必須エラーを文字表示してください。通常UIでは主武器を単独解除できないためnullへ到達しませんが、遷移gateも防御的に拒否します。

マウスドラッグと本書3.12のコントローラー持ち上げ操作、装備交換、装備からinventoryへの戻し、比較差分、lockを実装してください。INVENTORY、RESULT、FAILED、確認dialogは3.12の初期focus、全4方向neighbor、disabled skip、dialog cancel/confirm後の起点復元を厳密に使います。自動選択は本書の除外条件とbuild_value、item_id tie-breakを厳密に使います。単品廃棄と一括廃棄は装備中・lockedを拒否し、uniqueを含む場合は対象名付き確認を要求し、通貨・score・RNG消費を発生させないでください。合成は純粋FusionServiceをUIから呼び、inventoryとoverflowを横断する材料3枠、出力レアリティと抽選規則だけの非RNGプレビュー、ワイルド最大1、Legendary拒否、unique消失確認を実装してください。比較、一括選択、廃棄、合成、ワイルド投入、次戦／結果の全操作をゲームパッドだけでも完了可能にしてください。

4スキルのtrigger、level、値、対象選定、2装着枠、未装着library、Lv3後wild変換を実装してください。戦闘HUDの各slotへ、空なら「未装着」、封印なら「封印」、装着中ならスキル名、Lv、現在進捗／実効閾値、`pending_queue.size()`を「予約n」として常時表示してください。星落としだけは`進捗秒/実効閾値秒（残り秒）`を各小数1桁、他3種は整数`現在値/実効閾値`で示します。壊れた時計の着脱による閾値正規化と、発動予約後の剰余を同じphysics tickのsnapshotへ反映します。追加攻撃はCombatEvent.effect_chainに発動済みproc IDだけを残し、同じprocの再侵入を拒否しつつ、元の武器／スキルpayloadの1回再演と別効果のkill/hit条件を成立させてください。chain_depthは一次0、派生ごとに+1とし、16からの追加生成を技術保護で拒否してください。

本書5.4の`inventory_controller`、`result_controller`、`immortal_100`、`boss_299`を実装し、表の開始phase、件数、固定値、通常RNG不変をunit testで検証してください。

6ユニークを本書の部位、演算順、閾値、停止条件、snapshot、0.15秒遅延で実装してください。血塗れの短剣のkill bonusはwaveごとにresetし、壊れた時計の整数半減はceil、臆病者の靴は移動中progressも停止、不死者の胸当ては自身の軽減特性を倍化せず、反響は一次攻撃countへ含めず、空洞の王冠は第2slotを操作不能にしてください。

W8報酬公開後も通常どおり整理と合成を行い、overflowが解消された後に結果へ進めてください。結果画面には本書3.11の全項目と内訳を表示し、「同じseedで再挑戦」「新しいseedで再挑戦」「タイトルへ」「終了」の4導線を実装してください。FAILED画面は失敗wave、cleared_waves、seed、combat_score、final_build_score、両者と一致する途中合計を表示し、同じ4導線を持たせてください。「終了」はSceneTree.quit(0)を呼びます。

unit/scenario testとして、36/overflow境界と安定index順、マウスdragとゲームパッド持ち上げの結果一致、MAIN_WEAPON単独解除拒否と交換成功、主武器nullを注入した遷移gate拒否、比較、lock、自動選択、単品/一括廃棄と全保護条件、廃棄時の無報酬/RNG不変、全fusion条件、全skill level/trigger/wild、6unique単体、100%軽減時の報復の鐘、反響と王冠が同じpayloadをちょうど1回再演、追加攻撃が自身のtrigger_progressを進めず別skillだけを進めること、A→B許可/A→B→A拒否、chain_depth=16拒否、臆病者の靴でwave開始から15tick待機・境界へ入力して実移動0なら停止扱い、最終score、W8後整理、同seed retry初期化を実装してください。2枠スキルHUDは空、4trigger種の通常進捗、発動直前、発動予約後の剰余と予約数、壊れた時計着脱、空洞の王冠封印の固定stateで表示文字と数値をassertします。最高DPSはtick T-60のsampleを含みT-61を除外し、overkillを除き、COMBAT退出でrecent dequeだけが空・peak保持、次wave冒頭damageと前wave末尾damageを合算しないことを検証します。反響は装備前攻撃を数えず、一次攻撃1→2→3で1件予約してprogress 0、同じitemのwave間で2を保持、取り外し／別item交換／再装備で0、retryで空IDかつ0となる境界を個別に検証します。スキル予約は、1イベントで閾値3回分を越えたとき`pending_queue.size() == 3`と正しい剰余になり、3件が同じorigin eventとchainを値コピーで保持し、activation_serialが連続昇順であること、対象0では保持され対象出現後に1tick 1回ずつ消費すること、REWARD_REVEAL / INVENTORY / 次waveへ持ち越すこと、未装着中は増えず再装着後に既存値から続くこと、壊れた時計の着脱時に次COMBAT直前の閾値正規化が空chainで行われること、ラン終了と同seed／新seed retryで空へ戻ることを個別に検証してください。反響と王冠の9tick遅延予約が親chain、aim情報、serial順を保持し、臆病者停止中は保留、停止解除後は発動、COMBAT終了とretryでは破棄されることも検証します。王冠の4スキルを有効敵0でdueにし、星落とし・魂の連鎖は空振り消費、千刃陣・報復の鐘は命中0の範囲イベント1回で消費され、いずれもScheduledProcReplay queueへ残らないことを固定テストします。

FocusController testは各画面の全visible/enabled要素に4方向neighborがあり画面外へ出ないこと、初期focus、overflow 0/4件、wild 0/1個、次戦enabled/disabled、K0/K1とvisible library catalog、確認dialogの初期cancelと復帰を検証します。controller scenarioはpointer event 0件で`inventory_controller`の比較、item持上げ/配置/B取消/X lock、一括選択、unique確認cancel/confirm、合成、wild、overflow解消を行います。skillの初期`starfall=0, thousand_blades=1, soul_chain=-1, bell_of_retribution=-1`から、K4→K0後を`-1,1,0,-1`、K3→K0後を`-1,0,1,-1`、K2→K1後を`1,0,-1,-1`と正確にassertし、K5を持ち上げてB取消後も`1,0,-1,-1`のままとします。各段階で同じskill_idの装着参照が最大1件であることもassertします。空洞の王冠を装備した別固定stateではK1 disabledを4方向移動がskipし、王冠解除後にK1へ到達でき、操作途中のdisableで持上げがcancelされることを検証します。その後に次戦へ進み、`result_controller`とFAILEDの全4導線へfocusだけで到達してください。

上記FocusController testへoverflow 40件、BulkSelectDialog、FusionDialogの全focus IDとneighborも追加します。overflow 40件は`qa-overflow-long-00..39`の順で作り、O0→O39→O0と逆方向を含む全件到達、各focus時の完全表示をassertします。BulkSelectDialogでCommonを決定するとmarkがexactに`qa-inventory-00, qa-inventory-01, qa-inventory-02`となり、A1でその3件だけを廃棄することをpointer event 0で検証します。別cloneではmark 0、last focus=`qa-inventory-33`からA1を実行し、血塗れの短剣の確認取消で不変、承認でその1件だけが消えることを検証します。

FusionDialogのcontroller testは初期`inventory_controller` cloneを使う。last focus=`qa-inventory-33`からA2を開いてFR=Rare、Aで`qa-inventory-18`→F0、`qa-inventory-19`→F1、`qa-inventory-33`→F2の順に入れ、3 IDのsource slotが確定前に不変、FA2 enabled、unique警告取消でFと全RNG stateが不変、承認でexact 3 IDだけを消費してEpic 1件を得ることをassertします。別cloneではlast focus=`qa-inventory-03`からA3を開き、use_wild=true、`qa-inventory-03`→F0、`qa-inventory-04`→F1として確定し、Common 2件とwild 1個だけを消費してRare 1件を得ます。さらにlocked `qa-inventory-34`、Legendary `qa-inventory-35`、異レア品の投入拒否、FからのA解除、FR変更時clear、B取消時のRunState / RunRngStreams全state不変、マウスdragでも同じF配置結果を個別cloneでassertしてください。

スキル報酬適用testでは、空洞の王冠なしでslot0使用・slot1空なら新規skillがslot1、王冠ありでslot0空ならslot0、王冠ありでslot0使用中なら未装着-1となり、封印slot1へは一度も自動装着されないことを固定します。全4skillについてpending 1件、tick開始snapshotの敵0、手順3で敵1体spawnのtickではqueueを保持し、次tickのsnapshotへ入った時だけ1件消費することも検証し、王冠ScheduledProcReplayの空振り消費規則とは別testにしてください。

全組合せ試験として、各unique×各skill×各weapon typeを最低1ケース、broken_clock×starfall、echo_gauntlet×thousand_blades、hollow_crown×全4skill、immortal_breastplate×100%軽減を個別に検証してください。

evidenceをinventory_full、fusion_unique_warning、broken_build、final_resultの4状態で生成してください。broken_buildは不死者の胸当てで軽減100%かつ火力不足になり得る構成に加え、異なるtrigger種の2スキルについて名前、Lv、進捗／閾値、予約数がHUDで読めるようにし、final_resultはseedとscore内訳まで読めるようにしてください。

import、全テスト、debug exportを通し、すべて成功後だけ feat: implement inventory skills and scoring でコミットしてください。最後に本書2.4の形式で報告し、次工程を開始せず停止してください。
~~~

### 10.2 合格条件

- 6枠、36枠、overflow、開始ロックが仕様どおり。
- MAIN_WEAPONは初期化から結果まで常に非nullで、単独解除と主武器nullの次戦／結果遷移を拒否し、主武器同士の交換は成功する。
- INVENTORY、RESULT、FAILED、確認dialogの初期focus、全neighbor、disabled skip、復帰に加え、スキル装着・交換・取消と空洞の王冠による第2slot skipがpointer eventなしのcontroller testを通る。
- overflow 40件をゲームパッドだけで全件巡回でき、BulkSelectDialogとFusionDialogのレアリティ、材料F0..F2、wild、確定、取消が固定focus graphとexact item ID testを通る。
- equipped/locked/uniqueを自動選択しない。
- equipped/lockedを廃棄できず、uniqueは確認必須。廃棄で通貨、score、RNG結果が増減しない。
- 3装備、2装備+1wildだけが成功し、Legendaryは拒否。
- unique素材は対象名付き確認なしに消費されない。
- 4skillがLv3まで上がり、その後wildへ変換し、trigger剰余と予約回数の保持・1tick 1発・resetが仕様どおり。
- 戦闘HUDの2枠がスキル名、Lv、trigger種別に応じた進捗／実効閾値、予約数を常時表示し、空slotと封印状態も文字で区別できる。
- 6uniqueの数値と相互作用が固定テストを通る。
- damage reduction 100%でHPは減らず、hit triggerは増える。
- 自己再帰せず、異なるeffect間の連鎖は成立する。
- スコア固定例が12,055。
- W8後にも開封、整理、合成ができ、overflow解消後だけRESULTへ進む。
- artifacts/gate-05/inventory_full.png、fusion_unique_warning.png、broken_build.png、final_result.png が存在。

## 11. 工程6 — チュートリアル、音、アクセシビリティ、性能、Windows Release

### 11.1 コピー用指示文

~~~text
直前の人間メッセージが本書2.4の「ゲート5承認 H。工程6へ進んでよい」と完全に対応することを確認してください。Project JARJAR の工程6だけを実行し、Hと現在のclean HEADの完全一致、main branch、remote 0件を確認してください。満たさなければ停止してください。これは最終工程ですが、全合格前に完成扱いしないでください。

文脈チュートリアル、プロシージャル効果音、演出調整、設定画面、バランスsimulation、性能試験、Windows x86_64 Release export、最終QAを実装してください。外部素材、外部アドオン、Steamworksは使いません。

初回チュートリアルは、W1開始時に「WASD / 矢印 / 左スティックで移動」を表示し、累積1.0秒移動するまで戦闘timerとspawnを停止します。累積1.0秒で表示を自動終了し、戦闘中に取消入力は受理しません。最初の箱吸収時に「宝箱は自動回収されます」を2秒、最初の開封画面で「報酬は獲得時に確定しています」を表示し、最初のinventoryで装備、lock、3対1合成、一時受取欄を順に説明します。戦闘外の説明は入力を奪わず、ui_cancelで閉じられます。W1 inventoryを離れた時にtutorial_seen=trueを保存します。設定画面に「チュートリアルを再表示」を置き、falseへ戻せるようにします。

AudioStreamWAVを実行時生成するAudioFactoryを作り、外部音源を使わず、pickup=880Hz/0.05秒、通常開封=523Hz/0.08秒、Rare=659Hz/0.12秒、Epic先バレ=220→880Hz sweep/0.55秒、Legendary先バレ=330→1320Hz sweep/0.75秒、wave clear=523/659/784Hzを各0.12秒、fusion=392→784Hz/0.30秒としてください。全音を44,100Hz、16-bit signed PCM、mono、位相0開始の正弦波とし、sweepは開始Hzから終了Hzまで時間に対して線形補間した瞬時周波数を位相積分します。最大振幅は0.65、先頭と末尾の各5msを0↔1のlinear envelopeで乗算します。16個のAudioStreamPlayerを固定poolにし、17音目は再生開始時刻が最古のvoice、同時刻ならindex最小を停止して再利用します。UI音量は整数0..100、保存値は`value / 100.0`の0..1とし、読込表示は`round(saved * 100)`です。最終gainはmaster×sfx、music設定は将来互換として保存するだけでMVPにBGMは実装しません。

設定画面にmaster/music/sfxの0..100、Reduce Motion、Reduce Flashes、Controller Vibration、チュートリアル再表示を置いてください。振動OFFならInput.start_joy_vibrationを一度も呼びません。Reduce Motion/Flashesは箱、reward、fusion、wave clear、damage表現すべてへ反映します。

文言、focus順、キーボード/ゲームパッド両操作を本書3.12どおりに仕上げてください。TITLEへ設定を追加して最終の3要素順へ更新し、設定overlayの全8要素、全画面の設定復帰、確認dialog、REWARD_REVEALのA／マウス長押し競合、INVENTORYのitem／skill操作を含むFocusController回帰testを実装します。controller-only scenarioはpointer event count=0をassertし、TITLE開始、設定の全項目変更とB復帰、REWARD_REVEAL、INVENTORY、RESULT、FAILEDの主要導線をすべて操作します。フォーカス中の要素には形状の異なる可視枠を常時出し、色だけに依存せず、すべての操作ボタンへ日本語ラベルと対応するキーボード／ゲームパッド表記を付けます。1920×1080、1600×900、1280×720で文字の欠け、重なり、画面外を0にしてください。

100 seed loot simulationを最終実行し、各wave平均15..25箱を満たしてください。ここではGate 4で人間承認済みの箱率、レア率、quotaを凍結し、変更してはいけません。失敗した場合は実装バグを直し、確率値を変更して通してはいけません。これはGate 4基準commit前の初期箱率校正窓を取り消す規則ではなく、Gate 4承認後の回帰固定である。

performance suiteを作り、run seed `5002000`、Compatibility、1920×1080、vsync offで、敵500体、飛翔物1,200、VFX 800を同時維持して120秒実行してください。最初の30秒をwarm-upとして除外し、残り90秒で平均fps>=60、p95 frame time<=16.67ms、1% low fps>=50、worst frame<=33.33ms、pool overflow=0、effect-chain depth overflow=0、orphan Node=0を要求します。各render frame終了時に、開始からの累積`elapsed_usec`と直前render frameからの差分`frame_time_usec`をTime.get_ticks_usecから記録する。計測集合はframe終了時刻が30秒超120秒以下のsampleとし、N件の平均fpsを`1,000,000 × N / sum(frame_time_usec)`で求める。昇順sampleのpercentileはnearest-rankの0始まりindex=`ceil(p × N)-1`とし、p95とp99を求め、1% low fpsは`1,000,000 / p99_frame_time_usec`、worstは最大frame_time_usecとする。N=0なら不合格です。static memoryは`OS.get_static_memory_usage()`が返すbyte整数だけを使い、30..59秒と90..119秒の各整数秒を最初に越えたframeで1回ずつ、各30sampleを取得し、昇順中央2値の算術平均を区間中央値とする。値が0以下なら未対応／取得失敗として不合格とし、別APIへfallbackしない。後半中央値が前半の105%以下でなければ失敗です。計測ホストのWindows版、CPU名、論理コア数、GPU名、RAM容量、Godot完全versionを`artifacts/gate-06/performance-summary.txt`へ記録する。`performance.csv`の列は`frame_index,elapsed_usec,frame_time_usec,active_enemy,active_projectile,active_vfx,projectile_pool_used,vfx_pool_used,static_memory_bytes`に固定し、`static_memory_bytes`へ上記APIの未加工byte整数を入れる。全frameでactive_enemy=500、active_projectile=1,200、active_vfx=800でなければ不合格です。ホスト性能が不足しても負荷や基準を下げず、実測値とハードウェア情報を報告してゲートを未合格のまま停止します。

Windows Desktop presetでRelease exportを`build/windows/ProjectJARJAR.exe`、`ProjectJARJAR.console.exe`、`ProjectJARJAR.pck`へ生成し、リポジトリルート外の一時作業ディレクトリへ3件を同じbasenameのままコピーしてsmoke testを行ってください。`--smoke-run`は通常UIから到達できないRelease対応の決定的driverとし、次の手順だけを自動実行します。(1) TITLEを初期表示する。(2) GameAppがdriver生成前にSettingsStoreを`initialize_ephemeral()`済みで、`initialized=true`、`runner_safe_mode=false`、`active_settings_path=""`、既定値であることを検証し、再初期化せずruntime上だけtutorial_seen=trueとする。(3)通常の新規ランfactoryへrun seed `20260827`を渡してW1を開始し、初期木の棒ID=`i-00000000013527db-00-0000`、drop_serial=1、phase=COMBATを検証する。(4)combat / loot / fusion RNGを消費せず、最初のcombat tick直前にtime_remainingをphysics delta 1回分、wave_kills=0、HP=maxへ設定し、通常のtickと時間切れ遷移でFAILEDへ入る。(5)FAILED画面の通常command handlerへ同seed再挑戦を渡し、新しいRunStateがseed `20260827`、同じ木の棒ID、drop_serial=1、phase=COMBAT、全ラン用counterとRunRngStreamsの3 seed / stateがfactory初期状態であることを検証する。(6)再挑戦後の状態へ手順4と同じtimeout注入をもう1回行い、通常tickで再びFAILEDへ入る。(7)FAILED画面の通常command handlerでTITLEへ戻ってから正常終了する。全検証成功時だけ終了0、値不一致は終了1、引数不正は終了2とし、通常起動ではdriverを作らず通常タイトルを表示します。さらにconsole wrapper経由で`--release-pack-audit=<絶対path>`を実行し、SettingsStoreを未初期化のままPCKの全pathをUTF-8 BOMなし・LF・1path/行で4.1の唯一の許可先`artifacts/gate-06/release-pack-manifest.txt`へ出力します。manifest非空、tests、src/debug、scenes/debug、outputs、docsの禁止prefix 0件、`res://scenes/main.tscn`がPackedSceneとしてloadでき、`res://data/balance/balance_manifest.tres`がBalanceManifestとしてloadできることをすべて確認してください。

Release build identityは、ProjectJARJAR.exeの小文字SHA-256とProjectJARJAR.pckの小文字SHA-256を`exe_sha256=<64hex>;pck_sha256=<64hex>`の1行に連結した値とする。自動smokeはRelease E2Eの代替ではありません。同じidentityのEXE/PCKペアをデバッグ引数なしで起動し、通常UIだけで新seed開始、8ウェーブ完走、各ウェーブの開封、装備変更、1回以上の合成、W8後RESULT、同seed再挑戦、ノルマ前FAILED、FAILEDから同seed再挑戦、再びノルマ前FAILED、FAILEDからタイトル復帰、終了までを通してください。実行日時、表示seed、各遷移の合否、Release build identityを`artifacts/gate-06/release-e2e.md`へ記録します。途中でdebug引数、QA状態、editor実行を使った場合は不合格です。

最終QA matrixをdocs/final-qa.mdへ記録し、8wave完走、ノルマ前死亡、時間切れ、ノルマ後死亡、100%軽減、overflow、全開封、同seed再挑戦、新seed再挑戦、終了を手動確認してください。

evidenceをtutorial_move、accessibility_reward、full_load、release_resultの4状態で生成してください。tutorial_moveは初回移動説明と停止中timer、accessibility_rewardはReduce Motion/Flashes有効時のLegendary表示、full_loadは敵500体+飛翔物1,200+VFX 800と性能overlay、release_resultは通常の最終結果画面を示します。保存先はartifacts/gate-06です。

人間プレイテスト用`docs/playtest-protocol.md`、run単位の`docs/playtest-results.csv`、整理区間単位の`docs/playtest-inventory-times.csv`を作ってください。参加者は全員、export済みの同一Release buildをデバッグ引数なしで使います。5人以上が各3ラン実施します。各参加者は、Project JARJARの過去または現行buildを一度もプレイせず、対面・配信・録画のゲームプレイも一度も見ていない新規参加者に限定します。聞き手は開始前にこの2条件を質問し、両方を満たす人だけを採用します。過去のどの`balance_revision`の受入データにも参加した人を再利用しません。`docs/playtest-protocol.md`へ、個人情報を含めずに対象revisionごとの「全testerの初見資格確認済み=yes」と確認日を記録します。

`playtest-results.csv`は1runにつき1行とし、列を`tester_id,run_index,run_seed,reward_experience_1_to_5,immediate_retry_yes_no,is_first_run,first_time_eligible_yes_no,run_clear,cleared_waves,broken_build_yes_no,combat_score,final_build_score,total_score`へ固定します。`playtest-inventory-times.csv`は1整理区間につき1行とし、列を`tester_id,run_index,wave_number,seconds`へ固定します。両CSVはUTF-8 BOMなし、LF、カンマ区切り、1行目header、空セルなし、小数点`.`とする。yes/no列は小文字`yes`または`no`だけ、run_indexは1..3、run_seedは画面表示と一致する0..9,223,372,036,854,775,807の整数、rewardは整数1..5、cleared_wavesは整数0..8、3つのscore列は0以上の整数、wave_numberは1..8、secondsは0より大きく小数3桁以内とする。`is_first_run=yes`は各testerのrun_index=1だけ、`first_time_eligible_yes_no=yes`は採用したtesterの全3行で必須とし、`run_clear=yes`ならcleared_waves=8、noなら0..7である。各行で`combat_score + final_build_score = total_score`を必須とする。

整理区間は、クリアした各waveで全報酬公開後にINVENTORYへ入った瞬間から、次のCOMBATまたはRESULTへ遷移する瞬間までとし、W8最終整理を含みます。各results行に対するinventory-timesのwave_number集合は、cleared_waves=0なら空、1以上なら重複なしの連続整数`1..cleared_waves`と完全一致させる。REWARD_REVEALの開封時間と設定画面の滞在時間は計測せず、失敗waveには整理区間行を作りません。個人名、メール、端末識別子は収集せず、tester_idはT01から参加人数分を連番にします。中央値は昇順の奇数件なら中央1値、偶数件なら中央2値の算術平均、百分率は該当行数÷対象行数×100で丸めず判定します。合格条件は報酬体験平均4.0以上、即時再挑戦yes 70%以上、全15run以上から得た全整理区間行のseconds中央値30..60秒、各testerの最初のrunだけを対象にした初見クリア率40..60%、全testerが3run以内に壊れbuildを1回以上経験、完走runにおける戦闘由来score比率の中央値65..75%、です。

各testerは`run_with_clean_settings.ps1`で既定settingsと`tutorial_seen=false`から個別に起動し、1つのprocess内でWASDを使って3ラン続ける。設定は変更しない。run 1はTITLEの「開始」で新seed、run 2と3は直前のRESULTまたはFAILEDで「新しいseedで再挑戦」を選び、同じseed再挑戦は選ばない。各runのRESULTまたはFAILED表示直後、次の導線を押す前に、同じ聞き手が画面からrun_seed、RESULTならrun_clear=yes・FAILEDならno、cleared_waves、combat_score、final_build_score、total_scoreを転記する。転記時に画面上でも`combat_score + final_build_score = total_score`を照合し、不一致ならそのbuildのプレイテストを中止して実装不具合として報告し、当該データを集計しない。その後、同じ聞き手が順番どおり「このランの宝箱開封・整理・合成体験を、1=非常に悪い、2=悪い、3=普通、4=良い、5=非常に良いで評価してください」「今すぐもう1ラン遊びたいですか。yesかnoで答えてください」「このランで、ゲームを壊したと感じるほど強いビルドを経験しましたか。yesかnoで答えてください」と質問して記録する。run 3回答後はTITLEへ戻って終了する。整理時間は聞き手が別のstopwatchで計測し、ゲーム内ログを追加しない。

tester起動時は新しいPowerShell sessionで次の4行を実行する。`$testerId`の`T01`だけを、その回に割り当てたT02、T03…へ置換し、ほかの引数は変えない。

$testerId = "T01"
$jarjarReleaseExe = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.exe").Path
$jarjarReleaseDir = Split-Path -Parent $jarjarReleaseExe
& ".\tests\run_with_clean_settings.ps1" -Executable $jarjarReleaseExe -Arguments ([string[]]@()) -Label ("playtest_" + $testerId.ToLowerInvariant()) -ExpectedExitCodes @(0) -WorkingDirectory $jarjarReleaseDir

各testerの3ラン終了までscriptを閉じない。終了後の`$LASTEXITCODE`が0でなければ当該processを不合格とする。最初のCOMBATへ入る前の起動失敗だけは、同じ人がclean settingsから再試行できる。COMBAT開始後に中断した場合は、その人のresults行とinventory-times行をすべて破棄し、その人を再採用しない。別の未経験参加者を採用し、破棄で空いた最小tester_idを割り当て、最終CSVではT01から欠番なく連番にする。

エージェントは参加者や回答を捏造しない。人間プレイテスト以外のGate 6検証が通った時点で、Release build identity、`balance_revision`、Gate 5の承認済み40文字HEAD、初見資格の質問文と確認欄を`docs/playtest-protocol.md`へ記録し、CSVはheaderだけのまま、未コミットで「Gate 6プレイテスト待ち」と報告して停止する。人間が同じEXE/PCKペアで実施した2つのCSVを提供し、「Gate 6のプレイテスト集計を再開 H」と指示した後だけ集計を再開する。Hはprotocol記載のGate 5承認済みHEADであり、再開時に`git rev-parse HEAD`と完全一致させる。

Release build identity、balance_revision、Hのいずれかがprotocol記載値に一致しない、protocolの初見資格確認がyesでない、15run未満、参加者5人未満、各人3runでない、列不足、範囲外値、`first_time_eligible_yes_no`がyes以外、または3つのscore列の加算不一致があれば集計せず停止する。`playtest-results.csv`の一意キーは`(tester_id, run_index)`、`playtest-inventory-times.csv`の一意キーは`(tester_id, run_index, wave_number)`とし、各ファイル内で同じ一意キーが重複しても停止する。さらに、各results行に対応するinventory-timesのwave_number集合が`1..cleared_waves`と完全一致しない、resultsにないtester/runのinventory行がある、同一tester内でrun_seedが重複する場合も停止する。実データが揃い、全条件を満たすまでGate 6を合格扱いせず、commitもしない。

import、全unit/scenario/simulation test、performance、Release export、pack audit、exported smoke、手動QA、人間プレイテストをすべて通した後だけ feat: polish and export MVP でコミットしてください。build、artifactsはコミットしません。最後に本書2.4の形式で最終報告し、EXE/PCKの絶対パス、Release build identity、全試験結果、playtest集計、commit hashを提示して停止してください。
~~~

### 11.2 性能コマンド

~~~powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$env:JARJAR_GODOT = (Resolve-Path -LiteralPath ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe").Path
New-Item -ItemType Directory -Force -Path ".\artifacts\gate-06" | Out-Null

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\run_gate_checks.ps1" -GateNumber 6 -Suite all
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
. ".\tests\process_log.ps1"
$logPath = [System.IO.Path]::GetFullPath(".\artifacts\gate-06\tests.txt")

$performanceSettings = [System.IO.Path]::GetFullPath(".\artifacts\gate-06\test-user\performance\settings.cfg")
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $performanceSettings) | Out-Null
$testUserRoot = [System.IO.Path]::GetFullPath(".\artifacts\gate-06\test-user") + [System.IO.Path]::DirectorySeparatorChar
if (-not $performanceSettings.StartsWith($testUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "performance settings path escaped test-user" }
if (Test-Path -LiteralPath $performanceSettings) { Remove-Item -LiteralPath $performanceSettings -Force -ErrorAction Stop }
Invoke-JarjarLoggedProcess -LogPath $logPath -Label "performance" -FilePath $env:JARJAR_GODOT -Arguments @("--path", ".", "--", "--performance=full_hd_500_2000", "--run-seed=5002000", ("--settings-path=" + $performanceSettings))

New-Item -ItemType Directory -Force -Path ".\build\windows" | Out-Null
Invoke-JarjarLoggedProcess -LogPath $logPath -Label "export_release" -FilePath $env:JARJAR_GODOT -Arguments @("--headless", "--path", ".", "--export-release", "Windows Desktop", ".\build\windows\ProjectJARJAR.exe")
$jarjarReleaseExe = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.exe").Path
$jarjarReleaseConsoleExe = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.console.exe").Path
$jarjarReleasePck = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.pck").Path
$jarjarReleaseDir = Split-Path -Parent $jarjarReleaseExe

$smokeRoot = Join-Path $env:TEMP ("project-jarjar-export-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $smokeRoot | Out-Null
Copy-Item -LiteralPath $jarjarReleaseExe -Destination $smokeRoot -ErrorAction Stop
Copy-Item -LiteralPath $jarjarReleaseConsoleExe -Destination $smokeRoot -ErrorAction Stop
Copy-Item -LiteralPath $jarjarReleasePck -Destination $smokeRoot -ErrorAction Stop
$jarjarSmokeExe = (Resolve-Path -LiteralPath (Join-Path $smokeRoot "ProjectJARJAR.exe")).Path
$jarjarSmokeConsoleExe = (Resolve-Path -LiteralPath (Join-Path $smokeRoot "ProjectJARJAR.console.exe")).Path
$jarjarSmokePck = (Resolve-Path -LiteralPath (Join-Path $smokeRoot "ProjectJARJAR.pck")).Path
if (-not (Test-Path -LiteralPath $jarjarSmokeExe)) { throw "smoke EXE copy missing" }
if (-not (Test-Path -LiteralPath $jarjarSmokeConsoleExe)) { throw "smoke console wrapper copy missing" }
if (-not (Test-Path -LiteralPath $jarjarSmokePck)) { throw "smoke PCK copy missing" }
& ".\tests\run_with_clean_settings.ps1" -Executable $jarjarSmokeConsoleExe -Arguments @("--", "--smoke-run") -Label "smoke_release" -ExpectedExitCodes @(0) -WorkingDirectory $smokeRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$jarjarManifest = [System.IO.Path]::GetFullPath(".\artifacts\gate-06\release-pack-manifest.txt")
& ".\tests\run_with_clean_settings.ps1" -Executable $jarjarReleaseConsoleExe -Arguments @("--", ("--release-pack-audit=" + $jarjarManifest)) -Label "release_pack_audit" -ExpectedExitCodes @(0) -WorkingDirectory $jarjarReleaseDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not (Test-Path -LiteralPath $jarjarManifest)) { throw "release pack manifest missing" }
if ((Get-Item -LiteralPath $jarjarManifest).Length -eq 0) { throw "release pack manifest empty" }

$jarjarForbiddenManifest = Join-Path $env:TEMP ("project-jarjar-forbidden-manifest-" + [guid]::NewGuid().ToString("N") + ".txt")
try {
    & ".\tests\run_with_clean_settings.ps1" -Executable $jarjarReleaseConsoleExe -Arguments @("--", ("--release-pack-audit=" + $jarjarForbiddenManifest)) -Label "release_pack_path_reject" -ExpectedExitCodes @(2) -WorkingDirectory $jarjarReleaseDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (Test-Path -LiteralPath $jarjarForbiddenManifest) { throw "rejected pack audit wrote outside fixed target" }
    $packRejectCount = @((Get-Content -LiteralPath $logPath) | Where-Object { $_ -ceq "RELEASE_ARGUMENT_REJECTED name=--release-pack-audit" }).Count
    if ($packRejectCount -ne 1) { throw ("pack path rejection marker count: " + $packRejectCount) }
} finally {
    if (Test-Path -LiteralPath $jarjarForbiddenManifest -PathType Leaf) { Remove-Item -LiteralPath $jarjarForbiddenManifest -Force -ErrorAction Stop }
}

$jarjarQaIds = @("weapon_bow", "weapon_staff", "weapon_sword", "pre_quota_death", "pre_quota_timeout", "post_quota_death", "reward_controls", "inventory_controller", "result_controller", "immortal_100", "boss_299")
foreach ($jarjarQaId in $jarjarQaIds) {
    & ".\tests\run_with_clean_settings.ps1" -Executable $jarjarReleaseConsoleExe -Arguments @("--", ("--qa-scenario=" + $jarjarQaId)) -Label ("release_qa_reject_" + $jarjarQaId) -ExpectedExitCodes @(2) -WorkingDirectory $jarjarReleaseDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$jarjarRejectedReleaseCases = @(
    [pscustomobject]@{ Label = "release_evidence_reject"; Arguments = [string[]]@("--", "--evidence=gate_06:release_result") },
    [pscustomobject]@{ Label = "release_smoke_quit_reject"; Arguments = [string[]]@("--", "--smoke-quit=1") },
    [pscustomobject]@{ Label = "release_performance_reject"; Arguments = [string[]]@("--", "--performance=full_hd_500_2000") },
    [pscustomobject]@{ Label = "release_run_seed_reject"; Arguments = [string[]]@("--", "--run-seed=1") },
    [pscustomobject]@{ Label = "release_suite_reject"; Arguments = [string[]]@("--", "--suite", "unit") },
    [pscustomobject]@{ Label = "release_unknown_reject"; Arguments = [string[]]@("--", "--unknown-qa-option") },
    [pscustomobject]@{ Label = "release_duplicate_reject"; Arguments = [string[]]@("--", "--smoke-run", "--smoke-run") },
    [pscustomobject]@{ Label = "release_combined_reject"; Arguments = [string[]]@("--", "--smoke-run", ("--release-pack-audit=" + $jarjarManifest)) }
)
foreach ($jarjarRejectedCase in $jarjarRejectedReleaseCases) {
    & ".\tests\run_with_clean_settings.ps1" -Executable $jarjarReleaseConsoleExe -Arguments $jarjarRejectedCase.Arguments -Label $jarjarRejectedCase.Label -ExpectedExitCodes @(2) -WorkingDirectory $jarjarReleaseDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$jarjarRejectedSettings = [System.IO.Path]::GetFullPath(".\artifacts\gate-06\test-user\release-reject\settings.cfg")
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $jarjarRejectedSettings) | Out-Null
if (-not $jarjarRejectedSettings.StartsWith($testUserRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "release reject settings path escaped test-user" }
if (Test-Path -LiteralPath $jarjarRejectedSettings) { Remove-Item -LiteralPath $jarjarRejectedSettings -Force -ErrorAction Stop }
& ".\tests\run_with_clean_settings.ps1" -Executable $jarjarReleaseConsoleExe -Arguments @("--", ("--settings-path=" + $jarjarRejectedSettings)) -Label "release_settings_path_reject" -ExpectedExitCodes @(2) -WorkingDirectory $jarjarReleaseDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (Test-Path -LiteralPath $jarjarRejectedSettings) { throw "Release wrote rejected settings path" }

$jarjarExeSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $jarjarReleaseExe).Hash.ToLowerInvariant()
$jarjarConsoleSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $jarjarReleaseConsoleExe).Hash.ToLowerInvariant()
$jarjarPckSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $jarjarReleasePck).Hash.ToLowerInvariant()
$jarjarReleaseIdentity = "exe_sha256=" + $jarjarExeSha + ";pck_sha256=" + $jarjarPckSha
$jarjarReleaseIdentity | Set-Content -LiteralPath ".\artifacts\gate-06\release-build-identity.txt" -Encoding UTF8
("console_sha256=" + $jarjarConsoleSha) | Set-Content -LiteralPath ".\artifacts\gate-06\release-console-sha256.txt" -Encoding UTF8
$jarjarReleaseIdentity
~~~

### 11.3 最終自動受入条件

- 同一 seed・同一入力記録で敵順、loot全フィールド、名前、合成結果が再現。
- 開封速度と全開封で loot が不変。
- 各ウェーブに主武器1個以上。
- 100 seedで各ウェーブ平均15..25箱。
- 100 seedの固定貪欲合成でfusion由来Epic>=95 seed、Legendary>=90 seed、両rarityのfusion生成総数>直ドロップ総数。
- 3対1、Legendary拒否、lock保護、unique警告、Lv3後wildがすべて成功。
- ノルマ前死亡、時間切れ、ノルマ後死亡、W8ボス未撃破、100%軽減が仕様どおり。
- effect chainが自己循環せず、異なる効果の連鎖が成立。
- 1080pで敵500+飛翔物1,200+VFX 800、平均>=60fps、p95<=16.67ms、1% low>=50fps、worst<=33.33ms、overflow 0、メモリ増加<=5%。
- `artifacts/gate-06/performance.csv`と`artifacts/gate-06/performance-summary.txt`が存在し、固定seed、全統計値、計測ホスト情報を含む。
- Release EXE/console wrapper/PCK export、一時ディレクトリからのsmoke、ReleaseでのGameApp Debug/test専用6引数、runner-local `--suite`、未知・重複・複数option拒否（終了2、指定cfgを生成しない）が成功し、全wrapper実行で実ユーザー設定の復元と非settings file manifest不変が成立。
- release-pack-manifest.txtが非空、禁止prefixが0件、必須resource 2件がload可能であり、release-build-identity.txtがEXE/PCK双方、release-console-sha256.txtがQA用console wrapperのSHA-256を含む。
- デバッグ引数なしの同一Release build identityで8ウェーブ完走、報酬・合成・RESULT、同seed再挑戦、ノルマ前FAILED、同seed再挑戦後の再FAILED、タイトル復帰、終了までのE2Eが成功し、release-e2e.mdが存在。
- parser error、runtime error、push_error、orphan Node、Resource leakが0。
- artifacts/gate-06/tutorial_move.png、accessibility_reward.png、full_load.png、release_result.png が存在。
- Gate 6基準commit作成後のGit working treeがclean。commit前の受入実行中は当該Gateの未コミット変更だけを許容する。

### 11.4 人間受入条件

Project JARJARの全buildを未プレイ・未観戦で、過去revisionの受入データへ参加していない新規tester 5人以上が各3ランを完了し、次をすべて満たす。

- 報酬体験の平均が4.0/5以上。
- 「すぐ再挑戦したい」が全回答の70%以上。
- `playtest-inventory-times.csv`の全整理区間行をまとめたseconds中央値が30..60秒。各行は全報酬公開後のINVENTORY開始から次のCOMBATまたはRESULTまでで、W8を含み、開封時間と設定画面滞在を除く。
- 各testerの第1ランだけで算出した初見クリア率が40..60%。
- 全testerが3ラン以内に「明確に壊れた」と感じるbuildを1回以上経験。
- 完走runの合計scoreに占める戦闘由来scoreの比率中央値が65..75%。

いずれかの人間受入条件が未達なら、エージェントは実測表、原因仮説、変更候補を報告して未合格のまま停止し、値や実装を変更しない。初見クリア率について人間が再調整を指示する場合、人間は敵HP、敵ダメージ、spawn rateのうち変更する1パラメータ系統と、変更対象ごとの旧値→新値を明示する。各数値の1回の変更幅は±10%以内とし、エージェントが系統または値を選んではならない。quota、箱率、レア率、合成比、unique効果は変更対象外とする。報酬体験、再挑戦意向、整理時間、壊れbuild率、score比率の未達でも、エージェントは承認された正確なUI変更または数値だけを実装する。

承認後の修正では、企画書、本書、該当Resource、期待値テスト、`data/balance/balance_manifest.tres`の`balance_revision`を同じ未コミット変更で同期し、revisionを1増やす。初期値は0とする。変更後は旧プレイテスト行を新revisionへ流用せず、以前のrevisionへ参加した人を再利用しない新規tester 5人以上×各3ランを、新しいRelease buildで最初から実施する。すべての自動・手動・人間受入条件が合格するまでGate 6をコミットしない。

## 12. 最終QAシナリオ

手動QAは次を順に行い、各行の合否と注記を`docs/final-qa.md`へ記録する。Debug QA状態の起動は5.4の形式とprocess loggerを使い、確認後はTITLEまたは終了でプロセスを閉じる。

手順10の起動は次に固定する。

~~~powershell
$jarjarReleaseExe = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.exe").Path
$jarjarReleaseConsoleExe = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.console.exe").Path
$jarjarReleaseDir = Split-Path -Parent $jarjarReleaseExe
& ".\tests\run_with_clean_settings.ps1" -Executable $jarjarReleaseConsoleExe -Arguments ([string[]]@()) -Label "release_e2e_manual" -ExpectedExitCodes @(0) -WorkingDirectory $jarjarReleaseDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
~~~

1. 通常debugをゲームパッドだけで2回起動する。1回目はTITLEで設定overlayを開閉してTITLEの「終了」を選ぶ。2回目はTITLEの「開始」でW1へ入り、左スティック移動と、戦闘中に他のgameplay actionがないことを確認する。W1確認後のプロセス終了だけはOSのwindow closeを使い、ゲーム内操作評価へ含めない。
2. `reward_controls`をゲームパッドだけで4回起動し、1〜3回目は無入力の通常自動、A長押し4倍、Y全開封を1方式ずつ使い、固定4報酬の順序と値を自動テストsnapshotに照合する。4回目はReduce Motion / Flashesと振動OFFでY全開封し、代替表示を確認する。
3. `inventory_controller`をゲームパッドだけで操作し、36枠+overflow 4、比較、itemとskillのA持上げ／配置／交換、B取消、X lock、一括選択、unique保護付き廃棄、3対1合成、wild投入、overflow解消、次戦を確認する。空洞の王冠を持つ固定testでは第2skill slotがskipされることも照合する。マウスとキーボードは触らない。
4. `pre_quota_death`で次tickにFAILEDとなり、そのwaveの報酬が失われることを確認する。
5. `pre_quota_timeout`で次tickにFAILEDとなることを確認する。
6. `post_quota_death`で次tickにREWARD_REVEALへ進むことを確認する。
7. `immortal_100`で接触後もHP100、hit判定5回目で報復の鐘発動、実ダメージ0を確認する。
8. `boss_299`でBOSS生存中は299/300かつ通常spawn停止、BOSS撃破後は通常spawn再開、300到達、報酬、整理、RESULTまで進むことを確認する。
9. `result_controller`でseed、撃破、超過、箱、合成、最高DPS、装備6枠、スキル2枠、全score内訳、合計12,055を照合し、同seed、新seed、TITLE、終了の4導線を1回ずつ別起動で確認する。
10. 日本語Windows環境で、同じRelease build identityのEXE/PCKを同basenameのconsole wrapperから、`tests/run_with_clean_settings.ps1`を使ってデバッグ引数なしで起動する。初回チュートリアルの移動1秒までtimer/spawn停止、新seedで8wave完走、各報酬、装備変更、1回以上の合成、RESULT、同seed再挑戦、ノルマ前FAILED、FAILEDから同seed再挑戦、再びノルマ前FAILED、FAILEDからTITLE復帰、終了を一続きで確認する。外部ファイル欠落、表示崩れ、クラッシュを0件とし、標準出力／標準エラーscan成功、終了後の元settings SHA-256復元一致を確認する。
11. 自動replay scenarioで同じseed・同じ入力記録を2回流し、敵順とloot全fieldが一致する結果を`docs/final-qa.md`から`artifacts/gate-06/tests.txt`の該当test名へ参照する。

## 13. 完了報告テンプレート

~~~text
Project JARJAR Gate N 完了

変更概要
- ...

検証
- command: ...
  exit: 0
  result: passed X / failed 0

合格条件
- [x] ...

証跡
- C:\absolute\path\to\artifacts\gate-NN\example.png
- C:\absolute\path\to\artifacts\gate-NN\tests.txt

コミット
- 基準commit: <hash> <固定message>
- 追補commit: なし（1件以上ある場合は、`<40文字hash> fix: address Gate N review`を古い順に1件1行で全件列挙）
- candidate HEAD: <40文字hash>
- git status --short: 出力なし

既知の問題
- なし

次工程は未着手。人間の明示承認を待つ。
~~~

ゲート6だけは、上記に Release EXE/PCK双方の絶対パスとRelease build identity、performance summary、人間プレイテスト集計を追加する。

## 14. MVP外として触らない項目

日替りseed、高難度、オンラインランキング、Steam実績、クラウド保存、多言語、マルチプレイ、ラン途中保存、恒久強化、恒久解禁、課金箱、賭け金、リール、クレジット、配当表は実装しない。これらを示唆する無効ボタン、ダミーメニュー、未使用APIも作らない。

本MVPのスロット的演出は、溜め、真の先バレ、段階点灯、祝福音だけに限定する。報酬はゲームプレイでのみ獲得し、現金、仮想通貨、広告視聴と接続しない。

## 15. 実装時に参照する一次資料

- [Godot 4.7 系アーカイブ](https://godotengine.org/download/archive/)
- [Godot 4.7.2-stable 直接ページ](https://godotengine.org/download/archive/4.7.2-stable/)
- [Godot 4.7 コマンドライン](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- [Godot 4.7 RandomNumberGenerator](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)
- [Godot 4.7 ProjectSettings（desktop file logging既定値を含む）](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html)
- [Godot 4.7 shader cache設定](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-rendering-shader-compiler-shader-cache-enabled)
- [Godot 4.7 ファイルパス・custom user dir・self-contained mode](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html)
- [Godot 4.7 MultiMesh](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html)
- [Godot 4.7 プロジェクトexport](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html)
- [Godot Windows export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_windows.html)
- [Godot 4.7 Windows console wrapper](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformwindows.html#class-editorexportplatformwindows-property-debug-export-console-wrapper)
- [Godot 4.7.2 console wrapper modeと生成名の一次ソース](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/export/editor_export_platform_pc.cpp#L53-L58)
- [Godot 4.7.2でscript main loopにもAutoloadを生成する起動処理](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L4183-L4243)

参照資料と本書が異なる場合、API名やCLI構文はGodot 4.7.2の一次資料へ合わせる。ただし、ゲーム仕様、数値、状態遷移、乱数契約、合格条件は変更せず、互換上の差異をゲート報告へ明記する。
