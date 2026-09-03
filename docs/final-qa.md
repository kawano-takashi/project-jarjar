# Project JARJAR 最終QA記録

**状態: 人間QA未実施（balance revision 8 source gate未実施、正式候補未固定）**

この文書は候補固定前の自動調整記録、対象identityに対する自動検証結果、および人間が実機で確認した事実を記録する。
過去のrevision、別のEXE/PCK、別の候補HEADの結果は転記しない。`ManualQa`の終了コード0だけでは合格にしない。
ユーザーが最終調整完了を明示するまで正式candidateを固定せず、対象identityも記入しない。
revision 7以前のsource gate、回帰、QA、build identity、playtest記録は履歴専用であり、revision 8候補の証拠として無効である。

## 対象identity

- candidate_head:
- exe_sha256:
- pck_sha256:
- balance_revision: `8`
- 実施日:
- 判定: 未実施

4値のいずれかが変わったら、この記録を無効として新しい対象で全項目を再実施する。

## revision 8 source gate

未実施。通常`swarmer`を6.4m/sへ高速化し、通常waveと独立した50体の高速群れイベントを追加したため、
revision 7以前の自動調整結果は流用しない。既存の全体balance値、受入閾値、bot方針は変更せず、
高速群れを含む再調整を別作業で一度だけ行う。

## revision 5自動調整済みsource gate（履歴・revision 8へ流用禁止）

seed `17`、`29`、`43`、`61`を`cautious`、`normal`、`evolution`の各方針で実行する専用12run source gateがPASSした。
実測は次のとおりである。

- 2:00以前の死亡: 0/12
- 最終ボス到達: 11/12
- 最終ボス撃破: 6/12
- 3:00までの初回進化: 0/12
- normal方針の5:00までの初回進化: 2/4
- normal方針の7:00までの初回進化: 4/4
- normal方針の初回進化時刻平均: 321.641667秒
- 画面外weapon hit / kill: 0 / 0（該当runはいずれも0/12）
- 最大hit中心距離: 9.623473167m
- 最大kill中心距離: 9.570774078m
- 最大effect外縁距離: 8.996990412m
- VFX admitted / suppressed / important drop: 90,151 / 0 / 0
- audio admitted / suppressed: 53,321 / 181,691
- pool overflow: 0run、orphan: 0run
- 必須metric取得: 12/12

自動調整の最終値は`xp_yield_percent=90`、通常敵damage scale `0.55`、bossのHP `0.5625`、
damage `0.57`、action rate `1.0`である。segment値は次のとおりである。

| segment | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| target_active | 16 | 24 | 36 | 52 | 72 | 96 | 120 | 144 | 168 | 192 |
| hp_multiplier | 0.15 | 0.17 | 0.20 | 0.24 | 0.30 | 0.45 | 0.65 | 0.90 | 1.25 | 1.75 |
| damage_multiplier | 0.18 | 0.20 | 0.22 | 0.25 | 0.29 | 0.36 | 0.45 | 0.56 | 0.72 | 0.95 |

実測CSVとsummaryは`artifacts/balance/revision-5/`に保存している。このPASSはrevision 5の自動調整完了記録であり、
空欄のrevision 8正式candidate identityに対する性能試験、Release検証、ManualQa、
人間playtestの完了を意味しない。
上記の調整値、segment、候補抽選、進化条件、出現・攻撃・10:00遷移のいずれかを変更した場合、このsource gate結果を無効として
専用12runを全件再実行する。

## 自動検証記録

- 全GDScript回帰: PASS（2026-09-03、revision 8高速群れ実装後121/121）
- GDScript guard: PASS（101ファイル）
- 変更GDScript check-only: PASS（revision 8の変更19/19）
- revision 8専用12run source gate: 未実施
- revision 7以前のsource gate: 履歴専用、revision 8へ流用禁止
- Full HD性能試験（`--performance=full_hd_500_2000`）: 未実施
- pool overflow / orphan: revision 5専用12runでは0run / 0run、正式候補の性能試験は未実施
- Release export: 未実施
- Verify（pack audit、Release smoke、引数拒否、build鮮度、identity）: 未実施
- ManualQa: 未実施
- 人間playtest: 未実施

## 人間による確認

次の各項目をキーボード、マウス、ゲームパッドで確認し、合格・不合格と観察事実を記録する。

