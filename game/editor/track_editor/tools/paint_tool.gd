extends BrushTool
## The Paint tool (EDT-02): paints the ground's layers (grass, dirt, sand, gravel, rock, snow,
## concrete, asphalt). Wheels drive on what's painted (D91).

var layer := 1


func _init() -> void:
	strength = 0.8


func title() -> String:
	return "Paint"


func hint() -> String:
	return "Drag to paint · keys or controller: Enter turns the brush on · wheels feel what's painted"


func _apply(at: Vector2, dt: float) -> Rect2i:
	return draft.terrain.field.paint(layer, at, radius, clampf(strength * dt * 6.0, 0.0, 1.0), falloff)


func _region(rect: Rect2i) -> Variant:
	return draft.terrain.field.splat_region_get(rect)


func _stride() -> int:
	return TerrainData.LAYERS.size()


func _commit(rect: Rect2i, before: Variant, after: Variant) -> void:
	draft.paint_stroke(rect, before, after)


func _live(rect: Rect2i) -> void:
	var tv := view.preview.terrain_view()
	if tv:
		tv.update_paint(rect)


func panel() -> Array:
	if draft.terrain == null:
		return [UiKit.label("This track has no terrain.", 22)]
	var layers := []
	for i in TerrainData.LAYERS.size():
		layers.append([i, String(TerrainData.LAYERS[i]).capitalize()])
	var out := [UiKit.spinner("Layer", layers, layer, func(v: int) -> void: layer = v, "What the ground is")]
	out.append(UiKit.number("Strength", strength, 0.05, 1.0, 0.05, "%.2f", func(v: float) -> void: strength = v))
	out.append_array(_size_rows())
	return out
