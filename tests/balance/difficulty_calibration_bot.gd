class_name DifficultyCalibrationBot
extends RefCounted

## 難易度検証を自動化するための、決定論的な操作ボットです。
##
## 画面内の敵・弾・攻撃予告・取得物を観測し、複数の移動候補について
## 一定時間先まで接触を予測します。そのうえで、安全性と目的地への進みやすさを
## 比較し、最も適した移動方向とレベルアップ候補を選びます。
##
## `run_seed` から候補の走査順や巡回方向を決めるため、同じ状態とシードなら
## 同じ判断を再現できます。難易度計測や回帰テストでの利用を想定しています。



#region 設定値と識別子

# ボットの行動傾向。移動時の目的地重みとアップグレード規則が変わる。
enum Policy { CAUTIOUS, NORMAL, EVOLUTION }

# --- 将来予測と計算量の設定 ---
# 何 Tick 先まで衝突を予測するか。
const PREDICTION_HORIZON_TICKS: int = 120
# 追尾敵の向きを再計算する間隔。短いほど精密だが計算量が増える。
const SEEK_RECURSION_STEP_TICKS: int = 30
# 通常の移動候補として全周を何方向へ分割するか。
const HEADING_DIRECTION_COUNT: int = 32
# 脅威の混雑度を集約する角度セクター数。
const DENSITY_SECTOR_COUNT: int = 16
# 個別の連続衝突判定を行う通常脅威の最大数。必須脅威は別枠。
const DETAIL_THREAT_LIMIT: int = 32
# 実際の当たり半径へ加える回避用の余白。
const SAFETY_MARGIN: float = 0.20

# --- 画面内判定とプレイヤー物理 ---
# 画面相当矩形の半幅と半奥行き。対象半径を加えて交差判定する。
const VIEW_HALF_WIDTH: float = 16.0
const VIEW_HALF_DEPTH: float = 10.9869713097598
# シミュレーション本体と同じプレイヤー半径・速度を参照する。
const PLAYER_RADIUS: float = CombatEnvelope.PLAYER_BODY_RADIUS
const PLAYER_SPEED: float = CombatSimulation.PLAYER_SPEED
const SECONDS_PER_TICK: float = 1.0 / float(RunState.TICKS_PER_SECOND)
const PREDICTION_SECONDS: float = (
	float(PREDICTION_HORIZON_TICKS) / float(RunState.TICKS_PER_SECOND)
)
# 画面の右方向・下方向を表すワールド空間の単位ベクトル。
# ワールド座標に対して画面が 45 度回転しているため、内積で射影する。
const SCREEN_RIGHT_WORLD: Vector2 = Vector2(0.70710678, -0.70710678)
const SCREEN_DOWN_WORLD: Vector2 = Vector2(0.70710678, 0.70710678)

# --- 候補方向の効用スコア ---
# この距離以内へ壁が近づくと、内側へ戻す補正を発生させる。
const WALL_MARGIN: float = 2.0
# 壁から離れる方向を優先する重み。
const WALL_WEIGHT: float = 4.0
# 前 Tick と同じ方向を保ち、細かい振動を抑える重み。
const CONTINUITY_WEIGHT: float = 0.35
# 脅威密度が高い方向を避ける重み。
const DENSITY_WEIGHT: float = 0.12
# 予測終了時点で脅威から離れている候補への小さな加点。
const END_CLEARANCE_WEIGHT: float = 0.02

# --- 浮動小数点比較用の許容誤差 ---
const VECTOR_EPSILON: float = 0.000001
const SCORE_EPSILON: float = 0.000001
const TIME_EPSILON: float = 0.000001

# --- 取得物の画面内判定に使う見かけ半径 ---
const PICKUP_VISIBILITY_RADIUS: float = 0.5
const CHEST_VISIBILITY_RADIUS: float = 0.7
const XP_VISIBILITY_RADIUS: float = 0.22
# ArenaPickup.Kind と衝突しない、経験値カテゴリ用の内部 ID。
const OBJECTIVE_XP: int = -1

# --- 脅威辞書の形状・種類タグ ---
# 脅威辞書の主要キー:
# `shape`, `kind`, `stable_key`, `stable_id`, `position`, `velocity`,
# `radius`, `damage`, `first_active_tick`, `travel_seconds`, `stop_scale`。
# 専用クラスを増やさず、敵・弾・予告を同じ予測処理へ渡すための共通レコード。
const SHAPE_CIRCLE: StringName = &"circle"
const SHAPE_SWARM_ENVELOPE: StringName = &"swarm_envelope"
const KIND_ENEMY: StringName = &"enemy"
const KIND_SWARM_MEMBER: StringName = &"swarm_member"
const KIND_PROJECTILE: StringName = &"projectile"
const KIND_MATERIALIZING: StringName = &"materializing"
const KIND_TELEGRAPH: StringName = &"telegraph"
const KIND_BOSS_SPOKE: StringName = &"boss_spoke"
const KIND_SWARM_ENVELOPE: StringName = &"swarm_envelope"

# --- 目的地とアップグレード方針 ---
# 取得物が見つからないときに巡回する、アリーナ内の四つの目標点。
const PATROL_WAYPOINTS: Array[Vector2] = [
	Vector2(-10.0, -10.0),
	Vector2(10.0, -10.0),
	Vector2(10.0, 10.0),
	Vector2(-10.0, 10.0),
]
# 方針ごとの目的地方向の重み。慎重 < 通常 < 進化。
const OBJECTIVE_WEIGHT_BY_POLICY: Array[float] = [0.75, 1.5, 2.25]
# 慎重方針で提示されていれば即選ぶ、生存寄りアップグレードの優先順。
const CAUTIOUS_UPGRADE_PRIORITY: Array[StringName] = [
	&"repair_core",
	&"life_lattice",
	&"zero_field",
	&"resonance_wave",
]

#endregion

#region 実行時状態

# 現在の行動方針。
var policy: int = Policy.NORMAL
# 現在 Tick で保持している移動入力。
var _held_input: Vector2 = Vector2.ZERO
# 最後に移動判断を行った戦闘 Tick。
var _last_decision_tick: int = -1
# 巡回や脅威回避で左回り／右回りのどちらを先に試すか。値は -1 または 1。
var _handedness: float = 1.0
# 全方位候補の走査開始角度をずらす、シード由来の添字。
var _direction_offset: int = 0
# 現在向かっている巡回点の添字。
var _patrol_index: int = 0
# 距離やスコアが同じとき、小さい ID と大きい ID のどちらを選ぶか。
var _prefer_lower_id: bool = true
# 一度画面内で確認し、まだ消失を確認していない宝箱 ID と位置。
var _seen_chests: Dictionary[int, Vector2] = {}
# 敵・弾の速度を差分推定するための、前 Tick の位置と Tick。
var _observations: Dictionary[String, Dictionary] = {}
# 通常方針で進化まで集中育成する武器系統 ID。
var _normal_focus_lineage: StringName = &""
# 直近判断時に画面内で数えた脅威の内訳。
var _last_threat_counts: Dictionary[String, int] = {
	"enemy": 0,
	"projectile": 0,
	"materializing": 0,
	"telegraph": 0,
	"boss_warning": 0,
	"swarm_member": 0,
}
# 直近の候補評価と採用結果。デバッグ表示や自動テストで参照する。
var _last_avoidance_debug: Dictionary = {
	"visible_threat_count": 0,
	"detailed_threat_count": 0,
	"safe_candidate_count": 0,
	"candidate_count": 0,
	"selected_first_collision_tick": -1,
	"selected_contact_tick_count": 0,
	"selected_peak_damage": 0.0,
	"selected_end_clearance": INF,
	"used_unavoidable_fallback": false,
}


#endregion

#region 公開 API

## 行動方針とラン用シードを設定し、内部状態を初期化します。
##
## 方針が範囲外なら `false` を返します。同じ `run_seed` を渡した場合は、
## 巡回方向・候補順・同点時の選択規則も同じになります。
func initialize(p_policy: int, run_seed: int) -> bool:
	if p_policy < Policy.CAUTIOUS or p_policy > Policy.EVOLUTION:
		return false
	policy = p_policy
	_held_input = Vector2.ZERO
	_last_decision_tick = -1
	# シードから「右回り／左回り」「候補の開始角度」「同点時の ID 順」を決める。
	# ランダム API を使わないため、実行環境に依存せず再現できる。
	_handedness = -1.0 if (absi(run_seed) % 2) == 0 else 1.0
	_direction_offset = absi(run_seed) % HEADING_DIRECTION_COUNT
	_patrol_index = absi(run_seed) % PATROL_WAYPOINTS.size()
	_prefer_lower_id = (absi(run_seed) % 2) != 0
	# 前回ランの観測・記憶・デバッグ値をすべて破棄する。
	_seen_chests.clear()
	_observations.clear()
	_normal_focus_lineage = &""
	_last_threat_counts = {
		"enemy": 0,
		"projectile": 0,
		"materializing": 0,
		"telegraph": 0,
		"boss_warning": 0,
		"swarm_member": 0,
	}
	_last_avoidance_debug = {
		"visible_threat_count": 0,
		"detailed_threat_count": 0,
		"safe_candidate_count": 0,
		"candidate_count": 0,
		"selected_first_collision_tick": -1,
		"selected_contact_tick_count": 0,
		"selected_peak_damage": 0.0,
		"selected_end_clearance": INF,
		"used_unavoidable_fallback": false,
	}
	return true


## 現在の戦闘 Tick に対する移動入力を返します。
##
## 同じ Tick 内で複数回呼ばれても再計算せず、直前に決めた入力を返します。
func movement_input(simulation: CombatSimulation) -> Vector2:
	if simulation == null or simulation.state == null:
		return Vector2.ZERO
	var current_tick: int = simulation.state.combat_tick
	# 物理・描画など複数箇所から呼ばれても、同じ Tick では判断を固定する。
	if current_tick == _last_decision_tick:
		return _held_input
	_last_decision_tick = current_tick
	_held_input = _decide_movement(simulation)
	return _held_input


## 提示されたレベルアップ候補から、現在の方針に合う候補の添字を返します。
##
## 選択できない入力の場合は `-1` を返します。
func choose_upgrade(
	offer: LevelOffer,
	state: RunState,
	catalog: DefinitionCatalog,
) -> int:
	if offer == null or state == null or catalog == null or offer.options.is_empty():
		return -1
	# 慎重方針は生存系を固定優先し、進化方針は特定ビルドの完成を優先する。
	if policy == Policy.CAUTIOUS:
		for preferred_id: StringName in CAUTIOUS_UPGRADE_PRIORITY:
			var preferred_index: int = _find_option(offer, preferred_id)
			if preferred_index >= 0:
				return preferred_index
	elif policy == Policy.EVOLUTION:
		if state.passive(&"cycle_crystal") == null:
			var cycle_index: int = _find_option(offer, &"cycle_crystal")
			if cycle_index >= 0:
				return cycle_index
		var homing: RunWeapon = state.weapon_for_lineage(&"homing_core")
		if homing != null and not homing.evolved and homing.level < 8:
			var homing_index: int = _find_option(offer, &"homing_core")
			if homing_index >= 0:
				return homing_index
	# 方針固有の候補がなければ、汎用の進化シナジー規則へフォールバックする。
	return _normal_upgrade_choice(offer, state, catalog)


