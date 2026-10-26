class_name EventFlow
extends RefCounted
## One event being set up (docs/UI_FLOW.md §5, §6): where (`context`), what (`type`, `variant`,
## `tt`), and the choices so far (`event`, `track`, `class_id`, `cup`). The event pages share one.
## It knows the type's steps and crumbs, the tracks and classes it offers, what it remembers
## (`recall()`, `remember()`, in P1's profile under `event_memory`) and how it starts (`start()`).
##
## P4 moves Racing's Regular and Stock Car here; the other types still run on their old menus.

const STOCK_CAR := "official.track.stock_car"
## Racing's types and their names.
const RACING := {
	"regular": "Regular",
	"stock_car": "Stock Car",
	"kart": "Kart",
	"custom": "Custom",
}
## The types run on these pages so far (Drive again offers only them).
const MOVED := ["racing/regular", "racing/stock_car"]

## "local" (Local Drive), "host" (hosting, P8) or "change" (the lobby's Change event, P9).
var context := "local"
## "racing", "endless", "highway", "mini" or "free".
var type := "racing"
## Racing: "regular", "stock_car", "kart" or "custom". Mini Games: "sumo", "drag" or "kart_battle".
var variant := "regular"
## A time trial (Racing's switch).
var tt := false
var event := RaceEvent.new()
## A track's path; "" for types that make their own.
var track := ""
var class_id := ""
## A kart cup's path, or "".
var cup := ""


static func racing(variant_id: String, time_trial := false, where := "local") -> EventFlow:
	var f := EventFlow.new()
	f.context = where
	f.type = "racing"
	f.variant = variant_id
	f.tt = time_trial
	return f


## "racing/regular", "racing/regular/tt" (the key of its memory, before "online/").
func id() -> String:
	var out := type if variant.is_empty() else "%s/%s" % [type, variant]
	return out + "/tt" if tt else out


func memory_key() -> String:
	return id() if context == "local" else "online/" + id()


## The Settings page's title: "Regular race", "Stock Car time trial".
func name() -> String:
	if type == "racing":
		return "%s %s" % [RACING.get(variant, variant), "time trial" if tt else "cup" if not cup.is_empty() else "race"]
	return id().capitalize()


## The type in a breadcrumb: "Regular", "Stock Car Time Trial".
func crumb() -> String:
	if type == "racing":
		return String(RACING.get(variant, variant)) + (" Time Trial" if tt else "")
	return id().capitalize()


## The crumbs of the page `page` ("Settings", "Class", "Players").
func crumbs(page: String) -> PackedStringArray:
	var out := PackedStringArray(["Local Drive"])
	if context == "host":
		out = PackedStringArray(["Drive Online", "Host"])
	elif context == "change":
		out = PackedStringArray(["Drive Online", "Lobby"])
	if type == "racing":
		out.append("Racing")
	out.append(crumb())
	out.append(page)
	return out


## How the class is chosen: "pick" (the Class page), "fixed" (the type has one) or "card" (each
## player picks on their card: karts).
static func class_rule(type_id: String, variant_id: String) -> String:
	if variant_id in ["stock_car", "sumo"]:
		return "fixed"
	if variant_id in ["kart", "kart_battle"]:
		return "card"
	return "pick"


func has_class_step() -> bool:
	return class_rule(type, variant) == "pick"


## The step row's names (docs/UI_FLOW.md §5.1).
static func steps_for(where: String, type_id: String, variant_id: String, time_trial: bool) -> PackedStringArray:
	var out := PackedStringArray()
	if where == "host":
		out.append("Host")
	out.append_array(["Event", "Settings"])
	if class_rule(type_id, variant_id) == "pick":
		out.append("Class")
	if where != "local":
		out.append("Lobby")
	elif not time_trial: # a time trial's players come in P6; until then P1 drives
		out.append("Players")
	return out


func steps() -> PackedStringArray:
	return steps_for(context, type, variant, tt)


## What Next on the Settings page leads to (its description).
func next_hint() -> String:
	if has_class_step():
		return "Pick the class"
	if tt:
		return "Start driving"
	return "The players: each picks a car and a class" if class_rule(type, variant) == "card" else "The players: each picks a car"


func has_track() -> bool:
	return type == "racing"


## The tracks the type offers ([TrackLibrary.list() entries]): Regular every circuit, Stock Car
## the ovals. Hosting lists only tracks that can be shared.
func tracks() -> Array[Dictionary]:
	var out := TrackLibrary.list(true, context == "local", "circuit")
	if variant == "stock_car":
		out = out.filter(func(e: Dictionary) -> bool: return "oval" in e.get("tags", []))
	return out


## The class the type always uses, or "".
func fixed_class() -> String:
	return STOCK_CAR if variant == "stock_car" else ""


