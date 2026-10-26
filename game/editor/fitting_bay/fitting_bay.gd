class_name FittingBay
extends Control
## The Fitting Bay (docs/VEHICLE_PACKAGE.md §7, PKG-02…04, PKG-07): turns a GLB, glTF or FBX
## into a .noss. Import works out the wheels, orientation, scale and the rest on its own, so
## "Save and drive" works straight away; the other steps adjust what it found. The draft is
## kept in user://fitting/ and survives test drives. The Import step also lists the cars that
## came from online games (docs/NETWORKING.md §7), to keep, export or fit.

signal closed

const STEPS := ["Import", "Orient", "Wheels", "Scale", "Paint", "Cockpit", "Sound", "Save"]
const IMPORT_DIR := "user://import/"
const FONT_SIZE := 24
const FAMILIES := [["car", "Car"], ["open", "Open-wheel"], ["truck", "Truck"]]
const FINISHES := [["solid", "Solid"], ["metallic", "Metallic"], ["pearl", "Pearl"], ["matte", "Matte"], ["chrome", "Chrome"]]
## The Wheel choice for making a new wheel.
const NEW_WHEEL := "new"
## Ride height slider range (m, fit.json body_lift_m).
const LIFT_MIN := -0.3
const LIFT_MAX := 0.6
## The body may sit this far into the ground (m) before the bay says so (a tyre's bulge).
const CLIP_TOLERANCE := 0.02

var draft: FittingDraft
var platform_id := ""
## Dev: import this file on open; with auto, save and drive as soon as it's in.
var import_path := ""
var auto := false
## Step to open on with a draft already in (e.g. "Sound" from the garage). Empty: Import, or
## Save when coming back from a test drive.
var start_step := ""

var _preview: BayPreview
var _content: VBoxContainer
var _status: Label
var _step := "Import"
var _step_buttons := {}
var _drive_button: Button
var _save_button: Button
var _dialog: FileDialog
var _busy := false
## The car last saved to the garage from here, for the Garage to pick on the way back.
var _saved_path := ""
## Import progress: the bar, what the worker is reporting into, and the Import step's buttons
## (greyed while a file is coming in).
var _progress: VBoxContainer
var _progress_src: ModelImport.Progress
var _import_buttons: Array[Button] = []
## The "already in your garage" question, what to undo if it's dismissed, and the control to
## give the focus back to.
var _overlay: Control
var _overlay_cancel := Callable()
var _overlay_focus: Control
var _t_open := 0
var _engine: EngineSound
var _rev_time := 0.0
## Skid button: the tires squeal, then a wheel locks.
var _skid_time := 0.0
var _sound_json := ""
var _audio_dialog: FileDialog
## Own recordings: what the next file is for (an emitter or an extra), its rpm and load.
var _rec_target := "exhaust"
var _rec_rpm := 3000.0
var _rec_kind := "on"
## Wheels step: the wheel being edited (an id, or NEW_WHEEL), whether its partner follows.
var _wheel_edit: WheelEdit
var _wheel_id := ""
var _mirror := true


