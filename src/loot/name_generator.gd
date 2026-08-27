class_name NameGenerator
extends RefCounted


const PREFIX_BY_AFFIX: Dictionary = {
	&"damage_pct": "猛撃の",
	&"attack_speed_pct": "疾風の",
	&"cooldown_reduction_pct": "時詠みの",
	&"area_pct": "広天の",
	&"pierce": "穿孔の",
	&"max_hp": "巨命の",
	&"damage_reduction_pct": "不落の",
	&"move_speed_pct": "俊足の",
	&"skill_power_pct": "星導の",
}
const SECONDARY_SUFFIX_BY_AFFIX: Dictionary = {
	&"damage_pct": "破軍",
	&"attack_speed_pct": "迅駆",
	&"cooldown_reduction_pct": "秒詠",
	&"area_pct": "天蓋",
	&"pierce": "貫星",
	&"max_hp": "長命",
	&"damage_reduction_pct": "城塞",
	&"move_speed_pct": "飛燕",
	&"skill_power_pct": "星火",
}
const MATERIAL_WORDS: PackedStringArray = [
	"木", "鉄", "黒曜石", "琥珀", "白銀", "竜骨", "星晶", "深紅鋼",
]
const SINGLE_AFFIX_SUFFIXES: PackedStringArray = ["萌芽", "余韻", "一閃", "静謐"]


static func create_name_rng(item_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SeedService.derive(item_seed, &"name")
	return rng


static func generate(
	item_seed: int,
	slot: GameTypes.EquipmentSlot,
	main_weapon_type: GameTypes.MainWeaponType,
	affixes: Array[AffixRoll]
) -> String:
	if affixes.is_empty():
		return "木の棒" if (
			slot == GameTypes.EquipmentSlot.MAIN_WEAPON
			and main_weapon_type == GameTypes.MainWeaponType.UNCLASSIFIED
		) else ""
	var rng: RandomNumberGenerator = create_name_rng(item_seed)
	var prefix: String = String(PREFIX_BY_AFFIX.get(affixes[0].affix_id, ""))
	var material: String = MATERIAL_WORDS[rng.randi_range(0, MATERIAL_WORDS.size() - 1)]
	var fixed_word: String = _fixed_word(slot, main_weapon_type)
	var suffix: String
	if affixes.size() >= 2:
		suffix = String(SECONDARY_SUFFIX_BY_AFFIX.get(affixes[1].affix_id, ""))
	else:
		suffix = SINGLE_AFFIX_SUFFIXES[rng.randi_range(0, SINGLE_AFFIX_SUFFIXES.size() - 1)]
	return "%s%s%s『%s』" % [prefix, material, fixed_word, suffix]


static func first_rng_values(item_seed: int, count: int = 3) -> Array[int]:
	var rng: RandomNumberGenerator = create_name_rng(item_seed)
	var values: Array[int] = []
	for _index: int in range(maxi(0, count)):
		values.append(rng.randi())
	return values


static func secondary_suffix(affix_id: StringName) -> String:
	return String(SECONDARY_SUFFIX_BY_AFFIX.get(affix_id, ""))


static func _fixed_word(
	slot: GameTypes.EquipmentSlot,
	main_weapon_type: GameTypes.MainWeaponType
) -> String:
	if slot == GameTypes.EquipmentSlot.MAIN_WEAPON:
		match main_weapon_type:
			GameTypes.MainWeaponType.BOW:
				return "弓"
			GameTypes.MainWeaponType.STAFF:
				return "杖"
			GameTypes.MainWeaponType.SWORD:
				return "剣"
			_:
				return "棒"
	match slot:
		GameTypes.EquipmentSlot.SUB_WEAPON:
			return "触媒"
		GameTypes.EquipmentSlot.HEAD:
			return "兜"
		GameTypes.EquipmentSlot.BODY:
			return "鎧"
		GameTypes.EquipmentSlot.HANDS:
			return "手甲"
		GameTypes.EquipmentSlot.FEET:
			return "靴"
	return ""
