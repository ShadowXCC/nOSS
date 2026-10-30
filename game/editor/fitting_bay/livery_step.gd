class_name LiveryStep
extends RefCounted
## The Fitting Bay's Livery step (docs/VEHICLE_PACKAGE.md §7, §12; docs/UI_FLOW.md §12): the car's
## liveries (which it wears, which is edited), the edited one's base paint, its layers, the picked
## layer's look and its place on the car. Everything here works from the list alone (keyboard,
## pad, screen reader); the 3D view adds pointing at the car (LiveryView).

const FINISHES := [["paint", "Like the paint"], ["gloss", "Gloss"], ["satin", "Satin"], ["matte", "Matte"],
	["metallic", "Metallic"], ["chrome", "Chrome"], ["pearl", "Pearl"]]
const COLOR_FROM := [["own", "Own colour"], ["primary", "Primary paint"], ["secondary", "Secondary paint"],
	["tertiary", "Tertiary paint"], ["contrast", "Contrast"]]
const CATEGORIES := [["basic", "Basic"], ["racing", "Racing"], ["graphics", "Graphics"], ["plates", "Plates"], ["sponsors", "Sponsors"]]
const ICON := preload("res://game/vehicles/livery/livery_icon.gdshader")

var bay: FittingBay


func _init(fitting_bay: FittingBay) -> void:
	bay = fitting_bay


func edit() -> LiveryEdit:
	return bay._livery_edit()


func build() -> Array:
	var e := edit()
	var out := []
	out.append(_heading("Liveries"))
	if bay.draft.liveries.is_empty():
		out.append(FittingBay._text("No liveries yet. Make one to add shapes, text and numbers."))
		out.append(UiKit.button("New livery", _do.bind(e.new_livery), "A livery with the car's paint"))
		return out
	var l := e.livery()
	var worn: Array = [["", "Plain paint"]]
	var editable: Array = []
	for x: Dictionary in bay.draft.liveries:
		worn.append([x.id, x.name])
		editable.append([x.id, x.name])
	out.append(UiKit.spinner("Wears", worn, bay.draft.worn, func(v: String) -> void:
		e.wear(v)
		bay._set_status("Wears " + String(e.livery().name if v == e.livery().id else _name_of(v))), "The livery the car wears in races"))
	out.append(UiKit.spinner("Editing", editable, bay.draft.editing, func(v: String) -> void:
		e.edit(v)
		bay._show_step("Livery", true), "The livery shown and changed here"))
	out.append(UiKit.text_field("Name", String(l.name), func(t: String) -> void: e.rename(t), LiveryData.MAX_NAME))
	out.append(_row([
		UiKit.button("New", _do.bind(e.new_livery), "A new livery with the car's paint"),
		UiKit.button("Copy", _do.bind(e.copy_livery), "A copy of this livery"),
		UiKit.button("Delete", _do.bind(e.delete_livery), "Delete this livery (Undo brings it back)"),
	]))
	out.append_array(_extra_livery_rows())

	out.append(_heading("Paint"))
	var base: Dictionary = l.get("base", {})
	for slot: String in ["primary", "secondary", "tertiary"]:
		if not bay.draft.paint.get("slots", {}).has(slot):
			continue
		var own: Dictionary = bay.draft.paint.slots[slot]
		var now: Dictionary = base.get(slot, own)
		var state := { "color": Color.html(now.color), "finish": String(now.finish) }
		out.append(UiKit.color(slot.capitalize() + " colour", state.color, func(c: Color) -> void:
			state.color = c
			e.set_base(slot, c, state.finish)
			bay._show_livery()))
		out.append(UiKit.spinner(slot.capitalize() + " finish", FittingBay.FINISHES, state.finish, func(v: String) -> void:
			state.finish = v
			e.set_base(slot, state.color, v)
			bay._show_livery()))

	out.append(_heading("Layers"))
	out.append(_row([
		UiKit.button("Add shape…", _shape_picker, "Pick a shape to add"),
		UiKit.button("Add text", _do.bind(e.add.bind("text")), "Add a line of text"),
		UiKit.button("Add number", _do.bind(e.add.bind("number")), "Add a race number"),
	]))
	out.append(_row([
		UiKit.button("Undo", _do.bind(e.undo), "Ctrl+Z"),
		UiKit.button("Redo", _do.bind(e.redo), "Ctrl+Y"),
		UiKit.button("Layers…", _layer_list, "Every layer, top first"),
	]))
	var c := e.current()
	if c.is_empty():
		out.append(FittingBay._text("No layers yet."))
		return out
	var items := []
	for i in range(e.layers().size() - 1, -1, -1):
		items.append([i, e.layer_label(i)])
	out.append(UiKit.spinner("Layer", items, e.layer, func(v: int) -> void:
		e.layer = v
		bay._show_step("Livery", true), "The layer to change"))
	out.append_array(_properties(e, c))
	out.append_array(_placement(e))
	return out