func _ready() -> void:
	_t_open = Time.get_ticks_msec()
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

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660, 0)
	split.add_child(panel)
	var side := VBoxContainer.new()
	panel.add_child(side)
	var title := UiKit.label("Fitting Bay", 38)
	side.add_child(title)
	var steps := HFlowContainer.new()
	for step in STEPS:
		var b := UiKit.button(step, _show_step.bind(step), "Fitting step: " + step)
		b.custom_minimum_size = Vector2(0, 48)
		b.toggle_mode = true
		steps.add_child(b)
		_step_buttons[step] = b
	side.add_child(steps)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_progress = UiKit.progress()
	_progress.visible = false
	side.add_child(_progress)
	_status = UiKit.label("", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	side.add_child(_status)
	var actions := HBoxContainer.new()
	_drive_button = UiKit.button("Save and drive", _save_and_drive, "Save the car to the garage and drive it")
	_save_button = UiKit.button("Save", _save, "Save the car to the garage")
	var exit := UiKit.button("Exit", _exit, "Back to the Garage" if Game.bay_from == "garage" else "Back to the main menu")
	for b in [_drive_button, _save_button, exit]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	side.add_child(actions)

	_preview = BayPreview.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.part_clicked.connect(_on_part_clicked)
	split.add_child(_preview)

	if draft == null and Game.bay_draft is FittingDraft:
		draft = Game.bay_draft
	if draft:
		_choose_platform()
		_refresh()
		_show_step(start_step if start_step else "Save")
	else:
		_show_step("Import")
	if import_path:
		_import(import_path)


# --- steps -------------------------------------------------------------------


## Shows `step`. With `keep_focus` the focus stays where it was in the list (the step built
## again after a change made from it) rather than going to the top.
func _show_step(step: String, keep_focus := false) -> void:
	if draft == null and step != "Import":
		step = "Import"
	var focus_at := _focus_index() if keep_focus and step == _step else -1
	_step = step
	for s: String in _step_buttons:
		_step_buttons[s].button_pressed = s == step
		_step_buttons[s].disabled = draft == null and s != "Import"
	for child in _content.get_children():
		child.queue_free()
	if step != "Sound":
		_stop_engine()
	_preview.overlays = {
		"forward": step in ["Import", "Orient"], "wheels": step in ["Wheels", "Import"], "envelope": step == "Scale",
		"cockpit": step == "Cockpit",
	}
	if step != "Cockpit" and _preview.view != "orbit":
		_preview.set_view("orbit", draft)
	var controls: Array = call("_step_" + step.to_lower())
	controls = controls.filter(func(c: Variant) -> bool: return c is Control)
	for c: Control in controls:
		if c.get_parent() == null:
			_content.add_child(c)
	var chain := _focusable(controls) + [_step_buttons[step], _drive_button, _save_button]
	UiKit.chain_focus(chain, focus_at < 0)
	if focus_at >= 0:
		var targets := chain.map(func(c: Control) -> Control: return UiKit._focus_target(c)).filter(func(c: Control) -> bool: return c != null)
		UiKit.focus_later(targets[mini(focus_at, targets.size() - 1)])
	_sync_wheel_view()
	_refresh(false)
	_update_actions()


## Where the focus is among the step's controls (as chained), or -1.
func _focus_index() -> int:
	var owner := UiKit.focus_owner(self) if is_inside_tree() else null
	if owner == null:
		return -1
	var i := 0
	for c in _content.get_children():
		if c is Label or c.is_queued_for_deletion():
			continue
		var target := UiKit._focus_target(c)
		if target == owner:
			return i
		if target:
			i += 1
	return -1


func _step_import() -> Array:
	var out := []
	_import_buttons.clear()
	if draft == null:
		out.append(_text("Pick a .glb, .gltf, .fbx or .noss file. It doesn't need any preparation."))
		_import_buttons.append(UiKit.button("Browse…", _browse, "Choose a car or model file"))
		DirAccess.make_dir_recursive_absolute(IMPORT_DIR)
		var files := _import_folder_files()
		out.append(_import_buttons[0])
		out.append(_text("Or put files in the import folder:" if files.is_empty() else "From the import folder:"))
		for f in files:
			_import_buttons.append(UiKit.button(f, _import.bind(IMPORT_DIR + f), "Import " + f))
			out.append(_import_buttons[-1])
		out.append(UiKit.button("Open import folder", func() -> void: OS.shell_open(ProjectSettings.globalize_path(IMPORT_DIR))))
		out.append_array(_downloads())
		return out
	out.append(UiKit.text_field("Name", draft.car_name, func(t: String) -> void: draft.car_name = t.strip_edges() if t.strip_edges() else "New car"))
	out.append(UiKit.text_field("Author", draft.author, func(t: String) -> void: draft.author = t.strip_edges() if t.strip_edges() else "Unknown", 64))
	out.append(UiKit.text_field("License", draft.license, func(t: String) -> void: draft.license = t.strip_edges() if t.strip_edges() else "Unknown", 128))
	out.append(UiKit.option("Type", FAMILIES, draft.family, func(v: String) -> void:
		draft.family = v
		_choose_platform()
		_refresh()))
	out.append(_text("From " + draft.source if draft.source else ""))
	out.append(UiKit.button("Import another model", func() -> void:
		_discard_draft()
		_show_step("Import"), "Start over with another file"))
	return out


## "From online games": the cars sitting in the content cache, each to save to the garage, export
## or open here. A part-finished download is listed, but can't be used yet.
func _downloads() -> Array:
	var out: Array = [UiKit.label("From online games", 30)]
	var entries := ContentImport.list("cars")
	if entries.is_empty():
		out.append(_text("None yet. Cars from games you join land here."))
	for e: Dictionary in entries:
		var car_name := _download_name(e)
		out.append(_text(ContentImport.label(e)))
		var row := HFlowContainer.new()
		for b: Button in [
			UiKit.button("Save to garage", _save_download.bind(e), "Keep %s in your garage" % car_name),
			UiKit.button("Export…", _export_download.bind(e), "Write %s out as a .noss file" % car_name),
			UiKit.button("Open in bay", _open_download.bind(e), "Fit %s before saving it" % car_name),
		]:
			b.custom_minimum_size = Vector2(0, 52)
			if e.complete:
				_import_buttons.append(b)
			else:
				b.disabled = true
				b.focus_mode = Control.FOCUS_NONE
			row.add_child(b)
		out.append(row)
	return out


func _step_orient() -> Array:
	return [
		_text("The yellow arrow shows the front."),
		UiKit.button("Turn left 90°", _rotate.bind(Vector3.UP, 90.0)),
		UiKit.button("Turn right 90°", _rotate.bind(Vector3.UP, -90.0)),
		UiKit.button("Turn around", _rotate.bind(Vector3.UP, 180.0)),
		UiKit.button("Tip forward 90°", _rotate.bind(Vector3.RIGHT, 90.0)),
		UiKit.button("Roll over 90°", _rotate.bind(Vector3.BACK, 90.0)),
		UiKit.button("Upside down", _rotate.bind(Vector3.BACK, 180.0)),
	]


func _step_wheels() -> Array:
	var out := []
	var mode: String = draft.fit.wheel_mode
	var found: bool = draft.fit.wheels.any(func(w: Dictionary) -> bool: return w.has("node"))
	out.append(_text("%d wheels found on the model." % draft.fit.wheels.size() if found
		else "No wheels found. Place them with the sliders, or pick a wheel below and click it on the model."))
	var modes := [["model", "Model's wheels"], ["stock", "Stock wheels"], ["static", "Fixed (no spin)"]]
	if not found:
		modes = modes.slice(1)
	out.append(UiKit.option("Wheels", modes, mode, func(v: String) -> void:
		draft.fit.wheel_mode = v
		_refresh()
		_show_step("Wheels")))
	out.append(UiKit.button("Find wheels again", _find_wheels, "Run the wheel finder on the model again"))
	if mode != "model":
		var a := _anchors()
		out.append(UiKit.number("Front axle", a.front, -4.0, 4.0, 0.01, "%.2f m", func(v: float) -> void: _move_anchor("front", v)))
		out.append(UiKit.number("Rear axle", a.rear, -4.0, 4.0, 0.01, "%.2f m", func(v: float) -> void: _move_anchor("rear", v)))
		out.append(UiKit.number("Track", a.track, 0.5, 2.6, 0.01, "%.2f m", func(v: float) -> void: _move_anchor("track", v)))
		out.append(UiKit.number("Radius", a.radius, 0.1, 0.8, 0.005, "%.3f m", func(v: float) -> void: _move_anchor("radius", v)))
		out.append(UiKit.number("Height", a.height, 0.0, 1.0, 0.005, "%.3f m", func(v: float) -> void: _move_anchor("height", v)))
	out.append_array(_wheel_controls(mode))
	out.append(UiKit.number("Ride height", float(draft.fit.get("body_lift_m", 0.0)), LIFT_MIN, LIFT_MAX, 0.005, "%+.3f m", _set_lift,
		"Raise or lower the body on its wheels"))
	var clip := _clip_depth()
	if clip > CLIP_TOLERANCE:
		out.append(_text("Body %d cm in the ground." % roundi(clip * 100.0)))
		out.append(UiKit.button("Lift clear", _lift_clear, "Raise the body just clear of the ground"))
	var floating := ModelAnalysis.floating_wheels(draft.fit)
	if not floating.is_empty():
		out.append(_text(_floating_text(floating) + "."))
		out.append(UiKit.button("Remove it" if floating.size() == 1 else "Remove them", _remove_wheels.bind(floating),
			"Not a wheel: keep it as part of the body"))
	return out


## The picked wheel: where it is and how big, its parts and Remove; or a new wheel from a part.
func _wheel_controls(mode: String) -> Array:
	var edit := _wheels()
	var out := []
	var ids := edit.ids()
	if _wheel_id != NEW_WHEEL and _wheel_id not in ids:
		_wheel_id = ids[0] if not ids.is_empty() else NEW_WHEEL
	var items: Array = Array(ids).map(func(id: String) -> Array: return [id, id]) + [[NEW_WHEEL, "New wheel"]]
	out.append(UiKit.spinner("Wheel", items, _wheel_id, func(v: String) -> void:
		_wheel_id = v
		_show_step("Wheels", true), "The wheel to edit"))
	if _wheel_id == NEW_WHEEL:
		out.append(_text("Click a wheel on the model, or pick a round part:"))
		var n := 0
		for part: Dictionary in edit.round_parts():
			n += 1
			out.append(_part_control(UiKit.button(WheelEdit.label(part, n), _new_wheel.bind(part), "Make a wheel from this part"), part))
		return out
	if edit.is_hub(_wheel_id):
		out.append(_text("Set by the model's hubs."))
	else:
		if edit.partner(_wheel_id):
			out.append(UiKit.check("Mirror", _mirror, func(on: bool) -> void: _mirror = on, "Move the wheel across the car with it"))
		var v := edit.values(_wheel_id)
		for row: Array in [["Across", "across", -2.0, 2.0], ["Height", "height", 0.0, 1.5], ["Along", "along", -4.0, 4.0],
				["Radius", "radius", 0.05, 1.0], ["Width", "width", 0.02, 1.0]]:
			out.append(UiKit.number(row[0], v[row[1]], row[2], row[3], 0.005, "%.3f m", func(x: float) -> void:
				edit.move(_wheel_id, row[1], x, _mirror)
				_refresh()))
		var listed := edit.parts(_wheel_id)
		if mode == "model" or listed.is_empty():
			out.append(_text("Parts. Click the model to add or drop one."))
			var n := 0
			for part: Dictionary in listed + edit.nearby(_wheel_id):
				n += 1
				var on := n <= listed.size()
				out.append(_part_control(UiKit.check(WheelEdit.label(part, n), on, func(_on: bool) -> void: _toggle_part(part),
					"Part of the wheel" if on else "Not part of the wheel"), part))
	out.append(UiKit.button("Remove wheel", func() -> void:
		var said := edit.remove(_wheel_id)
		_refresh()
		_show_step("Wheels", true)
		_set_status(said), "Not a wheel: keep its parts on the body"))
	var bare := edit.without_parts()
	if mode == "model" and not bare.is_empty():
		out.append(_text("No parts yet: " + ", ".join(bare)))
	return out


## Lights `part` up in the preview while `control` has the focus or the mouse.
func _part_control(control: Control, part: Dictionary) -> Control:
	for s: Signal in [control.focus_entered, control.mouse_entered]:
		s.connect(func() -> void: _preview.set_hover(part))
	for s: Signal in [control.focus_exited, control.mouse_exited]:
		s.connect(func() -> void:
			if is_same(_preview.hover, part):
				_preview.set_hover({}))
	return control


func _toggle_part(part: Dictionary) -> void:
	var said := _wheels().toggle(_wheel_id, part)
	_refresh()
	_show_step("Wheels", true)
	_set_status(said)


func _new_wheel(part: Dictionary) -> void:
	var id := _wheels().add(part)
	if id:
		_wheel_id = id
	_refresh()
	_show_step("Wheels", true)
	_set_status("New wheel " + id if id else "Not a round part")


## A click on the model in the Wheels step. A part of the picked wheel is dropped, a part of
## another wheel picks that wheel, and any other part is added (or becomes a new wheel). With
## stock or fixed wheels it only picks wheels, unless the picked one has no parts yet.
func _on_part_clicked(hit: Dictionary) -> void:
	if draft == null or _step != "Wheels":
		return
	var edit := _wheels()
	var part := edit.pick(hit)
	if part.is_empty():
		return
	var owner := edit.part_of(part.node) if part.surface < 0 else ""
	var said := ""
	if owner and owner != _wheel_id:
		_wheel_id = owner
		said = "Wheel " + owner
	elif _wheel_id == NEW_WHEEL:
		var id := edit.add(part)
		if id:
			_wheel_id = id
		said = "New wheel " + id if id else "Not a round part"
	elif draft.fit.wheel_mode == "model" or edit.parts(_wheel_id).is_empty():
		said = edit.toggle(_wheel_id, part)
	else:
		said = "Parts need Model's wheels"
	_refresh()
	_show_step("Wheels", true)
	_set_status(said)


func _find_wheels() -> void:
	var n := _wheels().find_again()
	_refresh()
	_show_step("Wheels", true)
	_set_status("%d wheels found" % n if n else "No wheels found")


func _wheels() -> WheelEdit:
	if _wheel_edit == null or _wheel_edit.draft != draft:
		_wheel_edit = WheelEdit.new(draft)
	return _wheel_edit


## The preview shows the picked wheel and its parts, and takes clicks (Wheels step only).
func _sync_wheel_view() -> void:
	var on := _step == "Wheels" and draft != null
	_preview.pick_enabled = on
	_preview.selected = _wheels().index_of(_wheel_id) if on else -1
	var w := _wheels().wheel(_wheel_id) if on else {}
	_preview.lit = PackedStringArray(w.get("spin_nodes", []) + w.get("fixed_nodes", []))
	_preview.hover = {}


func _step_scale() -> Array:
	var length := _model_length()
	var s := float(draft.fit.model_transform.scale)
	return [
		_text("Set the car's real length. The class can still scale it to fit (see below)."),
		UiKit.number("Length", length * s, 0.5, 12.0, 0.01, "%.2f m", func(v: float) -> void:
			draft.fit.model_transform.scale = v / maxf(length, 1e-6)
			_refresh()),
	]


func _step_paint() -> Array:
	var out := [_text("Pick which materials take the paint colour.")]
	var slots: Dictionary = draft.paint.get("slots", {})
	var slot_of := {}
	for slot: String in slots:
		for m: String in slots[slot].materials:
			slot_of[m] = slot
	var options := [["", "Not painted"], ["primary", "Primary"], ["secondary", "Secondary"], ["tertiary", "Tertiary"]]
	for m: String in _material_names():
		out.append(UiKit.option(m, options, slot_of.get(m, ""), _assign_material.bind(m)))
	for slot in ["primary", "secondary", "tertiary"]:
		if not slots.has(slot):
			continue
		var data: Dictionary = slots[slot]
		out.append(UiKit.color(slot.capitalize() + " colour", Color.html(data.color), func(c: Color) -> void:
			data.color = "#" + c.to_html(false).to_upper()
			_preview.visual.set_paint(slot, c, data.finish)))
		out.append(UiKit.option(slot.capitalize() + " finish", FINISHES, data.finish, func(v: String) -> void:
			data.finish = v
			_preview.visual.set_paint(slot, Color.html(data.color), v)))
	return out


func _step_cockpit() -> Array:
	var out := [_text("Green: driver's eye. Orange: hood camera. Pink: bumper camera.")]
	var eye: Vector3 = _preview.fitted.eye_point if _preview.fitted else Vector3.ZERO
	for axis: Array in [["Eye across", 0, -1.2, 1.2], ["Eye height", 1, 0.0, 2.5], ["Eye along", 2, -3.0, 3.0]]:
		out.append(UiKit.number(axis[0], eye[axis[1]], axis[2], axis[3], 0.01, "%.2f m", _set_point.bind("eye", axis[1])))
	for cam in ["hood", "bumper"]:
		var p: Variant = _preview.camera_point(draft, cam)
		var at: Vector3 = p if p != null else Vector3.ZERO
		out.append(UiKit.number(cam.capitalize() + " height", at.y, 0.0, 2.5, 0.01, "%.2f m", _set_point.bind(cam, 1)))
		out.append(UiKit.number(cam.capitalize() + " along", at.z, -3.0, 3.5, 0.01, "%.2f m", _set_point.bind(cam, 2)))
	for v: Array in [["orbit", "Outside view"], ["eye", "Driver's view"], ["hood", "Hood view"], ["bumper", "Bumper view"]]:
		out.append(UiKit.button(v[1], func() -> void: _preview.set_view(v[0], draft)))
	return out


func _step_sound() -> Array:
	var tweaks: Dictionary = draft.sound.get("tweaks", {})
	draft.sound.tweaks = tweaks
	var mix: Dictionary = tweaks.get("mix", {})
	tweaks.mix = mix
	var out := [
		UiKit.option("Engine", EngineSound.profiles(), draft.sound.base, func(v: String) -> void: draft.sound.base = v),
		UiKit.number("Pitch", float(tweaks.get("pitch", 1.0)), 0.8, 1.2, 0.01, "%.2f", func(v: float) -> void: tweaks.pitch = v),
	]
	for emitter in ["engine", "exhaust", "intake"]:
		out.append(UiKit.number(emitter.capitalize() + " level", float(mix.get(emitter, 1.0)), 0.0, 1.5, 0.05, "%.2f", func(v: float) -> void: mix[emitter] = v))
	out.append(UiKit.number("Idle lope", float(tweaks.get("idle_lope", 0.0)), 0.0, 1.0, 0.05, "%.2f", func(v: float) -> void: tweaks.idle_lope = v))
	out.append(UiKit.number("Crackle", float(tweaks.get("crackle", 0.0)), 0.0, 1.0, 0.05, "%.2f", func(v: float) -> void: tweaks.crackle = v))
	out.append(UiKit.option("Turbo", [["none", "None"], ["single", "Single"], ["twin", "Twin"]], tweaks.get("turbo", "none"), func(v: String) -> void: tweaks.turbo = v))
	out.append(UiKit.check("Blow-off valve", bool(tweaks.get("blowoff", false)), func(on: bool) -> void: tweaks.blowoff = on))
	out.append(UiKit.check("Supercharger", bool(tweaks.get("supercharger", false)), func(on: bool) -> void: tweaks.supercharger = on))
	out.append(UiKit.option("Gear whine", [["normal", "Normal"], ["straight_cut", "Straight-cut"]], tweaks.get("gear_whine", "normal"), func(v: String) -> void: tweaks.gear_whine = v))
	out.append(UiKit.option("Limiter", [["soft", "Soft"], ["bounce", "Bounce"], ["cut", "Cut"]], tweaks.get("limiter", "soft"), func(v: String) -> void: tweaks.limiter = v))
	var tires: Dictionary = draft.sound.get("tires", {})
	out.append(UiKit.option("Tires", EngineSound.tire_profiles(), String(tires.get("base", EngineSound.DEFAULT_TIRES)), func(v: String) -> void:
		tires.base = v
		draft.sound.tires = tires))
	_start_engine()
	out.append(UiKit.button("Rev", func() -> void: _rev_time = 0.9, "Rev the engine"))
	out.append(UiKit.button("Skid", func() -> void: _skid_time = 1.6, "Hear the tires"))
	out.append_array(_own_recordings())
	return out


## Own recordings (AV-06, docs/VEHICLE_PACKAGE.md §6): mono OGG or WAV loops, each at an rpm and
## load for an emitter, or an extra. The built-in engine fills whatever isn't recorded.
func _own_recordings() -> Array:
	var out := [_text("Own recordings: mono OGG or WAV loops, 44.1 or 48 kHz. The built-in sounds above fill the rest.")]
	var targets := [["exhaust", "Exhaust"], ["engine", "Engine"], ["intake", "Intake"], ["start", "Start"],
		["limiter", "Limiter"], ["backfire", "Backfire"], ["turbo", "Turbo"], ["blowoff", "Blow-off"], ["tires", "Tires"]]
	out.append(UiKit.spinner("For", targets, _rec_target, func(v: String) -> void:
		_rec_target = v
		_show_step("Sound"), "An emitter's loop, or an extra sound"))
	if _rec_target in EngineSound.EMITTERS:
		out.append(UiKit.number("At rpm", _rec_rpm, 500.0, 12000.0, 100.0, "%d rpm", func(v: float) -> void: _rec_rpm = v))
		out.append(UiKit.spinner("Load", [["on", "On-load (throttle)"], ["off", "Off-load (lifting)"]], _rec_kind, func(v: String) -> void: _rec_kind = v))
	out.append(UiKit.button("Add file", _browse_audio, "Pick a recording"))
	if draft.sound.has("layers"):
		out.append(UiKit.number("Recorded idle", float(draft.sound.get("rpm_idle", 800)), 300.0, 3000.0, 50.0, "%d rpm",
			func(v: float) -> void: draft.sound.rpm_idle = v, "The rpm your lowest recording stands for"))
		out.append(UiKit.number("Recorded top", float(draft.sound.get("rpm_max", 7000)), 2000.0, 15000.0, 100.0, "%d rpm",
			func(v: float) -> void: draft.sound.rpm_max = v, "The rpm your highest recording stands for"))
	for item: Array in draft.recordings_list():
		var rel: String = item[1]
		out.append(UiKit.button("%s: %s" % [item[0], rel], func() -> void:
			draft.remove_recording(rel)
			_refresh()
			_show_step("Sound"), "Press to remove"))
	if not draft.sound_files.is_empty():
		out.append(UiKit.button("Remove all recordings", func() -> void:
			draft.clear_recordings()
			_refresh()
			_show_step("Sound")))
	return out


func _browse_audio() -> void:
	if _audio_dialog == null:
		_audio_dialog = FileDialog.new()
		_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_audio_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_audio_dialog.use_native_dialog = true
		_audio_dialog.filters = PackedStringArray(["*.ogg, *.wav ; Recordings"])
		_audio_dialog.title = "Add a recording"
		_audio_dialog.file_selected.connect(add_recording)
		add_child(_audio_dialog)
	_audio_dialog.popup_file_dialog()


## Adds the recording at `path` for what's picked in the Sound step.
func add_recording(path: String) -> void:
	var err := draft.add_recording(path, _rec_target, _rec_rpm, _rec_kind)
	if err:
		_set_status("%s: %s" % [path.get_file(), err])
		return
	_refresh()
	_show_step("Sound")
	_set_status("Added " + path.get_file())


## The engine idling in the bay while the Sound step is open; Rev blips it.
func _start_engine() -> void:
	if _engine:
		return
	var loaded := PlatformLoader.load_official(platform_id)
	var engine: Dictionary = loaded.platform.engine if loaded.ok() else { "idle_rpm": 900, "redline_rpm": 7000 }
	_engine = EngineSound.new()
	_engine.manual = { "rpm": float(engine.idle_rpm), "load": 0.0, "throttle": 0.0, "speed": 0.0,
		"idle": float(engine.idle_rpm), "redline": float(engine.redline_rpm) }
	_engine.set_profile(draft.sound, draft.sound_streams())
	_sound_json = JSON.stringify(draft.sound)
	_preview.add_to_car(_engine)
	_engine.position = Vector3(0, _preview.fitted.ground_y + 0.6, 0) if _preview.fitted else Vector3.UP * 0.6


func _stop_engine() -> void:
	if _engine:
		_engine.queue_free()
		_engine = null


func _process(delta: float) -> void:
	if _progress_src:
		var p := _progress_src.read()
		UiKit.set_progress(_progress, float(p.fraction), String(p.phase))
	if _engine == null:
		return
	# A free-revving engine: up fast with throttle, back to idle without.
	var m := _engine.manual
	_rev_time -= delta
	var throttle := 1.0 if _rev_time > 0.0 else 0.0
	var target: float = m.redline if throttle > 0.0 else m.idle
	m.rpm = move_toward(m.rpm, target, delta * (9000.0 if throttle > 0.0 else 4500.0))
	m.throttle = throttle
	m.load = throttle
	_skid_time -= delta
	m.slip = 7.0 * clampf(_skid_time / 0.4, 0.0, 1.0) if _skid_time > 0.0 else 0.0
	m.lock = 1.0 if _skid_time > 0.0 and _skid_time < 0.6 else 0.0
	var now := JSON.stringify(draft.sound)
	if now != _sound_json:
		_sound_json = now
		_engine.set_profile(draft.sound, draft.sound_streams())


func _step_save() -> Array:
	var classes := _classes()
	var options := classes.map(func(r: PlatformLoader.Result) -> Array: return [r.platform.id, "%s %s" % [_mode_name(r.platform), r.platform.name]])
	var out := []
	if options.is_empty():
		out.append(_text("No class takes this type of car."))
	else:
		out.append(UiKit.option("Drive as", options, platform_id, func(v: String) -> void:
			platform_id = v
			_refresh()))
	out.append(UiKit.button("Test drive", _test_drive, "Drive the car on the Proving Ground, then come back here"))
	return out


# --- actions -----------------------------------------------------------------


func _browse() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.filters = PackedStringArray([
			"*.glb, *.gltf, *.fbx, *.noss ; Cars and models", "*.glb, *.gltf, *.fbx ; 3D models", "*.noss ; nOSS cars",
		])
		_dialog.title = "Import a car"
		_dialog.file_selected.connect(_import)
		add_child(_dialog)
	_dialog.popup_file_dialog()


func _import(path: String) -> void:
	if _busy:
		return
	if path.get_extension().to_lower() == "noss":
		_import_package(path)
		return
	_busy = true
	_set_status("Importing " + path.get_file())
	_progress_src = ModelImport.Progress.new()
	_show_progress(true)
	_update_actions()
	var t0 := Time.get_ticks_msec()
	ModelImport.import_async(path, func(result: ModelImport.Result) -> void:
		if not is_inside_tree():
			_busy = false
			if result.scene:
				result.scene.free()
			return
		if not result.ok():
			_import_failed(path, result.error)
			return
		# The analysis and the first draft write hold the frame, so no bar can move through
		# them: name the phase and let it paint, rather than freeze on the last percentage.
		_progress_src = null
		UiKit.set_progress(_progress, 1.0, "Working out the fit")
		await get_tree().process_frame
		_discard_draft()
		draft = FittingDraft.from_import(result)
		Game.bay_draft = draft
		_choose_platform()
		draft.save_draft()
		_busy = false
		_show_progress(false)
		print("Fitting Bay: imported %s in %d ms (%d tris)" % [path.get_file(), Time.get_ticks_msec() - t0, result.triangles])
		_refresh()
		_wheel_id = String(Game.dev.get("bay-wheel", ""))
		_show_step(String(Game.dev.get("bay-step", "Import")).capitalize())
		if auto:
			_save_and_drive(), PackageLoader.DEFAULT_LIMITS, ModelImport.TIMEOUT_S, _progress_src)


## Brings in a .noss (PKG-04), or a downloaded car (`shown` its name): its model, fit, paint and
## sound as they were packed. The loader checks the zip, its limits and every file's hash first,
## so a file from anywhere is safe to open. If the garage already holds that car, the player says
## what to do with it.
func _import_package(path: String, shown := "") -> void:
	shown = shown if shown else path.get_file()
	_busy = true
	_set_status("Opening " + shown)
	_show_progress(true)
	UiKit.set_progress(_progress, 0.3, "Reading " + shown)
	_update_actions()
	PackageLoader.load_async(path, func(pkg: VehiclePackage) -> void:
		if not is_inside_tree():
			_busy = false
			pkg.free_scenes()
			return
		if not pkg.ok():
			pkg.free_scenes()
			_import_failed(path, pkg.error if pkg.error else "Car failed to load")
			return
		UiKit.set_progress(_progress, 1.0, "Working out the fit")
		await get_tree().process_frame
		var brought := FittingDraft.from_package(pkg)
		pkg.free_scenes()
		# from_package() edits the file it came from. This one was picked off the player's
		# disk, so the garage decides where it lands instead.
		brought.edit_path = ""
		_busy = false
		_show_progress(false)
		var owned := GarageFiles.with_id(brought.id)
		if owned.is_empty():
			_take_draft(brought, "Imported " + shown)
		else:
			_ask_about_copy(brought, owned, shown))


func _import_failed(path: String, error: String) -> void:
	_busy = false
	_progress_src = null
	_show_progress(false)
	_set_status(error)
	_update_actions()
	print("Import failed: %s (%s)" % [path, error])


## Takes `brought` as the car being fitted and opens the Import step on it.
func _take_draft(brought: FittingDraft, status: String) -> void:
	_discard_draft()
	draft = brought
	Game.bay_draft = draft
	_choose_platform()
	draft.save_draft()
	_refresh()
	_show_step("Import")
	_set_status(status)


## An imported .noss the garage already has: overwrite that car, or keep both.
func _ask_about_copy(brought: FittingDraft, owned: String, shown: String) -> void:
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(menu, "%s is already in your garage." % brought.car_name, 760)
	var choices := [
		UiKit.button("Replace my copy", func() -> void:
			_overlay_cancel = Callable()
			_close_overlay()
			brought.edit_path = owned
			_take_draft(brought, "Replacing " + owned.get_file()), "Save writes over it and counts up its version"),
		UiKit.button("Add as a new car", func() -> void:
			_overlay_cancel = Callable()
			_close_overlay()
			brought.id = PackageWriter.new_uuid()
			brought.car_name = (brought.car_name + " copy").left(96)
			_take_draft(brought, "Imported " + shown + " as a copy"), "Keeps the car you already have"),
		UiKit.button("Cancel", _close_overlay, "Leave the garage as it is"),
	]
	for b: Button in choices:
		list.add_child(b)
	_show_overlay(menu)
	_overlay_cancel = func() -> void: # after _show_overlay: it closes whatever was open first
		brought.free_scene()
		_set_status("")
	UiKit.chain_focus(choices)


## A downloaded car opened to fit, as a .noss would be: the garage decides where it lands.
func _open_download(e: Dictionary) -> void:
	if not _busy:
		_import_package(String(e.dir), _download_name(e))


## Keeps a downloaded car in the garage; when it's there already, writes over it or keeps both.
func _save_download(e: Dictionary) -> void:
	var owned := GarageFiles.with_id(String((e.manifest as Dictionary).get("id", "")))
	if owned.is_empty():
		_write_download(e, false)
		return
	var menu := Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var list := UiKit.panel(menu, "%s is already in your garage." % _download_name(e), 760)
	var choices := [
		UiKit.button("Replace my copy", func() -> void:
			_close_overlay()
			_write_download(e, false), "Writes over it and counts up its version"),
		UiKit.button("Keep both", func() -> void:
			_close_overlay()
			_write_download(e, true), "Saves it beside the one you have"),
		UiKit.button("Cancel", _close_overlay, "Leave the garage as it is"),
	]
	for b: Button in choices:
		list.add_child(b)
	_show_overlay(menu)
	UiKit.chain_focus(choices)


func _write_download(e: Dictionary, as_copy: bool) -> void:
	var result := ContentImport.save_car(String(e.dir), as_copy)
	if not result.ok:
		_set_status(String(result.error))
		return
	_saved_path = String(result.path) # Exit picks it in the Garage
	_set_status("Saved as " + _saved_path.get_file())


func _export_download(e: Dictionary) -> void:
	var car_name := _download_name(e)
	UiKit.save_dialog(self, "Export " + car_name, ".noss", car_name, func(dest: String) -> void:
		var result := ContentImport.export_package("cars", String(e.dir), dest)
		_set_status("Exported to " + dest.get_file() if result.ok else String(result.error)))


static func _download_name(e: Dictionary) -> String:
	return String((e.manifest as Dictionary).get("name", "Unnamed"))


func _show_overlay(control: Control) -> void:
	_close_overlay()
	_overlay_focus = UiKit.focus_owner(self)
	_overlay = control
	add_child(control)


func _close_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if is_instance_valid(_overlay_focus) and _overlay_focus.is_inside_tree():
		UiKit.focus_later(_overlay_focus)
	_overlay_focus = null
	var cancel := _overlay_cancel
	_overlay_cancel = Callable()
	if cancel.is_valid():
		cancel.call()
	_update_actions()


func _show_progress(shown: bool) -> void:
	if _progress == null:
		return
	_progress.visible = shown
	if not shown:
		UiKit.set_progress(_progress, 0.0)


func _save() -> void:
	await _pack(false)


func _save_and_drive() -> void:
	await _pack(true)


func _pack(then_drive: bool) -> void:
	if draft == null or _busy:
		return
	_busy = true
	_set_status("Saving")
	await get_tree().process_frame
	var thumb: PackedByteArray = await _preview.thumbnail()
	var t0 := Time.get_ticks_msec()
	var result := draft.pack(thumb)
	_busy = false
	if not result.ok:
		_set_status(result.error)
		return
	print("Fitting Bay: saved %s in %d ms, %d s after opening" % [result.path, Time.get_ticks_msec() - t0, (Time.get_ticks_msec() - _t_open) / 1000])
	_set_status("Saved" if not result.unchanged else "No changes")
	_saved_path = result.path
	draft.delete_draft() # the garage has it now; edits make a new draft
	if then_drive:
		_leave()
		_discard_draft()
		Game.start_free_drive(result.path, platform_id)


func _test_drive() -> void:
	if draft == null:
		return
	var err := draft.save_draft()
	if err:
		_set_status(err)
		return
	Game.bay_draft = draft
	Game.start_free_drive(draft.draft_dir(), platform_id, true)


## Back where the bay was opened from: the Garage (on the car being fitted), else the main menu.
func _exit() -> void:
	var car: String = _saved_path if _saved_path else draft.edit_path if draft else ""
	_leave()
	_discard_draft()
	closed.emit()
	if Game.bay_from == "garage":
		Game.open_garage(car)
	else:
		Game.go_title()


## Takes the preview's car out before the scene goes, so the draft's model isn't freed.
func _leave() -> void:
	_stop_engine()
	if _preview.visual:
		_preview.visual.free()
		_preview.visual = null


func _discard_draft() -> void:
	if draft and Game.bay_draft == draft:
		Game.bay_draft = null
	if draft:
		draft.delete_draft()
		draft.free_scene()
	draft = null
	_wheel_edit = null


func _rotate(axis: Vector3, degrees: float) -> void:
	var r: Array = draft.fit.model_transform.rotation_deg
	var b := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))
	b = (Basis(axis, deg_to_rad(degrees)) * b).orthonormalized()
	var e := b.get_euler()
	draft.fit.model_transform.rotation_deg = [snappedf(rad_to_deg(e.x), 0.001), snappedf(rad_to_deg(e.y), 0.001), snappedf(rad_to_deg(e.z), 0.001)]
	_refresh()


