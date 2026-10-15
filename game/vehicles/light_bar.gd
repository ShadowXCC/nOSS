class_name LightBar
extends Node
## A police car's light bar (D116, ACC-04). The bar's red and blue halves are drawn twice: on
## LAYER_NORMAL with a full pattern (each half's triple flashes in turn), and on LAYER_CALM for
## players with Reduce flashing on: halves taking slow turns, never off, at most CALM_HZ
## flashes a second in all. Each player's camera sees one (cull_mask_for). No light is cast.

const LAYER_NORMAL := Flash.LAYER_NORMAL
const LAYER_CALM := Flash.LAYER_CALM
## Reduce flashing: the halves take turns this many times a second each, so the bar flashes at
## most 2 × CALM_HZ a second (WCAG: no more than three).
const CALM_HZ := 1.5
## Reduce flashing: the off half stays this bright (lower contrast).
const CALM_LOW := 0.35
## The full pattern: a cycle this long, each half's triple flashes in its half of it.
const CYCLE_S := 0.6
const GLOW := 6.0
const COLORS := { "red": Color(1.0, 0.1, 0.08), "blue": Color(0.15, 0.35, 1.0) }

var vehicle: Vehicle
var _time := 0.0
var _dark := false
var _normal := {} # "red"/"blue" -> [StandardMaterial3D]
var _calm := {} # the same, on the calm copies
var _calm_nodes: Array[MeshInstance3D] = []


## A camera mask that shows the bars for `reduce_flashing` (and not the others).
static func cull_mask_for(reduce_flashing: bool, mask: int) -> int:
	return Flash.cull_mask_for(reduce_flashing, mask)


## The halves' brightness (0..1) at time `t`: {red, blue}.
static func pattern(t: float, calm: bool) -> Dictionary:
	if calm:
		var phase := fmod(t * CALM_HZ, 1.0)
		var red := phase < 0.5
		return { "red": 1.0 if red else CALM_LOW, "blue": CALM_LOW if red else 1.0 }
	var c := fmod(t, CYCLE_S) / CYCLE_S
	var half := 0 if c < 0.5 else 1
	var k := fmod(c * 2.0, 1.0) # within this half: three flashes
	var flash := 1.0 if fmod(k * 3.0, 1.0) < 0.55 else 0.0
	return { "red": flash if half == 0 else 0.0, "blue": flash if half == 1 else 0.0 }


## Finds the bar's halves on `vehicle`'s model and makes their calm copies. False if it has none.
func setup(v: Vehicle) -> bool:
	vehicle = v
	if v.visual == null:
		return false
	for half: String in COLORS:
		_normal[half] = []
		_calm[half] = []
		for mi: MeshInstance3D in v.visual.find_children("lightbar_" + half + "*", "MeshInstance3D", true, false):
			if mi.has_meta(&"light_bar_copy"):
				continue
			mi.layers = 1 << (LAYER_NORMAL - 1)
			mi.material_override = _glow(half)
			(_normal[half] as Array).append(mi.material_override)
			var copy := mi.duplicate() as MeshInstance3D
			copy.name = String(mi.name) + "_calm"
			copy.set_meta(&"light_bar_copy", true)
			copy.layers = 1 << (LAYER_CALM - 1)
			copy.material_override = _glow(half)
			(_calm[half] as Array).append(copy.material_override)
			mi.add_sibling(copy)
			_calm_nodes.append(copy)
	return not (_normal.red as Array).is_empty()


func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var on := vehicle.light_bar
	if not on and _dark:
		return # off, and already shown off
	_dark = not on
	_time = _time + delta if on else 0.0
	var full := pattern(_time, false) if on else { "red": 0.0, "blue": 0.0 }
	var calm := pattern(_time, true) if on else { "red": 0.0, "blue": 0.0 }
	for half: String in COLORS:
		for m: StandardMaterial3D in _normal[half]:
			m.emission_energy_multiplier = GLOW * float(full[half])
		for m: StandardMaterial3D in _calm[half]:
			m.emission_energy_multiplier = GLOW * float(calm[half])


func _glow(half: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c: Color = COLORS[half]
	m.albedo_color = c.darkened(0.6)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	return m
