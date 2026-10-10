class_name FittingBay
extends Control
## The Fitting Bay (docs/VEHICLE_PACKAGE.md §7, PKG-02…04, PKG-07): turns a GLB, glTF or FBX
## into a .noss. Import works out the wheels, orientation, scale and the rest on its own, so
## "Save and drive" works straight away; the other steps adjust what it found. The draft is
## kept in user://fitting/ and survives test drives.

signal closed

const STEPS := ["Import", "Orient", "Wheels", "Scale", "Paint", "Cockpit", "Sound", "Save"]
const IMPORT_DIR := "user://import/"
const FONT_SIZE := 24
const FAMILIES := [["car", "Car"], ["open", "Open-wheel"], ["truck", "Truck"]]
const FINISHES := [["solid", "Solid"], ["metallic", "Metallic"], ["pearl", "Pearl"], ["matte", "Matte"], ["chrome", "Chrome"]]
const SOUND_BASES := [["i4", "Inline 4"], ["v8_crossplane", "V8"], ["flat6", "Flat 6"], ["ev", "Electric"]]

var draft: FittingDraft
var platform_id := ""
## Dev: import this file on open; with auto, save and drive as soon as it's in.
var import_path := ""
var auto := false

var _preview: BayPreview
var _content: VBoxContainer
var _status: Label
var _step := "Import"
var _step_buttons := {}
var _drive_button: Button
var _save_button: Button
var _dialog: FileDialog
var _busy := false
var _t_open := 0


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
	_status = UiKit.label("", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	side.add_child(_status)
	var actions := HBoxContainer.new()
	_drive_button = UiKit.button("Save and drive", _save_and_drive, "Save the car to the garage and drive it")
	_save_button = UiKit.button("Save", _save, "Save the car to the garage")
	var exit := UiKit.button("Exit", _exit, "Leave the Fitting Bay")
	for b in [_drive_button, _save_button, exit]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	side.add_child(actions)

	_preview = BayPreview.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_preview)

	if draft == null and Game.bay_draft is FittingDraft:
		draft = Game.bay_draft
	if draft:
		_choose_platform()
		_refresh()
		_show_step("Save" if Game.bay_draft == draft and draft.scene else "Import")
	else:
		_show_step("Import")
	if import_path:
		_import(import_path)


# --- steps -------------------------------------------------------------------


func _show_step(step: String) -> void:
	if draft == null and step != "Import":
		step = "Import"
	_step = step
	for s: String in _step_buttons:
		_step_buttons[s].button_pressed = s == step
		_step_buttons[s].disabled = draft == null and s != "Import"
	for child in _content.get_children():
		child.queue_free()
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
	UiKit.chain_focus(_focusable(controls) + [_step_buttons[step], _drive_button, _save_button])
	_refresh(false)
	_update_actions()


func _step_import() -> Array:
	var out := []
	if draft == null:
		out.append(_text("Pick a .glb, .gltf or .fbx file. It doesn't need any preparation."))
		out.append(UiKit.button("Browse…", _browse, "Choose a model file"))
		DirAccess.make_dir_recursive_absolute(IMPORT_DIR)
		var files := _import_folder_files()
		out.append(_text("Or put files in the import folder:" if files.is_empty() else "From the import folder:"))
		for f in files:
			out.append(UiKit.button(f, _import.bind(IMPORT_DIR + f), "Import " + f))
		out.append(UiKit.button("Open import folder", func() -> void: OS.shell_open(ProjectSettings.globalize_path(IMPORT_DIR))))
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
	out.append(_text("%d wheels found on the model." % draft.fit.wheels.size() if found else "No wheels found. Place them with the sliders."))
	var modes := [["model", "Model's wheels"], ["stock", "Stock wheels"], ["static", "Fixed (no spin)"]]
	if not found:
		modes = modes.slice(1)
	out.append(UiKit.option("Wheels", modes, mode, func(v: String) -> void:
		draft.fit.wheel_mode = v
		_refresh()
		_show_step("Wheels")))
	if mode != "model":
		var a := _anchors()
		out.append(UiKit.number("Front axle", a.front, -4.0, 4.0, 0.01, "%.2f m", func(v: float) -> void: _move_anchor("front", v)))
		out.append(UiKit.number("Rear axle", a.rear, -4.0, 4.0, 0.01, "%.2f m", func(v: float) -> void: _move_anchor("rear", v)))
		out.append(UiKit.number("Track", a.track, 0.5, 2.6, 0.01, "%.2f m", func(v: float) -> void: _move_anchor("track", v)))
		out.append(UiKit.number("Radius", a.radius, 0.1, 0.8, 0.005, "%.3f m", func(v: float) -> void: _move_anchor("radius", v)))
		out.append(UiKit.number("Height", a.height, 0.0, 1.0, 0.005, "%.3f m", func(v: float) -> void: _move_anchor("height", v)))
	return out


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
		UiKit.option("Engine", SOUND_BASES, draft.sound.base, func(v: String) -> void: draft.sound.base = v),
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
	if has_method("_sound_preview"):
		out.append_array(call("_sound_preview"))
	return out


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
		_dialog.filters = PackedStringArray(["*.glb, *.gltf, *.fbx ; 3D models"])
		_dialog.title = "Import a car"
		_dialog.file_selected.connect(_import)
		add_child(_dialog)
	_dialog.popup_file_dialog()