func _set_lift(value: float) -> void:
	draft.fit.body_lift_m = snappedf(value, 0.001)
	_refresh()


## Raises the body to 1 cm over the ground.
func _lift_clear() -> void:
	var clip := _clip_depth()
	if clip <= 0.0:
		return
	var lift := float(draft.fit.get("body_lift_m", 0.0)) + clip / _preview.fitted.scale + 0.01
	draft.fit.body_lift_m = minf(ceilf(lift / 0.005 - 1e-6) * 0.005, LIFT_MAX)
	_refresh()
	_show_step("Wheels")


## Takes wheels out of the fit (their parts stay on the body), and moves the ground to the rest.
func _remove_wheels(ids: PackedStringArray) -> void:
	draft.fit.wheels = draft.fit.wheels.filter(func(w: Dictionary) -> bool: return String(w.id) not in ids)
	var r: Array = draft.fit.model_transform.rotation_deg
	draft.fit.ground_y = ModelAnalysis.ground_of(draft.fit.wheels, Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2]))))
	_refresh()
	_show_step("Wheels")


func _assign_material(slot: String, material: String) -> void:
	var slots: Dictionary = draft.paint.get("slots", {})
	draft.paint.slots = slots
	for s: String in slots.keys():
		slots[s].materials = slots[s].materials.filter(func(m: String) -> bool: return m != material)
		if slots[s].materials.is_empty():
			slots.erase(s)
	if slot:
		if not slots.has(slot):
			slots[slot] = { "materials": [], "color": "#E8B71A" if slot == "primary" else "#1B1D22", "finish": "metallic" if slot == "primary" else "solid" }
		slots[slot].materials.append(material)
	_refresh()
	_show_step("Paint")


