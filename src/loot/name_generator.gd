class_name NameGenerator
extends RefCounted


const PREFIX_BY_AFFIX: Dictionary = {
	&"damage_pct": "猛撃の",
	&"attack_speed_pct": "疾風の",
	&"area_pct": "広天の",
	&"pierce": "穿孔の",
	&"max_hp": "巨命の",
	&"damage_reduction_pct": "不落の",
	&"move_speed_pct": "俊足の",
}
const SECONDARY_SUFFIX_BY_AFFIX: Dictionary = {
	&"damage_pct": "破軍",
	&"attack_speed_pct": "迅駆",
	&"area_pct": "天蓋",
	&"pierce": "貫星",
	&"max_hp": "長命",
	&"damage_reduction_pct": "城塞",
	&"move_speed_pct": "飛燕",
}
const MATERIAL_WORDS: PackedStringArray = [
	"木", "鉄", "黒曜石", "琥珀", "白銀", "竜骨", "星晶", "深紅鋼",
]
const SINGLE_AFFIX_SUFFIXES: PackedStringArray = ["萌芽", "余韻", "一閃", "静謐"]


static func create_name_rng(item_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SeedService.derive(item_seed, &"name")
	return rng


static func generate_charm(item_seed: int, affixes: Array[AffixRoll]) -> String:
	if affixes.is_empty():
		return "名もなきお守り"
	var rng: RandomNumberGenerator = create_name_rng(item_seed)
	var prefix: String = String(PREFIX_BY_AFFIX.get(affixes[0].affix_id, ""))
	var material: String = MATERIAL_WORDS[rng.randi_range(0, MATERIAL_WORDS.size() - 1)]
	var suffix: String
	if affixes.size() >= 2:
		suffix = String(SECONDARY_SUFFIX_BY_AFFIX.get(affixes[1].affix_id, "護り"))
	else:
		suffix = SINGLE_AFFIX_SUFFIXES[rng.randi_range(0, SINGLE_AFFIX_SUFFIXES.size() - 1)]
	return "%s%sのお守り『%s』" % [prefix, material, suffix]