func _properties(e: LiveryEdit, c: Dictionary) -> Array:
	var out := [_heading("Look")]
	if c.kind == "shape":
		var s := LiveryData.shape(String(c.shape))
		var names: Array = s.get("param_names", [])
		for i in names.size():
			out.append(UiKit.number(String(names[i]), float(c.params[i]), 0.0, 1.0, 0.01, "%.2f", func(v: float) -> void:
				var p: Array = (c.params as Array).duplicate()
				p[i] = v
				e.set_value("params", p, true)
				bay._show_livery()))
	elif c.kind == "text":
		out.append(UiKit.text_field("Text", String(c.text), func(t: String) -> void:
			if t.strip_edges():
				e.set_value("text", t.strip_edges().left(LiveryData.MAX_TEXT), true)
				bay._show_livery(), LiveryData.MAX_TEXT))
	else:
		var auto: bool = c.number == "auto"
		out.append(UiKit.spinner("Number", [["auto", "Racer's own"], ["fixed", "Fixed"]], "auto" if auto else "fixed", func(v: String) -> void:
			e.set_value("number", "auto" if v == "auto" else "1")
			bay._show_step("Livery", true), "Each racer's own number, or always the same"))
		if not auto:
			out.append(UiKit.text_field("Digits", String(c.number), func(t: String) -> void:
				if t.is_valid_int() and not t.begins_with("-") and not t.begins_with("+"):
					e.set_value("number", t, true)
					bay._show_livery(), 3))
	if c.kind != "shape":
		var fonts: Array = LiveryData.catalog().font_list.map(func(f: Dictionary) -> Array: return [f.id, f.name])
		out.append(UiKit.spinner("Font", fonts, String(c.font), func(v: String) -> void:
			e.set_value("font", v)
			bay._show_livery(), "The lettering"))
	var linked: bool = c.color in LiveryData.LINKS
	out.append(UiKit.spinner("Colour from", COLOR_FROM, c.color if linked else "own", func(v: String) -> void:
		e.set_value("color", "#FFFFFF" if v == "own" else v)
		bay._show_step("Livery", true), "Its own colour, or one of the car's"))
	if not linked:
		out.append(UiKit.color("Colour", Color.html(c.color), func(col: Color) -> void:
			e.set_value("color", "#" + col.to_html(false).to_upper(), true)
			bay._show_livery()))
	out.append(UiKit.slider("Opacity", float(c.opacity), func(v: float) -> void:
		e.set_value("opacity", snappedf(v, 0.01), true)
		bay._show_livery()))
	out.append(UiKit.spinner("Finish", FINISHES, String(c.finish), func(v: String) -> void:
		e.set_value("finish", v)
		bay._show_livery()))
	var surfaces := []
	for slot: String in ["primary", "secondary", "tertiary"]:
		if bay.draft.paint.get("slots", {}).has(slot):
			surfaces.append(slot)
	if not (bay.draft.paint.get("glass", []) as Array).is_empty():
		surfaces.append("glass")
	for surface: String in surfaces:
		out.append(UiKit.check("On " + surface, surface in c.on, func(on: bool) -> void:
			e.set_on(surface, on)
			bay._show_livery(), "Lands on the %s %s" % [surface, "" if surface == "glass" else "paint"]))
	out.append(UiKit.check("Cut-out", c.get("cut", false), func(on: bool) -> void:
		e.set_value("cut", on)
		bay._show_livery(), "Cuts through the layers under it (in its group) instead of drawing"))
	out.append(UiKit.check("Mirror", c.get("mirror", false), func(on: bool) -> void:
		e.set_value("mirror", on)
		bay._show_livery(), "Also on the other side of the car"))
	out.append(UiKit.check("Hidden", c.get("hidden", false), func(on: bool) -> void:
		e.set_value("hidden", on)
		bay._show_livery(), "Kept, but not drawn"))
	var groups: Array = [[0, "None"]]
	for g: Dictionary in e.livery().get("groups", []):
		groups.append([int(g.id), String(g.name)])
	groups.append([-1, "New group"])
	out.append(UiKit.spinner("Group", groups, int(c.get("group", 0)), func(v: int) -> void:
		var said := e.set_group(v)
		bay._show_step("Livery", true)
		bay._set_status(said), "Grouped layers move together, and a cut-out cuts only its group"))
	if c.get("group"):
		out.append(UiKit.check("Whole group", e.whole_group, func(on: bool) -> void: e.whole_group = on,
			"Moving, turning and sizing take the whole group"))
	return out


