# Project JARJAR Gate 6 人間プレイテスト手順

**状態: 使用禁止（ユーザー最終調整待ち）**

現在フェーズは `docs/project-status.md` を正とする。正式プレイテスト対象はまだ固定していないため、
現時点では候補者を採用せず、資格確認も結果収集も行わない。

## 正式対象の固定条件

ユーザー最終調整後に全検証とRelease exportを再実施し、
`artifacts/gate-06/playtest-target.txt`へ
`candidate_head=<40hex>`、`release_build_identity=<identity>`、`balance_revision=<integer>`を
記録する。`docs/project-status.md`が「正式playtest対象固定済み」へ更新され、同じ3値が一致するまで
下記手順を開始しない。EXE/PCK、identity、balance revision、または候補HEADが
変わった場合、以前の対象やデータを流用しない。

## 初見資格

聞き手は開始前に、候補者へ次の2問をそのまま質問する。

1. 「Project JARJARの過去または現行buildを、一度もプレイしたことがありませんか。」
2. 「Project JARJARのゲームプレイを、対面・配信・録画のいずれでも一度も見たことがありませんか。」

両方に「はい」と回答し、かつ過去のどの`balance_revision`の受入データにも参加していない人だけを採用する。
このQAの実機ゲームパッド操作者はtesterへ数えない。氏名、メールアドレス、端末識別子などの
個人情報は記録しない。

| balance_revision | 全testerの初見資格確認済み | 確認日 (YYYY-MM-DD) |
|---:|---|---|
| 0 | 未確認 |  |

実際に全員の条件を確認するまでは、上表を`yes`へ変更しない。

## 参加者と起動

- 新規tester 5人以上を採用し、`T01`から欠番なく割り当てる。
- 各testerは同じRelease buildで、同じ1process内に3runを続けて実施する。
- 設定は既定値のまま変更しない。全runでWASDを使用する。
- run 1はTITLEの「開始」で新seedを開始する。
- run 2、run 3は直前のRESULTまたはFAILEDで「新しいseedで再挑戦」を選ぶ。
- 「同じseedで再挑戦」は選ばない。

各testerの開始時に新しいPowerShell sessionで次を実行し、`T01`だけを割当IDへ置換する。

```powershell
$testerId = "T01"
$jarjarReleaseExe = (Resolve-Path -LiteralPath ".\build\windows\ProjectJARJAR.exe").Path
$jarjarReleaseDir = Split-Path -Parent $jarjarReleaseExe
& ".\tests\run_with_clean_settings.ps1" -Executable $jarjarReleaseExe -Arguments ([string[]]@()) -Label ("playtest_" + $testerId.ToLowerInvariant()) -ExpectedExitCodes @(0) -WorkingDirectory $jarjarReleaseDir
```

3run終了までPowerShell sessionを閉じない。終了コードが0でなければ、そのprocessは不合格とする。
最初のCOMBATより前の起動失敗だけは同じ人がclean settingsから再試行できる。COMBAT開始後に
中断した場合、その人の全行を破棄して再採用せず、別の未経験者へ空いた最小tester IDを割り当てる。

## 各runの記録

RESULTまたはFAILEDを表示した直後、次の導線を選ぶ前に、聞き手が画面から以下を転記する。

- run seed
- RESULTなら`run_clear=yes`、FAILEDなら`run_clear=no`
- cleared waves
- combat score
- final build score
- total score

画面上で`combat_score + final_build_score = total_score`も照合する。不一致ならそのbuildの
プレイテストを中止し、当該データを集計しない。

続けて、聞き手が次の3問を順番どおり質問する。

1. 「このランの宝箱開封・整理・合成体験を、1=非常に悪い、2=悪い、3=普通、4=良い、5=非常に良いで評価してください」
2. 「今すぐもう1ラン遊びたいですか。yesかnoで答えてください」
3. 「このランで、ゲームを壊したと感じるほど強いビルドを経験しましたか。yesかnoで答えてください」

run 3の回答後はTITLEへ戻り、ゲーム内の「終了」で閉じる。

## 整理時間

聞き手がゲーム外のstopwatchで、全報酬公開後にINVENTORYへ入った瞬間から、次のCOMBATまたは
RESULTへ遷移する瞬間までを計測する。W8最終整理を含む。REWARD_REVEALの時間、設定画面滞在、
失敗waveは記録しない。秒数は0より大きく、小数3桁以内で記録する。

各results行のinventory-timesは、`cleared_waves=0`なら0行、それ以外はwave `1..cleared_waves`を
重複なく完全に含める。

## CSV制約

- `docs/playtest-results.csv`: 1runにつき1行。
- `docs/playtest-inventory-times.csv`: 1整理区間につき1行。
- UTF-8 BOMなし、LF、カンマ区切り、空セルなし。
- yes/no列は小文字`yes`または`no`だけ。
- `run_index`は1..3、`run_seed`は画面表示と一致する0..9,223,372,036,854,775,807。
- rewardは整数1..5、`cleared_waves`は整数0..8、scoreは0以上の整数。
- `is_first_run=yes`は各testerのrun 1だけ。
- 採用testerの全3行で`first_time_eligible_yes_no=yes`。
- `run_clear=yes`なら`cleared_waves=8`、noなら0..7。
- resultsの一意キーは`(tester_id, run_index)`。
- inventory-timesの一意キーは`(tester_id, run_index, wave_number)`。
- 同一tester内でrun seedを重複させない。

## 合格判定

5人以上×各3run、合計15run以上が有効であることを確認してから集計する。

- 報酬体験平均: 4.0以上
- 即時再挑戦yes: 全回答の70%以上
- 全整理区間のseconds中央値: 30..60秒
- 各testerのrun 1だけによる初見クリア率: 40..60%
- 全testerが3run以内にbroken buildを1回以上経験
- 完走runの`combat_score / total_score`中央値: 65..75%

中央値は昇順で、奇数件は中央1値、偶数件は中央2値の算術平均とする。百分率は丸めずに判定する。
条件未達時は実測表と原因仮説を報告し、値や実装を独断で変更しない。

## 再開指示（正式対象固定後のみ）

同一EXE/PCKペアで記入済みの2つのCSVを提供した後、次の文言で再開する。

`Gate 6のプレイテスト集計を再開 H`

`H`は`artifacts/gate-06/playtest-target.txt`へ記録した40文字候補HEADへ置換する。再開時に
現在HEAD、target記録、identity、balance revision、初見資格`yes`、全CSV制約を再検証する。
不一致が1件でもあれば集計しない。
