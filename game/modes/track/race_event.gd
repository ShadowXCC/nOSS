class_name RaceEvent
extends RefCounted
## One track event and its rules (docs/GAMEMODES.md §1, MODE-02): which sessions it runs
## (practice, qualifying, race, or free drive and time trial on their own), the AI field, and
## the race rules, and the sky. The last race set up is remembered in settings.cfg. A highway
## event (§3) runs as one free session with its own rules (HighwayControl).

## "free" (free drive), "race" (a race weekend), "time_trial", "highway", "battle" (kart, an
## arena), "sumo" (a mini-game on shrinking platforms) or "drag" (a mini-game on a strip).
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
## A time trial's minutes (online, the host's: a timed session, docs/UI_FLOW.md §7.7); 0 = no end.
var tt_min := 0
var qualifying_min := 0
## Race length: laps, or minutes when race_min > 0.
var race_laps := 5
var race_min := 0
var ai_count := 11
var ai_skill := 70.0
## "standing", "rolling" or "track" (the track's: its `rules`, D207).
var start := "track"
## Grid order: "qualifying", "reverse" (of qualifying) or "random".
var grid := "qualifying"
## Car-to-car contact; false = ghosted.
var collisions := true
## "off", "lenient" or "strict".
var track_limits := "lenient"
## AI cars: "garage" (garage and built-in cars the class takes) or "builtin".
var ai_cars := "garage"
## Track-mode rules a track may suggest (its `rules`, D207): drafting ("track", "off" or "on"),
## and fuel use and tire wear (-1: the track's, 0: off, 1-10: times the platform's own rate).
var draft := "track"
var fuel_x := -1
var tyre_x := -1
## Pack racing for the AI: the track's `rules.pack` with drafting on. Set by resolved() only.
var pack := false
## Kart (D139, D144): item boxes on; a battle's rule ("standing": last one standing, "hits": most
## hits), its length in minutes, and a most-hits match's target (first to it wins; 0: time only).
var items := true
var battle_rule := "standing"
var battle_min := 5
var battle_hits := 10
## Sumo (docs/GAMEMODES.md §5): how many platforms are stacked (1-5), what's underneath
## ("lava" or "acid"), how a platform shrinks ("smooth", "crumble" or "stepped"), how long one
## takes to shrink away, whether the bottom one stops at a pillar instead of vanishing, and
## whether the cars get the kart drift ("drift": the hop and a quick pivot, D219; "off": not, and
## the handbrake works again instead). The old "boost" reads as "drift".
var sumo_tiers := 2
var sumo_hazard := "lava"
var sumo_shrink := "smooth"
var sumo_secs := 90
var sumo_pillar := false
var sumo_drift := "drift"
## Drag (docs/GAMEMODES.md §6, D168-D173): the strip's length in metres (1/8, 1/4 or 1/2 mile),
## how many boost charges each driver gets (0-3), whether shifts are timed against the tach and
## whether the QTEs fire at all, then each gimmick on its own: the Christmas tree (with reaction
## times and red lights), the two-step rev hold, the burnout, the tire-shake save, the
## perfect-shift chain, over-rev strain, and whether crossing the centreline loses the pass.
var drag_length_m := 402
var drag_boost := 1
var drag_timing := true
var drag_qtes := true
var drag_tree := true
var drag_two_step := true
var drag_burnout := true
var drag_shake := true
var drag_chain := true
var drag_money_shift := true
var drag_centreline := true
## The sky (ENV-01…03, D153): the time of day ("track": the track's own fixed sun, or a time),
## how fast it runs (game minutes per real minute; 0 stands still), the weather ("track": the
## track's own, "changing": fronts come and go), and the seed of the weather's fronts (0: picked
## when the session starts).
var time := "track"
var time_rate := 0
var weather := "track"
var env_seed := 0
## Endless (docs/GAMEMODES.md §4, D157): the road's seed and the biome it starts in (NossRoadGen
## order), traffic ("light", "normal", "heavy" or "off"), oncoming traffic on, and what happens when local
## players drift far apart ("bring": the one behind is brought up; "hold": the leader is held); the
## road's lanes (2 or 4: one or two each way) and the side they're driven on ("right" or "left",
## D190); garage cars in the traffic (D191); speed traps (D193) and, with `police`, the police
## (D194).
var road_seed := 1
var biome := 1
var endless_traffic := "light"
var oncoming := true
var spread := "bring"
var lanes := 2
var drive_side := "right"
var garage_traffic := true
var speed_traps := false

