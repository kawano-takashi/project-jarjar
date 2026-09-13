extends RefCounted

const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")
const BotObservation = preload("res://dev/bot/bot_observation.gd")

enum Role { SINGLE, AREA }
enum EvolutionState { NONE, PREPARING, READY }
enum Priority { MISSING_ROLE, PARTNER, CORE_UPGRADE, THIRD_WEAPON, SUPPORT, EXTRA_WEAPON }

## Bot preferences only. Within a role, retain the previous weapon preference.
const WEAPON_PREFERENCE: Array[float] = [110.0, 140.0, 84.0, 60.0, 90.0, 75.0, 85.0, 150.0]

var core_weapons: Array[StringName] = []
var evolution_state: EvolutionState = EvolutionState.NONE
var _knowledge: BotKnowledge
var _weapons: Dictionary[StringName, Dictionary] = {}
var _passives: Dictionary[StringName, int] = {}
var _weapon_snapshot: Array[Dictionary] = []
var _passive_snapshot: Array[Dictionary] = []
var _initialized: bool = false
var _expanded: bool = false
var _evolutions_left: int = 0


func _init(knowledge: BotKnowledge) -> void:
	_knowledge = knowledge


func reset() -> void:
	core_weapons.clear()
	_weapons.clear()
	_passives.clear()
	_weapon_snapshot.clear()
	_passive_snapshot.clear()
	_initialized = false
	_expanded = false
	_evolutions_left = 0
	evolution_state = EvolutionState.NONE


func observe(observation: BotObservation) -> void:
	if _initialized and observation.weapons == _weapon_snapshot and observation.passives == _passive_snapshot:
		return
	var previous: Array[StringName] = _weapons.keys()
	_weapon_snapshot = observation.weapons.duplicate(true)
	_passive_snapshot = observation.passives.duplicate(true)
	_weapons.clear()
	_passives.clear()
	_evolutions_left = _knowledge.max_evolutions
	for weapon: Dictionary in _weapon_snapshot:
		_weapons[_knowledge.weapon_lineages[weapon["id"]]] = weapon
		if weapon["evolved"]:
			_evolutions_left -= 1
	_evolutions_left = maxi(0, _evolutions_left)
	for passive: Dictionary in _passive_snapshot:
		_passives[passive["id"]] = int(passive["level"])
	# Commit only observed acquisitions; repeated menu decisions do not add cores.
	for lineage: StringName in _weapons:
		if _expanded or core_weapons.size() >= 3 or previous.has(lineage):
			continue
		if core_weapons.is_empty() or not _has_core_role(_role(lineage)) or core_weapons.size() >= 2:
			core_weapons.append(lineage)
	if core_weapons.size() >= 2 and _has_core_role(Role.SINGLE) and _has_core_role(Role.AREA):
		var complete: bool = true
		for lineage: StringName in core_weapons:
			if _remaining_levels(lineage) > 0:
				complete = false
		_expanded = _expanded or complete
	_initialized = true
	_refresh_evolution_state()


func choose_upgrade(observation: BotObservation) -> int:
	observe(observation)
	var selected: int = -1
	var best := PackedFloat64Array()
	var best_id: String = ""
	var reachable: int = _reachable_core_evolutions(&"")
	for index: int in observation.options.size():
		var option: Dictionary = observation.options[index]
		var rank: PackedFloat64Array = _rank(option, observation, reachable)
		var content_id: String = String(option["id"])
		if selected < 0 or _rank_before(rank, best) or (rank == best and content_id < best_id):
			selected = index
			best = rank
			best_id = content_id
	return selected


func _role(lineage: StringName) -> Role:
	var behavior: int = _knowledge.weapons[lineage]["behavior"]
	return Role.SINGLE if behavior in [GameTypes.WeaponBehavior.HOMING_PROJECTILE, GameTypes.WeaponBehavior.DIRECTIONAL_PROJECTILE, GameTypes.WeaponBehavior.MASS_PROJECTILE] else Role.AREA


func _has_core_role(role: Role) -> bool:
	for lineage: StringName in core_weapons:
		if _role(lineage) == role:
			return true
	return false


func _remaining_levels(lineage: StringName) -> int:
	var weapon: Dictionary = _weapons[lineage]
	return 0 if weapon["evolved"] else maxi(0, int(_knowledge.weapons[lineage]["max_level"]) - int(weapon["level"]))


func _can_finish_evolution(lineage: StringName) -> bool:
	return _evolutions_left > 0 and not _weapons[lineage]["evolved"] and _knowledge.evolutions.has(lineage) and (_remaining_levels(lineage) == 0 or _knowledge.weapons[lineage]["selectable"])


