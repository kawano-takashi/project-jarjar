class_name WeaponVisualStyle
extends RefCounted

## Presentation only. Attack regions retain combat geometry; small projectile
## silhouettes are enlarged for readability without changing hit detection.
const COLORS: Array[Color] = [
	Color("c6d3d5"), Color("72cbd3"), Color("95cbaa"), Color("e0d392"),
	Color("94b5e5"), Color("d499bb"), Color("b3a0d9"), Color("ddd5bf"),
	Color("82aebf"), Color("ff3030"),
]
## Display lifetimes in combat ticks (60 ticks = one second).
const ATTACK_TICKS: int = 9
const IMPACT_TICKS: int = 12
const TRAIL_TICKS: int = 5
const TRAIL_INTERVAL_TICKS: int = 3
const GROUND_HEIGHT_M: float = 0.04
const INSET_LINE_WIDTH: float = 0.045
const RANGE_LINE_WIDTH: float = 0.020
## Local silhouette width/length multipliers, shared by rendering and bot meshes.
const PROJECTILE_BODY_SCALE: Dictionary[int, Vector2] = {
	2: Vector2(1.8, 1.8),
	3: Vector2(1.8, 2.0),
	4: Vector2(1.6, 1.6),
	5: Vector2(1.25, 1.25),
}
## Small silhouettes remain above broad disks without changing their world positions.
const DRAW_ORDER: Array[int] = [2, 2, 6, 7, 5, 4, 3, 0, 2]
const PROJECTILE_SHADER: Shader = preload("res://src/gameplay/weapon_projectile.gdshader")
const EFFECT_SHADER: Shader = preload("res://src/gameplay/weapon_effect.gdshader")


static func color_for(kind: int) -> Color:
	return COLORS[clampi(kind, 0, COLORS.size() - 1)]


static func projectile_material(kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PROJECTILE_SHADER
	material.render_priority = DRAW_ORDER[clampi(kind, 0, DRAW_ORDER.size() - 1)]
	material.set_shader_parameter("weapon_color", color_for(kind))
	material.set_shader_parameter("visual_kind", kind)
	material.set_shader_parameter("line_width", INSET_LINE_WIDTH)
	return material


static func effect_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = EFFECT_SHADER
	material.render_priority = 1
	material.set_shader_parameter("line_width", RANGE_LINE_WIDTH)
	return material
