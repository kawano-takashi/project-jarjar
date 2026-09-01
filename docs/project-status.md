# Project JARJAR 現在の状態

- 更新日: 2026-09-02 (JST)
- 状態: **Survivors型全面再設計 revision 5 source gate PASS・正式candidate未固定**
- playable baseline: 未固定（revision 5 作業ツリー）
- balance revision: `5`（source調整完了）
- 正式playtest target: 未固定
- 自動調整記録: `artifacts/balance/revision-5/`（2026-09-02、専用12run source gate PASS）

## 現在地

旧「60秒×8wave → 宝箱開封 → 倉庫・装備・合成」ループを廃止し、30×30mの有限アリーナで
10分間連続戦闘した後に最終ボスを倒す構成へ全面刷新した。revision 5では敵の行動、スポーン、
武器の標的取得・効果範囲、カメラを画面内戦闘へ合わせて再構築した。旧戦利品、レアリティ、接辞、
着脱装備、倉庫、合成、装備スコアは互換層を設けず削除済みである。

新しいランでは追尾核Lv1から開始し、敵の経験値結晶でレベルアップする。戦闘を停止した3択から
武器5枠・パッシブ5枠を育てる。所持枠が埋まる前は通常weight抽選より先に所持品優先抽選を2回試行する。
各試行の成功確率は `p = clamp(1 + 0.3 × x - 1 / totalLuck, 0, 1)`、`x`はoffer発生時のlevelが偶数なら2、奇数なら1とし、
成功時は未最大の所持品から一様抽選する。2回目が1回目と重複した場合は代替を再抽選せず、その枠を
通常weightの重複なし抽選へ戻す。残りも同じ通常抽選で埋め、最大3択とする。

2:00、4:00、6:00、8:00のエリート宝箱は進化、通常強化、または全回復のいずれか1効果を与える。
進化に固定時刻ゲートは設けず、実際の候補抽選、XP取得、宝箱取得を含む初回進化時刻で調整を判定する。
10:00以降は通常スポーンを止め、3段階の最終ボス戦へ移る。

被弾後は30 combat tick（0.5秒）の連続被弾防止とする。これとは別に、レベルアップや宝箱の自動モーダル列がすべて
終了した後だけ45 combat tick（0.75秒）の復帰保護を与える。列の中間や手動ポーズ復帰ではこの45 tickを付与しない。

## revision 5実装と最終調整値

revision 5の画面内戦闘契約は次のとおりである。

- アリーナは30×30m。通常敵は上下左右4辺の外周固定スポーンとする。これはアリーナ上の出現位置契約であり、
  カメラ外からの出現を保証するものではない。
- 通常敵とエリートは接触追跡だけを行い、投射物を発射しない。予告付きの放射状投射物を使うのは最終ボスだけである。
- 通常敵、エリート、最終ボスはそれぞれ21/36/60 combat tickの出現待機を持つ。ボス召喚は削除し、最終ボスは中央へ登場する。
- 戦闘範囲は標的中心8m、効果外縁9m、damage中心10m。安定化した直交投影カメラはsize `18`、follow tau `0.12`秒である。
- compact HUD、撃破feedback、重要VFX保護、audio admissionを含む画面内presentation契約を実装した。

自動調整の最終値は次のとおりである。

- starter: `homing_core`
- `xp_yield_percent`: `90`
- `normal_enemy_damage_scale`: `0.55`
- boss: `boss_hp_multiplier=0.5625`（base 40,000から22,500 HP）、`boss_damage_multiplier=0.57`、
  `boss_action_rate_multiplier=1.0`

| segment | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| target_active | 16 | 24 | 36 | 52 | 72 | 96 | 120 | 144 | 168 | 192 |
| hp_multiplier | 0.15 | 0.17 | 0.20 | 0.24 | 0.30 | 0.45 | 0.65 | 0.90 | 1.25 | 1.75 |
| damage_multiplier | 0.18 | 0.20 | 0.22 | 0.25 | 0.29 | 0.36 | 0.45 | 0.56 | 0.72 | 0.95 |

## revision 5 source gate結果

2026-09-02にseed `17`、`29`、`43`、`61`をcautious、normal、evolutionの各方針で実行する、
専用の決定的12run source gateを完走し、`passed=true`でPASSした。

- 2:00以前の死亡: 0/12
- 最終ボス到達: 11/12（合格範囲9〜11/12）
- 最終ボス撃破: 6/12（合格範囲5〜8/12）
- 3:00までの初回進化: 0/12
- normal方針の5:00までの初回進化: 2/4
- normal方針の7:00までの初回進化: 4/4
- normal方針の初回進化時刻平均: 321.641667秒（合格範囲288〜324秒）
- offscreen weapon hit run: 0/12、offscreen weapon kill run: 0/12
- `max_hit_center_distance`: 9.623473167m、`max_kill_center_distance`: 9.570774078m、
  `max_effect_outer_distance`: 8.996990412m