# --- geometry helpers ------------------------------------------------------------


## Model space to the vehicle frame (metres), as Fitting does before any platform scaling.
func _base() -> Transform3D:
	return WheelEdit.base(draft.fit)


## Anchor values in metres: front and rear axle positions, track, radius, hub height above ground.
func _anchors() -> Dictionary:
	var base := _base()
	var s := float(draft.fit.model_transform.scale)
	var a := { "front": 0.0, "rear": 0.0, "track": 0.0, "radius": 0.0, "height": 0.0 }
	var nf := 0
	var nr := 0
	for w: Dictionary in draft.fit.wheels:
		var v := base * Vector3(w.center[0], w.center[1], w.center[2])
		if int(w.axle) == 1:
			a.front += v.z
			nf += 1
		else:
			a.rear += v.z
			nr += 1
		a.track = maxf(a.track, 2.0 * absf(v.x))
		a.radius = float(w.radius) * s
		a.height = v.y - _ground()
	a.front /= maxi(nf, 1)
	a.rear /= maxi(nr, 1)
	return a


func _move_anchor(key: String, value: float) -> void:
	var a := _anchors()
	a[key] = value
	var inverse := _base().affine_inverse()
	var s := float(draft.fit.model_transform.scale)
	var ground := _ground()
	for w: Dictionary in draft.fit.wheels:
		var side := 1.0 if w.side == "L" else -1.0 if w.side == "R" else 0.0
		var v := Vector3(side * a.track / 2.0, ground + a.height, a.front if int(w.axle) == 1 else a.rear)
		var c := inverse * v
		w.center = [c.x, c.y, c.z]
		w.radius = a.radius / s
		w.width = a.radius / s * 0.7
	_refresh()


