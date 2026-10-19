class_name PlayerInput
extends RefCounted
## One local player's controls, read only from the devices they claimed (docs/INPUT.md §3,
## LOC-04, ACC-06). Every bound input on every one of their devices counts and the largest
## value wins, so two devices can drive one car. Hold actions can be toggles. Menu directions
## repeat with the player's delay and rate.
##
## Devices are polled, not read from events, so input works the same whichever window has
## focus. Players polls this once per physics tick (poll) and once per frame (poll_menu).

## An axis or pedal counts as pressed past this.
const PRESS := 0.5
const TRIGGER_DEADZONE := 0.05
const STEER := ["steer_left", "steer_right"]
## Free look (the right stick): the stick's deadzone, straight.
const LOOK := ["look_left", "look_right", "look_up", "look_down"]
## Keys the rebinding capture watches. On a shared keyboard, the other player's keys are skipped.
const CAPTURE_KEYS := [
	KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_M,
	KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
	KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_BACKSPACE, KEY_TAB,
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_SEMICOLON,
	KEY_APOSTROPHE, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BACKSLASH, KEY_MINUS, KEY_EQUAL,
	KEY_QUOTELEFT, KEY_INSERT, KEY_DELETE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN,
	KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8,
	KEY_KP_9, KEY_KP_ENTER, KEY_KP_ADD, KEY_KP_SUBTRACT, KEY_KP_MULTIPLY, KEY_KP_DIVIDE,
	KEY_KP_PERIOD, KEY_F1, KEY_F2, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10,
	KEY_F11, KEY_F12,
]
const PAD_BUTTON_COUNT := 21
const PAD_AXIS_COUNT := 6

var profile: PlayerProfile
## The player's devices: Devices.list() entries, keyboard ones with a "zone".
var devices: Array[Dictionary] = []
var wheel := WheelInput.new()

## Tests: fake sim-device state, {"b<device>:<button>": bool, "a<device>:<axis>": float}.
static var test_sim := {}

var _refs := {} # action -> [{kind, device, ref}]
var _toggled := {} # action -> latched on
var _down := {} # action -> pressed at the last poll
var _edges := {} # action -> became pressed at the last poll
var _menu_time := {} # action -> seconds held (INF: held before the menu opened)
var _capture := {}
var _axis_rest := {} # "device:axis" -> value when the capture started


## Re-reads bindings and calibration; call after devices or the profile's input change.
func rebuild() -> void:
	_refs.clear()
	var sims: Array = []
	for d: Dictionary in devices:
		if d.kind == "sim":
			sims.append(d)
		var preset_id := preset_of(d)
		var overrides: Dictionary = profile.data.input.bindings.get(override_key(d, preset_id), {})
		var map := Bindings.effective(preset_id, overrides)
		for action: String in map:
			for r: Dictionary in map[action]:
				if not _refs.has(action):
					_refs[action] = []
				_refs[action].append({ "kind": d.kind, "device": d.get("id", -1), "ref": r })
	wheel.configure(sims, profile.data.get("wheel", {}))
	settle()


## Which preset a device of this player uses.
func preset_of(d: Dictionary) -> String:
	match d.kind:
		"keyboard":
			match String(d.get("zone", "full")):
				"left": return "kb_left"
				"right": return "kb_right"
			return String(profile.data.input.presets.get("keyboard", "kb_full"))
		"gamepad":
			return String(profile.data.input.presets.get("gamepad", "pad_standard"))
	return String(d.get("preset", "sim_generic"))


## Where a profile keeps its overrides for this device: per preset, or per sim device.
static func override_key(d: Dictionary, preset_id: String) -> String:
	return "sim:" + String(d.guid) if d.kind == "sim" else preset_id


## Treats everything held right now as already handled: no edge, no menu press, until it's
## let go. Call when a menu opens, so the press that opened it doesn't also act inside it.
func settle() -> void:
	for action: String in Bindings.ACTIONS:
		var held := _source(action) > PRESS
		_down[action] = held
		_edges[action] = false
		if held:
			_menu_time[action] = INF
		else:
			_menu_time.erase(action)


