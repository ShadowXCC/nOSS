class_name Palette
extends RefCounted
## Colour palettes (ACC-02, docs/ACCESSIBILITY.md §2): Default, three colourblind presets and
## Custom, per player. Every colour cue in the HUD, flags, racing line and player markers
## comes from here, and every one also has a shape, icon or text. Includes colour-vision
## simulation (Machado et al. 2009, full severity) so tests can check that the colours that
## must differ still do.

const PRESET_NAMES := [["default", "Default"], ["deuteranopia", "Deuteranopia"], ["protanopia", "Protanopia"],
	["tritanopia", "Tritanopia"], ["custom", "Custom"]]

## Roles: good/bad (delta, lap valid), warn, the flags, the racing line by target speed
## (fast, lift, brake), slip, and the four player colours.
const PRESETS := {
	"default": {
		"good": Color("#5be673"), "bad": Color("#ff6659"), "warn": Color("#ffcc4d"),
		"flag_green": Color("#33bf4d"), "flag_yellow": Color("#ffd91a"), "flag_blue": Color("#3373ff"),
		"line_fast": Color("#40d966"), "line_lift": Color("#ffd633"), "line_brake": Color("#ff4033"),
		"slip": Color("#ffb21a"),
		"p1": Color("#E8B71A"), "p2": Color("#4FA3FF"), "p3": Color("#FF6B5E"), "p4": Color("#5FD08A"),
	},
	# Red-green (green-blind): blue for good, orange and vermilion for bad (Okabe-Ito).
	"deuteranopia": {
		"good": Color("#56b4e9"), "bad": Color("#e69f00"), "warn": Color("#f0e442"),
		"flag_green": Color("#009e73"), "flag_yellow": Color("#f0e442"), "flag_blue": Color("#0072b2"),
		"line_fast": Color("#56b4e9"), "line_lift": Color("#f0e442"), "line_brake": Color("#d55e00"),
		"slip": Color("#e69f00"),
		"p1": Color("#f0e442"), "p2": Color("#56b4e9"), "p3": Color("#d55e00"), "p4": Color("#cc79a7"),
	},
	# Red-green (red-blind): like deuteranopia, with a brighter vermilion (reds look dark).
	"protanopia": {
		"good": Color("#56b4e9"), "bad": Color("#ffb000"), "warn": Color("#f0e442"),
		"flag_green": Color("#009e73"), "flag_yellow": Color("#f0e442"), "flag_blue": Color("#0072b2"),
		"line_fast": Color("#56b4e9"), "line_lift": Color("#f0e442"), "line_brake": Color("#ff7a1a"),
		"slip": Color("#ffb000"),
		"p1": Color("#f0e442"), "p2": Color("#56b4e9"), "p3": Color("#ff7a1a"), "p4": Color("#cc79a7"),
	},
	# Blue-yellow: red against teal, no blue-yellow pairs.
	"tritanopia": {
		"good": Color("#00c2b8"), "bad": Color("#ff3d5a"), "warn": Color("#ff9ec4"),
		"flag_green": Color("#00a896"), "flag_yellow": Color("#ffffff"), "flag_blue": Color("#7a1f2b"),
		"line_fast": Color("#00c2b8"), "line_lift": Color("#f2f2f2"), "line_brake": Color("#ff3d5a"),
		"slip": Color("#ff3d5a"),
		"p1": Color("#ffffff"), "p2": Color("#00c2b8"), "p3": Color("#ff3d5a"), "p4": Color("#8c5aa8"),
	},
}
## Pairs that must stay apart (CIE76 ΔE) for each palette's own kind of colour vision.
const MUST_DIFFER := [["good", "bad"], ["flag_green", "flag_yellow"], ["flag_yellow", "flag_blue"],
	["line_fast", "line_brake"], ["line_lift", "line_brake"], ["line_fast", "line_lift"],
	["p1", "p2"], ["p1", "p3"], ["p1", "p4"], ["p2", "p3"], ["p2", "p4"], ["p3", "p4"]]
const MIN_DIFFERENCE := 20.0

## Machado 2009 simulation matrices at full severity, linear RGB.
const SIMULATION := {
	"protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
	"deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
	"tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}


## The palette a profile uses (custom colours over the default for any role they set).
static func of(profile: PlayerProfile) -> Dictionary:
	var id := String(profile.data.get("palette", "default")) if profile else "default"
	if id == "custom":
		var out: Dictionary = PRESETS.default.duplicate()
		var custom: Variant = profile.data.get("palette_custom", {})
		if custom is Dictionary:
			for role: String in custom:
				if out.has(role) and custom[role] is String and Color.html_is_valid(custom[role]):
					out[role] = Color.html(custom[role])
		return out
	return PRESETS.get(id, PRESETS.default)


static func color(profile: PlayerProfile, role: String) -> Color:
	return of(profile).get(role, Color.WHITE)


## How `c` looks with `kind` colour vision ("protanopia", "deuteranopia", "tritanopia").
static func simulate(c: Color, kind: String) -> Color:
	if not SIMULATION.has(kind):
		return c
	var m: Array = SIMULATION[kind]
	var lin := Vector3(_to_linear(c.r), _to_linear(c.g), _to_linear(c.b))
	var out := Vector3(
		m[0][0] * lin.x + m[0][1] * lin.y + m[0][2] * lin.z,
		m[1][0] * lin.x + m[1][1] * lin.y + m[1][2] * lin.z,
		m[2][0] * lin.x + m[2][1] * lin.y + m[2][2] * lin.z)
	return Color(_to_srgb(out.x), _to_srgb(out.y), _to_srgb(out.z), c.a)


## CIE76 colour difference.
static func difference(a: Color, b: Color) -> float:
	return _lab(a).distance_to(_lab(b))


static func _to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _to_srgb(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


static func _lab(c: Color) -> Vector3:
	var r := _to_linear(c.r)
	var g := _to_linear(c.g)
	var b := _to_linear(c.b)
	var x := (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	var y := 0.2126 * r + 0.7152 * g + 0.0722 * b
	var z := (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))
