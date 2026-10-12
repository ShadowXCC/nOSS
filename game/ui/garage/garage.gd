class_name Garage
extends Control
## The garage (docs/VEHICLE_PACKAGE.md §8, PKG-05): every car with its thumbnail and details,
## a turntable preview, and drive, edit, duplicate, paint, sound and delete. Built-in cars
## can be driven, copied and edited as a copy.

const FONT_SIZE := 24
const COLUMNS := 3
const CARD := Vector2(300, 196)

var _cars: Array[Dictionary] = []
var _selected := -1
var _grid: GridContainer
var _cards: Array[Button] = []
var _preview: BayPreview
var _details: VBoxContainer
var _status: Label
var _loading := ""
var _overlay: Control
var _back_button: Button
## The selected car's enabled action buttons; the one that opened the overlay gets focus back.
var _actions: Array[Button] = []
var _last_action: Button


func _ready() -> void:
	var t := UiKit.theme().duplicate() as Theme
	t.default_font_size = FONT_SIZE
	theme = t
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 0)
	add_child(split)

	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(COLUMNS * (CARD.x + 16) + 40, 0)
	split.add_child(left)
	var list := VBoxContainer.new()
	left.add_child(list)
	list.add_child(UiKit.label("Garage", 38))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_grid)
	_back_button = UiKit.button("Back", _back, "Back to the title screen")
	list.add_child(_back_button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_preview = BayPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.turntable = true
	right.add_child(_preview)
	var info := PanelContainer.new()
	right.add_child(info)
	_details = VBoxContainer.new()
	info.add_child(_details)
	_status = UiKit.label("", 22)
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	right.add_child(_status)
	_reload()


func _reload(select_path := "") -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_cars = GarageFiles.list()
	var select := 0
	for i in _cars.size():
		var car := _cars[i]
		var m: Dictionary = car.manifest
		var b := Button.new()
		b.custom_minimum_size = CARD
		b.text = String(m.name)
		b.clip_text = true
		b.icon = car.thumbnail
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.accessibility_name = String(m.name)
		b.accessibility_description = "%s by %s, %s" % [_family_name(m.family), m.author, "built in" if car.official else "your car"]
		b.pressed.connect(_open_actions.bind(i))
		b.focus_entered.connect(_select.bind(i))
		_grid.add_child(b)
		_cards.append(b)
		if car.path == select_path:
			select = i
	_link_grid_focus()
	if not _cards.is_empty():
		_cards[select].grab_focus.call_deferred()
		_select(select)


## Arrow keys and pads move around the grid; down from the last row goes to Back. Confirm on a
## car goes to its actions, and back from there returns to the car.
func _link_grid_focus() -> void:
	for i in _cards.size():
		var c := _cards[i]
		var left := _cards[i - 1] if i % COLUMNS > 0 else c
		var right := _cards[i + 1] if i % COLUMNS < COLUMNS - 1 and i + 1 < _cards.size() else c
		var up := _cards[i - COLUMNS] if i >= COLUMNS else c
		var down: Control = _cards[i + COLUMNS] if i + COLUMNS < _cards.size() else _back_button
		c.focus_neighbor_left = c.get_path_to(left)
		c.focus_neighbor_right = c.get_path_to(right)
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_neighbor_bottom = c.get_path_to(down)
	if not _cards.is_empty():
		_back_button.focus_neighbor_top = _back_button.get_path_to(_cards[-1])
		_back_button.focus_neighbor_bottom = _back_button.get_path_to(_cards[0])


## The car's actions take the focus (confirm on its card).
func _open_actions(i: int) -> void:
	_select(i)
	if not _actions.is_empty():
		_actions[0].grab_focus()


func _focus_in_actions() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and _actions.has(f)


func _select(i: int) -> void:
	if i == _selected and _details.get_child_count() > 0:
		return
	_selected = i
	_last_action = null
	var car := _cars[i]
	var m: Dictionary = car.manifest
	for child in _details.get_children():
		child.queue_free()
	_details.add_child(UiKit.label(String(m.name), 32))
	var line := "%s · %s · %s triangles" % [_family_name(m.family), m.license, _thousands(car.triangles)]
	_details.add_child(UiKit.label("By %s · version %d" % [m.author, int(m.get("version", 1))], FONT_SIZE))
	_details.add_child(UiKit.label(line, FONT_SIZE))
	var actions := HFlowContainer.new()
	var buttons := [
		UiKit.button("Drive", _drive, "Pick a class and drive this car"),
		UiKit.button("Edit", _edit.bind(""), "Open in the Fitting Bay" + (" as a copy" if car.official else "")),
		UiKit.button("Paint", _paint, "Change its colours"),
		UiKit.button("Sound", _edit.bind("Sound"), "Tune its engine sound"),
		UiKit.button("Duplicate", _duplicate, "Make a copy in the garage"),
		UiKit.button("Copy sound to…", _copy_sound, "Give another car this engine sound"),
		UiKit.button("Delete", _delete, "Delete this car"),
	]
	_actions.clear()
	for b: Button in buttons:
		b.custom_minimum_size = Vector2(0, 52)
		if car.official and b.text in ["Paint", "Delete", "Sound"]:
			b.disabled = true
			b.focus_mode = Control.FOCUS_NONE
		else:
			_actions.append(b)
			b.pressed.connect(func() -> void: _last_action = b)
		actions.add_child(b)
	_details.add_child(actions)
	# Left/right and up/down both step through the enabled actions.
	UiKit.chain_focus(_actions, false)
	for k in _actions.size():
		_actions[k].focus_neighbor_left = _actions[k].focus_neighbor_top
		_actions[k].focus_neighbor_right = _actions[k].focus_neighbor_bottom
	# Load the car for the turntable.
	_preview.clear()
	_loading = car.path
	PackageLoader.load_async(car.path, func(pkg: VehiclePackage) -> void:
		if not is_inside_tree() or _loading != pkg.path:
			pkg.free_scenes()
			return
		if not pkg.ok():
			_status.text = "Car failed to load"
			return
		_preview.show_package(pkg, _platform_for(m.family))
		if car.thumbnail == null:
			_render_thumbnail(i))


## A car without a thumbnail gets one from the turntable view.
func _render_thumbnail(i: int) -> void:
	await get_tree().process_frame
	var png: PackedByteArray = await _preview.thumbnail()
	if png.is_empty() or i >= _cars.size():
		return
	GarageFiles.cache_thumbnail(_cars[i].path, png)
	_cars[i].thumbnail = GarageFiles.thumbnail(_cars[i].path)
	if i < _cards.size():
		_cards[i].icon = _cars[i].thumbnail


func _drive() -> void:
	var path: String = _cars[_selected].path
	var family: String = _cars[_selected].manifest.family
	var classes := ClassPicker.new()
	classes.current = String(Settings.profile.get("last_platform", ""))
	classes.family = family
	classes.picked.connect(func(id: String) -> void:
		_preview.clear()
		Game.start_free_drive(path, id))
	classes.closed.connect(_close_overlay)
	_show_overlay(classes)


func _edit(step: String) -> void:
	var path: String = _cars[_selected].path
	_status.text = "Loading"
	PackageLoader.load_async(path, func(pkg: VehiclePackage) -> void:
		if not pkg.ok():
			_status.text = "Car failed to load"
			pkg.free_scenes()
			return
		var draft := FittingDraft.from_package(pkg)
		pkg.free_scenes()
		Game.bay_draft = draft
		_preview.clear()
		Game.open_fitting_bay("", step if step else "Import"))


func _paint() -> void:
	var car := _cars[_selected]
	var files := GarageFiles.read_files(car.path)
	var paint: Variant = JSON.parse_string((files.get("paint.json", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if not paint is Dictionary or (paint.get("slots", {}) as Dictionary).is_empty():
		_status.text = "This car has no paint slots. Set them in the Fitting Bay."
		return
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(menu, "Paint", 720)
	# Presets and colours scroll; Save and Cancel stay in view below them.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var controls := []
	for preset: Dictionary in paint.get("presets", []):
		controls.append(UiKit.button(String(preset.name), func() -> void:
			for slot: String in paint.slots:
				if preset.has(slot):
					paint.slots[slot].color = preset[slot]
				if preset.has("finish") and slot == "primary":
					paint.slots[slot].finish = preset.finish
			_apply_paint(paint)))
	for slot: String in paint.slots:
		var data: Dictionary = paint.slots[slot]
		controls.append(UiKit.color(slot.capitalize(), Color.html(data.color), func(c: Color) -> void:
			data.color = "#" + c.to_html(false).to_upper()
			_paint_preview(slot, data)))
		controls.append(UiKit.option(slot.capitalize() + " finish", FittingBay.FINISHES, data.finish, func(v: String) -> void:
			data.finish = v
			_paint_preview(slot, data)))
	for c: Control in controls:
		rows.add_child(c)
	for c: Control in [UiKit.button("Save", func() -> void: _save_paint(paint)), UiKit.button("Cancel", _close_overlay)]:
		list.add_child(c)
		controls.append(c)
	_show_overlay(menu)
	UiKit.chain_focus(controls)


func _apply_paint(paint: Dictionary) -> void:
	for slot: String in paint.slots:
		_paint_preview(slot, paint.slots[slot])


func _paint_preview(slot: String, data: Dictionary) -> void:
	if _preview.visual:
		_preview.visual.set_paint(slot, Color.html(data.color), data.finish)


func _save_paint(paint: Dictionary) -> void:
	var path: String = _cars[_selected].path
	var result := GarageFiles.update(path, { "paint.json": PackageWriter.canonical_json(paint).to_utf8_buffer() })
	_close_overlay()
	_status.text = "Paint saved" if result.ok else String(result.error)
	if result.ok:
		_selected = -1
		_reload(path)


func _duplicate() -> void:
	var result := GarageFiles.copy_car(_cars[_selected].path)
	_status.text = "Copy made" if result.ok else String(result.error)
	if result.ok:
		_selected = -1
		_reload(result.path)


func _copy_sound() -> void:
	var source: String = _cars[_selected].path
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(menu, "Copy sound to", 720)
	var controls := []
	for car in _cars:
		if car.official or car.path == source:
			continue
		controls.append(UiKit.button(String(car.manifest.name), func() -> void:
			var result := GarageFiles.copy_sound(source, car.path)
			_close_overlay()
			_status.text = "Sound copied to %s" % car.manifest.name if result.ok else String(result.error)
			_selected = -1
			_reload(source)))
	if controls.is_empty():
		list.add_child(UiKit.label("No other cars in the garage"))
	controls.append(UiKit.button("Cancel", _close_overlay))
	for c: Control in controls:
		list.add_child(c)
	_show_overlay(menu)
	UiKit.chain_focus(controls)


func _delete() -> void:
	var car := _cars[_selected]
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(menu, "Delete %s?" % car.manifest.name, 720)
	var yes := UiKit.button("Delete", func() -> void:
		_preview.clear()
		var err := GarageFiles.delete(car.path)
		_close_overlay()
		_status.text = err if err else "Deleted"
		_selected = -1
		_reload())
	var no := UiKit.button("Keep", _close_overlay)
	list.add_child(yes)
	list.add_child(no)
	_show_overlay(menu)
	UiKit.chain_focus([no, yes])


func _show_overlay(control: Control) -> void:
	_close_overlay()
	_overlay = control
	add_child(control)


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if is_instance_valid(_last_action) and _last_action.is_inside_tree():
		_last_action.grab_focus.call_deferred()
	elif _selected >= 0 and _selected < _cards.size():
		_cards[_selected].grab_focus.call_deferred()


func _back() -> void:
	_preview.clear()
	Game.go_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_overlay):
			_close_overlay()
		elif _focus_in_actions() and _selected >= 0 and _selected < _cards.size():
			_cards[_selected].grab_focus()
		else:
			_back()


## A platform that can show a car of `family` (for the turntable's fit).
static func _platform_for(family: String) -> Dictionary:
	for mode in GameModes.list():
		for r in GameModes.classes(mode):
			if Fitting.compatible(r.platform, family):
				return r.platform
	return PlatformLoader.load_official(TrackSession.DEFAULT_PLATFORM).platform


static func _family_name(family: String) -> String:
	return { "car": "Car", "open": "Open-wheel", "truck": "Truck", "moto": "Motorbike" }.get(family, family)


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(-3)
	return s + out
