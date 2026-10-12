extends BrushTool
## The Terrain tool (EDT-02): raise, lower, smooth, flatten or roughen the ground with a brush.
## Roads that follow the ground follow it; the road's bed is cut into it as you go.

const MODES := [["raise", "Raise"], ["lower", "Lower"], ["smooth", "Smooth"], ["flatten", "Flatten"], ["noise", "Noise"]]
const MODE_IDS := { "raise": 0, "lower": 1, "smooth": 2, "flatten": 3, "noise": 4 }

var mode := "raise"
var target := 0.0
var _seed := 1


func _init() -> void:
	strength = 2.0


func title() -> String:
	return "Terrain"


func hint() -> String:
	return "Drag to shape the ground · keys or controller: Enter turns the brush on · Ctrl+Z undoes a stroke"


func _apply(at: Vector2, dt: float) -> Rect2i:
	var per := strength * dt if mode in ["raise", "lower", "noise"] else clampf(strength * 0.5 * dt * 10.0, 0.0, 1.0)
	return draft.terrain.field.brush(MODE_IDS[mode], at, radius, per, falloff, target, 0.03, _seed)


func _region(rect: Rect2i) -> Variant:
	return draft.terrain.field.region_get(rect)


func _commit(rect: Rect2i, before: Variant, after: Variant) -> void:
	_seed += 1
	draft.terrain_stroke(rect, before, after)


func _live(rect: Rect2i) -> void:
	var t := draft.terrain
	var changed := t.field.conform(rect, TerrainData.road_samples(draft.track()), TerrainData.FALLOFF_M, TerrainData.BED_DEPTH_M)
	var tv := view.preview.terrain_view()
	if tv:
		tv.update_rect(changed)


func panel() -> Array:
	if draft.terrain == null:
		return [UiKit.label("This track has no terrain.", 22)]
	var out := [UiKit.spinner("Brush", MODES, mode, func(v: String) -> void:
		mode = v
		editor.refresh_panel())]
	out.append(UiKit.number("Strength", strength, 0.1, 10.0, 0.1, "%.1f m/s" if mode in ["raise", "lower", "noise"] else "%.1f", func(v: float) -> void: strength = v))
	out.append_array(_size_rows())
	if mode == "flatten":
		out.append(UiKit.number("Height", target, -100.0, 500.0, 0.5, "%.1f m", func(v: float) -> void: target = v, "Flatten to this height"))
		out.append(UiKit.button("Pick height", func() -> void:
			var hit := view.pick(view.cursor())
			if hit.hit:
				target = snappedf(draft.terrain.base_at(hit.position.x, hit.position.z), 0.1)
				editor.say("Height %.1f m" % target)
				editor.refresh_panel(), "The ground's height at the cursor"))
	var area := draft.terrain.area()
	out.append(UiKit.label("Ground %.0f × %.0f m" % [area.size.x, area.size.y], 22))
	out.append(UiKit.button("Fit terrain to track", _fit, "Grow or shrink the ground round the road"))
	return out


func _fit() -> void:
	var t := draft.track()
	if t.samples.size() < 3:
		editor.say("Add the road first")
		return
	var box := Rect2(Vector2(t.samples[0].x, t.samples[0].z), Vector2.ZERO)
	for p in t.samples:
		box = box.expand(Vector2(p.x, p.z))
	draft.set_terrain(draft.terrain.fit_to(box), "Fit terrain to track")
	editor.say("Ground %.0f × %.0f m" % [draft.terrain.area().size.x, draft.terrain.area().size.y])