## 0..1 from this player's devices, the largest bound input; only `kind`'s devices if given.
## Stick axes for steering use the profile's deadzone and curve. Ignores toggles.
func value(action: String, kind := "") -> float:
	var best := 0.0
	for b: Dictionary in _refs.get(action, []):
		if kind and b.kind != kind:
			continue
		best = maxf(best, _read(b, action))
	return best


## A driving control: toggle-aware, wheel pedals included.
func analog(action: String) -> float:
	if action in profile.data.input.toggles and action in Bindings.HOLD:
		return 1.0 if _toggled.get(action, false) else 0.0
	return _source(action)


## Any of this player's devices has something bound to `action`.
func has_binding(action: String) -> bool:
	return not _refs.get(action, []).is_empty()


## What to call the input bound to `action` on screen ("W", "RB", "Button 4"), for a prompt that
## has to name a button (DragPrompts). `prefer` is the kind of device to look at first — the one
## the player is actually using — and "" takes whatever is bound. Empty if nothing is.
func label_for(action: String, prefer := "") -> String:
	var refs: Array = _refs.get(action, [])
	var kinds := ([prefer] if prefer else []) + ["keyboard", "gamepad", "sim"]
	for want: String in kinds:
		for b: Dictionary in refs:
			if String(b.kind) == want:
				return Bindings.ref_label(b.ref, want)
	return ""


func held(action: String) -> bool:
	return analog(action) > PRESS


## Pressed since the previous poll.
func just_pressed(action: String) -> bool:
	return _edges.get(action, false)


## Once per physics tick: edges and toggles.
func poll() -> void:
	var toggles: Array = profile.data.input.toggles
	for action: String in Bindings.DRIVING:
		var down := _source(action) > PRESS
		var edge: bool = down and not _down.get(action, false)
		_down[action] = down
		_edges[action] = edge
		if edge and action in toggles:
			_toggled[action] = not _toggled.get(action, false)


func clear_toggles() -> void:
	_toggled.clear()


## Once per frame: the menu actions that fire now (a press, or a repeat while held).
func poll_menu(delta: float) -> Array[String]:
	var out: Array[String] = []
	var delay := maxf(float(profile.data.input.get("menu_delay", 0.45)), 0.05)
	var period := 1.0 / clampf(float(profile.data.input.get("menu_rate", 10.0)), 1.0, 60.0)
	for action: String in Bindings.MENU_EVENTS:
		if value(action) <= PRESS:
			_menu_time.erase(action)
			continue
		if not _menu_time.has(action):
			_menu_time[action] = 0.0
			out.append(action)
			continue
		var t0: float = _menu_time[action]
		if is_inf(t0) or not Bindings.ACTIONS[action].get("repeat", false):
			continue
		var t1 := t0 + delta
		_menu_time[action] = t1
		if t1 >= delay and (t0 < delay or floori((t1 - delay) / period) > floori((t0 - delay) / period)):
			out.append(action)
	return out


## Starts watching this player's devices for a new press (rebinding).
func capture_start() -> void:
	_axis_rest.clear()
	for d: Dictionary in devices:
		if d.kind == "sim":
			for a in int(d.get("axes", 0)):
				_axis_rest["%d:%d" % [d.id, a]] = sim_axis(d.id, a)
	_capture = _snapshot()


## The first input pressed now that wasn't when the capture started:
## {kind, guid (sim), ref}, or {} if none yet.
func capture_poll() -> Dictionary:
	var now := _snapshot()
	for id: String in now:
		if not _capture.has(id):
			return now[id]
	_capture = now.duplicate() # a release then a press counts too
	for id: String in _capture.keys():
		if not now.has(id):
			_capture.erase(id)
	return {}