## `Policy` の値を、ログや集計で使う安定した文字列へ変換します。
static func policy_name_for(value: int) -> String:
	match value:
		Policy.CAUTIOUS:
			return "cautious"
		Policy.NORMAL:
			return "normal"
		Policy.EVOLUTION:
			return "evolution"
	return "invalid"


## 直近の観測数・脅威数・回避評価を、デバッグ表示用の辞書として返します。
## 内部辞書は複製して返すため、呼び出し側から状態を直接変更できません。
func debug_state() -> Dictionary:
	return {
		"seen_chest_count": _seen_chests.size(),
		"observation_count": _observations.size(),
		"threat_counts": _last_threat_counts.duplicate(),
		"avoidance": _last_avoidance_debug.duplicate(true),
		"prediction_horizon_ticks": PREDICTION_HORIZON_TICKS,
		"heading_direction_count": HEADING_DIRECTION_COUNT,
		"detail_threat_limit": DETAIL_THREAT_LIMIT,
		"safety_margin": SAFETY_MARGIN,
		"view_half_width": VIEW_HALF_WIDTH,
		"view_half_depth": VIEW_HALF_DEPTH,
	}


## 決定論テストや状態比較に使えるよう、内部状態を固定順序の配列へ変換します。
## Dictionary の列挙順に依存しないよう、ID とキーを明示的にソートします。
func deterministic_state_values() -> Array:
	# Dictionary の内部順序ではなく、ID 昇順の明示的な並びを作る。
	var chest_ids: Array[int] = []
	for pickup_id: int in _seen_chests:
		chest_ids.append(pickup_id)
	chest_ids.sort()
	var chest_entries: Array = []
	for pickup_id: int in chest_ids:
		chest_entries.append([pickup_id, _seen_chests[pickup_id]])
	# 観測履歴もキーでソートし、スナップショット比較を安定させる。
	var observation_keys: Array[String] = []
	for observation_key: String in _observations:
		observation_keys.append(observation_key)
	observation_keys.sort()
	var observation_entries: Array = []
	for observation_key: String in observation_keys:
		var observation: Dictionary = _observations[observation_key]
		observation_entries.append([
			observation_key,
			observation.get("position", Vector2.ZERO),
			int(observation.get("tick", -1)),
		])
	return [
		policy,
		_held_input,
		_last_decision_tick,
		_handedness,
		_direction_offset,
		_patrol_index,
		_prefer_lower_id,
		chest_entries,
		observation_entries,
		_last_threat_counts.duplicate(),
		String(_normal_focus_lineage),
	]


#endregion

#region 移動判断と脅威の抽出

# 1 Tick 分の移動判断をまとめて行う中心処理です。
# 観測、予測、候補生成、衝突評価、最終比較の順に処理します。
func _decide_movement(simulation: CombatSimulation) -> Vector2:
	var player_position: Vector2 = simulation.player_position
	# 1. 見えた宝箱と、以前見た宝箱の消失を更新する。
	_observe_chests(simulation, player_position)
	# 2. 画面内のエンティティを共通形式の脅威へ変換する。
	var collected: Dictionary = _collect_visible_threats(simulation, player_position)
	var visible_threats: Array[Dictionary] = collected.get("visible", [])
	var mandatory_threats: Array[Dictionary] = collected.get("mandatory", [])
	# 3. 計算量を抑えつつ、方向の偏りが出ないよう詳細評価対象を選ぶ。
	var detailed_threats: Array[Dictionary] = _select_detailed_threats(
		visible_threats,
		mandatory_threats,
		player_position,
	)
	# 4. 発生待ち・停止効果・寿命を含む将来経路を構築する。
	_prepare_threat_paths(detailed_threats, simulation.state)
	# 5. 詳細対象外も含め、全脅威から方向ごとの混雑度を作る。
	var density: PackedFloat32Array = _build_directional_density(
		visible_threats,
		player_position,
	)
	# 6. 取得目標への方向と、壁から内側へ戻す補正を求める。
	var objective: Vector2 = _objective_direction(simulation, player_position)
	var wall: Vector2 = _wall_correction(player_position)
	var nearest: Dictionary = _nearest_threat(visible_threats, player_position)
	var nearest_id: int = int(nearest.get("stable_id", 0))
	# 7. 全方位と目的別の追加候補を生成する。
	var candidates: Array[Dictionary] = _candidate_directions(
		objective,
		nearest,
		player_position,
		nearest_id,
		wall,
	)
	# 8. 各候補の接触時刻・接触時間・最大ダメージ・効用を評価する。
	var evaluated: Array[Dictionary] = []
	var safe_candidate_count: int = 0
	for candidate: Dictionary in candidates:
		var metrics: Dictionary = _evaluate_candidate(
			candidate,
			detailed_threats,
			density,
			objective,
			wall,
			player_position,
		)
		evaluated.append(metrics)
		if bool(metrics.get("safe", false)):
			safe_candidate_count += 1
	# 安全候補が一つもなければ、「最も被害を遅らせる候補」を選ぶモードへ切り替える。
	var use_fallback: bool = safe_candidate_count == 0
	var swarm_envelope_count: int = 0
	var boss_spoke_count: int = 0
	for threat: Dictionary in detailed_threats:
		var threat_kind: StringName = threat.get("kind", &"")
		if threat_kind == KIND_SWARM_ENVELOPE:
			swarm_envelope_count += 1
		elif threat_kind == KIND_BOSS_SPOKE:
			boss_spoke_count += 1
	# 9. 安全性を最優先した比較規則で、最終候補を一つに絞る。
	var best: Dictionary = {}
	for metrics: Dictionary in evaluated:
		if best.is_empty() or _candidate_is_better(metrics, best, use_fallback):
			best = metrics
	if best.is_empty():
		best = {
			"direction": Vector2.ZERO,
			"first_collision_tick": PREDICTION_HORIZON_TICKS + 1,
			"contact_tick_count": 0,
			"peak_damage": 0.0,
			"end_clearance": INF,
		}
	var selected_first_tick: int = int(best.get(
		"first_collision_tick",
		PREDICTION_HORIZON_TICKS + 1,
	))
	# 判断理由を後から検証できるよう、集計値を保存する。
	_last_avoidance_debug = {
		"visible_threat_count": visible_threats.size(),
		"detailed_threat_count": detailed_threats.size(),
		"regular_detailed_threat_count": (
			detailed_threats.size() - swarm_envelope_count - boss_spoke_count
		),
		"swarm_envelope_count": swarm_envelope_count,
		"boss_spoke_count": boss_spoke_count,
		"safe_candidate_count": safe_candidate_count,
		"candidate_count": candidates.size(),
		"selected_first_collision_tick": (
			-1 if selected_first_tick > PREDICTION_HORIZON_TICKS else selected_first_tick
		),
		"selected_contact_tick_count": int(best.get("contact_tick_count", 0)),
		"selected_peak_damage": float(best.get("peak_damage", 0.0)),
		"selected_end_clearance": float(best.get("end_clearance", INF)),
		"used_unavoidable_fallback": use_fallback,
	}
	return best.get("direction", Vector2.ZERO)