## The values each text field may take; the first is the default.
const CHOICES := {
	"kind": ["free", "race", "time_trial", "highway", "battle", "endless", "sumo", "drag"], "start": ["track", "standing", "rolling"], "grid": ["qualifying", "reverse", "random"],
	"draft": ["track", "off", "on"],
	"track_limits": ["lenient", "off", "strict"], "ai_cars": ["garage", "builtin"], "sub": ["cruise", "score", "run", "loop"],
	"battle_rule": ["standing", "hits"],
	"sumo_hazard": ["lava", "acid"], "sumo_shrink": ["smooth", "crumble", "stepped"],
	"sumo_drift": ["drift", "off"],
	"time": ["track", "dawn", "morning", "noon", "afternoon", "dusk", "night"],
	"weather": ["track", "clear", "cloudy", "rain", "storm", "fog", "snow", "changing"],
	"endless_traffic": ["light", "normal", "heavy", "off"], "spread": ["bring", "hold"],
	"drive_side": ["right", "left"],
}
## Time rates offered in menus (game minutes per real minute).
const TIME_RATES := [0, 1, 10, 30, 60, 120]
const KEYS := ["kind", "practice_min", "qualifying_min", "tt_min", "race_laps", "race_min", "ai_count", "ai_skill",
	"start", "grid", "collisions", "track_limits", "ai_cars", "draft", "fuel_x", "tyre_x", "sub", "police", "traffic", "run", "direction",
	"items", "battle_rule", "battle_min", "battle_hits",
	"sumo_tiers", "sumo_hazard", "sumo_shrink", "sumo_secs", "sumo_pillar", "sumo_drift",
	"drag_length_m", "drag_boost", "drag_timing", "drag_qtes", "drag_tree", "drag_two_step",
	"drag_burnout", "drag_shake", "drag_chain", "drag_money_shift", "drag_centreline",
	"time", "time_rate", "weather", "env_seed",
	"road_seed", "biome", "endless_traffic", "oncoming", "spread", "lanes", "drive_side", "garage_traffic", "speed_traps"]
## Written only for highway events (circuit events stay as older games and servers know them).
const HIGHWAY_KEYS := ["sub", "police", "traffic", "run", "direction"]
## Written only for circuit events (free drive, time trial, race weekends).
const TRACK_KEYS := ["draft", "fuel_x", "tyre_x"]
## Written only for time trials.
const TT_KEYS := ["tt_min"]
## A time trial's minutes at most.
const TT_MAX := 60
## Fuel and tire multipliers at most.
const WEAR_X_MAX := 10
## Written only for battles, or with items off.
const KART_KEYS := ["items", "battle_rule", "battle_min", "battle_hits"]
## Written only for sumo matches.
const SUMO_KEYS := ["sumo_tiers", "sumo_hazard", "sumo_shrink", "sumo_secs", "sumo_pillar", "sumo_drift"]
## Written only for drag matches.
const DRAG_KEYS := ["drag_length_m", "drag_boost", "drag_timing", "drag_qtes", "drag_tree",
	"drag_two_step", "drag_burnout", "drag_shake", "drag_chain", "drag_money_shift", "drag_centreline"]
## Written only for endless events.
const ENDLESS_KEYS := ["road_seed", "biome", "endless_traffic", "oncoming", "spread", "lanes", "drive_side", "garage_traffic", "speed_traps"]
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