## The vehicle-frame ground under the model (its lowest point), metres.
func _ground() -> float:
	return WheelEdit.floor_y(draft.fit)


## How far the body sits in the ground as fitted, metres (0 or less: clear of it).
func _clip_depth() -> float:
	var bottom := draft.body_bottom() if draft else INF
	if _preview.fitted == null or is_inf(bottom):
		return 0.0
	return _preview.fitted.ground_y - _preview.fitted.scale * bottom


## "Wheel C2 is off the ground", or "Wheels C2, C3 are off the ground".
static func _floating_text(ids: PackedStringArray) -> String:
	return ("Wheel %s is off the ground" if ids.size() == 1 else "Wheels %s are off the ground") % ", ".join(ids)


## The model's length in its own units (along the car).
func _model_length() -> float:
	var env: Dictionary = draft.fit.envelope
	var r: Array = draft.fit.model_transform.rotation_deg
	var rot := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))
	var box := Transform3D(rot, Vector3.ZERO) * AABB(Vector3(env.min[0], env.min[1], env.min[2]), Vector3(env.max[0], env.max[1], env.max[2]) - Vector3(env.min[0], env.min[1], env.min[2]))
	return box.size.z


## Moves the eye point or a camera along one vehicle axis (metres, before platform scaling).
func _set_point(value: float, which: String, axis: int) -> void:
	var fitted := _preview.fitted
	var current: Vector3
	if which == "eye":
		current = fitted.eye_point
	else:
		var p: Variant = _preview.camera_point(draft, which)
		current = p if p != null else fitted.eye_point
	current[axis] = value
	var model := fitted.model_xform.affine_inverse() * current
	if which == "eye":
		draft.fit.eye_point = [model.x, model.y, model.z]
	else:
		if not draft.fit.has("cameras"):
			draft.fit.cameras = {}
		draft.fit.cameras[which] = [model.x, model.y, model.z]
	_refresh(false)
	if _preview.view != "orbit":
		_preview.set_view(_preview.view, draft)


