class_name LiveryView
extends Node
## Pointing at the car in the Fitting Bay's Livery step (docs/VEHICLE_PACKAGE.md §12, docs/UI_FLOW.md
## §12). With the mouse: a click picks the layer under it, a drag slides it over the body, the
## right button turns the view, the wheel zooms (with Shift it sizes the layer, with Ctrl turns
## it). With keys or a controller a crosshair is the cursor: arrows (left stick) move it, WASD
## (right stick) turn the view, Z/X (triggers) zoom, Enter (A) picks a layer up and puts it down
## where the cursor is. Tab, Esc or B go back to the list, never out of the bay.

const HELP := "Arrows move the cursor, WASD turn, Z and X zoom, Enter picks up and puts down, R turns, minus and equals size, brackets change layer, F flips, M mirrors, Delete deletes, Tab goes to the list"
const CURSOR_SPEED := 700.0 # px per second at full stick
const ORBIT_SPEED := 1.8
const DEADZONE := 0.2
## Steps for keys: degrees, and size per press.
const TURN_STEP := 15.0
const SIZE_STEP := 1.1

var preview: BayPreview
var bay: FittingBay
## Keys or a pad drive the cursor (the crosshair shows).
var keys := false
## The picked layer follows the cursor until it's put down.
var carrying := false
var cross := Crosshair.new()
## The mouse's left button went down on a layer: moving drags it.
var _pressed := false
var _moved := false
var _press_at := Vector2.ZERO
var _orbiting := false


func _init(view: BayPreview, fitting_bay: FittingBay) -> void:
	preview = view
	bay = fitting_bay
	name = "LiveryView"
	preview.add_child(cross)


func _exit_tree() -> void:
	if is_instance_valid(cross):
		cross.queue_free()


func edit() -> LiveryEdit:
	return bay._livery_edit()


## The cursor: the crosshair when keys or a pad drive, else the mouse.
func cursor() -> Vector2:
	return cross.spot() if keys else preview.get_local_mouse_position()


## Picks up the picked layer to put it down with the cursor (Place on car).
func start_carrying() -> void:
	if edit().current().is_empty():
		bay._set_status("No layer picked")
		return
	carrying = true
	_set_keys(not preview.get_global_rect().has_point(preview.get_global_mouse_position()))
	bay._set_status("Point at the car, then confirm")


## Handles an input event while the view has the focus; true if it was used.
func handle(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb:
		_set_keys(false)
		return _mouse_button(mb)
	var mm := event as InputEventMouseMotion
	if mm:
		_set_keys(false)
		if _orbiting:
			preview.orbit(-mm.relative.x * 0.008, -mm.relative.y * 0.006)
		elif _pressed and (_moved or mm.position.distance_to(_press_at) > BayPreview.CLICK_SLOP):
			_moved = true
			_follow(mm.position, true)
		elif carrying:
			_follow(mm.position, true)
		return true
	var key := event as InputEventKey
	if key and key.pressed:
		return _key(key)
	var jb := event as InputEventJoypadButton
	if jb and jb.pressed:
		return _pad(jb.button_index)
	return false


func _mouse_button(mb: InputEventMouseButton) -> bool:
	var e := edit()
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				preview.grab_focus()
				_press_at = mb.position
				_moved = false
				if carrying:
					_drop(mb.position)
					return true
				_pressed = _pick(mb.position)
			else:
				if _pressed and _moved:
					_drop(mb.position)
				_pressed = false
			return true
		MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			if mb.pressed:
				preview.grab_focus()
			return true
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return true
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if mb.shift_pressed and not e.current().is_empty():
				e.set_size(float(e.placement().size) * (SIZE_STEP if up else 1.0 / SIZE_STEP))
				_changed()
			elif mb.ctrl_pressed and not e.current().is_empty():
				e.turn_by(TURN_STEP if up else -TURN_STEP)
				_changed()
			else:
				preview.zoom_by(0.9 if up else 1.1)
			return true
	return false


func _key(key: InputEventKey) -> bool:
	var e := edit()
	match key.physical_keycode:
		KEY_TAB, KEY_ESCAPE:
			_to_list()
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not key.echo:
				_set_keys(true)
				_confirm()
			return true
		KEY_R:
			e.turn_by(-TURN_STEP if key.shift_pressed else TURN_STEP)
			_changed()
			return true
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_EQUAL, KEY_KP_ADD:
			var bigger := key.physical_keycode in [KEY_EQUAL, KEY_KP_ADD]
			if not e.current().is_empty():
				e.set_size(float(e.placement().size) * (SIZE_STEP if bigger else 1.0 / SIZE_STEP))
				_changed()
			return true
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if not key.echo:
				_step_layer(1 if key.physical_keycode == KEY_BRACKETRIGHT else -1)
			return true
		KEY_F:
			if not key.echo and not e.current().is_empty():
				var flips: Array = LiveryEdit.FLIPS.map(func(f: Array) -> String: return f[0])
				e.set_flip(flips[(flips.find(e.placement().flip) + 1) % flips.size()])
				_changed(true)
			return true
		KEY_M:
			if not key.echo and not e.current().is_empty():
				e.set_value("mirror", not e.current().get("mirror", false))
				_changed(true)
				bay._set_status("Mirrored" if e.current().get("mirror", false) else "Not mirrored")
			return true
		KEY_DELETE, KEY_BACKSPACE:
			if not key.echo:
				_say(e.delete_layer(), true)
			return true
		KEY_D:
			if key.ctrl_pressed:
				if not key.echo:
					_say(e.duplicate_layer(), true)
				return true
	if key.ctrl_pressed:
		return false # undo and redo are the bay's
	# Moving the cursor and the view is done each frame (_process); the keys are used here.
	return key.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D, KEY_Z, KEY_X]


