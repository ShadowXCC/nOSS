extends GdUnitTestSuite
## Button glyphs (docs/UI_FLOW.md §10.2): the family of a pad from its vendor and name, the main
## window's last-used family, a player's own device and bindings, and a text chip when there's
## no glyph.

const PAD := 7
const SONY_PAD := 8


func before() -> void:
	Settings.use_folder("user://tests/glyphs")


func after() -> void:
	Devices.test_devices = []
	Devices.last_family = "keyboard"
	Settings.use_folder("user://")


func test_a_pads_family_from_its_vendor_and_name() -> void:
	assert_str(Devices.family_of(0x054C, "Wireless Controller")).is_equal("playstation")
	assert_str(Devices.family_of(-1, "PS4 Controller")).is_equal("playstation")
	assert_str(Devices.family_of(-1, "Sony PS5 pad")).is_equal("playstation")
	assert_str(Devices.family_of(-1, "DualSense Wireless Controller")).is_equal("playstation")
	assert_str(Devices.family_of(-1, "dualshock 3")).is_equal("playstation")
	assert_str(Devices.family_of(0x045E, "Xbox Series X Controller")).is_equal("xbox")
	# Switch pads get Xbox glyphs; "ps" inside a word isn't PlayStation.
	assert_str(Devices.family_of(0x057E, "Nintendo Switch Pro Controller")).is_equal("xbox")
	assert_str(Devices.family_of(-1, "Steelseries Stratus Duo")).is_equal("xbox")
	assert_str(Devices.family_of(-1, "Upside Gamepad")).is_equal("xbox")


func test_the_window_follows_the_last_device_used() -> void:
	Devices.test_devices = [_pad(PAD, 0x045E, "Xbox pad"), _pad(SONY_PAD, 0x054C, "Wireless Controller")]
	Devices.last_family = "keyboard"
	await _press_button(SONY_PAD, JOY_BUTTON_A)
	assert_str(Devices.last_family).is_equal("playstation")
	await _release_button(SONY_PAD, JOY_BUTTON_A)
	await _press_button(PAD, JOY_BUTTON_A)
	assert_str(Devices.last_family).is_equal("xbox")
	await _release_button(PAD, JOY_BUTTON_A)
	var key := InputEventKey.new()
	key.keycode = KEY_DOWN
	key.physical_keycode = KEY_DOWN
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	assert_str(Devices.last_family).is_equal("keyboard")
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().process_frame
	assert_array(Glyphs.inputs("confirm", "keyboard").map(func(i: Dictionary) -> String: return i.id)).is_equal(["enter"])
	assert_array(Glyphs.inputs("cancel", "playstation").map(func(i: Dictionary) -> String: return i.id)).is_equal(["circle"])
	assert_array(Glyphs.inputs("tabs", "xbox").map(func(i: Dictionary) -> String: return i.id)).is_equal(["lb", "rb"])


## A player's prompts read their own preset: the left-hand pad confirms with LB.
func test_left_hand_pads_confirm_shows_lb() -> void:
	Devices.test_devices = [_pad(PAD, 0x045E, "Xbox pad"), _pad(SONY_PAD, 0x054C, "Wireless Controller")]
	var slot := _slot(["pad:test#%d" % PAD], "pad_left_hand")
	assert_str(slot.glyph_family()).is_equal("xbox")
	var confirm := Glyphs.inputs("confirm", slot.glyph_family(), slot)
	assert_array(confirm.map(func(i: Dictionary) -> String: return i.id)).is_equal(["lb"])
	assert_str(String(confirm[0].text)).is_equal("LB")
	assert_array(Glyphs.inputs("cancel", "xbox", slot).map(func(i: Dictionary) -> String: return i.id)).is_equal(["lt"])
	# Left and right both on the d-pad: one glyph.
	assert_array(Glyphs.inputs("change", "xbox", slot).map(func(i: Dictionary) -> String: return i.id)).is_equal(["dpad"])
	var sony := _slot(["pad:test#%d" % SONY_PAD], "pad_left_hand")
	assert_str(sony.glyph_family()).is_equal("playstation")
	assert_array(Glyphs.inputs("confirm", "playstation", sony).map(func(i: Dictionary) -> String: return i.id)).is_equal(["l1"])
	var standard := _slot(["pad:test#%d" % SONY_PAD], "pad_standard")
	assert_array(Glyphs.inputs("confirm", "playstation", standard).map(func(i: Dictionary) -> String: return i.id)).is_equal(["cross"])
	# Tabs (§10.1): the left-hand pad has only Next tab, on L3; the standard one LB and RB.
	assert_array(Glyphs.inputs("tabs", "xbox", slot).map(func(i: Dictionary) -> String: return i.id)).is_equal(["l3"])
	assert_array(Glyphs.inputs("tabs", "playstation", standard).map(func(i: Dictionary) -> String: return i.id)).is_equal(["l1", "r1"])
	var right_keys := _slot(["kb:right"], "pad_standard")
	assert_array(Glyphs.inputs("tabs", "keyboard", right_keys).map(func(i: Dictionary) -> String: return i.id)).is_equal(["comma", "period"])


