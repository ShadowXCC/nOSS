class_name FirstBootMenu
extends Control
## The accessibility screen (ACC-09, docs/ACCESSIBILITY.md §7): shown before anything else on
## first boot, and from each player's card for their own profile. Quick presets set sensible
## defaults in one step and can be combined; the photosensitivity notice has a one-press
## Reduce flashing. A screen reader reads it as it is; otherwise the first key press turns on
## speech for this screen.

signal done

## Each quick preset's settings (profile keys; "assists" and "input" merge one level down).
const PRESETS := {
	"vision": { "font": "clear", "text_scale": 1.5, "hud_scale": 1.4, "high_contrast": true, "narration": "race", "spotter": "voice" },
	"hearing": { "captions": true, "slip_indicator": true, "sound_arrows": true, "shift_light": true },
	"motion": { "camera_shake": 0.0, "head_movement": 0.0, "speed_fov": false, "horizon_lock": true, "reduce_flashing": true },
	"minimal_input": { "assists": { "abs": true, "tcs": true, "stability": true, "auto_gearbox": true, "steer_aid": true }, "input": { "toggles": ["throttle"] } },
}
const ONE_HANDED := {
	"left": { "keyboard": "kb_left", "gamepad": "pad_left_hand" },
	"right": { "keyboard": "kb_right", "gamepad": "pad_right_hand" },
}

var profile: PlayerProfile
## The player whose screen this is (null: first boot, P1's profile).
var slot: PlayerSlot

var _rows: Array = []
var _spoken := false


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if profile == null:
		profile = slot.profile if slot else Settings.primary
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	var list := UiKit.panel(self, "Accessibility" if slot == null else "Accessibility  ·  " + profile.display_name(), 1000)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 660)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var intro := UiKit.label("Set up how you play. Combine as many as you like; everything is in Settings later.", 26)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(intro)

	for item: Array in [["vision", "Vision", "Clear font, bigger text, high contrast, narration, spotter voice"],
			["hearing", "Hearing", "Captions, slip indicator, close-car arrows, shift light"],
			["motion", "Motion", "No camera shake or head movement, level horizon, fewer flashes"],
			["minimal_input", "Minimal input", "Driving assists on, throttle toggles"]]:
		var id: String = item[0]
		_add(rows, UiKit.check(item[1], has_preset(profile, id), func(on: bool) -> void:
			apply_preset(profile, id, on)
			_refresh_flashing(), item[2]))
	var hand := "off"
	for side: String in ONE_HANDED:
		if profile.data.input.presets.gamepad == ONE_HANDED[side].gamepad:
			hand = side
	_add(rows, UiKit.spinner("One-handed", [["off", "Off"], ["left", "Left hand"], ["right", "Right hand"]], hand,
		func(v: String) -> void: set_one_handed(profile, v), "Controller and keyboard layouts for one hand"))

	var heading := UiKit.label("Photosensitivity", 34)
	heading.add_theme_color_override("font_color", UiKit.ACCENT)
	rows.add_child(heading)
	var notice := UiKit.label("Some lights and effects flash. Reduce flashing keeps them to 3 a second or fewer, at lower contrast.", 26)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(notice)
	_add(rows, UiKit.check("Reduce flashing", bool(profile.data.reduce_flashing), func(on: bool) -> void:
		profile.set_value("reduce_flashing", on), "Photosensitivity: at most 3 flashes a second"))

	var more := UiKit.button("More settings", _open_settings, "Every option, one by one")
	var finish := UiKit.button("Done", _finish)
	list.add_child(more)
	list.add_child(finish)
	_rows.append(more)
	_rows.append(finish)
	UiKit.chain_focus(_rows)


## Whether a profile has everything a quick preset sets.
static func has_preset(p: PlayerProfile, id: String) -> bool:
	var preset: Dictionary = PRESETS[id]
	for key: String in preset:
		var want: Variant = preset[key]
		if want is Dictionary:
			for sub: String in want:
				if p.data[key].get(sub) != want[sub]:
					return false
		elif p.data.get(key) != want:
			return false
	return true


## Applies a quick preset, or puts its settings back to the defaults.
static func apply_preset(p: PlayerProfile, id: String, on: bool) -> void:
	var preset: Dictionary = PRESETS[id]
	for key: String in preset:
		var want: Variant = preset[key]
		if want is Dictionary:
			for sub: String in want:
				var value: Variant = want[sub] if on else PlayerProfile.DEFAULTS[key].get(sub)
				p.data[key][sub] = value.duplicate() if value is Array else value
		else:
			p.data[key] = want if on else PlayerProfile.DEFAULTS[key]
	p.save()
	Players.refresh_all()


static func set_one_handed(p: PlayerProfile, side: String) -> void:
	var presets: Dictionary = p.data.input.presets
	if ONE_HANDED.has(side):
		presets.keyboard = ONE_HANDED[side].keyboard
		presets.gamepad = ONE_HANDED[side].gamepad
	else:
		presets.keyboard = PlayerProfile.DEFAULTS.input.presets.keyboard
		presets.gamepad = PlayerProfile.DEFAULTS.input.presets.gamepad
	p.save()
	Players.refresh_all()


func _add(parent: Control, c: Control) -> void:
	parent.add_child(c)
	_rows.append(c)


func _refresh_flashing() -> void:
	# Motion turns Reduce flashing on; show it.
	for c: Control in _rows:
		if c is CheckButton and c.text == "Reduce flashing":
			(c as CheckButton).set_pressed_no_signal(bool(profile.data.reduce_flashing))


func _open_settings() -> void:
	var menu := PlayerSettingsMenu.new()
	menu.profile = profile
	menu.slot = slot
	UiKit.open_sub(self, menu, func() -> void: _build())


func _finish() -> void:
	Narrator.force_menus = false
	if slot == null:
		Settings.set_value("first_boot_done", true)
	done.emit()


## The first key or button press turns on speech for this screen (unless a screen reader is
## reading it already) and reads it from the top.
func _input(event: InputEvent) -> void:
	if _spoken or not is_visible_in_tree():
		return
	if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction) and event.is_pressed():
		_spoken = true
		if not Narrator.screen_reader_running():
			Narrator.force_menus = true
			var focused := get_viewport().gui_get_focus_owner()
			Narrator.say("Accessibility. Set up how you play. " + (Narrator.describe(focused) if focused else ""))


func _exit_tree() -> void:
	Narrator.force_menus = false
