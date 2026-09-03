# Project JARJAR 人間プレイテスト手順

**状態: 使用禁止（balance revision 8 source gate未実施・正式候補未固定）**

現在フェーズは `docs/project-status.md` を正とする。正式プレイテスト対象はまだ固定していないため、
現時点では候補者を採用せず、資格確認も結果収集も行わない。

## 正式対象の固定条件

ユーザーが最終調整完了を明示するまで、正式性能試験、Release export、Verify、ManualQa、人間playtestを実施しない。
完了明示後に全検証とRelease exportを再実施し、`docs/final-qa.md`へ人間によるManual QAのPASSを記録した後、
`artifacts/playtest/target.txt`へ次の4行を手動で記録する。

```text
candidate_head=<40hex>
exe_sha256=<64hex>
pck_sha256=<64hex>
balance_revision=8
```

`docs/project-status.md`が「正式playtest対象固定済み」へ更新され、同じ4値が一致するまで下記手順を開始しない。
EXE/PCK、balance revision、候補HEADのいずれかが変わった場合、以前の対象やデータを流用しない。
revision 7以前のsource gate、回帰、QA、build identity、playtest記録は履歴専用であり、revision 8候補の証拠として無効である。

## 専用12run調整ゲート

正式候補の固定前に、専用fixtureの決定的12runで実際の候補抽選、XP取得、宝箱取得を含む初回進化時刻を検査する。

- 12run全体で3:00までの初回進化が0件。
- 2:00以前の死亡が0/12、最終ボス到達が9〜11/12、撃破が5〜8/12。
- normal方針4runのうち正確に2runが5:00までに初回進化する。
- normal方針4runすべてが7:00までに初回進化する。
- normal方針4runの初回進化時刻の算術平均が288秒以上324秒以下。
- 全runでpool overflowとorphanが0。
- 全runで必須metricが存在し、weapon hitとkillが1件以上ある。
- 画面外weapon hitとkillが0で、hit/kill中心距離とeffect外縁距離が各combat envelope内に収まる。
- important VFX dropが0。

revision 8 source gateは未実施である。通常`swarmer`の高速化と50体群れイベントを追加したため、下記の旧結果は
履歴としてのみ保持し、revision 8の正式対象固定には使わない。

revision 5 source gateはseed `17`、`29`、`43`、`61`を`cautious`、`normal`、`evolution`の各方針で実行する
12runでPASSした。実測は2:00以前死亡0/12、最終ボス到達11/12、撃破6/12、3:00まで進化0/12、
normal方針は5:00まで2/4・7:00まで4/4・初回進化平均321.641667秒である。

画面外weapon hit / killは0 / 0（該当runはいずれも0/12）、最大hit中心距離は9.623473167m、
最大kill中心距離は9.570774078m、最大effect外縁距離は8.996990412mである。
VFX admitted / suppressed / important dropは90,151 / 0 / 0、audio admitted / suppressedは53,321 / 181,691、
pool overflowは0run、orphanは0run、必須metric取得は12/12である。
実測CSVとsummaryは`artifacts/balance/revision-5/`に保存している。
同じrevision 5作業ツリーで全GDScript回帰112/112もPASSしたが、revision 8の証拠としては無効である。

この自動調整の最終値は`xp_yield_percent=90`、通常敵damage scale `0.55`、bossのHP `0.5625`、
damage `0.57`、action rate `1.0`である。segment値は次のとおりである。

| segment | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| target_active | 16 | 24 | 36 | 52 | 72 | 96 | 120 | 144 | 168 | 192 |
| hp_multiplier | 0.15 | 0.17 | 0.20 | 0.24 | 0.30 | 0.45 | 0.65 | 0.90 | 1.25 | 1.75 |
| damage_multiplier | 0.18 | 0.20 | 0.22 | 0.25 | 0.29 | 0.36 | 0.45 | 0.56 | 0.72 | 0.95 |

この12runは調整用の自動ゲートであり、下記の初見tester、人間の回答、人間playtestの計測値として数えない。
上記のXP、通常敵damage、segment、boss、候補抽選、進化条件、出現・攻撃・10:00遷移のいずれかを変更した場合、
このsource gate結果を無効として全12runを再実行する。
ユーザーが最終調整完了を明示するまで正式candidateは固定せず、Full HD性能試験、Release export、Verify、ManualQa、
人間playtestは未実施のままとする。

## 初見資格

聞き手は開始前に、候補者へ次の2問をそのまま質問する。

1. 「Project JARJARの過去または現行buildを、一度もプレイしたことがありませんか。」
2. 「Project JARJARのゲームプレイを、対面・配信・録画のいずれでも一度も見たことがありませんか。」

両方に「はい」と回答し、過去のどの`balance_revision`の受入データにも参加していない人だけを採用する。
このQAの実機操作者はtesterへ数えない。氏名、メールアドレス、端末識別子などの個人情報は記録しない。

| balance_revision | 全testerの初見資格確認済み | 確認日 (YYYY-MM-DD) |
|---:|---|---|
| 6 | 未確認 |  |

実際に全員の条件を確認するまでは、上表を`yes`へ変更しない。

## 参加者と起動

