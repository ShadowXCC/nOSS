class_name RaceEvent
extends RefCounted
## One track event and its rules (docs/GAMEMODES.md §1, MODE-02): which sessions it runs
## (practice, qualifying, race, or free drive and time trial on their own), the AI field, and
## the race rules. The last race set up is remembered in settings.cfg. A highway event (§3) runs
## as one free session with its own rules (HighwayControl).

## "free" (free drive), "race" (a race weekend), "time_trial", "highway" or "battle" (kart, an
## arena).
var kind := "free"
## Highway: "cruise", "score" (score attack), "run" or "loop"; police on; traffic cars (-1: the
## track's own count); the run's id; the direction players start in (1 or -1; 0: both ways,
## turn about).
var sub := "cruise"
var police := false
var traffic := -1
var run := ""
var direction := 1
## Minutes; 0 = no such session.
var practice_min := 0
var qualifying_min := 0
## Race length: laps, or minutes when race_min > 0.
var race_laps := 5
var race_min := 0
var ai_count := 11
var ai_skill := 70.0
## "standing" or "rolling".
var start := "standing"
## Grid order: "qualifying", "reverse" (of qualifying) or "random".
var grid := "qualifying"
## Car-to-car contact; false = ghosted.
var collisions := true
## "off", "lenient" or "strict".
var track_limits := "lenient"
## AI cars: "garage" (garage and built-in cars the class takes) or "builtin".
var ai_cars := "garage"
## Kart (D139, D144): item boxes on; a battle's rule ("standing": last one standing, "hits": most
## hits) and its length in minutes.
var items := true
var battle_rule := "standing"
var battle_min := 5

## The values each text field may take; the first is the default.
const CHOICES := {
	"kind": ["free", "race", "time_trial", "highway", "battle"], "start": ["standing", "rolling"], "grid": ["qualifying", "reverse", "random"],
	"track_limits": ["lenient", "off", "strict"], "ai_cars": ["garage", "builtin"], "sub": ["cruise", "score", "run", "loop"],
	"battle_rule": ["standing", "hits"],
}
const KEYS := ["kind", "practice_min", "qualifying_min", "race_laps", "race_min", "ai_count", "ai_skill",
	"start", "grid", "collisions", "track_limits", "ai_cars", "sub", "police", "traffic", "run", "direction",
	"items", "battle_rule", "battle_min"]
## Written only for highway events (circuit events stay as older games and servers know them).
const HIGHWAY_KEYS := ["sub", "police", "traffic", "run", "direction"]
## Written only for battles, or with items off.
const KART_KEYS := ["items", "battle_rule", "battle_min"]
## Traffic cars at most.
const TRAFFIC_MAX := 400


static func free_drive() -> RaceEvent:
	var e := RaceEvent.new()
	e.kind = "free"
	e.ai_count = 0
	return e


static func time_trial() -> RaceEvent:
	var e := RaceEvent.new()
	e.kind = "time_trial"
	e.ai_count = 0
	return e


static func battle(rule := "standing", minutes := 5) -> RaceEvent:
	var e := RaceEvent.new()
	e.kind = "battle"
	e.ai_count = 7
	e.battle_rule = rule
	e.battle_min = minutes
	e.track_limits = "off"
	return e


static func highway(sub_mode := "cruise", with_police := false, traffic_cars := -1) -> RaceEvent:
	var e := RaceEvent.new()
	e.kind = "highway"
	e.ai_count = 0
	e.sub = sub_mode
	e.police = with_police
	e.traffic = traffic_cars
	e.track_limits = "off"
	return e


## The sessions in order: "free", "time_trial", or "practice", "qualifying", "race". A highway
## event is one free session (its own rules run beside it).
func sessions() -> PackedStringArray:
	if kind == "highway":
		return PackedStringArray(["free"])
	if kind == "battle":
		return PackedStringArray(["battle"])
	if kind != "race":
		return PackedStringArray([kind])
	var out := PackedStringArray()
	if practice_min > 0:
		out.append("practice")
	if qualifying_min > 0:
		out.append("qualifying")
	out.append("race")
	return out


func to_dict() -> Dictionary:
	var d := {}
	for key: String in KEYS:
		if key in HIGHWAY_KEYS and kind != "highway":
			continue
		if key in KART_KEYS and kind != "battle" and items:
			continue
		d[key] = get(key)
	return d


## Known keys of the right type are taken, anything else is ignored.
static func from_dict(d: Dictionary) -> RaceEvent:
	var e := RaceEvent.new()
	for key: String in KEYS:
		if d.has(key) and typeof(d[key]) in [typeof(e.get(key)), TYPE_INT, TYPE_FLOAT] and (typeof(e.get(key)) in [TYPE_INT, TYPE_FLOAT]) == (typeof(d[key]) in [TYPE_INT, TYPE_FLOAT]):
			e.set(key, d[key])
	e.ai_count = clampi(e.ai_count, 0, 15)
	e.ai_skill = clampf(e.ai_skill, 0.0, 100.0)
	e.race_laps = clampi(e.race_laps, 1, 99)
	e.practice_min = clampi(e.practice_min, 0, 120)
	e.qualifying_min = clampi(e.qualifying_min, 0, 120)
	e.race_min = clampi(e.race_min, 0, 240)
	e.traffic = clampi(e.traffic, -1, TRAFFIC_MAX)
	e.direction = clampi(e.direction, -1, 1)
	e.run = e.run.left(32)
	e.battle_min = clampi(e.battle_min, 1, 15)
	# Text fields only take their known values (events also come from servers).
	for key: String in CHOICES:
		if e.get(key) not in CHOICES[key]:
			e.set(key, CHOICES[key][0])
	return e


## "5 laps" or "20 min".
func race_length_text() -> String:
	return "%d min" % race_min if race_min > 0 else "%d lap%s" % [race_laps, "" if race_laps == 1 else "s"]
