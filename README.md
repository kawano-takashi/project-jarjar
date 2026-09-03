# Project JARJAR

Godot 4.7.2-stableで開発する、Windows向けの見下ろし型3Dサバイバル・ローグライトです。

30×30mのアリーナで追尾核Lv1から開始し、移動に集中しながら自動攻撃とレベルアップ3択で
10分間ビルドを成長させます。3択は未最大の所持品を優先抽選し、残りを通常weightの重複なし抽選で埋める
Vampire Survivors型の成長方式です。
武器5枠とパッシブ5枠を組み合わせます。進化では基本武器Lv8に対し、対応パッシブを触媒として
Lv1以上所持していればよく、触媒は最大Lv不要・進化後も消費されません。定時エリートが落とす宝箱で最大4本を進化させ、
10:00に出現する最終ボスを倒すとランクリアです。名称、形状、演出は幾何学テーマの独自表現です。

通常敵はプレイヤーを中心とした画面軸基準の10〜12m帯から出現し、定時抽選された50体の小型群れも
同じ生成帯から画面方向へ高速横断します。通常敵とエリートは接触追跡だけを行います。
予告付きの放射状投射物を使うのは最終ボスだけです。
戦闘範囲は標的中心8m・効果外縁9m・damage中心10m、安定化した直交投影カメラはsize `18`・follow tau `0.12`秒です。

## revision 11の現在地

プレイヤーと通常敵の座標移動速度をrevision 10から一律10%下げ、Player 4.5、Pursuer 2.16、
Swarmer 5.76、Shooter 2.7、Bulwark 1.215、Elite 1.8、Boss 1.44m/sとしました。
相対速度比、斜め入力の正規化、世界空間の方向等速性、カメラsize `18`・follow tau `0.12`秒は維持します。

50体群れは一律倍率の例外です。Hyper Mad Forestの公開映像2本から非衝突Bat Swarm個体を4体ずつ測り、
全8標本中央値`0.1307825102画面高/秒`を正射影18m・俯角55度へ換算した`2.59m/s`を採用しました。
生成距離、10×5隊列、総走行距離、HP、威力、頻度は変更せず、横断時間だけを延長しています。
通常敵・エリート・ボスへの1tick押し出し上限は、群れの定義速度を60で割って毎tick算出します。

revision 10で導入した追尾核は、弾数を同時生成せず、初弾を即時、その後を6 combat tick（0.10秒）間隔で1発ずつ発射します。
連射中は有効な標的を維持し、死亡または標的範囲外になった場合だけ未発射弾を現在位置から再照準します。
敵がいなくなっても残弾は最後の照準方向へ直進し、発射後は再追尾・跳弾せず最初に接触した有効敵へ1回だけ命中します。
進化後の無限追尾は従来どおり毎tick発射・飛翔中再追尾です。追尾核自体の威力、弾数、発動間隔、射程、成長表、武器説明文は変更していません。

通常敵は画面上下左右を各25%で選び、プレイヤーから辺距離10〜12m、辺方向位置`-d〜d`へ生成します。
アリーナ外でも21 tickの出現待機後に追尾・標的化・攻撃・接触が有効になり、内側へ連続移動してから境界制限を受けます。
10:00より前にプレイヤーから画面軸方向18mを越えた通常敵は、撃破・XP・drop・CHAINなしで破棄されます。
STOP中も生成管理と遠方破棄は進み、敵移動と接触は停止します。

通常waveとは別枠の50体群れも専用RNGで四辺と10〜12mを抽選し、プレイヤー正面をアンカーに10列×5行の
橙／赤チェック模様を即時生成します。方向は生成時のプレイヤーへ固定し、2.59m/sで`2d+2.8m`進むため、
全生存個体が対辺まで横断して同時に無報酬退場します。通常敵・エリート・ボスへの押し出しは維持します。
通常敵の遠方破棄は`normal_far_despawns`、群れの生成・撃破・退場・XPは従来どおり別統計で記録します。
revision 11実装後の全GDScript回帰129/129、GDScript guard 102ファイル、変更したGDScriptのcheck-only 14/14、
差分の空白検査がPASSしています。

2026-09-03のrevision 11正式12run source gateは一度だけ実施し、ボス到達12/12（必要9〜11）、
normal方針の7分以内進化3/4（必要4/4）、4組のwave pair判定により`passed=false`となりました。
計画どおり同じ作業内では再調整も再実行もしていません。正式candidateと正式playtest targetは未固定です。
Full HD性能試験、Release export、Verify、ManualQa、人間playtestは実施していません。

## revision 5自動調整の履歴（revision 11へ流用禁止）

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

これらはrevision 5の履歴値であり、revision 11の実データや現候補の証拠ではありません。

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
