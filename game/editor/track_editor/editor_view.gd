class_name EditorView
extends SubViewportContainer
## The track editor's 3D view (D95). With the mouse: left button picks and drags, right drag
## turns the camera, middle drag pans, the wheel zooms. With keys or a controller the view
## works round a crosshair in its middle: WASD or arrows (left stick) move, Q/E (right stick)
## turn, Z/X (triggers) zoom, Enter or Space (A) grabs and drops (a toggle), and shortcuts send
## actions to the editor. Tools get `pointer` events with what's under the cursor.

## {kind: press|drag|release|hover, screen, hit: {hit, position, normal, collider}, shift, alt, crosshair}
signal pointer(event: Dictionary)
## A shortcut: confirm, delete, prev, next, undo, redo, test, test_grid, panel, map, tool_<1-8>.
signal action(name: String)
## The camera zoomed enough that the gizmos should be redrawn at their new size.
signal zoomed

const PAN_SPEED := 0.9 # pivot distances per second
const TURN_SPEED := 1.6
const ZOOM_SPEED := 1.4
const DEADZONE := 0.2

var viewport := SubViewport.new()
var world := Node3D.new()
var camera := EditorCamera.new()
var preview := TrackPreview.new()
var gizmos := Gizmos.new()
var draft: TrackDraft
## Keys or a controller are driving the view: the crosshair is the cursor.
var crosshair := false
## Crosshair mode: an item is picked up and moves with the view until confirmed again.
var grabbing := false
var _cross := Crosshair.new()
var _left_down := false
var _drag_button := MOUSE_BUTTON_NONE
var _last_mouse := Vector2.ZERO
var _pad_pressed := {}


func _init() -> void:
	name = "EditorView"
	stretch = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	accessibility_name = "Track view"
	accessibility_description = "Arrows or WASD move, Q and E turn, Z and X zoom, Enter picks, Tab goes to the panel"
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	viewport.add_child(world)
	world.add_child(preview)
	world.add_child(gizmos)
	world.add_child(camera)
	_cross.visible = false
	_cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)


## Shows `d` (another draft replaces the one shown).
func open_draft(d: TrackDraft, style_id: String) -> void:
	if draft and draft.changed.is_connected(preview._on_changed):
		draft.changed.disconnect(preview._on_changed)
	draft = d
	for child in world.get_children():
		if child is WorldEnvironment or child is DirectionalLight3D:
			world.remove_child(child)
			child.queue_free()
	var style := StyleProfile.load_profile(style_id)
	style.apply_globals()
	var env := style.create_environment()
	# Editing looks from far above: the style's fog would hide the track.
	env.environment.fog_enabled = false
	env.environment.volumetric_fog_enabled = false
	world.add_child(env)
	world.add_child(style.create_sun())
	preview.setup(d)
	camera.camera.current = true


func _propagate_input_event(_event: InputEvent) -> bool:
	return false # the view's own input is handled here, not in the world


# --- picking ------------------------------------------------------------------------------


## What's under `screen` (view pixels): {hit, position, normal, collider}. The road, props and
## terrain by ray; the terrain's own heights if the ray misses (collision not in yet); the
## y = 0 plane last.
func pick(screen: Vector2) -> Dictionary:
	var cam := camera.camera
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var space := viewport.world_3d.direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 6000.0)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return { "hit": true, "position": hit.position, "normal": hit.normal, "collider": hit.collider }
	if draft and draft.terrain:
		var t := draft.terrain.field.raycast(from, dir, 6000.0)
		if t.hit:
			return { "hit": true, "position": t.position, "normal": Vector3.UP, "collider": null }
	if absf(dir.y) > 1e-4:
		var k := -from.y / dir.y
		if k > 0.0:
			return { "hit": true, "position": from + dir * k, "normal": Vector3.UP, "collider": null }
	return { "hit": false, "position": Vector3.ZERO, "normal": Vector3.UP, "collider": null }


## Where `p` shows on the view (pixels); off-screen or behind: (-1, -1).
func screen_of(p: Vector3) -> Vector2:
	var cam := camera.camera
	if cam.is_position_behind(p):
		return Vector2(-1, -1)
	return cam.unproject_position(p)


func center() -> Vector2:
	return size / 2.0


## The cursor: the crosshair in crosshair mode, else the mouse.
func cursor() -> Vector2:
	return center() if crosshair else get_local_mouse_position()


