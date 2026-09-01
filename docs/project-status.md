# Project JARJAR 現在の状態

- 更新日: 2026-09-01 (JST)
- 状態: **Survivors型全面再設計 revision 4自動調整完了・正式固定前**
- playable baseline: 未固定（revision 4 作業ツリー）
- balance revision: `4`
- 正式playtest target: 未固定
- 自動調整記録: `artifacts/balance/revision-4/`（2026-09-01、専用12run source gate PASS）

## 現在地

旧「60秒×8wave → 宝箱開封 → 倉庫・装備・合成」ループを廃止し、40×40mの有限アリーナで
10分間連続戦闘した後に最終ボスを倒す構成へ全面刷新した。旧戦利品、レアリティ、接辞、
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

## revision 4自動調整結果

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

revision 4は新しいコード、データ、UI、回帰、QA、playtest手順を一体で置換する破壊的変更である。
revision 3以前のRelease検証、手動QA、playtest対象・結果はすべて無効であり、現候補へ流用しない。
専用12runのPASSは自動調整完了の記録であり、正式candidateのidentityや正式検証結果ではない。
ユーザーが最終調整完了を明示するまで正式candidateを固定しない。Full HD性能試験、Release export、Verify、ManualQa、
人間playtestはすべて未実施であり、まだMVP候補固定ではない。

## 次の作業

1. revision 4の自動調整済み作業ツリーを保持し、ユーザーによる武器演出、敵圧、XPペース、文言その他の最終確認を待つ。
2. ユーザーが最終調整完了を明示した後だけ、全回帰、GDScript検査、性能試験、
   Release export、pack audit、smoke、Verify、ManualQaを実施する。
3. 新identity用の `docs/final-qa.md` に手動QAと自動検証結果を人間が記録する。
4. 手動QA合格後、新しい候補HEAD、EXE/PCK SHA-256、balance revisionを `artifacts/playtest/target.txt` へ手動で固定する。
5. その後だけ `docs/playtest-protocol.md` を有効化し、未経験者5人以上が各3runを実施する。

候補HEAD、EXE、PCK、balance revisionのいずれかが変わった場合、旧対象、旧QA、旧playtestデータを流用しない。
人間の参加、回答、計測値をエージェントが生成または補完してはならない。

## 正式受入後の棚卸し

5人以上×3run完了までは、revision 4の回帰テスト、Debug QA、性能試験、Release検証、
GDScript guard、比較用buildを保持する。正式受入後に再棚卸しし、配布・保守に不要な資材を削除する。
