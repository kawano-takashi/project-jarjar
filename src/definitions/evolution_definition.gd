class_name EvolutionDefinition
extends Resource


## 進化元の通常武器ID。必須、進化一覧内で重複不可。
@export var base_weapon_id: StringName = &""
## パッシブID。空文字不可、manifest内で重複不可。進化定義から参照する。
@export var passive_id: StringName = &""
## 進化先の武器ID。必須、is_evolvedがtrue、進化一覧内で重複不可。
@export var evolved_weapon_id: StringName = &""
