class_name Leaderboard
extends RefCounted
## Local leaderboards (docs/GAMEMODES.md §7, D118), one file per track:
## user://leaderboards/<track>.json, a list per board. A board is a platform's id (time-trial
## laps), or a platform's id and what's timed or scored after "|": "|score" (score attack, most
## points first), "|loop+1" and "|loop-1" (a highway loop's laps each way), "|run:<id>" (a run).
## Entries record the platform's id and content hash, the game version, assists and setup, and
## whether the road was wet or snowy (D153). Only
## official platforms at full game speed are listed (ACC-08: slower game speed never counts).

const SCHEMA := "noss.leaderboard/1"
const KEEP := 20

static var dir := "user://leaderboards/"
## A server's own boards (online scores and laps it timed itself), apart from its player's.
static var server_dir := "user://leaderboards/server/"


static func path_for(track_id: String, server := false) -> String:
	return (server_dir if server else dir).path_join(track_id + ".json")


## Best first (fastest, or the most points on a score board).
static func entries(track_id: String, board: String, server := false) -> Array:
	var data := _load(track_id, server)
	var list: Variant = data.boards.get(board, [])
	return list if list is Array else []


## Whether `board` is ranked by points (most first) rather than time.
static func by_score(board: String) -> bool:
	return board.ends_with("|score")


## An entry for `r`'s car now, with `values` ({time} or {score}): driver, car, platform and its
## hash, the game's version, the assists it used, game speed, date.
static func entry_of(r: Racer, values: Dictionary) -> Dictionary:
	var v := r.vehicle
	var out := {
		"name": r.display_name, "car": v.package.display_name() if v and v.package else "", "platform": v.base_platform.get("id", "") if v else "",
		"platform_hash": v.platform_hash if v else "", "version": ProjectSettings.get_setting("application/config/version"),
		"assists": Array(PackedStringArray(r.assists_used.keys().filter(func(k: String) -> bool: return r.assists_used[k]))),
		"game_speed": Engine.time_scale, "date": Time.get_datetime_string_from_system(), "road": road_of(v),
	}
	out.merge(values, true)
	return out


## The road under a car (D153): "dry", "wet" or "snow". Wet and snowy laps go on the same boards,
## tagged.
static func road_of(v: Vehicle) -> String:
	if v == null:
		return "dry"
	var c := v.road_conditions()
	return "snow" if c.y > 0.25 else "wet" if c.x > 0.25 else "dry"


## Whether a lap may be listed: official platform, full game speed.
static func counts(entry: Dictionary) -> bool:
	return String(entry.get("platform", "")).begins_with("official.") and is_equal_approx(float(entry.get("game_speed", 1.0)), 1.0)


## Adds a lap (or a run's time, or a score) to `board` (the entry's platform if empty); returns
## its place (1 = best), or 0 if it isn't listed.
static func submit(track_id: String, entry: Dictionary, board := "", server := false) -> int:
	if not counts(entry):
		return 0
	var data := _load(track_id, server)
	var key := board if board else String(entry.platform)
	var list: Array = data.boards.get(key, [])
	list.append(entry)
	if by_score(key):
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
	else:
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	var place := list.find(entry) + 1
	data.boards[key] = list.slice(0, KEEP)
	_save(track_id, data, server)
	return place if place <= KEEP else 0


static func _load(track_id: String, server := false) -> Dictionary:
	var path := path_for(track_id, server)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if data is Dictionary and data.get("schema") == SCHEMA and data.get("boards") is Dictionary:
		return data
	return { "schema": SCHEMA, "track": track_id, "boards": {} }


static func _save(track_id: String, data: Dictionary, server := false) -> void:
	DirAccess.make_dir_recursive_absolute(server_dir if server else dir)
	var f := FileAccess.open(path_for(track_id, server), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
