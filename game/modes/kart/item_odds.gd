class_name ItemOdds
extends RefCounted
## Which item a kart's box gives (data/items/odds.json, D140): by its place in a race, 0 for the
## leader to 1 for last, or by lives lost in a battle. Stronger items further back are the only
## catch-up (AI-05). The Leader Hunter only goes to the back of a big enough field, one at a
## time, with a cooldown.

const PATH := "res://data/items/odds.json"
const ITEMS := ["nitro", "nitro_x3", "oil_slick", "bolt", "seeker", "leader_hunter", "shield", "emp", "magnet"]
const NAMES := {
	"nitro": "Nitro", "nitro_x3": "Nitro ×3", "oil_slick": "Oil Slick", "bolt": "Bolt", "seeker": "Seeker",
	"leader_hunter": "Leader Hunter", "shield": "Shield", "emp": "EMP", "magnet": "Magnet",
}
## Uses in one slot (a triple is one item).
const COUNTS := { "nitro_x3": 3 }

var race_bands: Array = []
var battle_bands: Array = []
var hunter := { "from_place": 0.6, "min_karts": 4, "max_active": 1, "cooldown_s": 20.0 }
## Dev (--odds=cycle): items in turn, for checks that every item gets used.
var cycle := false
var _next := 0


static func load_default() -> ItemOdds:
	var o := ItemOdds.new()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or not JsonSchema.validate(data, JsonSchema.load_schema("item_odds")).is_empty():
		push_error("Invalid item odds: " + PATH)
		return o
	o.race_bands = data.race.bands
	o.battle_bands = data.battle.bands
	o.hunter = data.race.leader_hunter
	return o


static func item_name(item: String) -> String:
	return NAMES.get(item, item)


static func count_of(item: String) -> int:
	return COUNTS.get(item, 1)


## A race's roll: `place` 0 (leading) .. 1 (last) among `karts`; `hunters` Leader Hunters out now
## and `since_hunter` seconds since the last was given.
func roll(place: float, karts: int, rng: RandomNumberGenerator, hunters := 0, since_hunter := INF) -> String:
	if cycle:
		var item: String = ITEMS[_next % ITEMS.size()]
		_next += 1
		return item
	var odds := _band(race_bands, place).duplicate()
	var hunter_ok := place >= float(hunter.from_place) and karts >= int(hunter.min_karts) \
		and hunters < int(hunter.max_active) and since_hunter >= float(hunter.cooldown_s)
	if not hunter_ok:
		odds.erase("leader_hunter")
	return _pick(odds, rng)


## A battle's roll by lives lost (no Leader Hunter there).
func roll_battle(lives_lost: int, rng: RandomNumberGenerator) -> String:
	if cycle:
		var items := ITEMS.filter(func(i: String) -> bool: return i != "leader_hunter")
		var item: String = items[_next % items.size()]
		_next += 1
		return item
	var odds := _band(battle_bands, float(lives_lost)).duplicate()
	odds.erase("leader_hunter")
	return _pick(odds, rng)


## The first band reaching `x` (the last one past them all).
func _band(bands: Array, x: float) -> Dictionary:
	for b: Dictionary in bands:
		if x <= float(b.upto) + 1e-6:
			return b.odds
	return bands.back().odds if not bands.is_empty() else { "nitro": 1 }


func _pick(odds: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in odds:
		total += float(odds[k])
	if total <= 0.0:
		return "nitro"
	var r := rng.randf() * total
	for k: String in odds:
		r -= float(odds[k])
		if r < 0.0:
			return k
	return String(odds.keys().back())
