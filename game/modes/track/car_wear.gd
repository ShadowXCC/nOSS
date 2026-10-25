class_name CarWear
extends RefCounted
## One car's fuel and tires (D209). Fuel burns with the engine's work (its platform's litres per
## kWh, times the event's fuel use), tires wear with the work done sliding them (a tire's life is
## so many MJ of it, times the event's tire wear) and grip less as they do, down to the
## platform's worn grip. The car's mass doesn't change with its fuel (conformance and the online
## checks stay as they are). A class without its own figures takes DEFAULT_FUEL and DEFAULT_TIRES.

const DEFAULT_FUEL := { "tank_l": 70.0, "l_per_kwh": 0.32 }
const DEFAULT_TIRES := { "life_mj": 60.0, "worn_grip": 0.85 }
## "Fuel low" under this many laps.
const LOW_LAPS := 2.0
## A car reset dry gets a splash: this many laps' fuel (or SPLASH_L before a lap's measured).
const SPLASH_LAPS := 1.5
const SPLASH_L := 8.0
## Racing laps lap_fuel looks back over.
const LAP_USES := 3

var tank_l := 70.0
var fuel_l := 70.0
## Litres per joule of engine work (0: no fuel use).
var l_per_j := 0.0
## Per tire: how worn, 0 (new) to 1 (worn out); the work that wears one out, J (0: no wear).
var wear := PackedFloat32Array()
var life_j := 0.0
var worn_grip := 0.85
## Fuel a racing lap uses, litres: the most of the last LAP_USES (0: no lap measured yet).
var lap_fuel := 0.0
var _lap_uses := PackedFloat32Array()
var _lap := -1
var _fuel_at_lap := 0.0
var _refilled := false


## Fuel and tires for `platform` with the event's multipliers (0: off).
static func make(platform: Dictionary, wheels: int, fuel_x: int, tyre_x: int) -> CarWear:
	var w := CarWear.new()
	var fuel: Dictionary = platform.get("fuel", DEFAULT_FUEL)
	var tires: Dictionary = platform.get("tires", {})
	w.tank_l = float(fuel.get("tank_l", DEFAULT_FUEL.tank_l))
	w.fuel_l = w.tank_l
	w.l_per_j = float(fuel.get("l_per_kwh", DEFAULT_FUEL.l_per_kwh)) / 3.6e6 * fuel_x
	var life := float(tires.get("life_mj", DEFAULT_TIRES.life_mj)) * 1e6
	w.life_j = life / tyre_x if tyre_x > 0 else 0.0
	w.worn_grip = float(tires.get("worn_grip", DEFAULT_TIRES.worn_grip))
	w.wear.resize(wheels)
	return w


## The engine did `engine_j` of work: its fuel burns. True if it has just run dry.
func burn(engine_j: float) -> bool:
	if l_per_j <= 0.0 or fuel_l <= 0.0:
		return false
	fuel_l = maxf(fuel_l - engine_j * l_per_j, 0.0)
	return fuel_l <= 0.0


## Each tire slid with `slide_j` of work.
func scrub(slide_j: PackedFloat32Array) -> void:
	if life_j <= 0.0:
		return
	for i in mini(slide_j.size(), wear.size()):
		wear[i] = minf(wear[i] + slide_j[i] / life_j, 1.0)


## Tire `i`'s grip share now.
func grip_of(i: int) -> float:
	return lerpf(1.0, worn_grip, wear[i]) if i < wear.size() else 1.0


## The tires' grip share, the worst one's (what the car can count on).
func tire_grip() -> float:
	var g := 1.0
	for i in wear.size():
		g = minf(g, grip_of(i))
	return g


## How much tread is left, 0..1 (the most worn tire).
func tread() -> float:
	var worst := 0.0
	for w in wear:
		worst = maxf(worst, w)
	return 1.0 - worst


## Laps of fuel left at the last lap's rate (INF before a lap is measured, or with no fuel use).
func laps_left() -> float:
	if l_per_j <= 0.0:
		return INF
	return fuel_l / lap_fuel if lap_fuel > 0.0 else INF


func uses_fuel() -> bool:
	return l_per_j > 0.0


func wears_tires() -> bool:
	return life_j > 0.0


## Called as the car starts lap `lap`: measures the last lap's fuel.
func lap_started(lap: int) -> void:
	if lap == _lap:
		return
	if _lap >= 1 and lap == _lap + 1 and _fuel_at_lap > fuel_l and not _refilled:
		# A slow lap (through the pits, behind a crash) burns less: it isn't a racing lap's measure.
		# Of the last few that are, the hungriest (a lap in a draft, or held up, burns less too).
		var used := _fuel_at_lap - fuel_l
		if lap_fuel <= 0.0 or used > lap_fuel * 0.75:
			_lap_uses.append(used)
			if _lap_uses.size() > LAP_USES:
				_lap_uses.remove_at(0)
			lap_fuel = Array(_lap_uses).max()
	_refilled = false
	_lap = lap
	_fuel_at_lap = fuel_l


## Reset while dry (or nearly): a splash of fuel to reach the pits on. True if it got one.
func splash() -> bool:
	if not uses_fuel():
		return false
	var want := lap_fuel * SPLASH_LAPS if lap_fuel > 0.0 else SPLASH_L
	if fuel_l >= want:
		return false
	fuel_l = minf(want, tank_l)
	_refilled = true
	return true


## A pit stop's service: `litres` of fuel (to the tank's top at most), and `tires` new tires
## (4: all, 2: the two most worn).
func service(litres: float, tires: int) -> void:
	fuel_l = minf(fuel_l + maxf(litres, 0.0), tank_l)
	_refilled = litres > 0.0 # a lap with a refill in it isn't a measure
	if tires >= wear.size():
		wear.fill(0.0)
	elif tires > 0:
		var order := range(wear.size())
		order.sort_custom(func(a: int, b: int) -> bool: return wear[a] > wear[b])
		for k in tires:
			wear[order[k]] = 0.0
