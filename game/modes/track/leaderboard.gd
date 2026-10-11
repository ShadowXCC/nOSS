class_name Leaderboard
extends RefCounted
## Local time-trial leaderboards (docs/GAMEMODES.md §6), one file per track:
## user://leaderboards/<track>.json, a list per platform. Entries record the platform's id and
## content hash, the game version, assists and setup. Only official platforms at full game
## speed are listed (ACC-08: slower game speed never counts).

const SCHEMA := "noss.leaderboard/1"
const KEEP := 20

static var dir := "user://leaderboards/"


static func path_for(track_id: String) -> String:
	return dir.path_join(track_id + ".json")


## Fastest first.
static func entries(track_id: String, platform_id: String) -> Array:
	var data := _load(track_id)
	var list: Variant = data.boards.get(platform_id, [])
	return list if list is Array else []


## Whether a lap may be listed: official platform, full game speed.
static func counts(entry: Dictionary) -> bool:
	return String(entry.get("platform", "")).begins_with("official.") and is_equal_approx(float(entry.get("game_speed", 1.0)), 1.0)


## Adds a lap; returns its place (1 = fastest), or 0 if it isn't listed.
static func submit(track_id: String, entry: Dictionary) -> int:
	if not counts(entry):
		return 0
	var data := _load(track_id)
	var platform: String = entry.platform
	var list: Array = data.boards.get(platform, [])
	list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	var place := list.find(entry) + 1
	data.boards[platform] = list.slice(0, KEEP)
	_save(track_id, data)
	return place if place <= KEEP else 0


static func _load(track_id: String) -> Dictionary:
	var path := path_for(track_id)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if data is Dictionary and data.get("schema") == SCHEMA and data.get("boards") is Dictionary:
		return data
	return { "schema": SCHEMA, "track": track_id, "boards": {} }


static func _save(track_id: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path_for(track_id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
