class_name SurvivalContentManifest
extends Resource


## プレイヤーの基礎設定。必須のPlayerBalanceDefinition。
@export var player: PlayerBalanceDefinition = null

## 成長・抽選・経験値の設定。必須のProgressionBalanceDefinition。
@export var progression: ProgressionBalanceDefinition = null

## アリーナ寸法・配置・ドロップ設定。必須のArenaBalanceDefinition。
@export var arena: ArenaBalanceDefinition = null

## 戦闘補正と攻撃範囲の設定。必須のCombatBalanceDefinition。
@export var combat: CombatBalanceDefinition = null

## 出現ペース・出現位置・保護時間の設定。必須のSpawnBalanceDefinition。
@export var spawn: SpawnBalanceDefinition = null

## 区間の群れ予定が使う個体・隊列設定。必須。
@export var swarm_event: SwarmEventDefinition = null

## 全武器。必須参照のみ、ID重複不可。通常武器の重み合計は正。
@export var weapons: Array[WeaponDefinition] = []

## 全パッシブ。必須参照のみ、ID重複不可。有効な候補がある場合は重み合計が正。
@export var passives: Array[PassiveDefinition] = []

## 進化の対応関係の正本。必須参照のみ、進化元・進化先はそれぞれ重複不可。
@export var evolutions: Array[EvolutionDefinition] = []

## 全EnemyTypeの定義。各種別に1つ、必須参照のみ、ID重複不可。
@export var enemies: Array[EnemyDefinition] = []

## 実行する区間。1つ以上、必須参照のみ、配列順にduration_ticksを積算。最終終了時にボス出現。
@export var segments: Array[EnemySegmentDefinition] = []
