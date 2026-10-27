class_name PlayerSettingsMenu
extends TabbedPage
## One player's Driving Settings, saved in their profile and following them (docs/UI_FLOW.md
## §9.2, docs/ACCESSIBILITY.md, ACC-01, ACC-02, ACC-04, ACC-06), in tabs: Assists, Comfort,
## Vision & Hearing, HUD & Display, and Controls (presets, hold or toggle, menu repeat, stick
## deadzone, rebinding, wheel). Changes apply right away.

const KEYBOARD := [["kb_full", "Whole"], ["kb_left", "Left side"], ["kb_right", "Right side"]]
const FONTS := [["retro", "Game"], ["clear", "Clear"]]
## What each tab's "Reset to defaults" puts back (PlayerProfile.reset_keys). Controls takes the
## custom buttons and keys too; the wheel's setup stays.
const RESETS := {
	"Assists": ["assists"],
	"Comfort": ["camera_shake", "head_movement", "speed_fov", "horizon_lock", "game_speed"],
	"Vision & Hearing": ["palette", "palette_custom", "reduce_flashing", "narration", "narration_rate", "spotter",
		"captions", "shift_light", "slip_indicator", "sound_arrows"],
	"HUD & Display": ["hud_scale", "text_scale", "high_contrast", "font", "brightness", "hud_preset", "hud_hidden"],
	"Controls": ["input.presets", "input.bindings", "input.toggles", "input.menu_delay", "input.menu_rate", "rumble", "pad_deadzone"],
}

var profile: PlayerProfile
## The player whose devices rebinding and wheel setup use; null: every device.
var slot: PlayerSlot
## Assists allowed where this player is driving (AssistRules.allowed); empty: not in a session.
var allowed_assists: Array = []


func _ready() -> void:
	if profile == null:
		profile = slot.profile if slot else Settings.primary
	title = "Driving Settings · " + profile.display_name()
	if crumbs.is_empty():
		crumbs = ["Driving Settings"]
	tabs = ["Assists", "Comfort", "Vision & Hearing", "HUD & Display", "Controls"]
	super._ready()


