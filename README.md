# Project JARJAR

Godot 4.7.2-stableで開発する、Windows向けの見下ろし型3Dサバイバル・ローグライトです。

30×30mのアリーナで追尾核Lv1から開始し、移動に集中しながら自動攻撃とレベルアップ3択で
10分間ビルドを成長させます。3択は未最大の所持品を優先抽選し、残りを通常weightの重複なし抽選で埋める
Vampire Survivors型の成長方式です。
武器5枠とパッシブ5枠を組み合わせ、定時エリートが落とす宝箱で最大4本を進化させ、
10:00に出現する最終ボスを倒すとランクリアです。名称、形状、演出は幾何学テーマの独自表現です。

通常敵は上下左右4辺の外周固定スポーンですが、カメラ外からの出現を保証するものではありません。
通常敵とエリートは接触追跡だけを行い、予告付きの放射状投射物を使うのは最終ボスだけです。
戦闘範囲は標的中心8m・効果外縁9m・damage中心10m、安定化した直交投影カメラはsize `18`・follow tau `0.12`秒です。

## revision 6の現在地

基本武器8種はLv2〜Lv8の各レベルで直接変わる強化項目を1つに固定しました。弾数、波数、結晶数、環数、
軌道体数の増加はすべて`+1`です。所持済みのレベルアップ候補と通常強化宝箱には、今回変わる基礎値だけを表示します。
全GDScript回帰114/114、GDScript guard 98ファイル、変更GDScriptのcheck-only 15/15がPASSしています。

武器性能を変更したため、revision 5のsource gateはrevision 6へ流用しません。revision 6のsource再調整は未実施で、
正式candidateと正式playtest targetも未固定です。Full HD性能試験、Release export、Verify、ManualQa、人間playtestは
ユーザーが最終調整完了を明示するまで実行禁止です。

## revision 5自動調整の履歴（revision 6へ流用禁止）

balance revision 5の自動調整は、2026-09-02の専用12run source gateで`passed=true`となり完了しています。
seed `17`、`29`、`43`、`61`をcautious、normal、evolutionの各方針で実行した結果は、2:00以前死亡0/12、
ボス到達11/12、撃破6/12、3:00まで進化0/12、normal方針は5:00まで2/4・7:00まで4/4・
初回進化平均321.641667秒です。

offscreen weapon hit/killはともに0run、`max_hit_center_distance=9.623473167m`、
`max_effect_outer_distance=8.996990412m`でした。important VFX drop、全pool overflow、全pool orphanはいずれも0、
audio cueはadmitted 53,321・suppressed 181,691です。調整成果物は`artifacts/balance/revision-5/`にあります。
同じrevision 5作業ツリーの全GDScript回帰も112/112でPASSしました。

最終調整値は`xp_yield_percent=90`、`normal_enemy_damage_scale=0.55`、bossの
`hp_multiplier=0.5625`（base 40,000から22,500 HP）・`damage_multiplier=0.57`・`action_rate_multiplier=1.0`です。

| segment | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| target_active | 16 | 24 | 36 | 52 | 72 | 96 | 120 | 144 | 168 | 192 |
| hp_multiplier | 0.15 | 0.17 | 0.20 | 0.24 | 0.30 | 0.45 | 0.65 | 0.90 | 1.25 | 1.75 |
| damage_multiplier | 0.18 | 0.20 | 0.22 | 0.25 | 0.29 | 0.36 | 0.45 | 0.56 | 0.72 | 0.95 |

これらの値はrevision 6でも未再調整の初期値として残っていますが、revision 5の実測結果は現候補の証拠ではありません。

## revision 4の履歴（現候補へ流用禁止）

balance revision 4は、2026-09-01の専用12run source gateでPASSしていました。実測は2:00以前死亡0/12、
ボス到達9/12、撃破8/12、3:00まで進化0/12、normal方針は5:00まで2/4・7:00まで4/4・初回進化平均322.883秒、
pool overflow/orphanともに0runでした。履歴成果物は`artifacts/balance/revision-4/`にあります。

revision 4の最終値は`starter_weapon_id=homing_core`、`xp_yield_percent=165`、elite `xp_value=50`、segmentの
`target_active=[4, 6, 9, 13, 18, 36, 48, 60, 69, 100]`、`hp_multiplier=[0.15, 0.168, 0.192, 0.222, 0.258, 0.6, 0.936, 0.959, 1.44, 2.625]`、
`damage_multiplier=[0.25, 0.27, 0.29, 0.315, 0.345, 0.532, 0.672, 0.651, 0.824, 1.368]`、
bossのHP 1.5・damage 0.798・action rate 1.0でした。revision 4のcandidate、成果物、回帰、QA、build identityは
revision 5以降の証拠として無効であり、履歴としてのみ保持します。

- 現在の状態と次の作業: [docs/project-status.md](docs/project-status.md)
- コーディングエージェント向け制約: [AGENTS.md](AGENTS.md)
- 最終候補のQA記録: [docs/final-qa.md](docs/final-qa.md)
- 正式対象固定後のプレイテスト手順: [docs/playtest-protocol.md](docs/playtest-protocol.md)

プロジェクトはPATH上のGodot 4.7.2-stable Standardで開いてください。
