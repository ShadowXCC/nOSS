class_name CupRun
extends RefCounted
## A cup in progress (D145): four kart races in a row, points by finishing place (15, 12, 10, 8,
## 6, 4, 2, 1), ties to the most wins, then the better last race. The AI field stays the same
## through it (names, cars, paint, skill: the roster), and each race after the first starts in
## reverse order of the standings. Online the server keeps one (NetHost), its races the host's
## playlist (docs/NETWORKING.md §15). Built-in cups are in data/cups/, players' own in user://cups/
## (noss.cup/1).

const POINTS := [15, 12, 10, 8, 6, 4, 2, 1]
const BUILTIN_DIR := "res://data/cups/"
## The player's own cups (tests point it at their own folder).
static var user_dir := "user://cups/"
const SCHEMA := "noss.cup/1"

## The cup ({schema, id, name, races: [{track, laps}]}).
var cup := {}
var platform_id := ""
## The event each race copies (AI count and skill, items).
var template := RaceEvent.new()
## The race running or next (0-3).
var index := 0
## The AI field by AI index: [{car, paint, skill, class}], filled from the first race.
var roster: Array = []
## Racer key -> {name, points, wins, places: [int]}.
var table := {}


static func start(c: Dictionary, platform: String, base: RaceEvent) -> CupRun:
	var run := CupRun.new()
	run.cup = c
	run.platform_id = platform
	run.template = base
	return run


## Built-in cups, then the player's own: [{id, name, path, builtin}].
static func list() -> Array:
	var out := []
	for dir: String in [BUILTIN_DIR, user_dir]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for file: String in files:
			if file.ends_with(".cup.json"):
				var c := load_file(dir + file)
				if not c.is_empty():
					out.append({ "id": c.id, "name": c.name, "path": dir + file, "builtin": dir == BUILTIN_DIR })
	return out


## A cup file, checked; {} if it isn't one.
static func load_file(path: String) -> Dictionary:
	var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return c if c is Dictionary and check(c).is_empty() else {}


## What's wrong with cup `c` ("" if nothing).
static func check(c: Dictionary) -> String:
	if c.get("schema") != SCHEMA:
		return "Not a cup"
	if String(c.get("name", "")).strip_edges().is_empty():
		return "No name"
	var races: Variant = c.get("races")
	if not races is Array or (races as Array).size() != 4:
		return "Needs four races"
	for r: Variant in races:
		if not r is Dictionary or String(r.get("track", "")).is_empty() or int(r.get("laps", 0)) < 1 or int(r.get("laps", 0)) > 10:
			return "A race needs a track and 1 to 10 laps"
	return ""


## The first race whose track isn't here (its index), or -1.
static func missing_track(c: Dictionary) -> int:
	var races: Array = c.get("races", [])
	for i in races.size():
		if TrackLibrary.resolve(String(races[i].track)).is_empty():
			return i
	return -1


## Saves the player's cup `c` (its id from its name if it has none); "" or why not.
static func save(c: Dictionary) -> String:
	var why := check(c)
	if why:
		return why
	if String(c.get("id", "")).is_empty():
		c.id = _id_for(String(c.name))
	DirAccess.make_dir_recursive_absolute(user_dir)
	var f := FileAccess.open(user_dir + String(c.id) + ".cup.json", FileAccess.WRITE)
	if f == null:
		return "Can't save"
	f.store_string(JSON.stringify(c, "  ", false))
	return ""


static func delete(id: String) -> void:
	DirAccess.remove_absolute(user_dir + id + ".cup.json")


## A free id from a name: "My Cup" -> "my_cup", "my_cup_2"...
static func _id_for(cup_name: String) -> String:
	var base := cup_name.to_lower().strip_edges()
	var out := ""
	for ch in base:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while "__" in out:
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_").left(32)
	if out.is_empty():
		out = "cup"
	var id := out
	var n := 2
	while FileAccess.file_exists(user_dir + id + ".cup.json") or FileAccess.file_exists(BUILTIN_DIR + id + ".cup.json"):
		id = "%s_%d" % [out, n]
		n += 1
	return id


func races() -> Array:
	return cup.get("races", [])


func done() -> bool:
	return index >= races().size()


func track_for(i: int) -> String:
	return TrackLibrary.resolve(String(races()[i].track))


## Race `i`'s event: a race and nothing before it, the cup's laps, a random grid for the first
## and the standings reversed after.
func event_for(i: int) -> RaceEvent:
	var e := RaceEvent.from_dict(template.to_dict())
	e.kind = "race"
	e.practice_min = 0
	e.qualifying_min = 0
	e.race_min = 0
	e.race_laps = int(races()[i].laps)
	e.grid = "random" if i == 0 else "reverse"
	e.ai_cars = "builtin"
	return e


## A racer's key in the table: the player's slot (online, their id on the server), or the AI's name.
static func key_of(r: Racer) -> String:
	if r.net_id > 0 and r.net_id < NetProtocol.FIRST_AI_ID:
		return "net:%d" % r.net_id
	if r is SessionPlayer:
		return "p%d" % (r as SessionPlayer).slot.index
	return "ai:" + r.display_name


## A race's results (RaceControl rows) go into the table; the field's cars and paint are kept.
func add_results(rows: Array) -> void:
	for row: Dictionary in rows:
		var r: Racer = row.racer
		var key := key_of(r)
		var t: Dictionary = table.get(key, { "name": r.display_name, "points": 0, "wins": 0, "places": [] })
		var place := int(row.position)
		t.name = r.display_name
		t.points = int(t.points) + (POINTS[place - 1] if place <= POINTS.size() and not row.get("dnf", false) else 0)
		t.wins = int(t.wins) + (1 if place == 1 else 0)
		(t.places as Array).append(place)
		table[key] = t
	index += 1


## The AI field of the race just run, to keep for the next ones.
func keep_roster(session: TrackSession) -> void:
	if not roster.is_empty():
		return
	for r in session.racers:
		var a := r as AiRacer
		if a == null or a.vehicle == null or a.vehicle.package == null:
			continue
		var i := a.number - 5
		while roster.size() <= i:
			roster.append({})
		roster[i] = { "car": a.vehicle.package.path, "paint": a.paint, "skill": a.skill, "class": a.platform.platform.id }


## The table in order: [{key, name, points, wins, places}], points first, then wins, then the
## better last race.
func standings() -> Array:
	var out := []
	for key: String in table:
		var t: Dictionary = table[key].duplicate()
		t.key = key
		out.append(t)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.points) != int(b.points):
			return int(a.points) > int(b.points)
		if int(a.wins) != int(b.wins):
			return int(a.wins) > int(b.wins)
		var la: int = (a.places as Array).back() if not (a.places as Array).is_empty() else 99
		var lb: int = (b.places as Array).back() if not (b.places as Array).is_empty() else 99
		if la != lb:
			return la < lb
		return String(a.key) < String(b.key))
	return out


## The next race's grid, front first: the standings reversed (keys).
func grid_keys() -> Array:
	var order := standings().map(func(t: Dictionary) -> String: return t.key)
	order.reverse()
	return order