func _import(path: String) -> void:
	if _busy:
		return
	_busy = true
	_set_status("Importing " + path.get_file())
	var t0 := Time.get_ticks_msec()
	ModelImport.import_async(path, func(result: ModelImport.Result) -> void:
		_busy = false
		if not is_inside_tree():
			if result.scene:
				result.scene.free()
			return
		if not result.ok():
			_set_status(result.error)
			print("Import failed: %s (%s)" % [path, result.error])
			return
		_discard_draft()
		draft = FittingDraft.from_import(result)
		Game.bay_draft = draft
		_choose_platform()
		draft.save_draft()
		print("Fitting Bay: imported %s in %d ms (%d tris)" % [path.get_file(), Time.get_ticks_msec() - t0, result.triangles])
		_refresh()
		_show_step(String(Game.dev.get("bay-step", "Import")).capitalize())
		if auto:
			_save_and_drive())


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


func _exit() -> void:
	_leave()
	_discard_draft()
	closed.emit()
	Game.go_title()


## Takes the preview's car out before the scene goes, so the draft's model isn't freed.
func _leave() -> void:
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


func _rotate(axis: Vector3, degrees: float) -> void:
	var r: Array = draft.fit.model_transform.rotation_deg
	var b := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))
	b = (Basis(axis, deg_to_rad(degrees)) * b).orthonormalized()
	var e := b.get_euler()
	draft.fit.model_transform.rotation_deg = [snappedf(rad_to_deg(e.x), 0.001), snappedf(rad_to_deg(e.y), 0.001), snappedf(rad_to_deg(e.z), 0.001)]
	_refresh()


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
	var mt: Dictionary = draft.fit.model_transform
	var r: Array = mt.rotation_deg
	var o: Array = mt.offset_m
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2]))).scaled(Vector3.ONE * float(mt.scale)), Vector3(o[0], o[1], o[2]))


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
	var env: Dictionary = draft.fit.envelope
	var box := _base() * AABB(Vector3(env.min[0], env.min[1], env.min[2]), Vector3(env.max[0], env.max[1], env.max[2]) - Vector3(env.min[0], env.min[1], env.min[2]))
	return box.position.y


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
		platform_id = last if last in ids else (ids[0] if not ids.is_empty() else FreeDrive.DEFAULT_PLATFORM)


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
	_set_status("%s · %s %s\n%s" % [draft.car_name, _mode_name(loaded.platform), loaded.platform.name, ", ".join(notes)])
	_update_actions()
	if rebuild:
		draft.save_draft()


func _update_actions() -> void:
	_drive_button.disabled = draft == null or _busy
	_save_button.disabled = draft == null or _busy


func _set_status(text: String) -> void:
	_status.text = text


func _import_folder_files() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(IMPORT_DIR) if DirAccess.dir_exists_absolute(IMPORT_DIR) else PackedStringArray():
		if f.get_extension().to_lower() in ModelImport.EXTENSIONS:
			out.append(f)
	return out


static func _text(text: String) -> Label:
	var l := UiKit.label(text, FONT_SIZE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func _focusable(controls: Array) -> Array:
	return controls.filter(func(c: Control) -> bool: return not c is Label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_dialog == null or not _dialog.visible):
		get_viewport().set_input_as_handled()
		_exit()
