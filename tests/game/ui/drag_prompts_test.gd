extends GdUnitTestSuite
## Drag prompts and panel (D169): a prompt names the input the driver is actually holding, so the
## same moment reads "Space" on a keyboard, "RB" on a pad and the gate it wants on an H-shifter;
## and the panel says in words whatever its colours show.

const SHIFTER := { "kind": "sim", "key": "sim:shifter", "name": "Test shifter", "id": 211, "guid": "shifter", "preset": "sim_generic", "wheel": false, "buttons": 12, "axes": 0 }
const PEDALS := { "kind": "sim", "key": "sim:pedals", "name": "Test pedals", "id": 212, "guid": "pedals", "preset": "sim_generic", "wheel": false, "buttons": 0, "axes": 3 }


func before() -> void:
	Settings.use_folder("user://tests/drag_prompts")


func after() -> void:
	PlayerInput.test_sim = {}
	Devices.test_devices = []
	Players.clear()
	Settings.use_folder("user://")


func _input_for(kind: String) -> PlayerInput:
	var profile := PlayerProfile.create("drag_" + kind)
	var i := PlayerInput.new()
	i.profile = profile
	match kind:
		"keyboard":
			i.devices = [{ "kind": "keyboard", "key": "kb", "name": "Keyboard", "id": -1, "guid": "kb", "preset": "kb_full" }]
		"gamepad":
			i.devices = [{ "kind": "gamepad", "key": "pad:test#0", "name": "Test pad", "id": 0, "guid": "test", "preset": "pad_standard" }]
		"sim":
			profile.data.input.bindings = {
				"sim:shifter": { "gear_1": [{ "button": 0 }], "gear_2": [{ "button": 1 }], "gear_3": [{ "button": 2 }] },
				"sim:pedals": { "clutch": [{ "axis": 2, "dir": 1, "rest": -1.0 }] },
			}
			i.devices = [SHIFTER, PEDALS]
	i.rebuild()
	return i


func test_an_input_is_named_for_the_device_it_is_on() -> void:
	var keys := _input_for("keyboard")
	# The bottle sits on the handbrake, which a pass has no use for; it cannot share the ram's
	# input, because the ram sits on shift up and a pass is all shifting (D173).
	assert_str(keys.label_for("boost", "keyboard")).is_equal("Space")
	assert_str(keys.label_for("brake", "keyboard")).is_not_empty()
	var pad := _input_for("gamepad")
	assert_str(pad.label_for("boost", "gamepad")).is_equal("A")
	# Nothing bound at all gives nothing back, rather than a made-up name.
	assert_str(pad.label_for("gear_4", "gamepad")).is_empty()


func test_a_shifters_gates_are_known_and_named() -> void:
	var sim := _input_for("sim")
	assert_bool(sim.has_binding("gear_2")).is_true()
	assert_str(sim.label_for("gear_2", "sim")).is_equal("Button 2")
	# A clutch on its own pedal set counts as a clutch.
	assert_bool(sim.has_binding("clutch")).is_true()


func test_prompts_say_nothing_for_a_bot() -> void:
	var bot := AiRacer.new()
	bot.configure(0, 80.0)
	assert_object(DragPrompts.input_of(bot)).is_null()
	assert_str(DragPrompts.shift_text(bot, 2)).is_empty()
	assert_str(DragPrompts.launch_text(bot, "brake")).is_empty()
	assert_str(DragPrompts.shake_text(bot)).is_empty()
	assert_str(DragPrompts.two_step_text(bot, "clutch")).is_empty()
	bot.free()


func test_the_panel_says_in_words_what_its_colours_show() -> void:
	var panel := DragPanel.new()
	add_child(panel)
	# Inside the window: "Shift now", and the chain and the bottles counted.
	panel.show_drag({ "state": "Go", "gear": 2, "needle": 0.72, "window": [0.72, 0.17],
		"chain": 2, "boosts": 1, "boost_name": "Boost: Space", "prompt": "2nd gate", "units": "metric" })
	assert_str(panel.state_text()).is_equal("Go")
	assert_str(panel.extras_text()).contains("Shift now")
	assert_str(panel.extras_text()).contains("Chain x3")
	assert_str(panel.extras_text()).contains("Boost: Space x1")
	assert_str(panel.prompt_text()).is_equal("2nd gate")
	# Over-revving and a blown engine are words, not just a red bar.
	panel.show_drag({ "state": "Go", "gear": 3, "needle": 1.1, "window": [0.8, 0.11], "over_rev": true, "units": "metric" })
	assert_str(panel.extras_text()).contains("Over-revving")
	panel.show_drag({ "state": "Go", "gear": 3, "needle": 1.2, "window": [0.8, 0.11], "blown": true, "units": "metric" })
	assert_str(panel.extras_text()).contains("Engine gone")
	# The numbers, in the player's own units, and the whole lot spoken.
	panel.show_drag({ "state": "Through the lights", "gear": 6, "reaction": 0.042, "et": 9.871,
		"trap": 60.0, "units": "imperial" })
	assert_str(panel.numbers_text()).contains("RT 0.042")
	assert_str(panel.numbers_text()).contains("ET 9.871")
	assert_str(panel.numbers_text()).contains("134 mph")
	assert_str(String(panel.accessibility_name)).contains("Through the lights")
	assert_str(String(panel.accessibility_name)).contains("ET 9.871")
	panel.queue_free()
