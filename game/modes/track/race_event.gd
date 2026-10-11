class_name RaceEvent
extends RefCounted
## One track event and its rules (docs/GAMEMODES.md §1, MODE-02): which sessions it runs
## (practice, qualifying, race, or free drive and time trial on their own), the AI field, and
## the race rules. The last race set up is remembered in settings.cfg.

## "free" (free drive), "race" (a race weekend) or "time_trial".
var kind := "free"
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

const KEYS := ["kind", "practice_min", "qualifying_min", "race_laps", "race_min", "ai_count", "ai_skill",
	"start", "grid", "collisions", "track_limits", "ai_cars"]


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


## The sessions in order: "free", "time_trial", or "practice", "qualifying", "race".
func sessions() -> PackedStringArray:
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
	return e


## "5 laps" or "20 min".
func race_length_text() -> String:
	return "%d min" % race_min if race_min > 0 else "%d lap%s" % [race_laps, "" if race_laps == 1 else "s"]
