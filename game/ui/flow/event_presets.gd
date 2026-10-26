class_name EventPresets
extends RefCounted
## Custom's saved setups (docs/UI_FLOW.md §6.1): each a named copy of the Settings page's rows and
## the class, in user://event_presets/<slug>.json (a time trial's <slug>_tt.json):
## {schema, name, tt, event, track, class_id}. A race's presets and a time trial's are listed
## apart. Saving under a name that's there replaces it.

const SCHEMA := "noss.event_preset/1"

## The folder (Settings.use_folder points it at a test's).
static var dir := "user://event_presets/"


## The presets of a race (or with `tt`, a time trial), by name: [{name, path, tt, event, track,
## class_id}].
static func list(tt: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue
		var p := load_file(dir.path_join(file))
		if not p.is_empty() and bool(p.tt) == tt:
			out.append(p)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out


## A preset's file, checked ({} if it isn't one), its path added.
static func load_file(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not d is Dictionary or d.get("schema") != SCHEMA or String(d.get("name", "")).strip_edges().is_empty() \
			or not d.get("event") is Dictionary:
		return {}
	var p: Dictionary = d
	p.path = path
	p.tt = bool(p.get("tt", false))
	p.track = String(p.get("track", ""))
	p.class_id = String(p.get("class_id", ""))
	return p


## Saves `flow`'s setup as `preset_name`; its path, or "" if it can't be written.
static func save(preset_name: String, flow: EventFlow) -> String:
	var clean := preset_name.strip_edges().left(40)
	if clean.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(slug(clean) + ("_tt" if flow.tt else "") + ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({ "schema": SCHEMA, "name": clean, "tt": flow.tt, "event": flow.event_dict(),
		"track": flow.track, "class_id": flow.class_id }, "  ", false))
	return path


static func delete(path: String) -> void:
	if path.begins_with(dir):
		DirAccess.remove_absolute(path)


## Fills `flow` from `preset` (what the type has rows for: fit() sees to the rest).
static func apply(preset: Dictionary, flow: EventFlow) -> void:
	flow.event = RaceEvent.from_dict(preset.event)
	flow.track = String(preset.track)
	flow.class_id = String(preset.class_id)
	flow.fit()


## "My Race!" -> "my_race"; "preset" when nothing's left.
static func slug(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while "__" in out:
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_").left(40)
	return out if out else "preset"