## A player with the keyboard and a pad: the prompts follow whichever fired their last menu action.
func test_a_players_prompts_follow_their_last_menu_device() -> void:
	Devices.test_devices = [_pad(PAD, 0x045E, "Xbox pad")]
	var slot := _slot(["kb:full", "pad:test#%d" % PAD], "pad_standard")
	assert_str(slot.glyph_family()).is_equal("keyboard") # their first device until they use one
	await _press_button(PAD, JOY_BUTTON_A)
	assert_array(slot.input.poll_menu(0.016)).contains(["menu_confirm"])
	await _release_button(PAD, JOY_BUTTON_A)
	assert_str(slot.glyph_family()).is_equal("xbox")
	assert_array(Glyphs.inputs("confirm", "xbox", slot).map(func(i: Dictionary) -> String: return i.id)).is_equal(["a"])
	slot.input.poll_menu(0.016)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	assert_array(slot.input.poll_menu(0.016)).contains(["menu_confirm"])
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().process_frame
	assert_str(slot.glyph_family()).is_equal("keyboard")
	assert_array(Glyphs.inputs("confirm", "keyboard", slot).map(func(i: Dictionary) -> String: return i.id)).is_equal(["enter"])
	assert_array(Glyphs.inputs("change", "keyboard", slot).map(func(i: Dictionary) -> String: return i.id)).is_equal(["arrows"])


## A wheel's buttons have no glyphs: their names show, as for any missing glyph.
func test_a_missing_glyph_is_a_text_chip() -> void:
	var chip := Glyphs.icon({ "id": "no_such_glyph", "text": "LB" }, "xbox")
	assert_str(chip.name).is_equal("Chip")
	var labels := chip.find_children("*", "Label", true, false)
	assert_int(labels.size()).is_equal(1)
	assert_str((labels[0] as Label).text).is_equal("LB")
	chip.free()
	var sim := Glyphs.of_ref({ "button": 2 }, "sim", "sim")
	assert_str(String(sim.id)).is_empty()
	assert_str(String(sim.text)).is_equal("Button 3")
	var glyph := Glyphs.icon({ "id": "a", "text": "A" }, "xbox")
	assert_object(glyph).is_instanceof(TextureRect)
	assert_str(String(glyph.accessibility_name)).is_equal("A")
	glyph.free()


## Every glyph the spec lists is in the game.
func test_every_listed_glyph_is_there() -> void:
	var ids := {
		"keyboard": ["enter", "space", "escape", "backspace", "arrows", "q", "e", "comma", "period", "w", "a", "s", "d", "f", "g", "tab"],
		"xbox": ["a", "b", "x", "y", "lb", "rb", "lt", "rt", "dpad", "l3", "r3", "left_stick", "right_stick", "view", "menu"],
		"playstation": ["cross", "circle", "square", "triangle", "l1", "r1", "l2", "r2", "dpad", "l3", "r3", "left_stick", "right_stick", "share", "options"],
	}
	var missing: Array[String] = []
	for family: String in ids:
		for id: String in ids[family]:
			if Glyphs.texture(family, id) == null:
				missing.append("%s/%s" % [family, id])
	assert_array(missing).is_empty()


func _slot(keys: PackedStringArray, pad_preset: String) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.profile = PlayerProfile.create("glyphs_test")
	slot.profile.data.input.presets.gamepad = pad_preset
	slot.device_keys = keys
	slot.refresh(Devices.list())
	return slot


func _press_button(device: int, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e) # Devices sees it too, as the window's last input
	await get_tree().process_frame


func _release_button(device: int, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = false
	Input.parse_input_event(e)
	await get_tree().process_frame


static func _pad(id: int, vendor: int, joy_name: String) -> Dictionary:
	return { "kind": "gamepad", "key": "pad:test#%d" % id, "name": joy_name, "id": id, "guid": "test%d" % id, "vendor": vendor, "product": 1, "preset": "pad_standard" }