func _snapshot() -> Dictionary:
	var out := {}
	for d: Dictionary in devices:
		match d.kind:
			"keyboard":
				var blocked := Players.keys_of_others(self)
				for k: int in CAPTURE_KEYS:
					if Input.is_physical_key_pressed(k) and k not in blocked:
						out["k%d" % k] = { "kind": "keyboard", "ref": { "key": k } }
			"gamepad":
				for b in PAD_BUTTON_COUNT:
					if Input.is_joy_button_pressed(d.id, b):
						out["p%d:b%d" % [d.id, b]] = { "kind": "gamepad", "ref": { "button": b } }
				for a in PAD_AXIS_COUNT:
					var v := Input.get_joy_axis(d.id, a)
					if absf(v) > 0.6:
						out["p%d:a%d%s" % [d.id, a, "-" if v < 0.0 else "+"]] = { "kind": "gamepad", "ref": { "axis": a, "dir": -1 if v < 0.0 else 1 } }
			"sim":
				for b in int(d.get("buttons", 0)):
					if sim_button(d.id, b):
						out["s%d:b%d" % [d.id, b]] = { "kind": "sim", "guid": d.guid, "ref": { "button": b } }
				# An axis moved well away from where it was when the capture started: pedals and
				# levers, with their rest position so they read 0..1 over their travel.
				for a in int(d.get("axes", 0)):
					var v := sim_axis(d.id, a)
					var rest := float(_axis_rest.get("%d:%d" % [d.id, a], v))
					if absf(v - rest) > 0.5:
						var dir := 1 if v > rest else -1
						out["s%d:a%d%s" % [d.id, a, "+" if dir > 0 else "-"]] = { "kind": "sim", "guid": d.guid, "ref": { "axis": a, "dir": dir, "rest": snappedf(rest, 0.01) } }
	return out


func _source(action: String) -> float:
	var v := value(action)
	match action:
		"throttle":
			v = maxf(v, wheel.throttle())
		"brake":
			v = maxf(v, wheel.brake())
		"clutch":
			v = maxf(v, wheel.clutch())
		"handbrake":
			v = maxf(v, wheel.handbrake())
	return v


static func sim_button(device: int, button: int) -> bool:
	if not test_sim.is_empty():
		return bool(test_sim.get("b%d:%d" % [device, button], false))
	return NossInput.button(device, button)


static func sim_axis(device: int, axis: int) -> float:
	if not test_sim.is_empty():
		return float(test_sim.get("a%d:%d" % [device, axis], 0.0))
	return NossInput.axis(device, axis)


func _read(b: Dictionary, action: String) -> float:
	var r: Dictionary = b.ref
	match b.kind:
		"keyboard":
			return 1.0 if r.has("key") and Input.is_physical_key_pressed(r.key) else 0.0
		"gamepad":
			if r.has("button"):
				return 1.0 if Input.is_joy_button_pressed(b.device, r.button) else 0.0
			if r.has("axis"):
				var v := clampf(Input.get_joy_axis(b.device, r.axis) * r.dir, 0.0, 1.0)
				if action in STEER:
					return VehicleController.shape_axis(v, float(profile.data.pad_deadzone), float(profile.data.pad_linearity))
				if action in LOOK:
					return VehicleController.shape_axis(v, float(profile.data.pad_deadzone), 1.0)
				return VehicleController.shape_axis(v, TRIGGER_DEADZONE, 1.0)
		"sim":
			if r.has("button"):
				return 1.0 if sim_button(b.device, r.button) else 0.0
			if r.has("axis"):
				var v := sim_axis(b.device, r.axis)
				# Captured axes know where they rest: a pedal resting at -1 runs 0..1 over its travel.
				if r.has("rest"):
					var target := float(r.dir)
					var rest := float(r.rest)
					return clampf((v - rest) / (target - rest), 0.0, 1.0) if not is_equal_approx(target, rest) else 0.0
				return clampf(v * r.dir, 0.0, 1.0)
	return 0.0