- TITLEから開始し、追尾核Lv1をstarterとして30×30mアリーナでWASD、矢印、方向パッド、左スティックが画面基準移動になる。
- 通常敵とエリートがアリーナ外周の固定位置でmaterializeしてから接触追跡を開始する。出現時に画面外であることは必須としない。
- プレイヤー攻撃はすべて自動で、手動照準・攻撃入力がない。
- 通常敵とエリートは接触追跡だけを行い、遠距離攻撃をしない。最終ボスだけが例外として、予告付きの放射弾を撃つ。
- 通常`swarmer`がプレイヤーより速い6.4m/sで常時追尾する。定時抽選された別枠の群れは橙25体・赤25体の
  10×5千鳥配置を保ち、発生時に決めた画面方向へ32m/sで直進し、移動中のプレイヤーを再追尾しない。
- 群れが通常敵・エリート・ボスを進行方向へ押し、対象はアリーナ外へ出ない。プレイヤー、群れ同士、XP、宝箱、
  arena objectは押されず、50体が重なっても1回の被弾後30 combat tickの無敵時間が維持される。
- 敵の経験値結晶を取得すると戦闘が停止し、重複しない最大3候補を選べる。各候補は名前、レベル、
  `種別：武器`または`種別：パッシブ`、未所持なら概要・所持済みなら今回の強化差分、進化情報の順に表示される。
  基本武器の差分は1項目だけで、弾数などの個数増加は`+1`である。リロール、スキップ、除外はない。
- 所持枠が埋まる前の3択は、未最大所持品の優先抽選2回を通常weightより先に行う。2回目の重複時は代替を再抽選せず通常抽選へ戻る。
- HUDにHP、XPまたはMAX、level、時間、撃破数、武器5枠、パッシブ5枠、必要時のボスHPが表示される。
- 8武器・8パッシブの対応関係が最初から確認でき、基本武器Lv8と対応パッシブ所持で進化可能だと理解できる。
- 2:00、4:00、6:00、8:00のエリートが宝箱を1個ずつ落とし、未取得箱は消えない。
- 宝箱結果は1箱1効果で、通常強化ならレベルアップ候補と同じ強化差分を表示し、約2秒演出をA、Enter、クリックから即時スキップできる。
- 破壊ノードのHP回復、全XP吸引、5秒停止が機能し、停止中のボスだけが50%速度で動く。
- 10:00に通常スポーンが止まり、通常敵、残存する群れ、既存enemy projectileが即座に無害化・吸収される。この吸収ではXP、撃破数、CHAIN、dropを得ず、落下済みXPとarena objectは残る。
- 最終ボスがアリーナ中央へ60 combat tickかけて登場し、summonを行わない。
- 最終ボスは30 boss action tickの予告後、phaseごとに8発、12発、16発の放射弾を撃つ。
- 最終ボスの起動時と、その後1800 boss action tickごとのenrageが機能する。
- ボス撃破はRESULT、死亡はFAILEDになる。結果は `DEFEATED`、`PLAYER DEFEATED`、`NOT REACHED` を正しく区別する。
- 1回の被弾後は30 combat tick（0.5秒）の連続被弾防止が機能する。
- レベルアップや宝箱の自動モーダル列がすべて終了した後だけ45 combat tick（0.75秒）の復帰保護となり、列の中間と手動ポーズ復帰では付与されない。
- 戦闘ポーズで再開、設定、確認付きタイトル帰還を操作できる。
- RESULTに生存時間、最終level、総撃破、エリート撃破、ボス結果、進化数、武器系統別ダメージが表示される。
- 同seed再挑戦と新seed再挑戦が正しく動作する。
- XP、レベルアップ、宝箱、進化、ボス警告、被弾の効果音と振動が設定に従う。BGM項目はない。
- フォーカス、読み上げ、reduce motion、reduce flashes、設定画面からの復帰、確認ダイアログが正しく動作する。
- 旧宝箱開封、戦利品レアリティ、接辞、着脱装備、倉庫、合成、scoreの表示や操作が残っていない。

## 観察事実と最終判定

人間が実際に確認するまで観察事実、判定、参加、回答、計測値を生成または補完しない。

- 観察事実:
- 不具合:
- 人間の最終判定: 未実施
