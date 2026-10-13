extends Node
## Local players (autoload "Players", docs/ARCHITECTURE.md §6, docs/INPUT.md §3, LOC-01, LOC-04):
## up to 4 slots, each with a profile, the devices they claimed, a car and a monitor.
## - While `joining` is on, the first press on a free device claims the next slot.
## - With `adding` set, the next press on a free device goes to that player instead.
## - Every physics tick and frame it polls each player's input, and pushes their menu
##   navigation into their own viewport (PlayerSlot.menu_target).
## Which profile each device belongs to, and each profile's monitor, are remembered in
## user://players.json.

signal slots_changed
signal joined(slot: PlayerSlot)
signal left(slot: PlayerSlot)

const MAX := 4
## These mean "back", so they never join.
const NO_JOIN_KEYS := [KEY_ESCAPE, KEY_BACKSPACE]
const NO_JOIN_BUTTONS := [JOY_BUTTON_B, JOY_BUTTON_BACK, JOY_BUTTON_GUIDE]

var slots: Array[PlayerSlot] = []
## Press-to-join is open.
var joining := false:
	set(on):
		joining = on
		_baseline()
## The next press on a free device adds it to this player (null: off).
var adding: PlayerSlot:
	set(slot):
		adding = slot
		_baseline()

var memory_path := "user://players.json"

var _pressed := {} # free device key -> pressed last frame
var _memory := { "devices": {}, "screens": {} }


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ViewFocusBridge.install(get_tree().root)
	process_physics_priority = -90 # after Devices, before vehicles
	load_memory()
	Devices.devices_changed.connect(refresh_all)


func load_memory() -> void:
	_memory = { "devices": {}, "screens": {} }
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(memory_path)) if FileAccess.file_exists(memory_path) else null
	if saved is Dictionary:
		for key: String in _memory:
			if saved.get(key) is Dictionary:
				_memory[key] = saved[key]


func _physics_process(_delta: float) -> void:
	for slot in slots:
		if not slot.ai:
			slot.input.poll()


func _process(delta: float) -> void:
	if adding or (joining and not get_tree().paused):
		_scan_joins()
	elif joining:
		_baseline() # nobody joins mid-pause: presses then are for the pause menu
	for slot in slots:
		if slot.ai:
			continue
		var fired := slot.input.poll_menu(delta)
		for action in fired:
			# One key can fire two actions (Esc: back and pause); the first may close the menu.
			var target := slot.menu_target
			if target == null or not is_instance_valid(target) or not target.is_inside_tree():
				break
			push_action(target, Bindings.MENU_EVENTS[action])


## A press and release of `action` into `viewport`, as GUI navigation. The viewport's own
## focus comes back first (see track_focus).
static func push_action(viewport: Viewport, action: String) -> void:
	var c := focus_of(viewport)
	if c and viewport.gui_get_focus_owner() != c:
		c.grab_focus()
	for pressed in [true, false]:
		if not viewport.is_inside_tree():
			return # the press closed this screen
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		viewport.push_input(e)
	# This player acted last: the screen reader follows them (their control or its new state).
	ViewFocusBridge.point_at.call_deferred(focus_of(viewport))


## Godot keeps one focused control per OS window, so player menus sharing a window (views,
## Players screen cards) each remember their own and get it back before their input arrives.
static func track_focus(viewport: Viewport) -> void:
	viewport.gui_focus_changed.connect(func(c: Control) -> void:
		viewport.set_meta(&"player_focus", c)
		# After this frame's input: taking the window's focus now would cut the view's off.
		ViewFocusBridge.point_at.call_deferred(c))


## The control a player's viewport last focused, if it's still there and visible.
static func focus_of(viewport: Viewport) -> Control:
	var c: Variant = viewport.get_meta(&"player_focus") if viewport.has_meta(&"player_focus") else null
	if is_instance_valid(c) and c is Control and c.is_inside_tree() and c.is_visible_in_tree():
		return c
	return null


## Text size for shared menus: the largest of the joined players' (P1's if nobody joined),
## docs/ACCESSIBILITY.md §8.
func menu_text_scale() -> float:
	var scale := float(Settings.primary.data.get("text_scale", 1.0))
	for slot in slots:
		if not slot.ai:
			scale = maxf(scale, float(slot.profile.data.get("text_scale", 1.0)))
	return clampf(scale, 1.0, 2.0)


func count() -> int:
	return slots.size()


