class_name BalanceTestFixtures
extends RefCounted


static var _catalog: DefinitionCatalog = null


## Read-only default input for existing integration fixtures. Never mutate this catalog.
static func catalog() -> DefinitionCatalog:
	if _catalog == null:
		_catalog = DefinitionCatalog.new()
		assert(_catalog.load_and_validate(), _catalog.error_text)
	return _catalog


## Detached input, including every external .tres reference, for mutation tests.
static func manifest() -> SurvivalContentManifest:
	return catalog().manifest().duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as SurvivalContentManifest


static func grid() -> UniformGrid:
	var result := UniformGrid.new()
	return result


static func elite_events(ticks: Array, kind: GameTypes.ChestKind = GameTypes.ChestKind.NORMAL) -> Array[StageEventDefinition]:
	var result: Array[StageEventDefinition] = []
	for tick: int in ticks:
		var event := EliteSpawnDefinition.new()
		event.event_id = StringName("elite_%d" % result.size())
		event.start_tick = tick
		event.hp_multiplier = 1.0
		event.chest_kind = kind
		result.append(event)
	return result


static func xp_pool() -> XpPickupPool:
	var result := XpPickupPool.new()
	result.configure(catalog().manifest().progression)
	return result