# 画面内に見えている敵・弾・攻撃予告を、共通の「脅威」辞書へ変換します。
# 戻り値の `visible` は密度計算用、`mandatory` は詳細評価から外せない脅威です。
func _collect_visible_threats(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> Dictionary:
	var current_tick: int = simulation.state.combat_tick
	# `visible`: 画面内の全脅威。方向密度や最寄り判定にも使う。
	# `mandatory`: 件数上限に関係なく、詳細判定へ必ず残す合成脅威。
	var visible: Array[Dictionary] = []
	var mandatory: Array[Dictionary] = []
	var visible_observation_keys: Dictionary[String, bool] = {}
	var swarm_members: Dictionary[int, Array] = {}
	var enemy_count: int = 0
	var projectile_count: int = 0
	var materializing_count: int = 0
	var telegraph_count: int = 0
	var boss_warning_count: int = 0
	var swarm_member_count: int = 0
	# 敵 ID を固定順で走査し、処理順による非決定性を避ける。
	for entity_id: int in simulation.enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.alive or enemy.definition == null:
			continue
		var radius: float = enemy.body_radius()
		if not _circle_intersects_view(player_position, enemy.position, radius):
			continue
		var observation_key: String = "enemy:%d:%d" % [enemy.entity_id, enemy.generation]
		visible_observation_keys[observation_key] = true
		# 直近位置から実測速度を推定し、履歴がない場合は定義上の速度を使う。
		var fallback_velocity: Vector2 = _known_enemy_velocity(enemy, player_position)
		var velocity: Vector2 = _observe_velocity(
			observation_key,
			enemy.position,
			current_tick,
			fallback_velocity,
		)
		# 出現演出中の敵は、実際に有効になる Tick まで非接触として扱う。
		var first_active_tick: int = maxi(1, enemy.activation_tick - current_tick)
		var kind: StringName = KIND_ENEMY
		if enemy.is_materializing(current_tick):
			kind = KIND_MATERIALIZING
			materializing_count += 1
		elif enemy.is_swarm_event:
			kind = KIND_SWARM_MEMBER
			swarm_member_count += 1
		else:
			enemy_count += 1
		var damage: float = _enemy_damage(simulation, enemy)
		var speed: float = fallback_velocity.length()
		var travel_seconds: float = -1.0
		if enemy.movement_kind == EnemyEntity.MovementKind.FIXED_DIRECTION:
			travel_seconds = (
				enemy.remaining_travel_distance / speed
				if speed > VECTOR_EPSILON
				else 0.0
			)
		# 敵固有の状態を、後段が共通処理できる脅威レコードへ正規化する。
		var threat: Dictionary = {
			"shape": SHAPE_CIRCLE,
			"kind": kind,
			"stable_key": observation_key,
			"stable_id": enemy.entity_id * 8,
			"position": enemy.position,
			"velocity": velocity,
			"fallback_velocity": fallback_velocity,
			"radius": radius,
			"damage": damage,
			"first_active_tick": first_active_tick,
			"travel_seconds": travel_seconds,
			"seek_player": enemy.movement_kind == EnemyEntity.MovementKind.SEEK_PLAYER,
			"stop_scale": (
				0.5 if enemy.enemy_type == GameTypes.EnemyType.BOSS else 0.0
			),
			"suppress_damage_during_full_stop": true,
			"mandatory": false,
		}
		visible.append(threat)
		# 群れ個体は密度には残し、詳細判定では後で一つの包絡矩形へまとめる。
		if enemy.is_swarm_event and not enemy.is_materializing(current_tick):
			if not swarm_members.has(enemy.swarm_group_id):
				swarm_members[enemy.swarm_group_id] = []
			var group_members: Array = swarm_members[enemy.swarm_group_id]
			group_members.append(threat)
		# 地面予告は静止円として扱い、表示中は常にダメージ領域とみなす。
		if enemy.telegraph_active:
			var telegraph_radius: float = maxf(0.0, enemy.definition.area_radius)
			if _circle_intersects_view(
				player_position,
				enemy.telegraph_position,
				telegraph_radius,
			):
				telegraph_count += 1
				visible.append({
					"shape": SHAPE_CIRCLE,
					"kind": KIND_TELEGRAPH,
					"stable_key": "telegraph:%d:%d" % [enemy.entity_id, enemy.generation],
					"stable_id": enemy.entity_id * 8 + 1,
					"position": enemy.telegraph_position,
					"velocity": Vector2.ZERO,
					"fallback_velocity": Vector2.ZERO,
					"radius": telegraph_radius,
					"damage": damage,
					"first_active_tick": 1,
					"travel_seconds": -1.0,
					"stop_scale": 1.0,
					"suppress_damage_during_full_stop": false,
					"mandatory": false,
				})
		# ボスのチャージ中は、将来発射される弾道も先回りして追加する。
		if enemy.enemy_type == GameTypes.EnemyType.BOSS and enemy.boss_charge_active:
			var warning_radius: float = maxf(2.4, radius * 1.6)
			if _circle_intersects_view(player_position, enemy.position, warning_radius):
				boss_warning_count += 1
				var spokes: Array[Dictionary] = _boss_warning_spokes(
					simulation,
					enemy,
					velocity,
				)
				for spoke: Dictionary in spokes:
					visible.append(spoke)
					mandatory.append(spoke)
	# 群れごとの包絡矩形を作り、詳細判定へ必須脅威として追加する。
	var group_ids: Array[int] = []
	for group_id: int in swarm_members:
		group_ids.append(group_id)
	group_ids.sort()
	for group_id: int in group_ids:
		var envelope: Dictionary = _swarm_envelope(group_id, swarm_members[group_id])
		if not envelope.is_empty():
			mandatory.append(envelope)
	# 敵弾も同じ脅威レコードへ変換する。寿命と残り移動距離の短い方を採用する。
	for pool_index: int in simulation.projectile_pool.active_indices_snapshot():
		var projectile: ProjectileState = simulation.projectile_pool.slots[pool_index]
		if (
			projectile == null
			or not projectile.active
			or projectile.faction != ProjectileState.FACTION_ENEMY
		):
			continue
		if not _circle_intersects_view(
			player_position,
			projectile.position,
			projectile.radius,
		):
			continue
		var observation_key: String = "projectile:%d:%d" % [
			pool_index,
			projectile.generation,
		]
		visible_observation_keys[observation_key] = true
		var fallback_velocity: Vector2 = projectile.velocity
		var velocity: Vector2 = _observe_velocity(
			observation_key,
			projectile.position,
			current_tick,
			fallback_velocity,
		)
		var speed: float = maxf(fallback_velocity.length(), velocity.length())
		var travel_seconds: float = maxf(0.0, projectile.remaining_lifetime)
		if speed > VECTOR_EPSILON:
			travel_seconds = minf(
				travel_seconds,
				maxf(0.0, projectile.remaining_distance) / speed,
			)
		projectile_count += 1
		visible.append({
			"shape": SHAPE_CIRCLE,
			"kind": KIND_PROJECTILE,
			"stable_key": observation_key,
			"stable_id": 1_000_000 + pool_index * 32 + projectile.generation,
			"position": projectile.position,
			"velocity": velocity,
			"fallback_velocity": fallback_velocity,
			"radius": projectile.radius,
			"damage": projectile.damage,
			"first_active_tick": 1,
			"travel_seconds": travel_seconds,
			"stop_scale": projectile.stop_time_scale,
			"suppress_damage_during_full_stop": true,
			"mandatory": false,
		})
	# 画面外へ消えた対象の速度履歴を削除し、古い観測の再利用を防ぐ。
	_prune_observations(visible_observation_keys)
	_last_threat_counts = {
		"enemy": enemy_count,
		"projectile": projectile_count,
		"materializing": materializing_count,
		"telegraph": telegraph_count,
		"boss_warning": boss_warning_count,
		"swarm_member": swarm_member_count,
	}
	return {"visible": visible, "mandatory": mandatory}


# 敵の定義と移動種別から、観測できない場合にも使える既知速度を求めます。
func _known_enemy_velocity(enemy: EnemyEntity, player_position: Vector2) -> Vector2:
	if enemy.definition == null:
		return Vector2.ZERO
	if enemy.movement_kind == EnemyEntity.MovementKind.FIXED_DIRECTION:
		return enemy.fixed_direction.normalized() * enemy.definition.move_speed
	var direction: Vector2 = player_position - enemy.position
	if direction.length_squared() <= VECTOR_EPSILON:
		return Vector2.from_angle(
			TAU * float(absi(enemy.entity_id) % HEADING_DIRECTION_COUNT)
			/ float(HEADING_DIRECTION_COUNT)
		) * enemy.definition.move_speed
	return direction.normalized() * enemy.definition.move_speed


# 前 Tick の位置との差から実測速度を求め、取得できなければ既知速度を使います。
# 実測方向は採用しつつ、既知の移動速度がある場合はその速さへ正規化します。
func _observe_velocity(
	observation_key: String,
	position: Vector2,
	current_tick: int,
	fallback_velocity: Vector2,
) -> Vector2:
	var result: Vector2 = fallback_velocity
	# 連続する Tick の観測だけを速度推定に使う。途中で見失った履歴は無効。
	if _observations.has(observation_key):
		var previous: Dictionary = _observations[observation_key]
		var previous_tick: int = int(previous.get("tick", -2))
		if previous_tick == current_tick - 1:
			var previous_position: Vector2 = previous.get("position", position)
			var measured: Vector2 = (
				(position - previous_position) * float(RunState.TICKS_PER_SECOND)
			)
			if measured.length_squared() > VECTOR_EPSILON:
				var known_speed: float = fallback_velocity.length()
				result = (
					measured.normalized() * known_speed
					if known_speed > VECTOR_EPSILON
					else measured
				)
	_observations[observation_key] = {"position": position, "tick": current_tick}
	return result


# 今回の画面内観測に存在しなかった対象を、速度推定用の履歴から削除します。
func _prune_observations(visible_keys: Dictionary[String, bool]) -> void:
	var forgotten: Array[String] = []
	for observation_key: String in _observations:
		if not visible_keys.has(observation_key):
			forgotten.append(observation_key)
	for observation_key: String in forgotten:
		_observations.erase(observation_key)


# 敵の接触ダメージを求めます。ボスには現在の激昂スタック補正も適用します。
func _enemy_damage(simulation: CombatSimulation, enemy: EnemyEntity) -> float:
	var damage: float = enemy.definition.contact_damage * enemy.damage_multiplier
	# ボスの激昂スタックは、コンテンツ定義に従って乗算する。
	if enemy.enemy_type == GameTypes.EnemyType.BOSS and simulation.catalog != null:
		var manifest: SurvivalContentManifest = simulation.catalog.manifest()
		if manifest != null:
			damage *= 1.0 + (
				manifest.boss_attack_bonus_per_stack
				* float(simulation.state.boss_enrage_stacks)
			)
	return damage


# ボスのチャージ攻撃から、将来発射される放射状の弾を仮想脅威として生成します。
# まだ実体化していない弾も先読みし、必ず詳細衝突判定へ含めます。
func _boss_warning_spokes(
	simulation: CombatSimulation,
	boss: EnemyEntity,
	boss_velocity: Vector2,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# 発射が予測期間外なら、この時点では回避候補へ影響させない。
	var fire_delay: int = _boss_fire_delay_ticks(simulation.state, boss)
	if fire_delay < 1 or fire_delay > PREDICTION_HORIZON_TICKS:
		return result
	# 発射時点までにボス自身が移動する分だけ、弾の起点を先へ進める。
	var origin: Vector2 = boss.position + boss_velocity * _scaled_future_seconds(
		simulation.state,
		fire_delay,
		0.5,
	)
	var spoke_count: int = maxi(1, boss.boss_charge_spoke_count)
	var angle_step: float = TAU / float(spoke_count)
	var angle_offset: float = angle_step * 0.5 if boss.boss_charge_half_step else 0.0
	var lifetime_seconds: float = (
		float(boss.definition.projectile_lifetime_ticks)
		/ float(RunState.TICKS_PER_SECOND)
	)
	var damage: float = boss.definition.projectile_damage * boss.damage_multiplier
	var manifest: SurvivalContentManifest = simulation.catalog.manifest()
	if manifest != null:
		damage *= 1.0 + (
			manifest.boss_attack_bonus_per_stack
			* float(simulation.state.boss_enrage_stacks)
		)
	# 全スポークを独立した円形弾として登録する。
	for spoke_index: int in range(spoke_count):
		var direction: Vector2 = Vector2.from_angle(
			angle_offset + angle_step * float(spoke_index)
		)
		result.append({
			"shape": SHAPE_CIRCLE,
			"kind": KIND_BOSS_SPOKE,
			"stable_key": "boss_spoke:%d:%d:%d" % [
				boss.entity_id,
				boss.generation,
				spoke_index,
			],
			"stable_id": 2_000_000 + boss.entity_id * 32 + spoke_index,
			"position": origin,
			"velocity": direction * boss.definition.projectile_speed,
			"fallback_velocity": direction * boss.definition.projectile_speed,
			"radius": boss.definition.projectile_radius,
			"damage": damage,
			"first_active_tick": fire_delay + 1,
			"travel_seconds": lifetime_seconds,
			"stop_scale": 0.5,
			"suppress_damage_during_full_stop": true,
			"mandatory": true,
		})
	return result


# 停止効果中の時間倍率を考慮し、ボスのチャージ完了までの Tick 数を予測します。
# 予測範囲内に発射されない場合は `-1` を返します。
func _boss_fire_delay_ticks(state: RunState, boss: EnemyEntity) -> int:
	var elapsed: float = boss.boss_charge_elapsed_ticks
	# 停止期間中はチャージ進行を 0.5 Tick 相当として積算する。
	for future_tick: int in range(1, PREDICTION_HORIZON_TICKS + 1):
		var absolute_tick: int = state.combat_tick + future_tick
		var time_scale: float = 0.5 if absolute_tick < state.stop_until_tick else 1.0
		elapsed += time_scale
		if elapsed + TIME_EPSILON >= float(CombatEnvelope.BOSS_CHARGE_TICKS):
			return future_tick
	return -1


# 将来 Tick までに実際に進むゲーム内時間を、停止中の倍率込みで秒へ変換します。
func _scaled_future_seconds(
	state: RunState,
	future_ticks: int,
	stop_scale: float,
) -> float:
	var scaled_ticks: float = 0.0
	# 各 Tick の時間倍率を積算し、単純な Tick 数ではなく有効経過時間を得る。
	for future_tick: int in range(1, future_ticks + 1):
		var absolute_tick: int = state.combat_tick + future_tick
		scaled_ticks += stop_scale if absolute_tick < state.stop_until_tick else 1.0
	return scaled_ticks / float(RunState.TICKS_PER_SECOND)


# 同じ群れに属する敵を、進行方向に沿った一つの矩形包絡へまとめます。
# 個体数が多い群れを一体ずつ評価せず、すり抜け困難な面として扱うための近似です。
func _swarm_envelope(group_id: int, members: Array) -> Dictionary:
	if members.is_empty():
		return {}
	var first: Dictionary = members[0]
	var velocity: Vector2 = first.get("fallback_velocity", Vector2.ZERO)
	# 群れの進行方向をローカル X、直交方向をローカル Y として扱う。
	var forward: Vector2 = velocity.normalized()
	if forward.length_squared() <= VECTOR_EPSILON:
		forward = Vector2.RIGHT
	var side: Vector2 = Vector2(-forward.y, forward.x)
	var min_forward: float = INF
	var max_forward: float = -INF
	var min_side: float = INF
	var max_side: float = -INF
	var maximum_damage: float = 0.0
	var maximum_travel_seconds: float = 0.0
	var minimum_id: int = 2_100_000 + group_id
	# 各個体の半径を含めた最小・最大射影から、向き付き矩形の範囲を求める。
	for member_value: Variant in members:
		var member: Dictionary = member_value
		var position: Vector2 = member.get("position", Vector2.ZERO)
		var radius: float = float(member.get("radius", 0.0))
		var forward_value: float = position.dot(forward)
		var side_value: float = position.dot(side)
		min_forward = minf(min_forward, forward_value - radius)
		max_forward = maxf(max_forward, forward_value + radius)
		min_side = minf(min_side, side_value - radius)
		max_side = maxf(max_side, side_value + radius)
		maximum_damage = maxf(maximum_damage, float(member.get("damage", 0.0)))
		maximum_travel_seconds = maxf(
			maximum_travel_seconds,
			float(member.get("travel_seconds", 0.0)),
		)
		minimum_id = mini(minimum_id, int(member.get("stable_id", minimum_id)))
	# ローカル範囲の中央をワールド座標へ戻す。
	var center: Vector2 = (
		forward * (min_forward + max_forward) * 0.5
		+ side * (min_side + max_side) * 0.5
	)
	return {
		"shape": SHAPE_SWARM_ENVELOPE,
		"kind": KIND_SWARM_ENVELOPE,
		"stable_key": "swarm_envelope:%d" % group_id,
		"stable_id": minimum_id,
		"position": center,
		"motion_position": Vector2.ZERO,
		"velocity": velocity,
		"fallback_velocity": velocity,
		"radius": 0.0,
		"damage": maximum_damage,
		"first_active_tick": 1,
		"travel_seconds": maximum_travel_seconds,
		"stop_scale": 0.0,
		"suppress_damage_during_full_stop": true,
		"mandatory": true,
		"forward": forward,
		"side": side,
		"min_forward": min_forward,
		"max_forward": max_forward,
		"min_side": min_side,
		"max_side": max_side,
	}


# 高コストな詳細衝突判定へ渡す脅威を絞り込みます。
# 各方向の代表を残したうえで、接触予想時間が短い順に上限まで採用します。
func _select_detailed_threats(
	visible: Array[Dictionary],
	mandatory: Array[Dictionary],
	player_position: Vector2,
) -> Array[Dictionary]:
	# 群れ個体と必須脅威を除き、通常脅威だけを TTC 順に並べる。
	var regular: Array[Dictionary] = []
	for threat: Dictionary in visible:
		if bool(threat.get("mandatory", false)):
			continue
		if threat.get("kind", &"") == KIND_SWARM_MEMBER:
			continue
		var ranked: Dictionary = threat.duplicate()
		ranked["estimated_ttc"] = _estimated_threat_ttc(threat, player_position)
		regular.append(ranked)
	regular.sort_custom(_threat_priority_less)
	var selected: Array[Dictionary] = []
	var selected_keys: Dictionary[String, bool] = {}
	# まず各角度セクターで最優先の一件を確保し、片側だけを見る偏りを防ぐ。
	var sector_best: Dictionary[int, Dictionary] = {}
	# TTC 順の先頭、つまり各セクターで最も早く接触し得る脅威を代表にする。
	for threat: Dictionary in regular:
		var sector: int = _sector_for_offset(
			threat.get("position", player_position) - player_position,
		)
		if not sector_best.has(sector):
			sector_best[sector] = threat
	for sector: int in range(DENSITY_SECTOR_COUNT):
		if not sector_best.has(sector):
			continue
		var representative: Dictionary = sector_best[sector]
		var key: String = str(representative.get("stable_key", ""))
		selected.append(representative)
		selected_keys[key] = true
	# 残り枠を TTC 順で埋める。同じ脅威は再追加しない。
	for threat: Dictionary in regular:
		if selected.size() >= DETAIL_THREAT_LIMIT:
			break
		var key: String = str(threat.get("stable_key", ""))
		if selected_keys.has(key):
			continue
		selected.append(threat)
		selected_keys[key] = true
	# ボスの予告弾と群れ包絡は、上限を超えても必ず追加する。
	for threat: Dictionary in mandatory:
		var key: String = str(threat.get("stable_key", ""))
		if selected_keys.has(key):
			continue
		selected.append(threat)
		selected_keys[key] = true
	return selected


# プレイヤーと脅威が最速で接近すると仮定し、概算の接触予想 Tick を求めます。
# これは優先順位付け用の粗い値であり、実際の接触判定は後段で厳密に行います。
func _estimated_threat_ttc(threat: Dictionary, player_position: Vector2) -> float:
	var radius: float = float(threat.get("radius", 0.0))
	var clearance: float = maxf(
		0.0,
		player_position.distance_to(threat.get("position", player_position))
		- PLAYER_RADIUS
		- radius
		- SAFETY_MARGIN,
	)
	var velocity: Vector2 = threat.get("fallback_velocity", Vector2.ZERO)
	# 双方が互いへ最速接近する上限速度を使い、危険を過小評価しない。
	var closing_speed: float = PLAYER_SPEED + velocity.length()
	var active_delay: int = maxi(0, int(threat.get("first_active_tick", 1)) - 1)
	return (
		float(active_delay)
		+ clearance / maxf(0.001, closing_speed) * float(RunState.TICKS_PER_SECOND)
	)


# 脅威を接触予想時間の昇順で比較し、同値なら安定 ID で順序を確定します。
func _threat_priority_less(left: Dictionary, right: Dictionary) -> bool:
	var left_ttc: float = float(left.get("estimated_ttc", INF))
	var right_ttc: float = float(right.get("estimated_ttc", INF))
	if not is_equal_approx(left_ttc, right_ttc):
		return left_ttc < right_ttc
	return _stable_id_wins(
		int(left.get("stable_id", 0)),
		int(right.get("stable_id", 0)),
	)


#endregion

#region 移動経路の予測と候補評価

# 各脅威へ、予測期間中の区分線形な移動経路 `motion_segments` を付加します。
func _prepare_threat_paths(threats: Array[Dictionary], state: RunState) -> void:
	for threat: Dictionary in threats:
		threat["motion_segments"] = _threat_motion_segments(threat, state)


# 脅威の発生待ち・停止効果・寿命を考慮し、時間区間ごとの位置と速度を作ります。
# 各区間は一定速度なので、後段の衝突判定を解析的に計算できます。
func _threat_motion_segments(threat: Dictionary, state: RunState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# 脅威がダメージ判定を持ち始める時刻。
	var first_active_tick: int = maxi(1, int(threat.get("first_active_tick", 1)))
	var active_start: float = (
		float(first_active_tick - 1) / float(RunState.TICKS_PER_SECOND)
	)
	# 現在の停止効果が予測開始から何秒続くかを求める。
	var stop_end: float = maxf(
		0.0,
		float(state.stop_until_tick - state.combat_tick - 1)
		/ float(RunState.TICKS_PER_SECOND),
	)
	# 速度や有効状態が変わる時刻で経路を分割する。
	var breakpoints: Array[float] = [0.0, PREDICTION_SECONDS]
	_append_time_breakpoint(breakpoints, active_start)
	_append_time_breakpoint(breakpoints, stop_end)
	breakpoints.sort()
	var position: Vector2 = threat.get(
		"motion_position",
		threat.get("position", Vector2.ZERO),
	)
	# 実測速度がほぼ 0 の場合は、定義から求めた既知速度へ戻す。
	var base_velocity: Vector2 = threat.get("velocity", Vector2.ZERO)
	if base_velocity.length_squared() <= VECTOR_EPSILON:
		base_velocity = threat.get("fallback_velocity", Vector2.ZERO)
	var stop_scale: float = clampf(float(threat.get("stop_scale", 0.0)), 0.0, 1.0)
	# `-1` は無期限。それ以外は寿命または残り移動距離に相当する有効時間。
	var remaining_scaled_seconds: float = float(threat.get("travel_seconds", -1.0))
	var suppress_during_stop: bool = bool(
		threat.get("suppress_damage_during_full_stop", true)
	)
	# 各区間で速度・ダメージ有効性を固定し、区分線形経路として保存する。
	for index: int in range(breakpoints.size() - 1):
		var segment_start: float = breakpoints[index]
		var segment_end: float = breakpoints[index + 1]
		if segment_end <= segment_start + TIME_EPSILON:
			continue
		var midpoint: float = (segment_start + segment_end) * 0.5
		var active: bool = midpoint + TIME_EPSILON >= active_start
		var scale: float = stop_scale if midpoint < stop_end - TIME_EPSILON else 1.0
		var velocity: Vector2 = base_velocity * scale if active else Vector2.ZERO
		var damaging: bool = active and (not suppress_during_stop or scale > TIME_EPSILON)
		var resolved_end: float = segment_end
		if active and remaining_scaled_seconds >= 0.0:
			if remaining_scaled_seconds <= TIME_EPSILON:
				break
			if scale > TIME_EPSILON:
				resolved_end = minf(
					segment_end,
					segment_start + remaining_scaled_seconds / scale,
				)
		if resolved_end > segment_start + TIME_EPSILON:
			result.append({
				"start": segment_start,
				"end": resolved_end,
				"position": position,
				"velocity": velocity,
				"damaging": damaging,
			})
			var duration: float = resolved_end - segment_start
			position += velocity * duration
			if active and remaining_scaled_seconds >= 0.0:
				remaining_scaled_seconds = maxf(
					0.0,
					remaining_scaled_seconds - scale * duration,
				)
		if resolved_end < segment_end - TIME_EPSILON:
			break
	return result


# 予測範囲内の有効な時刻だけを、重複なしで区切り時刻へ追加します。
func _append_time_breakpoint(values: Array[float], value: float) -> void:
	if value <= TIME_EPSILON or value >= PREDICTION_SECONDS - TIME_EPSILON:
		return
	for existing: float in values:
		if is_equal_approx(existing, value):
			return
	values.append(value)


# 画面内の脅威を角度セクターへ集約し、各方向の「混雑度」を計算します。
# 近い・高ダメージ・すぐ有効になる脅威ほど重く評価します。
func _build_directional_density(
	threats: Array[Dictionary],
	player_position: Vector2,
) -> PackedFloat32Array:
	var density := PackedFloat32Array()
	density.resize(DENSITY_SECTOR_COUNT)
	density.fill(0.0)
	# 脅威の中心方向に重みを加え、隣接セクターにも半分をにじませる。
	for threat: Dictionary in threats:
		var position: Vector2 = threat.get("position", player_position)
		var offset: Vector2 = position - player_position
		if offset.length_squared() <= VECTOR_EPSILON:
			continue
		var radius: float = float(threat.get("radius", 0.0))
		var clearance: float = maxf(
			0.05,
			offset.length() - PLAYER_RADIUS - radius - SAFETY_MARGIN,
		)
		var damage_scale: float = 1.0 + minf(4.0, float(threat.get("damage", 0.0)) * 0.05)
		var delay_scale: float = 1.0 / float(maxi(1, int(threat.get("first_active_tick", 1))))
		var weight: float = damage_scale * (1.0 / clearance + delay_scale)
		var sector: int = _sector_for_offset(offset)
		density[sector] += weight
		density[wrapi(sector - 1, 0, DENSITY_SECTOR_COUNT)] += weight * 0.5
		density[wrapi(sector + 1, 0, DENSITY_SECTOR_COUNT)] += weight * 0.5
	return density


# 原点からの方向ベクトルを、0 以上 `DENSITY_SECTOR_COUNT` 未満の区画へ変換します。
func _sector_for_offset(offset: Vector2) -> int:
	if offset.length_squared() <= VECTOR_EPSILON:
		return 0
	var normalized_angle: float = fposmod(offset.angle(), TAU)
	return wrapi(
		floori(
			(normalized_angle + TAU / float(DENSITY_SECTOR_COUNT * 2))
			/ TAU
			* float(DENSITY_SECTOR_COUNT)
		),
		0,
		DENSITY_SECTOR_COUNT,
	)


# プレイヤーに最も近い脅威を返します。同距離なら安定 ID で決定します。
func _nearest_threat(
	threats: Array[Dictionary],
	player_position: Vector2,
) -> Dictionary:
	var nearest: Dictionary = {}
	var best_distance_squared: float = INF
	for threat: Dictionary in threats:
		var position: Vector2 = threat.get("position", player_position)
		var distance_squared: float = position.distance_squared_to(player_position)
		if (
			distance_squared < best_distance_squared - SCORE_EPSILON
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and (
					nearest.is_empty()
					or _stable_id_wins(
						int(threat.get("stable_id", 0)),
						int(nearest.get("stable_id", 0)),
					)
				)
			)
		):
			nearest = threat
			best_distance_squared = distance_squared
	return nearest


# 評価対象となる移動方向を、決定論的な順序で生成します。
# 全方位に加え、停止・前回入力・目的地方向・最寄り脅威への接線も候補にします。
func _candidate_directions(
	objective: Vector2,
	nearest: Dictionary,
	player_position: Vector2,
	nearest_id: int,
	wall: Vector2,
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	# シード由来のオフセットと最寄り脅威 ID から、全方位走査の開始点を決める。
	var start_index: int = wrapi(
		_direction_offset + absi(nearest_id),
		0,
		HEADING_DIRECTION_COUNT,
	)
	var step: int = 1 if _prefer_lower_id else -1
	# 均等分割した全方向を、固定された昇順または降順で追加する。
	for offset: int in range(HEADING_DIRECTION_COUNT):
		var direction_index: int = wrapi(
			start_index + offset * step,
			0,
			HEADING_DIRECTION_COUNT,
		)
		_append_candidate(candidates, _enforce_wall_inward(Vector2.from_angle(
			TAU * float(direction_index) / float(HEADING_DIRECTION_COUNT)
		), wall))
	# 特殊候補: 停止、現在方向の維持、取得目標への直進。
	_append_candidate(candidates, _enforce_wall_inward(Vector2.ZERO, wall))
	_append_candidate(candidates, _enforce_wall_inward(_held_input, wall))
	_append_candidate(candidates, _enforce_wall_inward(objective, wall))
	# 最寄り脅威から離れる法線だけでなく、左右へ回り込む接線も追加する。
	if not nearest.is_empty():
		var threat_position: Vector2 = nearest.get("position", player_position)
		var away: Vector2 = player_position - threat_position
		if away.length_squared() > VECTOR_EPSILON:
			away = away.normalized()
			var left_tangent: Vector2 = Vector2(-away.y, away.x)
			if _handedness < 0.0:
				_append_candidate(candidates, _enforce_wall_inward(-left_tangent, wall))
				_append_candidate(candidates, _enforce_wall_inward(left_tangent, wall))
			else:
				_append_candidate(candidates, _enforce_wall_inward(left_tangent, wall))
				_append_candidate(candidates, _enforce_wall_inward(-left_tangent, wall))
	return candidates


# 候補方向を正規化して追加します。ほぼ同じ向きの候補は重複として除外します。
func _append_candidate(candidates: Array[Dictionary], direction: Vector2) -> void:
	var resolved: Vector2 = (
		Vector2.ZERO
		if direction.length_squared() <= VECTOR_EPSILON
		else direction.normalized()
	)
	# 内積がほぼ 1 なら同方向とみなし、評価回数を増やさない。
	for candidate: Dictionary in candidates:
		var existing: Vector2 = candidate.get("direction", Vector2.ZERO)
		if resolved == Vector2.ZERO and existing == Vector2.ZERO:
			return
		if (
			resolved != Vector2.ZERO
			and existing != Vector2.ZERO
			and resolved.dot(existing) >= 0.999999
		):
			return
	candidates.append({"direction": resolved, "stable_rank": candidates.size()})


# 一つの移動候補について、予測期間内の接触と行動効用を評価します。
# 安全性の指標と目的地・壁・入力継続性などのスコアを辞書で返します。
func _evaluate_candidate(
	candidate: Dictionary,
	threats: Array[Dictionary],
	density: PackedFloat32Array,
	objective: Vector2,
	wall: Vector2,
	player_position: Vector2,
) -> Dictionary:
	var direction: Vector2 = candidate.get("direction", Vector2.ZERO)
	# 候補方向へ進んだときの、壁で折れるプレイヤー経路を作る。
	var player_segments: Array[Dictionary] = _player_motion_segments(
		player_position,
		direction,
	)
	# 各 Tick に「何かと接触するか」と「最大想定ダメージ」を集約する。
	# 同時に複数へ触れても、ここでは最大値だけをリスク指標として残す。
	var contact_ticks := PackedByteArray()
	contact_ticks.resize(PREDICTION_HORIZON_TICKS + 1)
	contact_ticks.fill(0)
	var damage_by_tick := PackedFloat32Array()
	damage_by_tick.resize(PREDICTION_HORIZON_TICKS + 1)
	damage_by_tick.fill(0.0)
	var end_clearance: float = INF
	# 全詳細脅威との連続時間上の接触区間を Tick 配列へ反映する。
	for threat: Dictionary in threats:
		var contact: Dictionary = _evaluate_threat_contact(player_segments, threat)
		end_clearance = minf(
			end_clearance,
			float(contact.get("end_clearance", INF)),
		)
		var damage: float = float(threat.get("damage", 0.0))
		var ranges: Array[Vector2i] = contact.get("tick_ranges", [])
		for tick_range: Vector2i in ranges:
			for tick: int in range(tick_range.x, tick_range.y + 1):
				contact_ticks[tick] = 1
				damage_by_tick[tick] = maxf(damage_by_tick[tick], damage)
	# Tick 配列を走査し、比較に使う衝突統計へ要約する。
	var first_collision_tick: int = PREDICTION_HORIZON_TICKS + 1
	var contact_tick_count: int = 0
	var peak_damage: float = 0.0
	for tick: int in range(1, PREDICTION_HORIZON_TICKS + 1):
		if contact_ticks[tick] == 0:
			continue
		if first_collision_tick > PREDICTION_HORIZON_TICKS:
			first_collision_tick = tick
		contact_tick_count += 1
		peak_damage = maxf(peak_damage, damage_by_tick[tick])
	var density_penalty: float = 0.0
	if direction.length_squared() > VECTOR_EPSILON:
		var sector: int = _sector_for_offset(direction)
		density_penalty = density[sector]
	var clearance_bonus: float = (
		0.0 if is_inf(end_clearance) else minf(8.0, end_clearance) * END_CLEARANCE_WEIGHT
	)
	# 安全候補同士では、目的地・壁回避・入力継続・混雑度・終端余裕を合成する。
	var utility: float = (
		direction.dot(objective) * OBJECTIVE_WEIGHT_BY_POLICY[policy]
		+ direction.dot(wall) * WALL_WEIGHT
		+ direction.dot(_held_input) * CONTINUITY_WEIGHT
		- density_penalty * DENSITY_WEIGHT
		+ clearance_bonus
	)
	return {
		"direction": direction,
		"stable_rank": int(candidate.get("stable_rank", 0)),
		"safe": contact_tick_count == 0,
		"first_collision_tick": first_collision_tick,
		"contact_tick_count": contact_tick_count,
		"peak_damage": peak_damage,
		"end_clearance": end_clearance,
		"utility": utility,
	}


# 二つの移動評価を比較し、`candidate` を採用すべきなら `true` を返します。
# 安全性を最優先し、不可避時は衝突の遅さ・短さ・低ダメージの順で比較します。
func _candidate_is_better(
	candidate: Dictionary,
	incumbent: Dictionary,
	use_fallback: bool,
) -> bool:
	var candidate_safe: bool = bool(candidate.get("safe", false))
	var incumbent_safe: bool = bool(incumbent.get("safe", false))
	# 一方だけ安全なら、他のスコアに関係なく安全側を採用する。
	if candidate_safe != incumbent_safe:
		return candidate_safe
	# 衝突不可避時は「遅い → 短い → 低ダメージ → 終端で遠い」の順。
	if use_fallback or not candidate_safe:
		var candidate_first: int = int(candidate.get("first_collision_tick", 0))
		var incumbent_first: int = int(incumbent.get("first_collision_tick", 0))
		if candidate_first != incumbent_first:
			return candidate_first > incumbent_first
		var candidate_contacts: int = int(candidate.get("contact_tick_count", 0))
		var incumbent_contacts: int = int(incumbent.get("contact_tick_count", 0))
		if candidate_contacts != incumbent_contacts:
			return candidate_contacts < incumbent_contacts
		var candidate_damage: float = float(candidate.get("peak_damage", 0.0))
		var incumbent_damage: float = float(incumbent.get("peak_damage", 0.0))
		if not is_equal_approx(candidate_damage, incumbent_damage):
			return candidate_damage < incumbent_damage
		var candidate_clearance: float = float(candidate.get("end_clearance", -INF))
		var incumbent_clearance: float = float(incumbent.get("end_clearance", -INF))
		if not is_equal_approx(candidate_clearance, incumbent_clearance):
			return candidate_clearance > incumbent_clearance
	# リスク指標が同等なら、通常の行動効用で比較する。
	var candidate_utility: float = float(candidate.get("utility", -INF))
	var incumbent_utility: float = float(incumbent.get("utility", -INF))
	if candidate_utility > incumbent_utility + SCORE_EPSILON:
		return true
	if candidate_utility < incumbent_utility - SCORE_EPSILON:
		return false
	return int(candidate.get("stable_rank", 0)) < int(incumbent.get("stable_rank", 0))


#endregion

#region 衝突判定と幾何計算

# 指定方向へ移動した場合のプレイヤー経路を、壁到達時刻で分割して作ります。
# 壁へ到達した軸だけ速度を 0 にし、もう一方の軸は移動を続けます。
func _player_motion_segments(
	player_position: Vector2,
	direction: Vector2,
) -> Array[Dictionary]:
	var velocity: Vector2 = direction.limit_length(1.0) * PLAYER_SPEED
	# X/Y それぞれについて、アリーナ境界へ到達する時刻を求める。
	var x_stop: float = _axis_stop_time(
		player_position.x,
		velocity.x,
		CombatSimulation.ARENA_MIN.x,
		CombatSimulation.ARENA_MAX.x,
	)
	var y_stop: float = _axis_stop_time(
		player_position.y,
		velocity.y,
		CombatSimulation.ARENA_MIN.y,
		CombatSimulation.ARENA_MAX.y,
	)
	# どちらかの軸が停止する時刻で、経路を区分する。
	var breakpoints: Array[float] = [0.0, PREDICTION_SECONDS]
	_append_time_breakpoint(breakpoints, x_stop)
	_append_time_breakpoint(breakpoints, y_stop)
	breakpoints.sort()
	var result: Array[Dictionary] = []
	for index: int in range(breakpoints.size() - 1):
		var segment_start: float = breakpoints[index]
		var segment_end: float = breakpoints[index + 1]
		var segment_position := Vector2(
			clampf(
				player_position.x + velocity.x * minf(segment_start, x_stop),
				CombatSimulation.ARENA_MIN.x,
				CombatSimulation.ARENA_MAX.x,
			),
			clampf(
				player_position.y + velocity.y * minf(segment_start, y_stop),
				CombatSimulation.ARENA_MIN.y,
				CombatSimulation.ARENA_MAX.y,
			),
		)
		var segment_velocity := Vector2(
			velocity.x if segment_start < x_stop - TIME_EPSILON else 0.0,
			velocity.y if segment_start < y_stop - TIME_EPSILON else 0.0,
		)
		result.append({
			"start": segment_start,
			"end": segment_end,
			"position": segment_position,
			"velocity": segment_velocity,
		})
	return result


# 一つの軸について、現在値から境界へ到達するまでの秒数を求めます。
func _axis_stop_time(value: float, velocity: float, minimum: float, maximum: float) -> float:
	if absf(velocity) <= VECTOR_EPSILON:
		return PREDICTION_SECONDS
	var target: float = maximum if velocity > 0.0 else minimum
	return clampf((target - value) / velocity, 0.0, PREDICTION_SECONDS)


# プレイヤー経路と一つの脅威経路の接触区間を求めます。
# 追尾敵だけは進行方向が変化するため、専用の近似処理へ分岐します。
func _evaluate_threat_contact(
	player_segments: Array[Dictionary],
	threat: Dictionary,
) -> Dictionary:
	var threat_segments: Array[Dictionary] = threat.get("motion_segments", [])
	# 追尾敵は速度方向が一定でないため、区間ごとに向きを更新する。
	if bool(threat.get("seek_player", false)):
		return _evaluate_seek_contact(player_segments, threat, threat_segments)
	var intervals: Array[Vector2] = []
	# プレイヤー区間と脅威区間が時間的に重なる組み合わせだけを判定する。
	for player_segment: Dictionary in player_segments:
		for threat_segment: Dictionary in threat_segments:
			if not bool(threat_segment.get("damaging", false)):
				continue
			var overlap_start: float = maxf(
				float(player_segment.get("start", 0.0)),
				float(threat_segment.get("start", 0.0)),
			)
			var overlap_end: float = minf(
				float(player_segment.get("end", 0.0)),
				float(threat_segment.get("end", 0.0)),
			)
			if overlap_end < overlap_start + TIME_EPSILON:
				continue
			var local_interval: Vector2
			if threat.get("shape", SHAPE_CIRCLE) == SHAPE_SWARM_ENVELOPE:
				local_interval = _swarm_contact_interval(
					player_segment,
					threat_segment,
					threat,
					overlap_start,
					overlap_end,
				)
			else:
				local_interval = _circle_contact_interval_for_segments(
					player_segment,
					threat_segment,
					float(threat.get("radius", 0.0)),
					overlap_start,
					overlap_end,
				)
			if local_interval.x >= 0.0:
				intervals.append(local_interval)
	return {
		"tick_ranges": _intervals_to_tick_ranges(intervals),
		"end_clearance": _threat_end_clearance(player_segments, threat, threat_segments),
	}


# プレイヤーを追尾する敵との接触を、短い区間ごとに追尾方向を更新して予測します。
# 完全な連続追尾ではなく、一定間隔で再計算する決定論的な近似です。
func _evaluate_seek_contact(
	player_segments: Array[Dictionary],
	threat: Dictionary,
	threat_segments: Array[Dictionary],
) -> Dictionary:
	var breakpoints: Array[float] = [0.0, PREDICTION_SECONDS]
	for player_segment: Dictionary in player_segments:
		_append_time_breakpoint(
			breakpoints,
			float(player_segment.get("start", 0.0)),
		)
		_append_time_breakpoint(
			breakpoints,
			float(player_segment.get("end", PREDICTION_SECONDS)),
		)
	for threat_segment: Dictionary in threat_segments:
		_append_time_breakpoint(
			breakpoints,
			float(threat_segment.get("start", 0.0)),
		)
		_append_time_breakpoint(
			breakpoints,
			float(threat_segment.get("end", PREDICTION_SECONDS)),
		)
	# 長い一定速度近似にならないよう、一定 Tick ごとにも区間を分割する。
	for prediction_tick: int in range(
		SEEK_RECURSION_STEP_TICKS,
		PREDICTION_HORIZON_TICKS,
		SEEK_RECURSION_STEP_TICKS,
	):
		_append_time_breakpoint(
			breakpoints,
			float(prediction_tick) * SECONDS_PER_TICK,
		)
	breakpoints.sort()
	var intervals: Array[Vector2] = []
	var enemy_position: Vector2 = threat.get("position", Vector2.ZERO)
	var safety_radius: float = (
		PLAYER_RADIUS + float(threat.get("radius", 0.0)) + SAFETY_MARGIN
	)
	var body_contact_radius: float = (
		PLAYER_RADIUS + float(threat.get("radius", 0.0))
	)
	var path_exists_at_horizon: bool = false
	# 各区間の開始時点で敵からプレイヤーへの方向を再計算する。
	for index: int in range(breakpoints.size() - 1):
		var segment_start: float = breakpoints[index]
		var segment_end: float = breakpoints[index + 1]
		if segment_end <= segment_start + TIME_EPSILON:
			continue
		var midpoint: float = (segment_start + segment_end) * 0.5
		var player_segment: Dictionary = _segment_covering(player_segments, midpoint)
		var threat_segment: Dictionary = _segment_covering(threat_segments, midpoint)
		if player_segment.is_empty() or threat_segment.is_empty():
			continue
		if segment_end >= PREDICTION_SECONDS - TIME_EPSILON:
			path_exists_at_horizon = true
		var duration: float = segment_end - segment_start
		var player_position: Vector2 = _segment_position_at(player_segment, segment_start)
		var player_velocity: Vector2 = player_segment.get("velocity", Vector2.ZERO)
		if not bool(threat_segment.get("damaging", false)):
			enemy_position += threat_segment.get("velocity", Vector2.ZERO) * duration
			continue
		var offset: Vector2 = player_position - enemy_position
		var distance: float = offset.length()
		var away: Vector2 = (
			offset / distance
			if distance > VECTOR_EPSILON
			else Vector2.from_angle(
				TAU * float(absi(int(threat.get("stable_id", 0))) % HEADING_DIRECTION_COUNT)
				/ float(HEADING_DIRECTION_COUNT)
			)
		)
		var enemy_speed: float = (
			threat_segment.get("velocity", Vector2.ZERO) as Vector2
		).length()
		var enemy_velocity: Vector2 = away * enemy_speed
		var local_interval: Vector2 = _circle_contact_interval(
			enemy_position - player_position,
			enemy_velocity - player_velocity,
			safety_radius,
			duration,
		)
		if local_interval.x >= 0.0:
			intervals.append(Vector2(
				segment_start + local_interval.x,
				segment_start + local_interval.y,
			))
		var player_end_position: Vector2 = _segment_position_at(
			player_segment,
			segment_end,
		)
		# 敵中心がプレイヤー本体へ食い込む距離まで進めないよう移動量を制限する。
		var maximum_travel: float = maxf(
			0.0,
			player_end_position.distance_to(enemy_position) - body_contact_radius,
		)
		enemy_position += away * minf(enemy_speed * duration, maximum_travel)
	var end_clearance: float = INF
	if path_exists_at_horizon and not player_segments.is_empty():
		var final_player_position: Vector2 = _segment_position_at(
			player_segments[player_segments.size() - 1],
			PREDICTION_SECONDS,
		)
		end_clearance = final_player_position.distance_to(enemy_position) - safety_radius
	return {
		"tick_ranges": _intervals_to_tick_ranges(intervals),
		"end_clearance": end_clearance,
	}


# 指定時刻を含む移動区間を返します。該当しなければ空の辞書を返します。
func _segment_covering(segments: Array[Dictionary], time_seconds: float) -> Dictionary:
	for segment: Dictionary in segments:
		if (
			time_seconds >= float(segment.get("start", 0.0)) - TIME_EPSILON
			and time_seconds <= float(segment.get("end", 0.0)) + TIME_EPSILON
		):
			return segment
	return {}


# 秒単位の接触区間を統合し、シミュレーションで使う Tick 範囲へ変換します。
func _intervals_to_tick_ranges(intervals: Array[Vector2]) -> Array[Vector2i]:
	# 重複区間を先に統合し、同じ Tick を何度も数えない。
	var merged: Array[Vector2] = _merge_intervals(intervals)
	var tick_ranges: Array[Vector2i] = []
	for interval: Vector2 in merged:
		var start_tick: int = maxi(
			1,
			ceili(interval.x * float(RunState.TICKS_PER_SECOND) - TIME_EPSILON),
		)
		var end_tick: int = mini(
			PREDICTION_HORIZON_TICKS,
			ceili(interval.y * float(RunState.TICKS_PER_SECOND) - TIME_EPSILON),
		)
		if end_tick >= start_tick:
			tick_ranges.append(Vector2i(start_tick, end_tick))
	return tick_ranges


# 二つの等速移動区間について、円同士が安全半径内へ入る時刻区間を求めます。
func _circle_contact_interval_for_segments(
	player_segment: Dictionary,
	threat_segment: Dictionary,
	threat_radius: float,
	overlap_start: float,
	overlap_end: float,
) -> Vector2:
	var player_position: Vector2 = _segment_position_at(player_segment, overlap_start)
	var threat_position: Vector2 = _segment_position_at(threat_segment, overlap_start)
	var relative_position: Vector2 = threat_position - player_position
	var relative_velocity: Vector2 = (
		threat_segment.get("velocity", Vector2.ZERO)
		- player_segment.get("velocity", Vector2.ZERO)
	)
	var radius: float = PLAYER_RADIUS + threat_radius + SAFETY_MARGIN
	var local: Vector2 = _circle_contact_interval(
		relative_position,
		relative_velocity,
		radius,
		overlap_end - overlap_start,
	)
	if local.x < 0.0:
		return local
	return Vector2(overlap_start + local.x, overlap_start + local.y)


# 相対位置と相対速度から、移動点が円内に存在する時間区間を二次方程式で求めます。
# 接触しない場合は `Vector2(-1, -1)` を返します。
func _circle_contact_interval(
	relative_position: Vector2,
	relative_velocity: Vector2,
	radius: float,
	duration: float,
) -> Vector2:
	# |p + vt|² = r² を `a t² + b t + c = 0` として解く。
	var c: float = relative_position.length_squared() - radius * radius
	var a: float = relative_velocity.length_squared()
	# 相対速度がない場合は、開始時点で円内かどうかだけで決まる。
	if a <= VECTOR_EPSILON:
		return Vector2(0.0, duration) if c <= 0.0 else Vector2(-1.0, -1.0)
	var b: float = 2.0 * relative_position.dot(relative_velocity)
	# 判別式が負なら、軌道は円と交差しない。
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return Vector2(-1.0, -1.0)
	var root: float = sqrt(maxf(0.0, discriminant))
	var entry: float = (-b - root) / (2.0 * a)
	var exit_time: float = (-b + root) / (2.0 * a)
	if c <= 0.0:
		entry = 0.0
	var clipped_entry: float = maxf(0.0, entry)
	var clipped_exit: float = minf(duration, exit_time)
	if clipped_exit < clipped_entry - TIME_EPSILON:
		return Vector2(-1.0, -1.0)
	return Vector2(clipped_entry, maxf(clipped_entry, clipped_exit))


# 群れの矩形包絡とプレイヤー円の接触区間を求めます。
# プレイヤー半径分だけ矩形を拡張し、点と矩形の交差問題へ置き換えます。
func _swarm_contact_interval(
	player_segment: Dictionary,
	threat_segment: Dictionary,
	threat: Dictionary,
	overlap_start: float,
	overlap_end: float,
) -> Vector2:
	var player_position: Vector2 = _segment_position_at(player_segment, overlap_start)
	var envelope_translation: Vector2 = _segment_position_at(threat_segment, overlap_start)
	var relative_position: Vector2 = player_position - envelope_translation
	var relative_velocity: Vector2 = (
		player_segment.get("velocity", Vector2.ZERO)
		- threat_segment.get("velocity", Vector2.ZERO)
	)
	var forward: Vector2 = threat.get("forward", Vector2.RIGHT)
	var side: Vector2 = threat.get("side", Vector2.DOWN)
	var expanded_radius: float = PLAYER_RADIUS + SAFETY_MARGIN
	# 群れの進行方向を基準とするローカル座標へ射影する。
	var local_position := Vector2(relative_position.dot(forward), relative_position.dot(side))
	var local_velocity := Vector2(relative_velocity.dot(forward), relative_velocity.dot(side))
	# 円対矩形を点対拡張矩形へ変換するため、プレイヤー半径分だけ外側へ広げる。
	var minimum := Vector2(
		float(threat.get("min_forward", 0.0)) - expanded_radius,
		float(threat.get("min_side", 0.0)) - expanded_radius,
	)
	var maximum := Vector2(
		float(threat.get("max_forward", 0.0)) + expanded_radius,
		float(threat.get("max_side", 0.0)) + expanded_radius,
	)
	var local: Vector2 = _ray_box_interval(
		local_position,
		local_velocity,
		minimum,
		maximum,
		overlap_end - overlap_start,
	)
	if local.x < 0.0:
		return local
	return Vector2(overlap_start + local.x, overlap_start + local.y)


# 2D の移動点が軸平行矩形内に入る時間区間を、各軸の区間の共通部分から求めます。
func _ray_box_interval(
	position: Vector2,
	velocity: Vector2,
	minimum: Vector2,
	maximum: Vector2,
	duration: float,
) -> Vector2:
	var entry: float = 0.0
	var exit_time: float = duration
	# スラブ法: X 軸と Y 軸の内部滞在区間の共通部分を取る。
	var x_interval: Vector2 = _axis_box_interval(
		position.x,
		velocity.x,
		minimum.x,
		maximum.x,
		duration,
	)
	if x_interval.x < 0.0:
		return Vector2(-1.0, -1.0)
	entry = maxf(entry, x_interval.x)
	exit_time = minf(exit_time, x_interval.y)
	var y_interval: Vector2 = _axis_box_interval(
		position.y,
		velocity.y,
		minimum.y,
		maximum.y,
		duration,
	)
	if y_interval.x < 0.0:
		return Vector2(-1.0, -1.0)
	entry = maxf(entry, y_interval.x)
	exit_time = minf(exit_time, y_interval.y)
	if exit_time < entry - TIME_EPSILON:
		return Vector2(-1.0, -1.0)
	return Vector2(entry, maxf(entry, exit_time))


# 一つの軸で、移動値が `[minimum, maximum]` 内にある時間区間を求めます。
func _axis_box_interval(
	position: float,
	velocity: float,
	minimum: float,
	maximum: float,
	duration: float,
) -> Vector2:
	if absf(velocity) <= VECTOR_EPSILON:
		return (
			Vector2(0.0, duration)
			if position >= minimum and position <= maximum
			else Vector2(-1.0, -1.0)
		)
	var first: float = (minimum - position) / velocity
	var second: float = (maximum - position) / velocity
	var entry: float = minf(first, second)
	var exit_time: float = maxf(first, second)
	if exit_time < 0.0 or entry > duration:
		return Vector2(-1.0, -1.0)
	return Vector2(maxf(0.0, entry), minf(duration, exit_time))


# 重複または隣接する時間区間を統合し、時刻順の非重複区間にします。
func _merge_intervals(intervals: Array[Vector2]) -> Array[Vector2]:
	if intervals.is_empty():
		return []
	# 開始時刻、終了時刻の順に並べてから一度だけ走査する。
	intervals.sort_custom(func(left: Vector2, right: Vector2) -> bool:
		if not is_equal_approx(left.x, right.x):
			return left.x < right.x
		return left.y < right.y
	)
	var result: Array[Vector2] = []
	var current: Vector2 = intervals[0]
	for index: int in range(1, intervals.size()):
		var next: Vector2 = intervals[index]
		if next.x <= current.y + TIME_EPSILON:
			current.y = maxf(current.y, next.y)
		else:
			result.append(current)
			current = next
	result.append(current)
	return result


# 等速移動区間上の、指定時刻における位置を返します。
func _segment_position_at(segment: Dictionary, time_seconds: float) -> Vector2:
	var start: float = float(segment.get("start", 0.0))
	var position: Vector2 = segment.get("position", Vector2.ZERO)
	var velocity: Vector2 = segment.get("velocity", Vector2.ZERO)
	return position + velocity * maxf(0.0, time_seconds - start)


# 予測終了時点で、プレイヤーと脅威の安全境界との余裕距離を求めます。
# 脅威が予測終了前に消える場合は、比較対象外を示す `INF` を返します。
func _threat_end_clearance(
	player_segments: Array[Dictionary],
	threat: Dictionary,
	threat_segments: Array[Dictionary],
) -> float:
	if player_segments.is_empty() or threat_segments.is_empty():
		return INF
	var final_threat_segment: Dictionary = threat_segments[threat_segments.size() - 1]
	# 予測終了時点まで存在しない脅威は、終端距離の評価から外す。
	if float(final_threat_segment.get("end", 0.0)) < PREDICTION_SECONDS - TIME_EPSILON:
		return INF
	var player_position: Vector2 = _segment_position_at(
		player_segments[player_segments.size() - 1],
		PREDICTION_SECONDS,
	)
	var threat_translation: Vector2 = _segment_position_at(
		final_threat_segment,
		PREDICTION_SECONDS,
	)
	# 群れは矩形上の最近点、通常脅威は中心間距離から余裕を計算する。
	if threat.get("shape", SHAPE_CIRCLE) == SHAPE_SWARM_ENVELOPE:
		var forward: Vector2 = threat.get("forward", Vector2.RIGHT)
		var side: Vector2 = threat.get("side", Vector2.DOWN)
		var relative: Vector2 = player_position - threat_translation
		var local := Vector2(relative.dot(forward), relative.dot(side))
		var closest := Vector2(
			clampf(
				local.x,
				float(threat.get("min_forward", 0.0)),
				float(threat.get("max_forward", 0.0)),
			),
			clampf(
				local.y,
				float(threat.get("min_side", 0.0)),
				float(threat.get("max_side", 0.0)),
			),
		)
		return local.distance_to(closest) - PLAYER_RADIUS - SAFETY_MARGIN
	return (
		player_position.distance_to(threat_translation)
		- PLAYER_RADIUS
		- float(threat.get("radius", 0.0))
		- SAFETY_MARGIN
	)


#endregion

#region 目的地・視界・壁際の制御

# 方針別の優先順で取得物を探し、最初に見つかった対象への単位方向を返します。
# 対象がなければ、アリーナ内の巡回方向を返します。
func _objective_direction(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> Vector2:
	# 優先カテゴリを順に調べ、カテゴリ内では最寄りの一個を選ぶ。
	var categories: Array[int] = _objective_categories(simulation.state)
	for category: int in categories:
		var target: Dictionary = (
			_nearest_xp(simulation, player_position)
			if category == OBJECTIVE_XP
			else (
				_nearest_seen_chest(player_position)
				if category == int(ArenaPickup.Kind.CHEST)
				else _nearest_arena_pickup(simulation, player_position, category)
			)
		)
		if bool(target.get("found", false)):
			var target_position: Vector2 = target.get("position", player_position)
			var offset: Vector2 = target_position - player_position
			if offset.length_squared() > VECTOR_EPSILON:
				return offset.normalized()
	return _patrol_direction(player_position)


# 現在 HP と方針から、宝箱・回復・経験値などを追う優先順を作ります。
func _objective_categories(state: RunState) -> Array[int]:
	var hp_ratio: float = state.current_hp / maxf(1.0, state.max_hp)
	# 慎重方針は HP 70% 以下で回復を最優先し、その後も安全系取得物を優先する。
	if policy == Policy.CAUTIOUS:
		var cautious: Array[int] = []
		if hp_ratio <= 0.70:
			cautious.append(int(ArenaPickup.Kind.HEAL))
		cautious.append_array([
			int(ArenaPickup.Kind.CHEST),
			int(ArenaPickup.Kind.STOP),
			int(ArenaPickup.Kind.VACUUM),
			OBJECTIVE_XP,
		])
		return cautious
	var result: Array[int] = [int(ArenaPickup.Kind.CHEST)]
	# 通常方針は 60%、進化方針は 50% まで宝箱を回復より優先する。
	var heal_threshold: float = 0.60 if policy == Policy.NORMAL else 0.50
	if hp_ratio <= heal_threshold:
		result.append(int(ArenaPickup.Kind.HEAL))
	result.append_array([
		OBJECTIVE_XP,
		int(ArenaPickup.Kind.VACUUM),
		int(ArenaPickup.Kind.STOP),
	])
	return result


# 指定種類の取得物から、画面内で最も近いものを探します。
func _nearest_arena_pickup(
	simulation: CombatSimulation,
	player_position: Vector2,
	kind_value: int,
) -> Dictionary:
	var result: Dictionary = {"found": false}
	var best_distance_squared: float = INF
	var best_id: int = -1
	# 実際に画面へ入っている取得物だけを候補にする。
	for pickup: ArenaPickup in simulation.arena_object_system.pickups:
		if not pickup.active or int(pickup.kind) != kind_value:
			continue
		var radius: float = (
			CHEST_VISIBILITY_RADIUS
			if pickup.kind == ArenaPickup.Kind.CHEST
			else PICKUP_VISIBILITY_RADIUS
		)
		if not _circle_intersects_view(player_position, pickup.position, radius):
			continue
		var distance_squared: float = pickup.position.distance_squared_to(player_position)
		if (
			distance_squared < best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and _id_wins_tie(pickup.pickup_id, best_id)
			)
		):
			best_distance_squared = distance_squared
			best_id = pickup.pickup_id
			result = {"found": true, "position": pickup.position}
	return result


# 画面内に存在する経験値取得物のうち、最も近いものを探します。
func _nearest_xp(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> Dictionary:
	var result: Dictionary = {"found": false}
	var best_distance_squared: float = INF
	var best_pool_index: int = -1
	# プール添字を安定 ID として使い、同距離でも選択を再現可能にする。
	for pool_index: int in simulation.xp_pickup_pool.active_indices_snapshot():
		var pickup: XpPickupState = simulation.xp_pickup_pool.slots[pool_index]
		if not _circle_intersects_view(
			player_position,
			pickup.position,
			XP_VISIBILITY_RADIUS,
		):
			continue
		var distance_squared: float = pickup.position.distance_squared_to(player_position)
		if (
			distance_squared < best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and _id_wins_tie(pool_index, best_pool_index)
			)
		):
			best_distance_squared = distance_squared
			best_pool_index = pool_index
			result = {"found": true, "position": pickup.position}
	return result


# 画面内で見つけた宝箱の位置を記憶し、画面外へ出ても目的地として保持します。
# 記憶位置が再び画面内に入ったのに実物がなければ、取得済みとして忘れます。
func _observe_chests(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> void:
	# 今回見えている宝箱 ID と、過去から記憶している位置を別々に管理する。
	var visible_chest_ids: Dictionary[int, bool] = {}
	for pickup: ArenaPickup in simulation.arena_object_system.pickups:
		if not pickup.active or pickup.kind != ArenaPickup.Kind.CHEST:
			continue
		if not _circle_intersects_view(
			player_position,
			pickup.position,
			CHEST_VISIBILITY_RADIUS,
		):
			continue
		visible_chest_ids[pickup.pickup_id] = true
		_seen_chests[pickup.pickup_id] = pickup.position
	# 記憶位置が画面内なのに ID が見えなければ、既に消えた宝箱と判断する。
	var forgotten_ids: Array[int] = []
	for pickup_id: int in _seen_chests:
		var known_position: Vector2 = _seen_chests[pickup_id]
		if (
			_circle_intersects_view(
				player_position,
				known_position,
				CHEST_VISIBILITY_RADIUS,
			)
			and not visible_chest_ids.has(pickup_id)
		):
			forgotten_ids.append(pickup_id)
	for pickup_id: int in forgotten_ids:
		_seen_chests.erase(pickup_id)


# 対象円が、45 度回転した画面相当の矩形と交差しているか判定します。
func _circle_intersects_view(
	player_position: Vector2,
	target_position: Vector2,
	radius: float,
) -> bool:
	# ワールド差分を画面右軸・画面下軸へ射影し、矩形の半幅と比較する。
	var offset: Vector2 = target_position - player_position
	return (
		absf(offset.dot(SCREEN_RIGHT_WORLD)) <= VIEW_HALF_WIDTH + maxf(0.0, radius)
		and absf(offset.dot(SCREEN_DOWN_WORLD)) <= VIEW_HALF_DEPTH + maxf(0.0, radius)
	)


# 記憶している未取得宝箱のうち、現在位置から最も近いものを返します。
func _nearest_seen_chest(player_position: Vector2) -> Dictionary:
	var result: Dictionary = {"found": false}
	var best_distance_squared: float = INF
	var best_id: int = -1
	for pickup_id: int in _seen_chests:
		var position: Vector2 = _seen_chests[pickup_id]
		var distance_squared: float = position.distance_squared_to(player_position)
		if (
			distance_squared < best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and _id_wins_tie(pickup_id, best_id)
			)
		):
			best_distance_squared = distance_squared
			best_id = pickup_id
			result = {"found": true, "position": position}
	return result


# 取得目標がないとき、四隅の巡回点を順番にたどる方向を返します。
func _patrol_direction(player_position: Vector2) -> Vector2:
	var target: Vector2 = PATROL_WAYPOINTS[_patrol_index]
	# 巡回点へ十分近づいたら、シード由来の回転方向で次の点へ進む。
	if player_position.distance_squared_to(target) <= 1.0:
		_patrol_index = wrapi(_patrol_index + int(_handedness), 0, PATROL_WAYPOINTS.size())
		target = PATROL_WAYPOINTS[_patrol_index]
	var offset: Vector2 = target - player_position
	return offset.normalized() if offset.length_squared() > VECTOR_EPSILON else Vector2.ZERO


# 壁から `WALL_MARGIN` 未満へ近づいたとき、内側へ押し戻す補正ベクトルを作ります。
func _wall_correction(player_position: Vector2) -> Vector2:
	var correction: Vector2 = Vector2.ZERO
	var left_distance: float = player_position.x - CombatSimulation.ARENA_MIN.x
	var right_distance: float = CombatSimulation.ARENA_MAX.x - player_position.x
	var top_distance: float = player_position.y - CombatSimulation.ARENA_MIN.y
	var bottom_distance: float = CombatSimulation.ARENA_MAX.y - player_position.y
	# 壁へ近いほど 0〜1 の大きな内向き成分を加える。
	if left_distance < WALL_MARGIN:
		correction.x += (WALL_MARGIN - left_distance) / WALL_MARGIN
	if right_distance < WALL_MARGIN:
		correction.x -= (WALL_MARGIN - right_distance) / WALL_MARGIN
	if top_distance < WALL_MARGIN:
		correction.y += (WALL_MARGIN - top_distance) / WALL_MARGIN
	if bottom_distance < WALL_MARGIN:
		correction.y -= (WALL_MARGIN - bottom_distance) / WALL_MARGIN
	return correction


# 壁際で外向き成分を許さないよう移動方向を補正し、単位ベクトルに戻します。
func _enforce_wall_inward(movement: Vector2, wall: Vector2) -> Vector2:
	var corrected: Vector2 = movement
	# 補正が要求する内向き成分を、候補方向の各軸へ最低限保証する。
	if wall.x > 0.0:
		corrected.x = maxf(corrected.x, wall.x)
	elif wall.x < 0.0:
		corrected.x = minf(corrected.x, wall.x)
	if wall.y > 0.0:
		corrected.y = maxf(corrected.y, wall.y)
	elif wall.y < 0.0:
		corrected.y = minf(corrected.y, wall.y)
	if corrected.length_squared() <= VECTOR_EPSILON:
		return Vector2.ZERO
	return corrected.normalized()


#endregion

#region アップグレード選択

# 通常ルールでアップグレード候補を選びます。
# 集中育成を優先し、それが無理なら進化相方の所有状況と現在レベルで順位付けします。
func _normal_upgrade_choice(
	offer: LevelOffer,
	state: RunState,
	catalog: DefinitionCatalog,
) -> int:
	# まず、現在ロックしている集中育成対象の進化条件を進める。
	var focus_index: int = _normal_focus_choice(offer, state, catalog)
	if focus_index >= 0:
		return focus_index
	var best_index: int = -1
	var best_priority: int = -1
	var best_ratio: float = -1.0
	# 優先度: 所有武器+相方あり > 新規+相方あり > 所有済み > 完全な新規。
	for index: int in range(offer.options.size()):
		var option: UpgradeOption = offer.options[index]
		var counterpart_owned: bool = _counterpart_is_owned(option, state, catalog)
		var priority: int = 0
		if option.kind == GameTypes.UpgradeKind.WEAPON and option.current_level > 0 and counterpart_owned:
			priority = 4
		elif option.current_level <= 0 and counterpart_owned:
			priority = 3
		elif option.current_level > 0:
			priority = 2
		else:
			priority = 1
		# 同じ優先度なら完成に近い候補を選び、ビルドを散らしにくくする。
		var ratio: float = float(option.current_level) / float(maxi(1, option.max_level))
		if (
			priority > best_priority
			or (
				priority == best_priority
				and (
					ratio > best_ratio
					or (
						is_equal_approx(ratio, best_ratio)
						and best_index >= 0
						and _option_id_wins_tie(
							option.content_id,
							offer.options[best_index].content_id,
						)
					)
				)
			)
		):
			best_priority = priority
			best_ratio = ratio
			best_index = index
	return best_index


# 未進化武器を一つ「集中育成対象」として固定し、相方パッシブと武器強化を優先します。
func _normal_focus_choice(
	offer: LevelOffer,
	state: RunState,
	catalog: DefinitionCatalog,
) -> int:
	var focused_weapon: RunWeapon = state.weapon_for_lineage(_normal_focus_lineage)
	# 対象が消えた、または進化済みなら、最初の未進化武器へロックし直す。
	if focused_weapon == null or focused_weapon.evolved:
		_normal_focus_lineage = &""
		for weapon: RunWeapon in state.weapons:
			if not weapon.evolved:
				_normal_focus_lineage = weapon.lineage_id
				focused_weapon = weapon
				break
	if focused_weapon == null or _normal_focus_lineage.is_empty():
		return -1
	var definition: WeaponDefinition = catalog.weapon(_normal_focus_lineage)
	if definition == null:
		return -1
	# 対応パッシブを未取得なら先に確保し、その後で武器レベルを上げる。
	if state.passive(definition.paired_passive_id) == null:
		var passive_index: int = _find_option(offer, definition.paired_passive_id)
		if passive_index >= 0:
			return passive_index
	if focused_weapon.level < definition.max_level:
		return _find_option(offer, _normal_focus_lineage)
	return -1


# 候補が武器なら対応パッシブ、パッシブなら対応武器を既に所有しているか確認します。
func _counterpart_is_owned(
	option: UpgradeOption,
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	if option.kind == GameTypes.UpgradeKind.WEAPON:
		var weapon_definition: WeaponDefinition = catalog.weapon(option.content_id)
		return (
			weapon_definition != null
			and not weapon_definition.paired_passive_id.is_empty()
			and state.passive(weapon_definition.paired_passive_id) != null
		)
	var passive_definition: PassiveDefinition = catalog.passive(option.content_id)
	return (
		passive_definition != null
		and not passive_definition.paired_weapon_id.is_empty()
		and state.weapon_for_lineage(passive_definition.paired_weapon_id) != null
	)


#endregion

#region 検索と決定論的な同点処理

# 提示候補から指定コンテンツ ID を探し、その添字を返します。なければ `-1` です。
func _find_option(offer: LevelOffer, content_id: StringName) -> int:
	for index: int in range(offer.options.size()):
		if offer.options[index].content_id == content_id:
			return index
	return -1


# 未選択状態を考慮しつつ、数値 ID の同点比較を行います。
func _id_wins_tie(candidate_id: int, incumbent_id: int) -> bool:
	if incumbent_id < 0:
		return true
	return _stable_id_wins(candidate_id, incumbent_id)


# シードから決めた昇順または降順の規則で、数値 ID の勝者を決めます。
func _stable_id_wins(candidate_id: int, incumbent_id: int) -> bool:
	return candidate_id < incumbent_id if _prefer_lower_id else candidate_id > incumbent_id


# シードから決めた昇順または降順の規則で、文字列 ID の勝者を決めます。
func _option_id_wins_tie(candidate_id: StringName, incumbent_id: StringName) -> bool:
	var candidate: String = String(candidate_id)
	var incumbent: String = String(incumbent_id)
	return candidate < incumbent if _prefer_lower_id else candidate > incumbent

#endregion