## The classes on the Class page: Track mode's for Regular.
func classes() -> Array[PlatformLoader.Result]:
	var out: Array[PlatformLoader.Result] = []
	for mode in GameModes.list():
		if mode.id == "track":
			out.append_array(GameModes.classes(mode))
	return out


## The type's last setup: its own memory, else the keys the old menus wrote (docs/UI_FLOW.md
## §5.8), else its defaults. Then fit() and the dev overrides (--race-laps and the rest).
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
	if not tt:
		Game.apply_dev_event(event)


func _recall_old() -> void:
	event = defaults()
	if variant in ["regular", "stock_car"] and not tt and Settings.race_event is Dictionary and not (Settings.race_event as Dictionary).is_empty():
		event = Settings.last_event()
	if variant == "regular":
		track = String(Settings.profile.get("last_track", ""))
		class_id = String(Settings.profile.get("last_platform", ""))


## A new setup: Regular 5 laps and 7 AI cars, Stock Car 10 and 11 (docs/UI_FLOW.md §6.1).
func defaults() -> RaceEvent:
	if tt:
		return RaceEvent.time_trial()
	var e := RaceEvent.new()
	e.kind = "race"
	e.race_laps = 10 if variant == "stock_car" else 5
	e.ai_count = 11 if variant == "stock_car" else 7
	return e


## Makes the setup one this type runs: its kind, the settings it has no rows for at their
## defaults, a track and a class it offers.
func fit() -> void:
	if tt:
		var sky := event
		event = RaceEvent.time_trial()
		for key in ["time", "time_rate", "weather", "env_seed"]:
			event.set(key, sky.get(key))
	elif type == "racing" and variant in ["regular", "stock_car"]:
		# Regular and Stock Car: the track's rules and the plain defaults for what they don't show.
		event.kind = "race"
		event.race_min = 0
		event.grid = "qualifying"
		event.track_limits = "lenient"
		event.ai_cars = "garage"
		event.start = "track"
		event.draft = "track"
		event.fuel_x = -1
		event.tyre_x = -1
	if has_track():
		var list := tracks()
		if not list.any(func(e: Dictionary) -> bool: return e.path == track):
			var picked := Game.selected_track("circuit")
			track = picked if list.any(func(e: Dictionary) -> bool: return e.path == picked) else String(list[0].path) if not list.is_empty() else ""
	if fixed_class():
		class_id = fixed_class()
	elif has_class_step():
		var ids := classes().map(func(r: PlatformLoader.Result) -> String: return String(r.platform.id))
		if class_id not in ids:
			var last := String(Settings.profile.get("last_platform", ""))
			class_id = last if last in ids else "official.track.gt" if "official.track.gt" in ids else String(ids[0]) if not ids.is_empty() else ""


## Saves the setup as this type's last.
func remember() -> void:
	var memory: Variant = Settings.profile.get("event_memory", {})
	var all: Dictionary = (memory as Dictionary).duplicate(true) if memory is Dictionary else {}
	all[memory_key()] = { "event": event.to_dict(), "track": track, "class_id": class_id, "cup": cup }
	Settings.set_value("event_memory", all)


## Starts the event (time trials: P1 alone until P6). Remembered first; Local Drive's is Drive
## again's too, and Game.flow_return keeps it for the results' "Event menu".
func start() -> void:
	remember()
	var data := to_dict()
	if context == "local":
		Settings.set_value("last_drive", data)
	Game.start_event(event, class_id, track)
	Game.flow_return = data


## The Players screen for this event; everyone Ready starts it.
func players_page() -> PlayersMenu:
	var players := PlayersMenu.new()
	players.platform_id = class_id
	players.started.connect(start)
	return players


func to_dict() -> Dictionary:
	return { "context": context, "type": type, "variant": variant, "tt": tt, "event": event.to_dict(), "track": track,
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


## Drive again's event (docs/UI_FLOW.md §5.2): the last one started from Local Drive, if its type
## runs on these pages and its track and class are still here; else null.
static func last_drive() -> EventFlow:
	var d: Variant = Settings.profile.get("last_drive", {})
	if not d is Dictionary or (d as Dictionary).is_empty():
		return null
	var f := from_dict(d)
	if f.id().trim_suffix("/tt") not in MOVED or not f.still_here():
		return null
	return f


## Its track and class are still installed.
func still_here() -> bool:
	if has_track() and TrackLibrary.resolve(track).is_empty():
		return false
	return class_id.is_empty() or PlatformLoader.load_official(class_id).ok()


## "Regular race · Piedmont Speedway · GT" (Drive again's description).
func summary() -> String:
	var bits := [name()]
	if has_track():
		bits.append(String(TrackLibrary.entry(track).get("name", track.get_file())))
	if class_id:
		var r := PlatformLoader.load_official(class_id)
		bits.append(String(r.platform.get("name", class_id)) if r.ok() else class_id)
	return " · ".join(bits)
