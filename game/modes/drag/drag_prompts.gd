class_name DragPrompts
extends RefCounted
## What a drag prompt says, per player, per device (D169, docs/INPUT.md §9). A prompt never says
## "press the button" — it names the input the driver is actually holding, so a keyboard reads
## "Space", a pad reads "A" or "RB", and a wheel reads the pedal or the gate it really has.
##
## Three things decide it, all of them already known: which device the player last drove with
## (VehicleController.active_device), what they have bound (PlayerInput.has_binding, and
## WheelInput.has_clutch for a pedal), and what that input is called (Bindings.ref_label through
## PlayerInput.label_for). Bots get no prompts, so everything here returns "" for them.

## Which kind of device a label should come from, for what the player last drove with. A wheel
## and its pedals are sim devices.
const DEVICE := { "keyboard": "keyboard", "gamepad": "gamepad", "wheel": "sim" }
## Gate actions, 1st to 7th: an H-shifter's prompt names the gate it wants, not "shift up".
const GATES := ["gear_1", "gear_2", "gear_3", "gear_4", "gear_5", "gear_6", "gear_7"]
const ORDINALS := ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th"]


## The player's controls, or null for a bot.
static func input_of(r: Racer) -> PlayerInput:
	var p := r as SessionPlayer
	return p.controller.input if p and p.controller else null


## The kind of device to name inputs from: what they last drove with.
static func device_of(r: Racer) -> String:
	var p := r as SessionPlayer
	var active := String(p.controller.active_device) if p and p.controller else "keyboard"
	return String(DEVICE.get(active, "keyboard"))


## What `action` is called for this player, or "" if they have nothing bound to it.
static func label(r: Racer, action: String) -> String:
	var input := input_of(r)
	return input.label_for(action, device_of(r)) if input else ""


## This player shifts with a gate box: an H-shifter, or keys bound to the gears.
static func has_gates(r: Racer) -> bool:
	var input := input_of(r)
	if input == null:
		return false
	for action: String in GATES:
		if input.has_binding(action):
			return true
	return false


static func has_clutch(r: Racer) -> bool:
	var input := input_of(r)
	return input != null and (input.wheel.has_clutch() or input.has_binding("clutch"))


## What to do to shift into `gear`: the gate on a shifter, else the shift input.
## "3rd gate", "RB", "Shift up".
static func shift_text(r: Racer, gear: int) -> String:
	var input := input_of(r)
	if input == null:
		return ""
	if has_gates(r) and gear >= 1 and gear <= GATES.size():
		var gate := label(r, GATES[gear - 1])
		return "%s: %s" % [ORDINALS[gear - 1], gate] if gate else "%s gate" % ORDINALS[gear - 1]
	var up := label(r, "shift_up")
	return up if up else "Shift up"


## What to let go of on the green, named: "Release Space", "Release clutch", "Throttle".
## `action` comes from DragControl.launch_action.
static func launch_text(r: Racer, action: String) -> String:
	if input_of(r) == null:
		return ""
	if action == "throttle":
		var t := label(r, "throttle")
		return "Throttle: %s" % t if t else "Throttle"
	# A pedal is held by the foot, so it reads by name; a button reads by its own label.
	if action == "clutch" and has_clutch(r):
		var c := label(r, "clutch")
		return "Release %s" % c if c else "Release the clutch"
	var b := label(r, "brake")
	return "Release %s" % b if b else "Release the brake"


## Catching a shake: ease off, or stab the clutch if there is one to stab.
static func shake_text(r: Racer) -> String:
	if input_of(r) == null:
		return ""
	if has_clutch(r):
		var c := label(r, "clutch")
		return "Clutch! %s" % c if c else "Clutch!"
	var t := label(r, "throttle")
	return "Ease off %s" % t if t else "Ease off!"


## The bottle: "Boost: E", or just "Boost" with nothing bound.
static func boost_text(r: Racer) -> String:
	var b := label(r, "boost")
	return "Boost: %s" % b if b else "Boost"


## The two-step, named for what they are holding: "Hold Space, revs in the band".
static func two_step_text(r: Racer, action: String) -> String:
	if input_of(r) == null:
		return ""
	if action == "throttle":
		return "Revs in the band"
	var held := label(r, "clutch" if action == "clutch" else "brake")
	return "Hold %s, revs in the band" % held if held else "Revs in the band"


## The burnout: throttle against the brake, named.
static func burnout_text(r: Racer) -> String:
	if input_of(r) == null:
		return ""
	var t := label(r, "throttle")
	var b := label(r, "brake")
	return "Throttle %s + brake %s" % [t, b] if t and b else "Throttle and brake"