- VFX: admitted 90,151、suppressed 0、important drop 0
- feedback: emitted 234,498、suppressed 0
- 全pool overflow: 0run、全pool orphan: 0run
- audio cue: admitted 53,321、suppressed 181,691

実測CSVとsummaryは`artifacts/balance/revision-5/`に保存している。同じ作業ツリーの全GDScript回帰は
112/112 PASS、GDScript guardは97ファイルPASS、変更GDScriptのcheck-onlyは41/41 PASSである。
このsource gateは自動調整完了の証拠であり、人間playtestの参加・回答・計測値や
正式candidateのidentity、正式性能試験、Release検証を代替しない。

revision 5への変更により、revision 4のcandidate、調整成果物、回帰、QA、build identityは現候補の証拠として無効であり、
履歴としてのみ保持する。現時点で正式candidateは未固定である。Full HD性能試験、Release export、Verify、ManualQa、
人間playtestはすべて未実施であり、ユーザーが最終調整完了を明示するまで実行してはならない。

## revision 4自動調整結果（履歴・流用禁止）

2026-09-01に、実際の候補抽選、XP取得、宝箱取得を含む専用の決定的12run source gateを実施し、PASSした。

- 2:00以前の死亡: 0/12
- 最終ボス到達: 9/12（合格範囲9〜11/12）
- 最終ボス撃破: 8/12（合格範囲5〜8/12）
- 3:00までの初回進化: 0/12
- normal方針の5:00までの初回進化: 2/4
- normal方針の7:00までの初回進化: 4/4
- normal方針の初回進化時刻平均: 322.883秒（合格範囲288〜324秒）
- pool overflow: 0run、orphan: 0run

同じ作業ツリーで全GDScript回帰91/91、変更GDScript 75ファイルのcheck-only、
GDScript guard 91ファイル、`git diff --check`がすべてPASSしている。

自動調整の最終値は次のとおりである。

- starter: `homing_core`
- `xp_yield_percent`: `165`
- elite `xp_value`: `50`
- boss: HP `1.5`、damage `0.798`、action rate `1.0`

| segment | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| target_active | 4 | 6 | 9 | 13 | 18 | 36 | 48 | 60 | 69 | 100 |
| hp_multiplier | 0.15 | 0.168 | 0.192 | 0.222 | 0.258 | 0.6 | 0.936 | 0.959 | 1.44 | 2.625 |
| damage_multiplier | 0.25 | 0.27 | 0.29 | 0.315 | 0.345 | 0.532 | 0.672 | 0.651 | 0.824 | 1.368 |

実測CSVとsummaryは`artifacts/balance/revision-4/`に保存している。これは調整用の自動source gateであり、
人間プレイテストの参加・回答・計測値を代替しない。正式な人間受入では、全有効runのうち最終ボスへ到達したrun
（`boss_result`が`defeated`または`player_defeated`）を70%以上80%以下とする。
上記のstarter、XP、segment、boss、候補抽選、進化条件のいずれかを変更した場合、このsource gate結果を無効として再実行する。

revision 4は新しいコード、データ、UI、回帰、QA、playtest手順を一体で置換した破壊的変更である。
revision 3以前のRelease検証、手動QA、playtest対象・結果はrevision 4時点でも無効だった。
revision 4の専用12run PASSも正式candidateのidentityや正式検証結果ではなく、現在はrevision 5へ流用できない履歴である。

## 次の作業

1. revision 5のsource調整済み作業ツリーを保持し、ユーザーによる武器演出、敵圧、XPペース、文言その他の最終確認を待つ。
2. ユーザーが最終調整完了を明示した後だけ、全回帰、GDScript検査、Full HD性能試験、
   Release export、pack audit、smoke、Verify、ManualQaを実施する。
3. 新identity用の `docs/final-qa.md` に手動QAと自動検証結果を人間が記録する。
4. 手動QA合格後、新しい候補HEAD、EXE/PCK SHA-256、balance revisionを `artifacts/playtest/target.txt` へ手動で固定する。
5. その後だけ `docs/playtest-protocol.md` を有効化し、未経験者5人以上が各3runを実施する。

候補HEAD、EXE、PCK、balance revisionのいずれかが変わった場合、旧対象、旧QA、旧playtestデータを流用しない。
人間の参加、回答、計測値をエージェントが生成または補完してはならない。

## 正式受入後の棚卸し

5人以上×3run完了までは、revision 5の回帰テスト、Debug QA、性能試験、Release検証、
GDScript guard、比較用buildを保持する。正式受入後に再棚卸しし、配布・保守に不要な資材を削除する。