## A drag match: passes down a strip, two lanes at a time, until one car is left (D168).
static func drag(length_m := 402, boost := 1) -> RaceEvent:
	var e := RaceEvent.new()
	e.kind = "drag"
	e.ai_count = 7
	e.drag_length_m = length_m
	e.drag_boost = boost
	e.track_limits = "off" # the strip has its own rule: the centreline (D171)
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
## event is one free session (its own rules run beside it), a run one "run" session (RunControl).
func sessions() -> PackedStringArray:
	if kind == "highway" and sub == "run":
		return PackedStringArray(["run"])
	if kind == "highway" or kind == "endless":
		return PackedStringArray(["free"])
	if kind == "battle":
		return PackedStringArray(["battle"])
	if kind == "sumo":
		return PackedStringArray(["sumo"])
	if kind == "drag":
		return PackedStringArray(["drag"])
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
		if key in HIGHWAY_KEYS and kind != "highway" and not (key == "police" and kind == "endless"):
			continue
		if key in KART_KEYS and kind != "battle" and items:
			continue
		if key in SUMO_KEYS and kind != "sumo":
			continue
		if key in DRAG_KEYS and kind != "drag":
			continue
		if key in ENDLESS_KEYS and kind != "endless":
			continue
		if key in TRACK_KEYS and kind not in ["free", "race", "time_trial"]:
			continue
		if key in TT_KEYS and kind != "time_trial":
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
	e.tt_min = clampi(e.tt_min, 0, TT_MAX)
	e.race_min = clampi(e.race_min, 0, 240)
	e.traffic = clampi(e.traffic, -1, TRAFFIC_MAX)
	e.direction = clampi(e.direction, -1, 1)
	e.run = e.run.left(32)
	e.battle_min = clampi(e.battle_min, 1, 15)
	e.battle_hits = clampi(e.battle_hits, 0, 50)
	e.sumo_tiers = clampi(e.sumo_tiers, 1, SumoLayout.RADII.size())
	e.sumo_secs = clampi(e.sumo_secs, 30, 300)
	e.drag_length_m = clampi(e.drag_length_m, DragLayout.LENGTHS[0], DragLayout.LENGTHS[DragLayout.LENGTHS.size() - 1])
	e.drag_boost = clampi(e.drag_boost, 0, 3)
	e.time_rate = clampi(e.time_rate, 0, 600)
	e.env_seed = clampi(e.env_seed, 0, 0x7FFFFFFF)
	e.road_seed = clampi(e.road_seed, 0, 0x7FFFFFFF)
	e.biome = clampi(e.biome, 0, 6)
	e.lanes = 4 if e.lanes >= 4 else 2
	e.fuel_x = clampi(e.fuel_x, -1, WEAR_X_MAX)
	e.tyre_x = clampi(e.tyre_x, -1, WEAR_X_MAX)
	# Text fields only take their known values (events also come from servers).
	for key: String in CHOICES:
		if e.get(key) not in CHOICES[key]:
			e.set(key, CHOICES[key][0])
	return e


## The track's suggested rules (its `rules`, D207), every key there: a track without any races
## as tracks always have (standing start, no drafting, no fuel use or tire wear).
static func track_rules(track: TrackData) -> Dictionary:
	return rules_of(track.raw.get("rules", {}) if track else {})


## A track file's `rules` with every key filled in.
static func rules_of(own: Variant) -> Dictionary:
	var out := { "start": "standing", "draft": false, "fuel_x": 0, "tyre_x": 0, "pack": false }
	if own is Dictionary:
		for key: String in out:
			if (own as Dictionary).has(key):
				out[key] = own[key]
	return out


## A copy with the track's suggestions where this event keeps "Track's" (D207). The session
## races the copy; the remembered event keeps "Track's" for the next track.
func resolved(track: TrackData) -> RaceEvent:
	var e := RaceEvent.new()
	for key: String in KEYS:
		e.set(key, get(key))
	var rules := track_rules(track)
	if e.start == "track":
		e.start = "rolling" if String(rules.start) == "rolling" else "standing"
	if e.draft == "track":
		e.draft = "on" if bool(rules.draft) else "off"
	if e.fuel_x < 0:
		e.fuel_x = clampi(int(rules.fuel_x), 0, WEAR_X_MAX)
	if e.tyre_x < 0:
		e.tyre_x = clampi(int(rules.tyre_x), 0, WEAR_X_MAX)
	e.pack = e.draft == "on" and bool(rules.pack)
	return e


## "5 laps" or "20 min".
func race_length_text() -> String:
	return "%d min" % race_min if race_min > 0 else "%d lap%s" % [race_laps, "" if race_laps == 1 else "s"]