func _build_tab(which: String) -> void:
	var d: Dictionary = profile.data
	match which:
		"Assists":
			add_heading("Assists")
			var by_device := [["auto", "Auto"], ["on", "On"], ["off", "Off"]]
			for item: Array in [["abs", "ABS", "Brakes without locking"], ["tcs", "Traction control", "No wheelspin"],
					["stability", "Stability control", "Brakes single wheels to stop slides"]]:
				var key: String = item[0]
				add_row(_assist(UiKit.check(item[1], bool(d.assists.get(key, false)), func(on: bool) -> void: profile.set_assist(key, on), item[2]), key))
			for item: Array in [["auto_gearbox", "Auto gearbox", "Auto: on with keyboard or controller, off with a wheel"],
					["auto_clutch", "Auto clutch", "Auto: on unless you have a clutch pedal"],
					["steer_aid", "Steer aid", "Less lock at speed, help to catch slides. Auto: off with a wheel"]]:
				var key: String = item[0]
				add_row(_assist(UiKit.spinner(item[1], by_device, String(d.assists.get(key, "auto")), func(v: String) -> void: profile.set_assist(key, v), item[2]), key))
			add_row(_assist(UiKit.check("Racing line", bool(d.assists.racing_line), func(on: bool) -> void: profile.set_assist("racing_line", on), "The AI line on the road, coloured by speed"), "racing_line"))
			add_heading("Access assists")
			add_row(_assist(UiKit.check("Auto-throttle", bool(d.assists.auto_throttle), func(on: bool) -> void: profile.set_assist("auto_throttle", on), "Holds the line's speed; you steer and can brake"), "auto_throttle"))
			add_row(_assist(UiKit.number("Brake assist", float(d.assists.brake_assist) * 100.0, 0, 100, 10, "%d%%", func(v: float) -> void: profile.set_assist("brake_assist", v / 100.0), "Brakes for corners and cars ahead"), "brake_assist"))
			add_row(_assist(UiKit.number("Steering assist", float(d.assists.steering_assist) * 100.0, 0, 100, 10, "%d%%", func(v: float) -> void: profile.set_assist("steering_assist", v / 100.0), "Steers toward the line"), "steering_assist"))
			add_row(_assist(UiKit.check("Autodrive", bool(d.assists.autodrive), func(on: bool) -> void: profile.set_assist("autodrive", on), "The car drives itself"), "autodrive"))
			add_row(_assist(UiKit.check("Item assist", bool(d.assists.get("item_assist", false)), func(on: bool) -> void: profile.set_assist("item_assist", on), "Kart: uses your item at a good moment"), "item_assist"))
		"Comfort":
			add_row(UiKit.slider("Camera shake", d.camera_shake, func(v: float) -> void: profile.set_value("camera_shake", v),
				"The view's rumble at speed"))
			add_row(UiKit.slider("Head movement", d.head_movement, func(v: float) -> void: profile.set_value("head_movement", v),
				"Cockpit view: the head sways as the car speeds up, brakes and turns"))
			add_row(UiKit.check("Speed FOV", d.speed_fov, func(on: bool) -> void: profile.set_value("speed_fov", on), "The view widens with speed"))
			add_row(UiKit.check("Horizon lock", d.horizon_lock, func(on: bool) -> void: profile.set_value("horizon_lock", on),
				"Cockpit, hood and bumper views: the horizon stays level"))
			add_row(UiKit.number("Game speed", d.game_speed * 100.0, 50, 100, 5, "%d%%", func(v: float) -> void: profile.set_value("game_speed", v / 100.0),
				"One player only. Slower laps don't go on leaderboards"))
		"Vision & Hearing":
			add_row(UiKit.spinner("Colours", Palette.PRESET_NAMES, d.palette, func(v: String) -> void:
				var was := String(profile.data.palette)
				profile.set_value("palette", v)
				if v == "custom" or was == "custom":
					_rebuild_at.call_deferred("Colours"), "Colourblind palettes"))
			if d.palette == "custom":
				for role: Array in [["good", "Good", "Time gained, valid laps"], ["bad", "Bad", "Time lost, invalid laps"],
						["line_fast", "Line: fast", "Racing line: full speed"], ["line_brake", "Line: brake", "Racing line: brake here"]]:
					var key: String = role[0]
					add_row(UiKit.color("  " + role[1], Palette.color(profile, key), func(c: Color) -> void:
						var custom: Dictionary = profile.data.palette_custom
						custom[key] = "#" + c.to_html(false)
						profile.save(), role[2]))
			add_row(UiKit.check("Reduce flashing", d.reduce_flashing, func(on: bool) -> void: profile.set_value("reduce_flashing", on), "At most 3 flashes a second, lower contrast"))
			add_row(UiKit.spinner("Narration", [["off", "Off"], ["menus", "Menus"], ["race", "Menus and race"]], d.narration,
				func(v: String) -> void: profile.set_value("narration", v), "Reads menus and race events aloud"))
			add_row(UiKit.number("Speech rate", d.narration_rate * 100.0, 50, 200, 10, "%d%%", func(v: float) -> void: profile.set_value("narration_rate", v / 100.0),
				"How fast narration and the spotter speak"))
			add_row(UiKit.spinner("Spotter", [["off", "Off"], ["markers", "Markers"], ["voice", "Voice"]], d.spotter,
				func(v: String) -> void: profile.set_value("spotter", v), "Car left, car right, clear"))
			add_row(UiKit.check("Captions", d.captions, func(on: bool) -> void: profile.set_value("captions", on), "Spoken lines as text"))
			add_row(UiKit.check("Shift light", d.shift_light, func(on: bool) -> void: profile.set_value("shift_light", on),
				"The rev bar flashes when it's time to shift"))
			add_row(UiKit.check("Slip indicator", d.slip_indicator, func(on: bool) -> void: profile.set_value("slip_indicator", on), "Tire icons light up when sliding"))
			add_row(UiKit.check("Close-car arrows", d.sound_arrows, func(on: bool) -> void: profile.set_value("sound_arrows", on), "Arrows at the screen edge"))
		"HUD & Display":
			add_row(UiKit.number("HUD size", d.hud_scale * 100.0, 50, 200, 10, "%d%%", func(v: float) -> void: profile.set_value("hud_scale", v / 100.0),
				"Your HUD's size"))
			add_row(UiKit.number("Menu text", d.text_scale * 100.0, 100, 200, 10, "%d%%", func(v: float) -> void: profile.set_value("text_scale", v / 100.0),
				"Text size in menus"))
			add_row(UiKit.check("High-contrast HUD", d.high_contrast, func(on: bool) -> void: profile.set_value("high_contrast", on),
				"Solid plates behind HUD text, thicker markers"))
			add_row(UiKit.spinner("Font", FONTS, d.font, func(v: String) -> void: profile.set_value("font", v), "Clear: an easy-to-read font"))
			add_row(UiKit.number("Brightness", d.brightness * 100.0, 50, 150, 5, "%d%%", func(v: float) -> void: profile.set_value("brightness", v / 100.0),
				"Your view's brightness"))
			add_row(UiKit.spinner("HUD", [["full", "Full"], ["minimal", "Minimal"], ["off", "Off"]], d.hud_preset,
				func(v: String) -> void: profile.set_value("hud_preset", v), "Everything, the essentials, or nothing; or pick below"))
			for element: Array in Hud.ELEMENTS:
				var id: String = element[0]
				add_row(UiKit.check("Show " + String(element[1]).to_lower(), id not in d.hud_hidden, func(on: bool) -> void:
					var hidden: Array = profile.data.hud_hidden
					hidden.erase(id)
					if not on:
						hidden.append(id)
					profile.save(), "In your HUD"))
		"Controls":
			if slot == null or slot.keyboard_zone() in ["", "full"]:
				add_row(UiKit.spinner("Keyboard", KEYBOARD, d.input.presets.keyboard, func(v: String) -> void: _set_input("presets", "keyboard", v),
					"The whole keyboard, or one side so two can share it"))
			add_row(UiKit.spinner("Controller", Bindings.presets_for("gamepad"), d.input.presets.gamepad, func(v: String) -> void: _set_input("presets", "gamepad", v),
				"Standard, or a layout for one hand"))
			add_row(UiKit.slider("Controller rumble", d.rumble, func(v: float) -> void: profile.set_value("rumble", v), "Slides, curbs and knocks"))
			add_row(UiKit.slider("Stick deadzone", d.pad_deadzone / 0.4, func(v: float) -> void:
				profile.set_value("pad_deadzone", v * 0.4)
				Players.refresh_all(), "How far a stick moves before it counts"))
			for action: String in Bindings.HOLD:
				add_row(UiKit.check("Toggle " + String(Bindings.ACTIONS[action].name).to_lower(), action in d.input.toggles, func(on: bool) -> void:
					var toggles: Array = profile.data.input.toggles
					toggles.erase(action)
					if on:
						toggles.append(action)
					profile.save(), "Press once to hold, again to let go"))
			add_row(UiKit.number("Menu repeat after", d.input.menu_delay, 0.2, 1.0, 0.05, "%.2f s", func(v: float) -> void: _set_input("", "menu_delay", v),
				"How long a held direction waits before it repeats"))
			add_row(UiKit.number("Menu repeat speed", d.input.menu_rate, 4, 20, 1, "%d / s", func(v: float) -> void: _set_input("", "menu_rate", v),
				"Steps a second while a direction is held"))
			add_row(UiKit.button("Buttons and keys", _open_bindings, "Rebind every action"))
			if slot:
				add_row(UiKit.button("Wheel setup", _open_wheel, "Device, axes, rotation and force feedback"))


