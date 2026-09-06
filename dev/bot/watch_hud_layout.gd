extends Node


func _ready() -> void:
	var hud := get_parent() as Control
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()


func _fit_viewport() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var factor: float = minf(1.0, minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0))
	if factor <= 0.0:
		return
	var hud := get_parent() as Control
	hud.scale = Vector2.ONE * factor
	hud.size = viewport_size / factor
