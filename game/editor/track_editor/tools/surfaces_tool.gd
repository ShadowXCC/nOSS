extends EditorTool
## The Surfaces tool (Track Fitting, EDT-08; docs/TRACK_EDITOR.md §7.1): what each part of an
## imported scene is to a car. Rules by name tag most of it; a material's own choice overrides
## them; clicking the scene picks the material under the cursor. Then "Measure widths" reads the
## road's width at each point off the scene. Only on tracks made from a scene.

const NAMES := {
	"asphalt": "Asphalt", "concrete": "Concrete", "curb": "Curb", "paint": "Paint", "grass": "Grass", "gravel": "Gravel",
	"dirt": "Dirt", "sand": "Sand", "snow": "Snow", "ice": "Ice", "wall": "Wall", "no-collide": "Only seen", "water": "Water",
}

var _focus_material := ""


func title() -> String:
	return "Surfaces"


func available() -> bool:
	return draft.scene != null


func hint() -> String:
	return "Click the scene to pick its material · set what it is below"


static func tag_items(with_auto := false) -> Array:
	var out := [["auto", "Untagged (solid)"]] if with_auto else []
	for t: String in SceneTrack.TAGS:
		out.append([t, NAMES[t]])
	return out


func pointer(e: Dictionary) -> void:
	if e.kind != "press" or not e.hit.hit:
		return
	view.grabbing = false
	var p: Vector3 = e.hit.position
	var hit := draft.scene.ray_down(p.x, p.z, p.y + 0.5, false)
	if not hit.hit:
		editor.say("Nothing there")
		return
	_focus_material = SceneTrack.material_group(String(hit.material))
	editor.say("%s: %s" % [_label(_focus_material), NAMES.get(hit.tag, "Untagged")])
	editor.refresh_panel()
	for c in editor._content.get_children():
		if c is Button and c.has_meta(&"material") and String(c.get_meta(&"material")) == _focus_material:
			UiKit.focus_later(c)


func draft_changed(what: StringName) -> void:
	if what in [&"scene", &"road"] and editor.tool == self:
		editor.refresh_panel()


func panel() -> Array:
	var scene := draft.scene
	var tags: Dictionary = scene.tags
	var out := [_text("%d surfaces, %d materials, %d triangles." % [scene.surfaces.size(), scene.materials().size(), scene.triangles])]
	var drivable := scene.surfaces.filter(func(s: Dictionary) -> bool: return s.tag in SceneTrack.DRIVABLE).size()
	if drivable == 0:
		out.append(_text("Nothing is tagged to drive on yet."))
	out.append(UiKit.label("Materials", 26))
	for m: Array in scene.materials():
		var name: String = m[0]
		var own := (m[2] as Array).any(func(n: String) -> bool: return (tags.materials as Dictionary).has(n))
		var b := UiKit.spinner("%s%s" % [_label(name), "" if own else " (rules)"], tag_items(true), scene.material_tag(name),
			func(tag: String) -> void: _set_material(name, tag), "%d surfaces" % m[1])
		b.set_meta(&"material", name)
		out.append(b)
	out.append(UiKit.button("Apply rules", _apply_rules, "Every material follows the rules below again"))
	out.append(UiKit.label("Rules", 26))
	for k in (tags.rules as Array).size():
		var r: Dictionary = tags.rules[k]
		out.append(UiKit.spinner(String(r.match), tag_items(), String(r.tag), func(tag: String) -> void: _set_rule(k, tag), "Names like this"))
	out.append(UiKit.text_field("New rule", "", func(_t: String) -> void: pass, 64, "A name pattern, like *road*: Enter adds it as asphalt", _add_rule))
	out.append(UiKit.spinner("Everything else", tag_items(true), String(tags.default), func(tag: String) -> void:
		var t := scene.tags.duplicate(true)
		t.default = tag
		draft.set_scene_tags(t, "Untagged surfaces")))
	out.append(UiKit.spinner("Style", [["own", "The scene's own"], ["retro", "Retro"]], String(tags.style), func(style: String) -> void:
		var t := scene.tags.duplicate(true)
		t.style = style
		draft.set_scene_tags(t, "Scene style"), "Retro makes its textures small and sharp"))
	out.append(UiKit.label("Road", 26))
	out.append(UiKit.button("Measure widths", _measure, "Read the road's width at each point off the scene"))
	return out


## Tags every material of group `name` (grey, grey2, ...).
func _set_material(name: String, tag: String) -> void:
	var t := draft.scene.tags.duplicate(true)
	for m: Array in draft.scene.materials():
		if m[0] == name:
			for material: String in m[2]:
				t.materials[material] = tag
	_focus_material = name
	draft.set_scene_tags(t, "Tag " + _label(name))
	editor.say("%s: %s" % [_label(name), NAMES.get(tag, "Untagged")])


func _apply_rules() -> void:
	var t := draft.scene.tags.duplicate(true)
	t.materials = {}
	t.meshes = {}
	draft.set_scene_tags(t, "Apply rules")
	editor.say("Rules applied")


func _set_rule(k: int, tag: String) -> void:
	var t := draft.scene.tags.duplicate(true)
	t.rules[k].tag = tag
	draft.set_scene_tags(t, "Change rule")


func _add_rule(pattern: String) -> void:
	pattern = pattern.strip_edges().left(64)
	if pattern.is_empty():
		return
	if not pattern.contains("*"):
		pattern = "*%s*" % pattern
	var t := draft.scene.tags.duplicate(true)
	(t.rules as Array).insert(0, { "match": pattern, "tag": "asphalt" })
	draft.set_scene_tags(t, "Add rule")
	editor.say("Rule %s added" % pattern)


func _measure() -> void:
	var t := draft.track()
	if t.samples.size() < 3:
		editor.say("Click along the road first (Road tool)")
		return
	var widths := draft.scene.measure_widths(t)
	if widths.is_empty():
		editor.say("No road under the points")
		return
	draft.set_point_attrs(widths, "Measure widths")
	editor.say("Widths measured at %d of %d points" % [widths.size(), draft.points().size()])


static func _label(material: String) -> String:
	return material if material else "Unnamed material"


static func _text(t: String) -> Label:
	var l := UiKit.label(t, 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