func _placement(e: LiveryEdit) -> Array:
	var p := e.placement()
	var box := e._bounds()
	var axes := LiveryEdit._axes(p.side)
	var span := func(axis: Vector3) -> Vector2:
		var a := box.position.dot(axis)
		var b := box.end.dot(axis)
		return Vector2(minf(a, b) - 0.2, maxf(a, b) + 0.2)
	var along: Vector2 = span.call(axes[0])
	var up: Vector2 = span.call(axes[1])
	var out := [_heading("Place")]
	out.append(UiKit.spinner("Side", LiveryEdit.SIDE_NAMES, p.side, func(v: String) -> void:
		var said := e.place_side(v)
		bay._show_step("Livery", true)
		bay._set_status(said), "The side of the car it's on"))
	out.append(UiKit.number("Along", clampf(p.along, along.x, along.y), along.x, along.y, 0.01, "%.2f m", func(v: float) -> void:
		e.slide("along", v)
		bay._show_livery()))
	out.append(UiKit.number("Height" if p.side != "top" else "Across", clampf(p.height, up.x, up.y), up.x, up.y, 0.01, "%.2f m", func(v: float) -> void:
		e.slide("height", v)
		bay._show_livery()))
	out.append(UiKit.number("Size", p.size, LiveryEdit.MIN_SIZE, 6.0, 0.01, "%.2f m", func(v: float) -> void:
		e.set_size(v)
		bay._show_livery(), "Its longer side"))
	out.append(UiKit.number("Stretch", p.stretch, 0.1, 8.0, 0.01, "%.2f", func(v: float) -> void:
		e.set_stretch(v)
		bay._show_livery(), "Width over height"))
	out.append(UiKit.number("Turn", p.turn, -180.0, 180.0, 1.0, "%d°", func(v: float) -> void:
		e.set_turn(v)
		bay._show_livery()))
	out.append(UiKit.spinner("Flip", LiveryEdit.FLIPS, p.flip, func(v: String) -> void:
		e.set_flip(v)
		bay._show_livery()))
	out.append(UiKit.number("Depth", p.depth, 0.01, 2.0, 0.01, "%.2f m", func(v: float) -> void:
		e.set_depth(v)
		bay._show_livery(), "How far in and out it reaches over the body"))
	out.append(_row([
		UiKit.button("Place on car", bay._place_on_car, "Point at the car to put it there"),
		UiKit.button("Duplicate", _do.bind(e.duplicate_layer), "Ctrl+D"),
		UiKit.button("Mirror copy", _do.bind(e.mirror_copy), "A copy on the other side of the car"),
	]))
	out.append(_row([
		UiKit.button("Up", _do.bind(e.reorder.bind("up")), "Over the layer above"),
		UiKit.button("Down", _do.bind(e.reorder.bind("down")), "Under the layer below"),
		UiKit.button("Top", _do.bind(e.reorder.bind("top")), "Over every layer"),
		UiKit.button("Bottom", _do.bind(e.reorder.bind("bottom")), "Under every layer"),
	]))
	out.append(UiKit.button("Delete layer", _do.bind(e.delete_layer), "Del"))
	return out