func _material_names() -> PackedStringArray:
	var names := PackedStringArray()
	if draft.scene == null:
		return names
	for mi: MeshInstance3D in draft.scene.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name and m.resource_name not in names:
				names.append(m.resource_name)
	return names


# --- classes ---------------------------------------------------------------------


## Classes that take the draft's type of car.
func _classes() -> Array[PlatformLoader.Result]:
	var out: Array[PlatformLoader.Result] = []
	for mode in GameModes.list():
		for r in GameModes.classes(mode):
			if Fitting.compatible(r.platform, draft.family):
				out.append(r)
	return out


func _choose_platform() -> void:
	var classes := _classes()
	var ids := classes.map(func(r: PlatformLoader.Result) -> String: return r.platform.id)
	var last := String(Settings.profile.get("last_platform", ""))
	if platform_id not in ids:
		platform_id = last if last in ids else (ids[0] if not ids.is_empty() else TrackSession.DEFAULT_PLATFORM)


static func _mode_name(platform: Dictionary) -> String:
	return String(platform.modes[0]).capitalize() if not platform.modes.is_empty() else ""


# --- display -----------------------------------------------------------------------


func _refresh(rebuild := true) -> void:
	if draft == null:
		_set_status("")
		return
	var loaded := PlatformLoader.load_official(platform_id)
	if not loaded.ok():
		return
	_preview.show_draft(draft, loaded.platform, rebuild)
	var notes := PackedStringArray(draft.notes)
	notes.append_array(_preview.fitted.notes)
	var clip := _clip_depth()
	if clip > CLIP_TOLERANCE:
		notes.append("Body %d cm in the ground" % roundi(clip * 100.0))
	var floating := ModelAnalysis.floating_wheels(draft.fit)
	if not floating.is_empty():
		notes.append(_floating_text(floating))
	_set_status("%s · %s %s\n%s" % [draft.car_name, _mode_name(loaded.platform), loaded.platform.name, ", ".join(notes)])
	_update_actions()
	if rebuild:
		draft.save_draft()


func _update_actions() -> void:
	_drive_button.disabled = draft == null or _busy
	_save_button.disabled = draft == null or _busy
	for b in _import_buttons:
		if is_instance_valid(b):
			b.disabled = _busy


func _set_status(text: String) -> void:
	_status.text = text


func _import_folder_files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(IMPORT_DIR) if DirAccess.dir_exists_absolute(IMPORT_DIR) else PackedStringArray():
		var ext := f.get_extension().to_lower()
		if ext in ModelImport.EXTENSIONS or ext == "noss":
			out.append(f)
	return out


static func _text(text: String) -> Label:
	var l := UiKit.label(text, FONT_SIZE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## The controls to chain: no labels, and each button of a row of them.
static func _focusable(controls: Array) -> Array:
	var out := []
	for c: Control in controls:
		if c is FlowContainer:
			out.append_array(c.get_children())
		elif not c is Label:
			out.append(c)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_dialog == null or not _dialog.visible):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_overlay):
			_close_overlay()
		else:
			_exit()
