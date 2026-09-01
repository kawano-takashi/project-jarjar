# Project JARJAR

Godot 4.7.2-stableで開発する、Windows向けの見下ろし型3Dサバイバル・ローグライトです。

40×40mのアリーナで追尾核Lv1から開始し、移動に集中しながら自動攻撃とレベルアップ3択で
10分間ビルドを成長させます。3択は未最大の所持品を優先抽選し、残りを通常weightの重複なし抽選で埋める
Vampire Survivors型の成長方式です。
武器5枠とパッシブ5枠を組み合わせ、定時エリートが落とす宝箱で最大4本を進化させ、
10:00に出現する最終ボスを倒すとランクリアです。名称、形状、演出は幾何学テーマの独自表現です。

balance revision 4の自動調整は、2026-09-01の専用12run source gateでPASSして完了しています。実測は2:00以前死亡0/12、
ボス到達9/12、撃破8/12、3:00まで進化0/12、normal方針は5:00まで2/4・7:00まで4/4・初回進化平均322.883秒、
pool overflow/orphanともに0runです。調整成果物は`artifacts/balance/revision-4/`にあります。

自動調整の最終値は`starter_weapon_id=homing_core`、`xp_yield_percent=165`、elite `xp_value=50`、segmentの
`target_active=[4, 6, 9, 13, 18, 36, 48, 60, 69, 100]`、`hp_multiplier=[0.15, 0.168, 0.192, 0.222, 0.258, 0.6, 0.936, 0.959, 1.44, 2.625]`、
`damage_multiplier=[0.25, 0.27, 0.29, 0.315, 0.345, 0.532, 0.672, 0.651, 0.824, 1.368]`、
bossのHP 1.5・damage 0.798・action rate 1.0です。

ただし、ユーザーが最終調整完了を明示するまで正式candidateは未固定です。Full HD性能試験、Release export、Verify、
ManualQa、人間playtestは未実施で、正式な5人以上×3runのプレイテスト対象もまだ固定していません。
revision 3以前のRelease検証、手動QA、playtest対象・結果はすべて無効です。

- 現在の状態と次の作業: [docs/project-status.md](docs/project-status.md)
- コーディングエージェント向け制約: [AGENTS.md](AGENTS.md)
- 最終候補のQA記録: [docs/final-qa.md](docs/final-qa.md)
- 正式対象固定後のプレイテスト手順: [docs/playtest-protocol.md](docs/playtest-protocol.md)

プロジェクトはPATH上のGodot 4.7.2-stable Standardで開いてください。