func _pad(button: JoyButton) -> bool:
	var e := edit()
	match button:
		JOY_BUTTON_A:
			_set_keys(true)
			_confirm()
		JOY_BUTTON_B:
			_to_list()
		JOY_BUTTON_X:
			_say(e.delete_layer(), true)
		JOY_BUTTON_Y:
			_say(e.duplicate_layer(), true)
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			var right := button == JOY_BUTTON_DPAD_RIGHT
			if carrying:
				e.turn_by(-TURN_STEP if right else TURN_STEP)
				_changed()
			else:
				_say(e.redo() if right else e.undo(), true)
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			var up := button == JOY_BUTTON_DPAD_UP
			if carrying:
				e.set_size(float(e.placement().size) * (SIZE_STEP if up else 1.0 / SIZE_STEP))
				_changed()
			else:
				_step_layer(1 if up else -1)
		_:
			return false # the shoulders go to the bay: the steps
	return true


## Enter or A: puts a carried layer down at the cursor, or picks up the layer under it.
func _confirm() -> void:
	if carrying:
		_drop(cursor())
	elif _pick(cursor()):
		carrying = true
		bay._set_status("Picked up " + LiveryData.layer_name(edit().current()))


## Picks the top layer under `at` (a point on this view). False if there's none.
func _pick(at: Vector2) -> bool:
	var hit := preview.pick(at)
	var i := layer_at(hit)
	if i < 0:
		bay._set_status("Nothing here")
		return false
	edit().layer = i
	bay._show_step("Livery", true)
	bay._set_status(edit().layer_label())
	return true


## The top shown layer whose box holds `hit` (a pick: model-space position and normal), or -1.
func layer_at(hit: Dictionary) -> int:
	if hit.is_empty() or not hit.has("position"):
		return -1
	var e := edit()
	var ls := e.layers()
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var plane := LiveryRenderer.mirror_plane(preview.visual.fitted.model_xform, preview.visual.fitted.model_bounds) if preview.visual else Vector4.ZERO
	var mn := Vector3(plane.x, plane.y, plane.z)
	for i in range(ls.size() - 1, -1, -1):
		var l: Dictionary = ls[i]
		if l.get("hidden", false):
			continue
		if _covers(l, p, n) or (l.get("mirror", false) and _covers(l, p - 2.0 * (p.dot(mn) - plane.w) * mn, n - 2.0 * n.dot(mn) * mn)):
			return i
	return -1


