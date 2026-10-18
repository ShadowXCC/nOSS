class_name RaceEvent
extends RefCounted
## One track event and its rules (docs/GAMEMODES.md §1, MODE-02): which sessions it runs
## (practice, qualifying, race, or free drive and time trial on their own), the AI field, and
## the race rules, and the sky. The last race set up is remembered in settings.cfg. A highway
## event (§3) runs as one free session with its own rules (HighwayControl).

## "free" (free drive), "race" (a race weekend), "time_trial", "highway", "battle" (kart, an
## arena) or "sumo" (a mini-game on shrinking platforms).
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
## hits), its length in minutes, and a most-hits match's target (first to it wins; 0: time only).
var items := true
var battle_rule := "standing"
var battle_min := 5
var battle_hits := 10
## Sumo (docs/GAMEMODES.md §5): how many platforms are stacked (1-3), what's underneath
## ("lava" or "acid"), how a platform shrinks ("smooth", "crumble" or "stepped"), how long one
## takes to shrink away, and whether the bottom one stops at a pillar instead of vanishing.
var sumo_tiers := 2
var sumo_hazard := "lava"
var sumo_shrink := "smooth"
var sumo_secs := 90
var sumo_pillar := false
## The sky (ENV-01…03, D153): the time of day ("track": the track's own fixed sun, or a time),
## how fast it runs (game minutes per real minute; 0 stands still), the weather ("track": the
## track's own, "changing": fronts come and go), and the seed of the weather's fronts (0: picked
## when the session starts).
var time := "track"
var time_rate := 0
var weather := "track"
var env_seed := 0
## Endless (docs/GAMEMODES.md §4, D157): the road's seed and the biome it starts in (NossRoadGen
## order), traffic ("light", "normal" or "off"), oncoming traffic on, and what happens when local
## players drift far apart ("bring": the one behind is brought up; "hold": the leader is held).
var road_seed := 1
var biome := 1
var endless_traffic := "light"
var oncoming := true
var spread := "bring"

## The values each text field may take; the first is the default.
const CHOICES := {
	"kind": ["free", "race", "time_trial", "highway", "battle", "endless", "sumo"], "start": ["standing", "rolling"], "grid": ["qualifying", "reverse", "random"],
	"track_limits": ["lenient", "off", "strict"], "ai_cars": ["garage", "builtin"], "sub": ["cruise", "score", "run", "loop"],
	"battle_rule": ["standing", "hits"],
	"sumo_hazard": ["lava", "acid"], "sumo_shrink": ["smooth", "crumble", "stepped"],
	"time": ["track", "dawn", "morning", "noon", "afternoon", "dusk", "night"],
	"weather": ["track", "clear", "cloudy", "rain", "storm", "fog", "snow", "changing"],
	"endless_traffic": ["light", "normal", "off"], "spread": ["bring", "hold"],
}
## Time rates offered in menus (game minutes per real minute).
const TIME_RATES := [0, 1, 10, 30, 60, 120]
const KEYS := ["kind", "practice_min", "qualifying_min", "race_laps", "race_min", "ai_count", "ai_skill",
	"start", "grid", "collisions", "track_limits", "ai_cars", "sub", "police", "traffic", "run", "direction",
	"items", "battle_rule", "battle_min", "battle_hits",
	"sumo_tiers", "sumo_hazard", "sumo_shrink", "sumo_secs", "sumo_pillar",
	"time", "time_rate", "weather", "env_seed",
	"road_seed", "biome", "endless_traffic", "oncoming", "spread"]
## Written only for highway events (circuit events stay as older games and servers know them).
const HIGHWAY_KEYS := ["sub", "police", "traffic", "run", "direction"]
## Written only for battles, or with items off.
const KART_KEYS := ["items", "battle_rule", "battle_min", "battle_hits"]
## Written only for sumo matches.
const SUMO_KEYS := ["sumo_tiers", "sumo_hazard", "sumo_shrink", "sumo_secs", "sumo_pillar"]
## Written only for endless events.
const ENDLESS_KEYS := ["road_seed", "biome", "endless_traffic", "oncoming", "spread"]
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


## A sumo match: platforms that shrink until one car is left (D162).
static func sumo(tiers := 2, hazard := "lava") -> RaceEvent:
	var e := RaceEvent.new()
	e.kind = "sumo"
	e.ai_count = 7
	e.sumo_tiers = tiers
	e.sumo_hazard = hazard
	e.track_limits = "off"
	return e


## An endless drive (D157): the day and the weather go by on their own unless set.
static func endless(seed_value := 1, start_biome := 1) -> RaceEvent:
	var e := RaceEvent.new()
	e.kind = "endless"
	e.ai_count = 0
	e.road_seed = seed_value
	e.biome = start_biome
	e.track_limits = "off"
	e.time = "morning"
	e.time_rate = 30
	e.weather = "changing"
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
	if kind == "highway" or kind == "endless":
		return PackedStringArray(["free"])
	if kind == "battle":
		return PackedStringArray(["battle"])
	if kind == "sumo":
		return PackedStringArray(["sumo"])
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
		if key in SUMO_KEYS and kind != "sumo":
			continue
		if key in ENDLESS_KEYS and kind != "endless":
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
	e.battle_hits = clampi(e.battle_hits, 0, 50)
	e.sumo_tiers = clampi(e.sumo_tiers, 1, 3)
	e.sumo_secs = clampi(e.sumo_secs, 30, 300)
	e.time_rate = clampi(e.time_rate, 0, 600)
	e.env_seed = clampi(e.env_seed, 0, 0x7FFFFFFF)
	e.road_seed = clampi(e.road_seed, 0, 0x7FFFFFFF)
	e.biome = clampi(e.biome, 0, 6)
	# Text fields only take their known values (events also come from servers).
	for key: String in CHOICES:
		if e.get(key) not in CHOICES[key]:
			e.set(key, CHOICES[key][0])
	return e


## "5 laps" or "20 min".
func race_length_text() -> String:
	return "%d min" % race_min if race_min > 0 else "%d lap%s" % [race_laps, "" if race_laps == 1 else "s"]