## Livery rows that come with sharing (Import…, Export…, From car…).
func _extra_livery_rows() -> Array:
	return []


## Runs an edit that changes the list, then shows the step again and says what happened.
func _do(fn: Callable) -> void:
	var said: Variant = fn.call()
	bay._show_step("Livery", true)
	if said is String and said:
		bay._set_status(said)


func _name_of(id: String) -> String:
	for x: Dictionary in bay.draft.liveries:
		if x.id == id:
			return String(x.name)
	return "plain paint" if id.is_empty() else id


# --- pickers -----------------------------------------------------------------------


## The shapes, by kind, each with its picture and name.
func _shape_picker() -> void:
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(menu, "Add shape", 1180)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 760)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.add_child(scroll)
	UiKit.keep_in_view(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var buttons: Array[Button] = []
	for cat: Array in CATEGORIES:
		var shapes: Array = LiveryData.catalog().shape_list.filter(func(s: Dictionary) -> bool: return s.category == cat[0])
		if shapes.is_empty():
			continue
		body.add_child(UiKit.label(cat[1], 30))
		var flow := HFlowContainer.new()
		body.add_child(flow)
		for s: Dictionary in shapes:
			var b := _shape_button(s)
			flow.add_child(b)
			buttons.append(b)
	var cancel := UiKit.button("Cancel", bay._close_overlay)
	list.add_child(cancel)
	bay._show_overlay(menu)
	if not buttons.is_empty():
		UiKit.focus_later(buttons[0])


func _shape_button(s: Dictionary) -> Button:
	var span := int(s.get("span", 1))
	var b := Button.new()
	b.custom_minimum_size = Vector2(120 * span + 20 * (span - 1), 150)
	b.accessibility_name = String(s.name)
	b.accessibility_description = "Add it"
	b.tooltip_text = String(s.name)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 8
	box.offset_bottom = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	box.add_child(icon(s, Vector2(0, 96)))
	var name := UiKit.label(String(s.name), 20)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	b.pressed.connect(func() -> void:
		bay._close_overlay()
		_do(edit().add.bind("shape", String(s.id))))
	return b


## A shape's picture, drawn by the livery shader's own code.
static func icon(s: Dictionary, min_size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = PlaceholderTexture2D.new()
	t.custom_minimum_size = min_size
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = ICON
	var code := int(s.get("index", 0))
	if s.get("kind") == "atlas":
		code += LiveryRenderer.ATLAS_CODE + 256 * (int(s.get("span", 1)) - 1)
	var params := Vector4.ZERO
	var p: Array = s.get("params", [])
	for i in mini(p.size(), 4):
		params[i] = float(p[i])
	m.set_shader_parameter("code", code)
	m.set_shader_parameter("params", params)
	m.set_shader_parameter("aspect", float(s.get("span", 1)))
	m.set_shader_parameter("shapes", LiveryRenderer.shapes_atlas())
	t.material = m
	return t


## Every layer, top first: pressing one picks it.
func _layer_list() -> void:
	var e := edit()
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(menu, "Layers", 760)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.add_child(scroll)
	UiKit.keep_in_view(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var buttons := []
	for i in range(e.layers().size() - 1, -1, -1):
		var b := UiKit.button(e.layer_label(i), func() -> void:
			e.layer = i
			bay._close_overlay()
			bay._show_step("Livery", true), "Pick it")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.add_child(b)
		buttons.append(b)
	if buttons.is_empty():
		body.add_child(UiKit.label("No layers yet"))
	var close := UiKit.button("Close", bay._close_overlay)
	list.add_child(close)
	buttons.append(close)
	bay._show_overlay(menu)
	UiKit.chain_focus(buttons)


static func _heading(text: String) -> Label:
	return UiKit.label(text, 30)


static func _row(buttons: Array) -> HFlowContainer:
	var row := HFlowContainer.new()
	for b: Button in buttons:
		b.custom_minimum_size = Vector2(0, 52)
		row.add_child(b)
	return row