# --- input --------------------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		_set_crosshair(false)
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				camera.zoom(0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom(1.0 / 0.88)
			MOUSE_BUTTON_LEFT:
				_left_down = mb.pressed
				if mb.pressed:
					grab_focus()
				_emit("press" if mb.pressed else "release", mb.position, mb.shift_pressed, mb.alt_pressed)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_drag_button = mb.button_index if mb.pressed else MOUSE_BUTTON_NONE
				if mb.pressed:
					grab_focus()
		_last_mouse = mb.position
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm:
		_set_crosshair(false)
		var d := mm.position - _last_mouse
		_last_mouse = mm.position
		if _drag_button == MOUSE_BUTTON_RIGHT:
			camera.orbit(-d.x * 0.006, -d.y * 0.006)
		elif _drag_button == MOUSE_BUTTON_MIDDLE:
			var scale := camera.distance / maxf(size.y, 1.0) * 1.2
			camera.pan(-d.x * scale, d.y * scale)
		_emit("drag" if _left_down else "hover", mm.position, mm.shift_pressed, mm.alt_pressed)
		accept_event()
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var name := _key_action(key)
		if name:
			_set_crosshair(name not in ["undo", "redo", "panel"])
			_do(name)
			accept_event()
		elif key.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_Z, KEY_X, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			_set_crosshair(true)
			accept_event()
		return
	var jb := event as InputEventJoypadButton
	if jb and jb.pressed:
		var name := _pad_action(jb.button_index)
		if name:
			_set_crosshair(name not in ["undo", "redo", "panel"])
			_do(name)
			accept_event()


func _key_action(key: InputEventKey) -> String:
	match key.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			return "confirm"
		KEY_DELETE, KEY_BACKSPACE:
			return "delete"
		KEY_BRACKETLEFT:
			return "prev"
		KEY_BRACKETRIGHT:
			return "next"
		KEY_F5:
			return "test_grid" if key.shift_pressed else "test"
		KEY_F6, KEY_ESCAPE:
			return "panel"
		KEY_M:
			return "map"
	if key.ctrl_pressed and key.physical_keycode == KEY_Z:
		return "redo" if key.shift_pressed else "undo"
	if key.ctrl_pressed and key.physical_keycode == KEY_Y:
		return "redo"
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_8 and not key.ctrl_pressed:
		return "tool_%d" % (key.physical_keycode - KEY_1 + 1)
	return ""


func _pad_action(button: JoyButton) -> String:
	match button:
		JOY_BUTTON_A:
			return "confirm"
		JOY_BUTTON_X:
			return "delete"
		JOY_BUTTON_LEFT_SHOULDER:
			return "prev"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "next"
		JOY_BUTTON_DPAD_LEFT:
			return "undo"
		JOY_BUTTON_DPAD_RIGHT:
			return "redo"
		JOY_BUTTON_B:
			return "panel"
		JOY_BUTTON_Y:
			return "map"
		JOY_BUTTON_START:
			return "test"
	return ""


func _do(name: String) -> void:
	if name == "map":
		camera.toggle_map()
		return
	if name == "confirm":
		# A toggle: pick up (press), carry with the view (drag), put down (release).
		grabbing = not grabbing
		_emit("press" if grabbing else "release", center(), false, false)
	action.emit(name)


## Keys and sticks move the camera while the view has focus; in crosshair mode the cursor
## follows, so a carried item moves with it.
func _process(delta: float) -> void:
	var scale := clampf(camera.distance / 120.0, 0.4, 25.0)
	if absf(scale - gizmos.point_scale) > gizmos.point_scale * 0.15:
		gizmos.point_scale = scale
		zoomed.emit()
	if not has_focus():
		_cross.visible = false
		return
	var move := Vector2.ZERO
	var turn := Vector2.ZERO
	var zoom := 0.0
	var keys := {
		KEY_W: Vector2(0, 1), KEY_UP: Vector2(0, 1), KEY_S: Vector2(0, -1), KEY_DOWN: Vector2(0, -1),
		KEY_A: Vector2(-1, 0), KEY_LEFT: Vector2(-1, 0), KEY_D: Vector2(1, 0), KEY_RIGHT: Vector2(1, 0),
	}
	for k: Key in keys:
		if Input.is_physical_key_pressed(k):
			move += keys[k]
	if Input.is_physical_key_pressed(KEY_Q):
		turn.x += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		turn.x -= 1.0
	if Input.is_physical_key_pressed(KEY_Z):
		zoom -= 1.0
	if Input.is_physical_key_pressed(KEY_X):
		zoom += 1.0
	for pad in Input.get_connected_joypads():
		var l := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), -Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		var r := Vector2(-Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		move += l if l.length() > DEADZONE else Vector2.ZERO
		turn += r if r.length() > DEADZONE else Vector2.ZERO
		zoom += Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) - Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT)
	var fine := 0.3 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	var moving := move != Vector2.ZERO or turn != Vector2.ZERO or absf(zoom) > DEADZONE
	if moving:
		_set_crosshair(true)
		camera.pan(move.x * camera.distance * PAN_SPEED * delta * fine, move.y * camera.distance * PAN_SPEED * delta * fine)
		camera.orbit(turn.x * TURN_SPEED * delta * fine, turn.y * TURN_SPEED * 0.5 * delta * fine)
		if absf(zoom) > DEADZONE:
			camera.zoom(1.0 + zoom * ZOOM_SPEED * delta * fine)
	_cross.visible = crosshair
	if crosshair and (moving or grabbing):
		_emit("drag" if grabbing else "hover", center(), false, false)


func _set_crosshair(on: bool) -> void:
	if crosshair == on:
		return
	crosshair = on
	if not on and grabbing:
		grabbing = false # the mouse took over: put it down
		_emit("release", center(), false, false)
	_cross.visible = on
	_cross.queue_redraw()


func _emit(kind: String, screen: Vector2, shift: bool, alt: bool) -> void:
	pointer.emit({ "kind": kind, "screen": screen, "hit": pick(screen), "shift": shift, "alt": alt, "crosshair": crosshair })


## The crosshair in crosshair mode.
class Crosshair:
	extends Control

	func _draw() -> void:
		var c := size / 2.0
		for w: Array in [[4.0, Color(0, 0, 0, 0.8)], [2.0, Color.WHITE]]:
			draw_line(c - Vector2(14, 0), c - Vector2(4, 0), w[1], w[0])
			draw_line(c + Vector2(4, 0), c + Vector2(14, 0), w[1], w[0])
			draw_line(c - Vector2(0, 14), c - Vector2(0, 4), w[1], w[0])
			draw_line(c + Vector2(0, 4), c + Vector2(0, 14), w[1], w[0])
