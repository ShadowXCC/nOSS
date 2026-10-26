class_name EventFlow
extends RefCounted
## One event being set up (docs/UI_FLOW.md §5, §6): where (`context`), what (`type`, `variant`,
## `tt`), and the choices so far (`event`, `track`, `class_id`, `cup`). The event pages share one.
## It knows the type's steps and crumbs, the tracks and classes it offers, what it remembers
## (`recall()`, `remember()`, in P1's profile under `event_memory`) and how it starts (`start()`).

const STOCK_CAR := "official.track.stock_car"
const SUMO := "official.sumo.standard"
## The kart class a kart event starts from; each player picks their own on their card (D149).
const KART := "official.kart.medium"
## Racing's types and their names.
const RACING := {
	"regular": "Regular",
	"stock_car": "Stock Car",
	"kart": "Kart",
	"custom": "Custom",
}
## Mini Games' types and their names.
const MINI := {
	"sumo": "Sumo Wrestling",
	"drag": "Drag Strip",
	"kart_battle": "Kart Battle",
}
## The types without variants and their names.
const PLAIN := {
	"endless": "Endless",
	"highway": "Highway",
	"free": "Free Drive",
}

## "local" (Local Drive), "host" (hosting, P8) or "change" (the lobby's Change event, P9).
var context := "local"
## "racing", "endless", "highway", "mini" or "free".
var type := "racing"
## Racing: "regular", "stock_car", "kart" or "custom". Mini Games: "sumo", "drag" or "kart_battle".
## The others: "".
var variant := "regular"
## A time trial (Racing's switch).
var tt := false
var event := RaceEvent.new()
## A track's path (an arena's, a highway's); "" for types that make their own.
var track := ""
var class_id := ""
## A kart cup's path, or "" (a kart race).
var cup := ""
## Hosting: the server's options from the Host page (name, password, port, ...); its rotation is
## this event (server_config()).
var server: ServerConfig


static func make(type_id: String, variant_id := "", time_trial := false, where := "local") -> EventFlow:
	var f := EventFlow.new()
	f.context = where
	f.type = type_id
	f.variant = variant_id
	f.tt = time_trial
	return f


static func racing(variant_id: String, time_trial := false, where := "local") -> EventFlow:
	return make("racing", variant_id, time_trial, where)


## "racing/regular", "racing/regular/tt", "endless", "mini/drag" (the key of its memory, before
## "online/").
func id() -> String:
	var out := type if variant.is_empty() else "%s/%s" % [type, variant]
	return out + "/tt" if tt else out


func memory_key() -> String:
	return id() if context == "local" else "online/" + id()


## The Settings page's title: "Regular race", "Stock Car time trial", "Kart cup", "Drag Strip".
func name() -> String:
	if type == "racing":
		return "%s %s" % [RACING.get(variant, variant), "time trial" if tt else "cup" if not cup.is_empty() else "race"]
	return crumb()


## The type in a breadcrumb: "Regular", "Stock Car Time Trial", "Sumo Wrestling", "Free Drive".
func crumb() -> String:
	if type == "racing":
		return String(RACING.get(variant, variant)) + (" Time Trial" if tt else "")
	if type == "mini":
		return String(MINI.get(variant, variant))
	return String(PLAIN.get(type, type.capitalize()))


## The crumbs of the page `page` ("Settings", "Class", "Players").
func crumbs(page: String) -> PackedStringArray:
	var out := PackedStringArray(["Local Drive"])
	if context == "host":
		out = PackedStringArray(["Drive Online", "Host"])
	elif context == "change":
		out = PackedStringArray(["Drive Online", "Lobby"])
	if type == "racing":
		out.append("Racing")
	elif type == "mini":
		out.append("Mini Games")
	out.append(crumb())
	out.append(page)
	return out


## How the class is chosen: "pick" (the Class page), "fixed" (the type has one) or "card" (each
## player picks on their card: karts).
static func class_rule(_type_id: String, variant_id: String) -> String:
	if variant_id in ["stock_car", "sumo"]:
		return "fixed"
	if variant_id in ["kart", "kart_battle"]:
		return "card"
	return "pick"