## Whether `l`'s box holds model-space point `p` on a surface facing `n` (as the shader decides).
static func _covers(l: Dictionary, p: Vector3, n: Vector3) -> bool:
	var normal := LiveryEdit._v(l.normal)
	var right := LiveryEdit._v(l.right)
	var d := p - LiveryEdit._v(l.at)
	var u := d.dot(right) / maxf(absf(float(l.size[0])), 1e-9)
	var v := d.dot(normal.cross(right)) / maxf(absf(float(l.size[1])), 1e-9)
	return absf(u) <= 0.5 and absf(v) <= 0.5 and absf(d.dot(normal)) <= float(l.depth) and n.dot(normal) > 0.12


## The picked layer at the body under `at`, facing out of it there.
func _follow(at: Vector2, merge: bool) -> void:
	var hit := preview.pick(at)
	if hit.is_empty() or not hit.has("position"):
		return
	edit().place_at(hit.position, hit.normal, merge)
	_changed()


func _drop(at: Vector2) -> void:
	var hit := preview.pick(at)
	carrying = false
	if hit.is_empty() or not hit.has("position"):
		bay._show_step("Livery", true)
		bay._set_status("Off the car: left where it was")
		return
	edit().place_at(hit.position, hit.normal, true)
	bay._show_step("Livery", true)
	bay._show_livery()
	bay._set_status("Placed")


func _step_layer(d: int) -> void:
	var e := edit()
	var n := e.layers().size()
	if n == 0:
		bay._set_status("No layers")
		return
	e.layer = posmod(e.layer + d, n)
	bay._show_step("Livery", true)
	bay._show_livery()
	bay._set_status(e.layer_label())


## Back to the list (the Layer row); a carried layer is put back down where it is.
func _to_list() -> void:
	carrying = false
	_set_keys(false)
	bay._focus_livery_list()


func _say(said: String, rebuild: bool) -> void:
	if rebuild:
		bay._show_step("Livery", true)
	bay._show_livery()
	if said:
		bay._set_status(said)


## The layer changed: the car shows it (and the list, when `rebuild`).
func _changed(rebuild := false) -> void:
	if rebuild:
		bay._show_step("Livery", true)
	bay._show_livery()


func _set_keys(on: bool) -> void:
	if keys == on:
		return
	keys = on
	cross.visible = on
	if on and (cross.at.x < 0.0 or not Rect2(Vector2.ZERO, preview.size).has_point(cross.at)):
		cross.at = preview.size / 2.0


func _process(delta: float) -> void:
	if not preview.has_focus():
		cross.visible = false
		return
	cross.visible = keys
	var move := Vector2.ZERO
	var turn := Vector2.ZERO
	var zoom := 0.0
	for k: Array in [[KEY_UP, Vector2.UP], [KEY_DOWN, Vector2.DOWN], [KEY_LEFT, Vector2.LEFT], [KEY_RIGHT, Vector2.RIGHT]]:
		if Input.is_physical_key_pressed(k[0]):
			move += k[1]
	for k: Array in [[KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN], [KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT]]:
		if Input.is_physical_key_pressed(k[0]) and not Input.is_key_pressed(KEY_CTRL):
			turn += k[1]
	if not Input.is_key_pressed(KEY_CTRL):
		if Input.is_physical_key_pressed(KEY_Z):
			zoom -= 1.0
		if Input.is_physical_key_pressed(KEY_X):
			zoom += 1.0
	for pad in Input.get_connected_joypads():
		var l := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if l.length() > DEADZONE:
			move += l
	if move != Vector2.ZERO:
		_set_keys(true)
		cross.at = (cross.spot() + move.limit_length(1.5) * CURSOR_SPEED * delta).clamp(Vector2.ZERO, preview.size)
	if turn != Vector2.ZERO:
		preview.orbit(-turn.x * ORBIT_SPEED * delta, -turn.y * ORBIT_SPEED * 0.6 * delta)
	if zoom != 0.0:
		preview.zoom_by(1.0 + zoom * delta)
	if carrying and keys and (move != Vector2.ZERO or turn != Vector2.ZERO or zoom != 0.0):
		_follow(cross.spot(), true)
