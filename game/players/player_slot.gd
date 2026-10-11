class_name PlayerSlot
extends RefCounted
## One local player (docs/ARCHITECTURE.md §6, LOC-01): number, profile, claimed devices,
## car, monitor, and where their menu input goes.

## Player colours, always shown with the number (never colour alone, docs/ACCESSIBILITY.md §1).
const COLORS := [Color("#E8B71A"), Color("#4FA3FF"), Color("#FF6B5E"), Color("#5FD08A")]

var index := 0
var profile: PlayerProfile
var input := PlayerInput.new()
## Devices.list() keys this player claimed; keyboard as "kb:full", "kb:left" or "kb:right".
var device_keys: PackedStringArray = []
## Car package; empty: the profile's last car.
var car_path := ""
## Monitor for this player's view; -1: the main window's.
var screen := -1
## The viewport this player's menu navigation goes to; null: none.
var menu_target: Viewport
var ready := false
## Dev: driven by the line follower instead of devices.
var ai := false


func number() -> int:
	return index + 1


func tag() -> String:
	return "P%d" % number()


## This player's colour from their own palette (colourblind presets change it).
func color() -> Color:
	return Palette.color(profile, "p%d" % (index % 4 + 1)) if profile else COLORS[index % COLORS.size()]


func display_name() -> String:
	return profile.display_name() if profile else tag()


## The keyboard zone this player has ("full", "left", "right"), or "" without the keyboard.
func keyboard_zone() -> String:
	for key in device_keys:
		if key.begins_with("kb:"):
			return key.substr(3)
	return ""


## Matches device_keys to the connected devices and rebuilds the input.
func refresh(all: Array[Dictionary]) -> void:
	var mine: Array[Dictionary] = []
	for key in device_keys:
		if key.begins_with("kb:"):
			var kb: Dictionary = all[0].duplicate() if not all.is_empty() and all[0].kind == "keyboard" else { "kind": "keyboard", "key": "kb", "name": "Keyboard", "id": -1, "guid": "kb" }
			kb.zone = key.substr(3)
			kb.key = key
			mine.append(kb)
			continue
		for d: Dictionary in all:
			if d.key == key:
				mine.append(d)
	input.profile = profile
	input.devices = mine
	input.rebuild()


## "Keyboard (left), Xbox One" style summary of what this player drives with.
func devices_text() -> String:
	var names := PackedStringArray()
	for d: Dictionary in input.devices:
		var zone := String(d.get("zone", "full"))
		names.append(d.name + ("" if zone == "full" or d.kind != "keyboard" else " (%s)" % zone))
	return ", ".join(names) if not names.is_empty() else "No device"