func has_class_step() -> bool:
	return class_rule(type, variant) == "pick"


## The step row's names (docs/UI_FLOW.md §5.1).
static func steps_for(where: String, type_id: String, variant_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if where == "host":
		out.append("Host")
	out.append_array(["Event", "Settings"])
	if class_rule(type_id, variant_id) == "pick":
		out.append("Class")
	out.append("Players" if where == "local" else "Lobby")
	return out


func steps() -> PackedStringArray:
	return steps_for(context, type, variant)


## What Next on the Settings page leads to (its description).
func next_hint() -> String:
	if has_class_step():
		return "Pick the class"
	if context == "host":
		return "Start the server and open the lobby"
	return "The players: each picks a car and a class" if class_rule(type, variant) == "card" else "The players: each picks a car"


## The Settings page's Next: "Start hosting" when it hosts (no Class step), else "Next".
func next_text() -> String:
	return "Start hosting" if context == "host" and not has_class_step() else "Next"


## Sumo, Drag and Endless make their own ground; the rest are on a track.
func has_track() -> bool:
	return type in ["racing", "highway", "free"] or variant == "kart_battle"


## The kind of track the Track row offers: "circuit", "highway", "arena", or "" (Free Drive: a
## circuit or a highway).
func track_type() -> String:
	match type:
		"highway":
			return "highway"
		"free":
			return ""
	return "arena" if variant == "kart_battle" else "circuit"


## Free Drive on a highway.
func on_highway() -> bool:
	return type == "highway" or (type == "free" and TrackLibrary.type_of(track) == "highway")


## The tracks the type offers ([TrackLibrary.list() entries]): every circuit (ovals, kart and
## real-world ones), Stock Car only the ovals, Kart the kart and stunt tracks first; Highway the
## highways, Kart Battle the arenas, Free Drive every circuit and every highway. Hosting lists only
## tracks that can be shared.
func tracks() -> Array[Dictionary]:
	var personal := context == "local"
	if type == "free":
		var both := TrackLibrary.list(true, personal, "circuit")
		both.append_array(TrackLibrary.list(true, personal, "highway"))
		return both
	var out := TrackLibrary.list(true, personal, track_type())
	if variant == "stock_car":
		out = out.filter(func(e: Dictionary) -> bool: return "oval" in e.get("tags", []))
	elif variant == "kart":
		var karts := out.filter(_for_karts)
		karts.append_array(out.filter(func(e: Dictionary) -> bool: return not _for_karts(e)))
		out = karts
	return out


static func _for_karts(e: Dictionary) -> bool:
	return "kart" in e.get("tags", []) or "stunt" in e.get("tags", [])


## The class the type always uses, or "".
func fixed_class() -> String:
	match variant:
		"stock_car":
			return STOCK_CAR
		"sumo":
			return SUMO
	return ""


## The classes on the Class page: Track mode's for Regular, any mode's for Custom and Free Drive,
## the type's own mode's for Endless, Highway and Drag Strip. On a highway Free Drive leaves out
## the Drag classes: no automatic gearbox, so the highway's autodrive can't drive them.
func classes() -> Array[PlatformLoader.Result]:
	var only := ""
	match id().trim_suffix("/tt"):
		"racing/regular":
			only = "track"
		"endless", "highway":
			only = type
		"mini/drag":
			only = "drag"
	var out: Array[PlatformLoader.Result] = []
	for mode in GameModes.list():
		if (only and mode.id != only) or (type == "free" and mode.id == "drag" and on_highway()):
			continue
		out.append_array(GameModes.classes(mode))
	return out


## The type's last setup: its own memory, else the keys the old menus wrote (docs/UI_FLOW.md
## §5.8), else its defaults. Then fit() and, for a race, the dev overrides (--race-laps and the
## rest).
func recall() -> void:
	var memory: Variant = Settings.profile.get("event_memory", {})
	var saved: Variant = memory.get(memory_key()) if memory is Dictionary else null
	if saved is Dictionary and saved.get("event") is Dictionary and not (saved.event as Dictionary).is_empty():
		event = RaceEvent.from_dict(saved.event)
		track = String(saved.get("track", ""))
		class_id = String(saved.get("class_id", ""))
		cup = String(saved.get("cup", ""))
	else:
		_recall_old()
	fit()
	if event.kind == "race":
		Game.apply_dev_event(event)


## The old menus' memory (each read once, until the type has its own).
func _recall_old() -> void:
	event = defaults()
	var profile := Settings.profile
	var last: Variant
	match id():
		"racing/regular", "racing/stock_car", "racing/custom":
			if Settings.race_event is Dictionary and not (Settings.race_event as Dictionary).is_empty():
				event = Settings.last_event()
		"racing/kart", "mini/kart_battle":
			last = profile.get("last_kart")
			if last is Dictionary and last.get("event") is Dictionary:
				var battle := variant == "kart_battle"
				if (String(last.get("kind", "")) == "battle") == battle:
					event = RaceEvent.from_dict(last.event)
				track = TrackLibrary.resolve(String(last.get("arena" if battle else "track", "")))
				if not battle and last.get("kind") == "cup":
					cup = String(last.get("cup", ""))
			class_id = String(profile.get("last_kart_platform", ""))
		"endless":
			last = profile.get("last_endless")
		"highway":
			last = profile.get("last_highway")
		"mini/sumo":
			last = profile.get("last_sumo")
		"mini/drag":
			last = profile.get("last_drag")
			class_id = String(profile.get("last_drag_class", ""))
		"free":
			last = profile.get("last_free")
	if last is Dictionary and not (last as Dictionary).is_empty() and type != "racing" and variant != "kart_battle":
		event = RaceEvent.from_dict(last)
	if id() in ["racing/regular", "racing/regular/tt", "racing/custom", "racing/custom/tt", "highway", "free"]:
		track = String(profile.get("last_track", ""))
	if id() in ["racing/regular", "racing/regular/tt", "racing/custom", "racing/custom/tt", "free"]:
		class_id = String(profile.get("last_platform", ""))


## A new setup (docs/UI_FLOW.md §6.1): Regular 5 laps and 7 AI cars, Stock Car 10 and 11, Kart 3
## laps and 7 AI karts; the others as their old menus started.
func defaults() -> RaceEvent:
	if tt:
		return RaceEvent.time_trial()
	match id():
		"racing/regular", "racing/stock_car":
			var e := RaceEvent.new()
			e.kind = "race"
			e.race_laps = 10 if variant == "stock_car" else 5
			e.ai_count = 11 if variant == "stock_car" else 7
			return e
		"racing/kart":
			var e := RaceEvent.new()
			e.race_laps = 3
			e.ai_count = 7
			return e
		"racing/custom":
			var e := RaceEvent.new()
			e.kind = "race"
			return e
		"mini/kart_battle":
			return RaceEvent.battle()
		"mini/sumo":
			return RaceEvent.sumo()
		"mini/drag":
			return RaceEvent.drag()
		"endless":
			return RaceEvent.endless(EndlessCode.random_seed(), EndlessBiomes.index_of("forest"))
		"highway":
			return RaceEvent.highway("cruise", false, -1)
	return RaceEvent.free_drive()


## Makes the setup one this type runs: its kind, the settings it has no rows for at their
## defaults, a track and a class it offers.
func fit() -> void:
	# Online, time trials, kart cups and the highway's Score attack, Run and Loop wait for their
	# network code (docs/UI_FLOW.md §7.2, P10).
	if context != "local":
		tt = false
		cup = ""
		if type == "highway":
			event.sub = "cruise"
	if tt:
		var was := event
		event = RaceEvent.time_trial()
		var keep := ["time", "time_rate", "weather", "env_seed"]
		if variant == "custom":
			keep.append("track_limits")
		for key in keep:
			event.set(key, was.get(key))
	else:
		match id():
			"racing/regular", "racing/stock_car":
				# The track's rules and the plain defaults for what they don't show.
				event.kind = "race"
				event.race_min = 0
				event.grid = "qualifying"
				event.track_limits = "lenient"
				event.ai_cars = "garage"
				event.start = "track"
				event.draft = "track"
				event.fuel_x = -1
				event.tyre_x = -1
			"racing/kart":
				# One race, or a cup's: a random grid of built-in karts, no practice or qualifying.
				event.kind = "race"
				event.practice_min = 0
				event.qualifying_min = 0
				event.race_min = 0
				event.grid = "random"
				event.ai_cars = "builtin"
				event.race_laps = clampi(event.race_laps, 1, 10)
				event.ai_count = clampi(event.ai_count, 0, 11)
			"racing/custom":
				event.kind = "race"
			"mini/kart_battle":
				event.kind = "battle"
				event.ai_cars = "builtin"
				event.track_limits = "off"
				event.ai_count = clampi(event.ai_count, 0, 11)
				if event.battle_min not in [3, 5, 7, 10]:
					event.battle_min = 5
				if event.battle_hits not in [5, 10, 15, 20, 0]:
					event.battle_hits = 10
			"mini/sumo", "mini/drag", "endless", "highway":
				event.kind = "sumo" if variant == "sumo" else "drag" if variant == "drag" else type
				event.ai_count = clampi(event.ai_count, 0, 15 if variant == "drag" else 11)
			"free":
				event.kind = "free"
	if has_track():
		var list := tracks()
		if not list.any(func(e: Dictionary) -> bool: return e.path == track):
			# Kart starts on a kart track rather than the last one picked elsewhere.
			var picked := "" if variant == "kart" and not Game.dev.has("track") else Game.selected_track(track_type())
			if list.any(func(e: Dictionary) -> bool: return e.path == picked):
				track = picked
			elif variant == "kart" and not list.is_empty() and _for_karts(list[0]):
				track = String(list[0].path) # a kart track first
			else:
				track = String(list[0].path) if not list.is_empty() else ""
	if variant == "kart" and not cup.is_empty() and CupRun.load_file(cup).is_empty():
		cup = String(CupRun.list()[0].path) if not CupRun.list().is_empty() else ""
	if fixed_class():
		class_id = fixed_class()
	elif class_rule(type, variant) == "card":
		if class_id not in GameModes.kart_classes(KART):
			class_id = KART
	else:
		var ids := classes().map(func(r: PlatformLoader.Result) -> String: return String(r.platform.id))
		if class_id not in ids:
			var last := String(Settings.profile.get("last_platform", ""))
			class_id = last if last in ids else "official.track.gt" if "official.track.gt" in ids else String(ids[0]) if not ids.is_empty() else ""


## It can go on: a track to drive (an arena for a battle), and a cup with all its tracks.
func ready_to_go() -> bool:
	if has_track() and track.is_empty():
		return false
	if variant == "kart" and not tt and not cup.is_empty():
		return CupRun.missing_track(CupRun.load_file(cup)) < 0
	return true


## Saves the setup as this type's last.
func remember() -> void:
	var memory: Variant = Settings.profile.get("event_memory", {})
	var all: Dictionary = (memory as Dictionary).duplicate(true) if memory is Dictionary else {}
	all[memory_key()] = { "event": event_dict(), "track": track, "class_id": class_id, "cup": cup }
	Settings.set_value("event_memory", all)


## Every setting of the event, those its kind doesn't use too (RaceEvent.to_dict() leaves those
## out): Free Drive keeps its highway traffic, Kart its battle's rules.
func event_dict() -> Dictionary:
	var d := {}
	for key: String in RaceEvent.KEYS:
		d[key] = event.get(key)
	return d


## The event as it runs: Free Drive on a highway is a Cruise with or without its traffic.
func session_event() -> RaceEvent:
	if type == "free" and on_highway():
		var e := RaceEvent.highway("cruise", false, 0 if event.traffic == 0 else -1)
		for key in ["time", "time_rate", "weather", "env_seed"]:
			e.set(key, event.get(key))
		return e
	return event


## Starts the event for everyone who joined. Remembered first; Local Drive's is Drive again's too,
## and Game.flow_return keeps it for the results' "Event menu". Hosting, it hosts (host()).
func start() -> void:
	if context == "host":
		host()
		return
	remember()
	var data := to_dict()
	if context == "local":
		Settings.set_value("last_drive", data)
	var e := session_event()
	if variant == "kart" and not cup.is_empty() and not tt:
		Game.start_cup_race(CupRun.start(CupRun.load_file(cup), class_id, e))
	elif e.kind == "free":
		Game.start_free_drive("", class_id, false, false, track, e)
	else:
		Game.start_event(e, class_id, track if has_track() else "")
	Game.flow_return = data


## Hosting (docs/UI_FLOW.md §7.2): the server with this event, its lobby next (Net.joined). The
## host options are kept for next time, without the password. "" or why it couldn't.
func host() -> String:
	remember()
	var cfg := server_config()
	var saved := cfg.to_dict()
	saved.password = ""
	Settings.set_value("net_host", saved)
	if Net.host(cfg, Net.local_players()) != OK:
		return "Can't open UDP %d" % cfg.port
	return ""


## The server's config: the Host page's options, this event its one rotation item. Endless has no
## track (its road comes from its seed); Sumo and Drag make their own ground, so any track will do.
func server_config() -> ServerConfig:
	var cfg := server if server else ServerConfig.defaults()
	var where := ServerConfig.ENDLESS if type == "endless" else track if has_track() else ServerConfig.DEFAULT_TRACK
	cfg.rotation = [{ "track": where, "class": class_id, "event": session_event().to_dict() }]
	return cfg


## The Players screen for this event; everyone Ready starts it.
func players_page() -> PlayersMenu:
	var players := PlayersMenu.new()
	players.platform_id = class_id
	players.started.connect(start)
	return players


func to_dict() -> Dictionary:
	return { "context": context, "type": type, "variant": variant, "tt": tt, "event": event_dict(), "track": track,
		"class_id": class_id, "cup": cup }


static func from_dict(d: Dictionary) -> EventFlow:
	var f := EventFlow.new()
	f.context = String(d.get("context", "local"))
	f.type = String(d.get("type", "racing"))
	f.variant = String(d.get("variant", ""))
	f.tt = bool(d.get("tt", false))
	f.event = RaceEvent.from_dict(d.get("event", {}) if d.get("event") is Dictionary else {})
	f.track = String(d.get("track", ""))
	f.class_id = String(d.get("class_id", ""))
	f.cup = String(d.get("cup", ""))
	return f


## A type the pages know.
func known() -> bool:
	match type:
		"racing":
			return RACING.has(variant)
		"mini":
			return MINI.has(variant) and not tt
	return PLAIN.has(type) and variant.is_empty() and not tt


## Drive again's event (docs/UI_FLOW.md §5.2): the last one started from Local Drive, if its type
## is known and its track, cup and class are still here; else null.
static func last_drive() -> EventFlow:
	var d: Variant = Settings.profile.get("last_drive", {})
	if not d is Dictionary or (d as Dictionary).is_empty():
		return null
	var f := from_dict(d)
	if not f.known() or not f.still_here():
		return null
	return f


## Its track, cup and class are still installed.
func still_here() -> bool:
	if has_track() and TrackLibrary.resolve(track).is_empty():
		return false
	if not cup.is_empty() and (CupRun.load_file(cup).is_empty() or CupRun.missing_track(CupRun.load_file(cup)) >= 0):
		return false
	return class_id.is_empty() or PlatformLoader.load_official(class_id).ok()


## "Regular race · Piedmont Speedway · GT", "Kart cup · Spark Cup", "Endless · Cruiser" (Drive
## again's description). A kart event leaves the class out: each player picks their own.
func summary() -> String:
	var bits := [name()]
	if not cup.is_empty():
		bits.append(String(CupRun.load_file(cup).get("name", cup.get_file())))
	elif has_track():
		bits.append(String(TrackLibrary.entry(track).get("name", track.get_file())))
	if class_id and class_rule(type, variant) != "card":
		var r := PlatformLoader.load_official(class_id)
		bits.append(String(r.platform.get("name", class_id)) if r.ok() else class_id)
	return " · ".join(bits)
