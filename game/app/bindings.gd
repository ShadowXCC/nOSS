class_name Bindings
extends RefCounted
## Input actions and their default keys and gamepad buttons (docs/INPUT.md §1). Keyboard
## keys can be rebound and are saved in the player profile. Analog gamepad axes are read
## directly by VehicleController; wheels go through noss_core (NossInput).

const ACTIONS := {
	"steer_left": { "name": "Steer left", "default_keys": [KEY_LEFT, KEY_A] },
	"steer_right": { "name": "Steer right", "default_keys": [KEY_RIGHT, KEY_D] },
	"throttle": { "name": "Throttle", "default_keys": [KEY_UP, KEY_W] },
	"brake": { "name": "Brake", "default_keys": [KEY_DOWN, KEY_S] },
	"handbrake": { "name": "Handbrake", "default_keys": [KEY_SPACE], "pad": [JOY_BUTTON_A] },
	"shift_up": { "name": "Shift up", "default_keys": [KEY_E], "pad": [JOY_BUTTON_RIGHT_SHOULDER] },
	"shift_down": { "name": "Shift down", "default_keys": [KEY_Q], "pad": [JOY_BUTTON_LEFT_SHOULDER] },
	"camera_next": { "name": "Camera", "default_keys": [KEY_C], "pad": [JOY_BUTTON_Y] },
	"look_back": { "name": "Look back", "default_keys": [KEY_B], "pad": [JOY_BUTTON_RIGHT_STICK] },
	"reset_car": { "name": "Reset car", "default_keys": [KEY_R], "pad": [JOY_BUTTON_BACK] },
	"hotswap_menu": { "name": "Change car", "default_keys": [KEY_TAB], "pad": [JOY_BUTTON_DPAD_UP] },
	"pause": { "name": "Pause", "default_keys": [KEY_ESCAPE], "pad": [JOY_BUTTON_START] },
}
## Actions shown in the bindings screen, in order.
const REBINDABLE := ["steer_left", "steer_right", "throttle", "brake", "handbrake", "shift_up", "shift_down", "camera_next", "look_back", "reset_car", "hotswap_menu"]

## Gamepad buttons only listen to this device, so wheels and pedals (which Godot also sees
## as joypads) can't trigger them. -1 until a gamepad is picked.
static var gamepad := -1


## Registers every action with defaults, then the profile's key overrides
## ({action: [keycodes]}).
static func apply(overrides := {}) -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.2)
		var keys: Array = overrides.get(action, ACTIONS[action]["default_keys"])
		for key: int in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for button: int in ACTIONS[action].get("pad", []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = button
			jb.device = gamepad
			InputMap.action_add_event(action, jb)


## Picks the gamepad whose buttons drive the actions.
static func use_gamepad(device: int, overrides := {}) -> void:
	if device == gamepad:
		return
	gamepad = device
	apply(overrides)


static func keys_for(action: String) -> Array:
	var keys := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			keys.append(ev.physical_keycode)
	return keys


static func key_label(action: String) -> String:
	var names := keys_for(action).map(func(k: int) -> String: return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k)))
	return " / ".join(names) if not names.is_empty() else "-"