## P1. Without any players, P1 is made: the primary profile, the keyboard, the first free
## gamepad and every wheel and pedal set, so one person can just drive.
func primary_slot() -> PlayerSlot:
	if slots.is_empty():
		var keys: PackedStringArray = ["kb:full"]
		var pad_found := false
		for d: Dictionary in Devices.list():
			if d.kind == "gamepad" and not pad_found:
				keys.append(d.key)
				pad_found = true
			elif d.kind == "sim":
				keys.append(d.key)
		_add_slot(Settings.primary, keys)
	return slots[0]


## Claims the next slot with `device` (a free_devices() entry).
func join(device: Dictionary, profile: PlayerProfile = null) -> PlayerSlot:
	if slots.size() >= MAX:
		return null
	if profile == null:
		profile = _profile_for(device.key)
	var slot := _add_slot(profile, [device.key])
	print("%s joined: %s (%s)" % [slot.tag(), slot.display_name(), device.name])
	joined.emit(slot)
	return slot


## Dev and tests: a player driven by the line follower, with a throwaway profile.
func add_ai() -> PlayerSlot:
	if slots.size() >= MAX:
		return null
	var slot := PlayerSlot.new()
	slot.index = slots.size()
	slot.ai = true
	var data := { "name": "AI %d" % slot.number() }
	# Dev: --ai-profile='{"hud_scale": 1.5}' sets options on these throwaway profiles.
	var extra: Variant = JSON.parse_string(String(Game.dev.get("ai-profile", "{}")))
	if extra is Dictionary:
		data.merge(extra, true)
	slot.profile = PlayerProfile.create("ai%d" % slot.number(), data)
	slots.append(slot)
	slot.refresh(Devices.list())
	slots_changed.emit()
	return slot


func remove_ai() -> void:
	for slot in slots.duplicate():
		if slot.device_keys.is_empty() and slot.profile.id.begins_with("ai"):
			leave(slot)


func leave(slot: PlayerSlot) -> void:
	if slot not in slots:
		return
	slots.erase(slot)
	slot.menu_target = null
	for i in slots.size():
		slots[i].index = i
	if not slots.is_empty() and not slots[0].ai and slots[0].profile != Settings.primary:
		Settings.set_primary(slots[0].profile)
	print("%s left" % slot.display_name())
	left.emit(slot)
	slots_changed.emit()


func clear() -> void:
	for slot in slots.duplicate():
		leave(slot)


func add_device(slot: PlayerSlot, device: Dictionary) -> void:
	if owner_of(device.key) != null:
		return
	slot.device_keys.append(device.key)
	slot.refresh(Devices.list())
	print("%s added %s" % [slot.tag(), device.name])
	_remember(slot)
	slots_changed.emit()


func remove_device(slot: PlayerSlot, key: String) -> void:
	var i := slot.device_keys.find(key)
	if i >= 0:
		slot.device_keys.remove_at(i)
		slot.refresh(Devices.list())
		slots_changed.emit()


## Moves a player's keyboard to "full", "left" or "right". The whole keyboard can't be taken
## while another player has a side. False if not allowed.
func set_keyboard_zone(slot: PlayerSlot, zone: String) -> bool:
	var current := slot.keyboard_zone()
	if current.is_empty() or zone == current:
		return false
	for other in slots:
		if other != slot and other.keyboard_zone() in ["full", zone] + (["left", "right"] if zone == "full" else []):
			return false
	slot.device_keys[slot.device_keys.find("kb:" + current)] = "kb:" + zone
	slot.refresh(Devices.list())
	slots_changed.emit()
	return true


func set_profile(slot: PlayerSlot, profile: PlayerProfile) -> void:
	for other in slots:
		if other != slot and other.profile == profile:
			return
	slot.profile = profile
	slot.refresh(Devices.list())
	if slot.index == 0:
		Settings.set_primary(profile)
	_remember(slot)
	slots_changed.emit()


func set_screen(slot: PlayerSlot, screen: int) -> void:
	slot.screen = screen
	_memory.screens[slot.profile.id] = screen
	_save_memory()
	slots_changed.emit()


func owner_of(key: String) -> PlayerSlot:
	for slot in slots:
		if key in slot.device_keys:
			return slot
		if key.begins_with("kb:") and not slot.keyboard_zone().is_empty():
			var mine := slot.keyboard_zone()
			if mine == "full" or key == "kb:full" or key == "kb:" + mine:
				return slot
	return null