func _refresh_evolution_state() -> void:
	evolution_state = EvolutionState.NONE
	for lineage: StringName in _weapons:
		if not _can_finish_evolution(lineage):
			continue
		var partner: StringName = _knowledge.evolutions[lineage]["passive"]
		if _passives.has(partner):
			if _remaining_levels(lineage) == 0:
				evolution_state = EvolutionState.READY
				return
			evolution_state = EvolutionState.PREPARING
		elif _passives.size() < _knowledge.passive_slots and _knowledge.passives[partner]["selectable"]:
			evolution_state = EvolutionState.PREPARING


## Count simultaneously reachable core evolutions, including shared partners.
## Comparing before/after preserves material slots without vetoing every offer.
func _reachable_core_evolutions(added_passive: StringName) -> int:
	var slots: int = _knowledge.passive_slots - _passives.size() - int(added_passive != &"")
	var ready_partners: int = 0
	var missing: Dictionary[StringName, int] = {}
	for lineage: StringName in core_weapons:
		if not _can_finish_evolution(lineage):
			continue
		var partner: StringName = _knowledge.evolutions[lineage]["passive"]
		if _passives.has(partner) or partner == added_passive:
			ready_partners += 1
		elif _knowledge.passives[partner]["selectable"]:
			missing[partner] = missing.get(partner, 0) + 1
	var counts: Array[int] = missing.values()
	counts.sort()
	counts.reverse()
	for index: int in mini(maxi(0, slots), counts.size()):
		ready_partners += counts[index]
	return mini(_evolutions_left, ready_partners)


func _rank(option: Dictionary, observation: BotObservation, reachable: int) -> PackedFloat64Array:
	var content_id: StringName = option["id"]
	var level: int = option["level"]
	var is_weapon: bool = int(option["kind"]) == GameTypes.UpgradeKind.WEAPON
	var lost_routes: int = 0
	var priority: Priority = Priority.SUPPORT
	var remaining: int = 0
	var joined: int = 0
	var role_preference: int = 0
	var partner_preference: int = 0
	var preference: float
	if is_weapon:
		var lineage: StringName = _knowledge.weapon_lineages[content_id]
		var role: Role = _role(lineage)
		preference = WEAPON_PREFERENCE[int(_knowledge.weapons[content_id]["behavior"])]
		if level == 0:
			if not _has_core_role(role):
				priority = Priority.MISSING_ROLE
			elif _expanded or core_weapons.size() == 2:
				priority = Priority.THIRD_WEAPON
			else:
				priority = Priority.EXTRA_WEAPON
			role_preference = int(role != Role.AREA)
			partner_preference = 1
			if _knowledge.evolutions.has(lineage) and _passives.has(_knowledge.evolutions[lineage]["passive"]):
				partner_preference = 0
		elif _expanded or core_weapons.has(lineage):
			priority = Priority.CORE_UPGRADE
			remaining = _remaining_levels(lineage)
			joined = core_weapons.find(lineage) if core_weapons.has(lineage) else core_weapons.size()
		else:
			preference += float(level) * 3.0
	else:
		preference = _passive_preference(content_id, level, observation)
		if level == 0:
			lost_routes = reachable - _reachable_core_evolutions(content_id)
			var targets: Array[StringName] = _weapons.keys() if _expanded else core_weapons
			remaining = 2147483647
			for index: int in targets.size():
				var lineage: StringName = targets[index]
				if _can_finish_evolution(lineage) and _knowledge.evolutions[lineage]["passive"] == content_id:
					priority = Priority.PARTNER
					if _remaining_levels(lineage) < remaining:
						remaining = _remaining_levels(lineage)
						joined = index
			if priority != Priority.PARTNER:
				remaining = 0
	# Gaining routes must not outrank securing a missing attack role.
	return PackedFloat64Array([maxi(0, lost_routes), priority, remaining, joined, role_preference, partner_preference, -preference])


func _passive_preference(content_id: StringName, level: int, observation: BotObservation) -> float:
	var stat: StringName = _knowledge.passives[content_id]["stat"]
	var preferences: Dictionary[StringName, float] = {
		&"recovery_per_second": 70.0, &"max_hp_pct": 65.0, &"cooldown_pct": 68.0,
		&"might_pct": 52.0, &"area_pct": 50.0, &"duration_pct": 30.0,
		&"projectile_speed_pct": 15.0, &"luck_pct": 18.0,
	}
	var preference: float = preferences[stat]
	if stat == &"luck_pct" and level == 0 and _weapons.size() == 1 and int(_weapon_snapshot[0]["level"]) < 4:
		preference = maxf(preference, 90.0)
	if stat in [&"recovery_per_second", &"max_hp_pct"]:
		preference += (1.0 - observation.hp / observation.max_hp) * 40.0
	return preference


static func _rank_before(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	for index: int in left.size():
		if left[index] != right[index]:
			return left[index] < right[index]
	return false