func _reset(which: String) -> void:
	profile.reset_keys(RESETS[which])
	Players.refresh_all()
	theme = UiKit.page_theme_for(self) # the font may have changed back


func _reset_detail(which: String) -> String:
	return "Custom buttons and keys go too. Wheel setup stays." if which == "Controls" else ""


## Assists the class or mode doesn't allow show as "Not allowed here" and can't be changed.
func _assist(c: Control, key: String) -> Control:
	if allowed_assists.is_empty() or key in allowed_assists:
		return c
	var target := UiKit._focus_target(c)
	if target is BaseButton:
		(target as BaseButton).disabled = true
	elif target is Range:
		(target as Range).editable = false
	if target:
		target.accessibility_description = "Not allowed here"
	return c


## Builds the current tab again (rows came or went) with focus back on the row named `prefix`.
func _rebuild_at(prefix: String) -> void:
	show_tab(tab, prefix)


func _set_input(group: String, key: String, value: Variant) -> void:
	if group:
		profile.data.input[group][key] = value
	else:
		profile.data.input[key] = value
	profile.save()
	Players.refresh_all()


func _open_bindings() -> void:
	var menu := BindingsMenu.new()
	menu.profile = profile
	menu.slot = slot
	menu.crumbs = crumbs + PackedStringArray(["Buttons and keys"])
	open_over(menu)


func _open_wheel() -> void:
	var menu := WheelMenu.new()
	menu.slot = slot
	menu.crumbs = crumbs + PackedStringArray(["Wheel setup"])
	open_over(menu)