## Devices nobody has claimed. The keyboard is offered whole while nobody has it, then only
## the free side once a player has taken one side.
func free_devices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in Devices.list():
		if d.kind == "keyboard":
			var zones := slots.map(func(s: PlayerSlot) -> String: return s.keyboard_zone())
			var offer := ""
			if "full" in zones or ("left" in zones and "right" in zones):
				offer = ""
			elif "left" in zones:
				offer = "right"
			elif "right" in zones:
				offer = "left"
			else:
				offer = "full"
			if offer:
				var kb := d.duplicate()
				kb.key = "kb:" + offer
				kb.zone = offer
				kb.name = "Keyboard" if offer == "full" else "Keyboard %s side" % offer
				out.append(kb)
		elif owner_of(d.key) == null:
			out.append(d)
	return out


## Physical keys bound on other players' keyboard sides (rebinding skips them).
func keys_of_others(input: PlayerInput) -> Array:
	var keys := []
	for slot in slots:
		if slot.input == input:
			continue
		for d: Dictionary in slot.input.devices:
			if d.kind == "keyboard":
				var map := Bindings.effective(slot.input.preset_of(d), slot.profile.data.input.bindings.get(slot.input.preset_of(d), {}))
				for refs: Array in map.values():
					for r: Dictionary in refs:
						if r.has("key"):
							keys.append(r.key)
	return keys


func refresh_all() -> void:
	var all := Devices.list()
	for slot in slots:
		slot.refresh(all)


## Saves which profile each player's devices belong to (call when a session starts).
func remember_all() -> void:
	for slot in slots:
		_remember(slot, false)
	_save_memory()


func _add_slot(profile: PlayerProfile, keys: PackedStringArray) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.index = slots.size()
	slot.profile = profile
	slot.device_keys = keys
	var screen := int(_memory.screens.get(profile.id, -1))
	slot.screen = screen if screen < DisplayServer.get_screen_count() else -1
	slots.append(slot)
	slot.refresh(Devices.list())
	if slot.index == 0:
		Settings.set_primary(profile)
	_remember(slot)
	slots_changed.emit()
	return slot


## The remembered profile for a device, else the first one nobody uses (P1: the primary),
## else a new one.
func _profile_for(device_key: String) -> PlayerProfile:
	var used := slots.map(func(s: PlayerSlot) -> String: return s.profile.id)
	var remembered := String(_memory.devices.get(device_key, ""))
	if remembered and remembered not in used and FileAccess.file_exists(PlayerProfile.path_for(remembered)):
		return Settings.get_profile(remembered)
	if slots.is_empty() and Settings.primary.id not in used:
		return Settings.primary
	for id in Settings.profile_ids():
		if id not in used:
			return Settings.get_profile(id)
	return Settings.new_profile()


func _remember(slot: PlayerSlot, save := true) -> void:
	for key in slot.device_keys:
		if not key.begins_with("kb:"):
			_memory.devices[key] = slot.profile.id
	if save:
		_save_memory()


func _save_memory() -> void:
	var f := FileAccess.open(memory_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_memory, "  ", true) + "\n")


func _baseline() -> void:
	_pressed.clear()
	for d in free_devices():
		_pressed[d.key] = _is_pressed(d)


func _scan_joins() -> void:
	var free := free_devices()
	var seen := {}
	for d in free:
		var down := _is_pressed(d)
		seen[d.key] = true
		var was: bool = _pressed.get(d.key, true) # new devices need a release first
		_pressed[d.key] = down
		if not down or was:
			continue
		if adding:
			var slot := adding
			adding = null
			add_device(slot, d)
			return
		if joining and slots.size() < MAX:
			join(d)
			_baseline()
			return
	for key: String in _pressed.keys():
		if not seen.has(key):
			_pressed.erase(key)


## Any join-worthy press on a free device.
func _is_pressed(d: Dictionary) -> bool:
	match d.kind:
		"keyboard":
			var zone := String(d.get("zone", "full"))
			var keys: Array = PlayerInput.CAPTURE_KEYS if zone == "full" else Bindings.keys_of("kb_" + zone)
			for k: int in keys:
				if k not in NO_JOIN_KEYS and Input.is_physical_key_pressed(k):
					return true
		"gamepad":
			for b in PlayerInput.PAD_BUTTON_COUNT:
				if b not in NO_JOIN_BUTTONS and Input.is_joy_button_pressed(d.id, b):
					return true
		"sim":
			for b in int(d.get("buttons", 0)):
				if PlayerInput.sim_button(d.id, b):
					return true
	return false