- 新規tester 5人以上を採用し、`T01`から欠番なく割り当てる。
- 各testerは同じRelease buildで、同じ1process内に3runを続けて実施する。
- 設定は既定値のまま変更しない。全runで同じ入力方式を使用する。
- run 1はTITLEの「開始」で新seedを開始する。
- run 2、run 3は直前のRESULTまたはFAILEDで「新しいseedで再挑戦」を選ぶ。
- 「同じseedで再挑戦」は使用しない。

各testerの開始時に新しいPowerShell sessionで次を実行し、`T01`だけを割当IDへ置換する。

```powershell
.\tests\release.ps1 -Task Playtest -TesterId T01
```

3run終了までPowerShell sessionを閉じない。終了コードが0でなければ、そのprocessは不合格とする。
最初のCOMBATより前の起動失敗だけは同じ人がclean settingsから再試行できる。COMBAT開始後に中断した場合、
その人の全行を破棄して再採用せず、別の未経験者へ空いた最小tester IDを割り当てる。

## 各runの記録

RESULTまたはFAILEDを表示した直後、次の導線を選ぶ前に、聞き手が画面から以下を転記する。

- run seed
- RESULTなら`run_clear=yes`、FAILEDなら`run_clear=no`
- survival_seconds
- final_level
- total_kills
- elite_kills
- boss_result（`defeated`、`player_defeated`、`not_reached`）
- evolution_count

続けて、聞き手が次の3問を順番どおり質問する。

1. 「このランの成長と3択の体験を、1=非常に悪い、2=悪い、3=普通、4=良い、5=非常に良いで評価してください」
2. 「今すぐもう1ラン遊びたいですか。yesかnoで答えてください」
3. 「このランで、ゲームを壊したと感じるほど強いビルドを経験しましたか。yesかnoで答えてください」

run 1だけは上の3問に続けて、次の理解度質問をそのまま質問する。説明や誘導を追加してから
答え直してもらってはならない。

4. 「基本武器をLv8にして対応パッシブを持ち、宝箱を取ると進化できる、と分かりやすく理解できましたか。yesかnoで答えてください」

各runについて、進化を1回以上経験したかを記録する。経験した場合は画面のラン時間から最初の進化秒を転記する。
run 3の回答後はTITLEへ戻り、ゲーム内の「終了」で閉じる。

## CSV制約

- `docs/playtest-results.csv`: 1runにつき1行。
- `docs/playtest-build-experiences.csv`: 1runにつき1行。
- `docs/playtest-understanding.csv`: 1testerにつきrun 1直後の理解度回答を1行。
- UTF-8 BOMなし、LF、カンマ区切り、空セルなし。
- yes/no列は小文字`yes`または`no`だけ。
- `run_index`は1..3、`run_seed`は画面表示と一致する0..9,223,372,036,854,775,807。
- `is_first_run=yes`と`run_index=1`は同値とする。run 1は必ず`yes`、run 2とrun 3は必ず`no`とする。
- `growth_choice_experience_1_to_5`は整数1..5、`survival_seconds`は0以上、`final_level`は1以上。
- `boss_result`は`defeated`、`player_defeated`、`not_reached`だけ。
- `run_clear=yes`なら`boss_result=defeated`、noなら`player_defeated`または`not_reached`。
- `evolution_count`は0..4。`evolution_experienced_yes_no=yes`なら1..4と一致し、`first_evolution_seconds`は0より大きい。
- 進化なしの場合、`evolution_experienced_yes_no=no`かつ`first_evolution_seconds=0`とする。
- resultsとbuild-experiencesの一意キーは`(tester_id, run_index)`で完全一致する。
- understandingの一意キーは`tester_id`で、`run_index=1`とする。
- resultsに存在する全testerがunderstandingにちょうど1行存在し、understandingに余分なtesterを含めない。
- 各testerは3runを持ち、同一tester内でrun seedを重複させない。
- 採用testerの全3行で`first_time_eligible_yes_no=yes`とする。

## 合格判定

5人以上×各3run、合計15run以上が有効であることを確認してから集計する。

- 成長・選択体験平均: 4.0以上
- 即時再挑戦yes: 全回答の70%以上
- 各testerのrun 1だけによる初見クリア率: 40%以上60%以下
- 最終ボス到達率: 全有効runのうち `boss_result` が `defeated` または `player_defeated` であるrunが70%以上80%以下
- run 1直後の進化条件理解度yes: 全testerの80%以上
- 全testerが3run以内に進化を1回以上経験
- 全testerが3run以内に圧倒的なビルドを1回以上経験

百分率は丸めずに判定する。条件未達時は実測表と原因仮説を報告し、値や実装を独断で変更しない。
人間の参加、回答、測定値を生成または補完してはならない。

## 再開指示（正式対象固定後のみ）

同一EXE/PCKペアで記入済みの3つのCSVを提供した後、次の文言で再開する。

`正式プレイテスト集計を再開 H`

`H`は`artifacts/playtest/target.txt`へ記録した40文字候補HEADへ置換する。再開時に現在HEAD、target記録、
EXE/PCK SHA-256、balance revision、初見資格`yes`、全CSV制約を再検証する。不一致が1件でもあれば集計しない。
