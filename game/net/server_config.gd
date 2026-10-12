class_name ServerConfig
extends RefCounted
## A server's settings (docs/NETWORKING.md §9, MP-06): the dedicated server's --config file
## (schema data/schemas/server.schema.json), or what a listen server's host picks in the menu.
## Missing keys take the defaults below.

const SCHEMA := "noss.server/1"
const TRACKS_DIR := "res://content/tracks/"
const DEFAULT_TRACK := "proving_ground"

var name := "nOSS server"
var port := NetProtocol.DEFAULT_PORT
var password := ""
var max_players := NetProtocol.MAX_PLAYERS
var motd := ""
var admins := PackedStringArray()
var whitelist := PackedStringArray()
var bans := PackedStringArray()
var lan := true
var upnp := false
## Car states per second from clients: 30, 60, or 0 (60 on fast links, else 30).
var state_rate := 0
## [{track, class, event}], run in turn.
var rotation: Array[Dictionary] = []
var rules := {
	"classes": [], "assists": null, "tuning": "allow", "fitting": "normal", "hotswap": "practice",
	"ghost_bad_links": true,
}
var caps := {
	"max_package_mb": 50, "own_sounds": true, "custom_platforms": false,
	"transfer_kbps": 2048, "client_kbps": 8192,
}
## "off", "warn", "flag" or "kick".
var plausibility := "flag"
## The file it came from ("" for a menu-made config); track paths are relative to it, and bans
## added at run time are saved back to it.
var path := ""


static func defaults() -> ServerConfig:
	var c := ServerConfig.new()
	c.rotation = [{ "track": DEFAULT_TRACK, "class": "official.track.gt", "event": RaceEvent.free_drive().to_dict() }]
	return c


## The config in `file`, or null with the reasons in `errors`.
static func load_file(file: String, errors: PackedStringArray = []) -> ServerConfig:
	if not FileAccess.file_exists(file):
		errors.append("No such file: " + file)
		return null
	if FileAccess.get_file_as_bytes(file).size() > 1 << 20:
		errors.append("Config too large")
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not data is Dictionary:
		errors.append("Not valid JSON: " + file)
		return null
	var c := from_dict(data, errors)
	if c:
		c.path = file
	return c


## A config from parsed JSON, or null with the reasons in `errors`.
static func from_dict(d: Dictionary, errors: PackedStringArray = []) -> ServerConfig:
	errors.append_array(JsonSchema.validate(d, JsonSchema.load_schema("server")))
	if not errors.is_empty():
		return null
	var c := defaults()
	for key: String in ["name", "password", "motd", "lan", "upnp", "plausibility"]:
		if d.has(key):
			c.set(key, d[key])
	for key: String in ["port", "max_players", "state_rate"]:
		if d.has(key):
			c.set(key, int(d[key]))
	for key: String in ["admins", "whitelist", "bans"]:
		if d.has(key):
			c.set(key, PackedStringArray(d[key]))
	if d.has("rotation"):
		c.rotation.assign(d.rotation)
	if d.has("rules"):
		c.rules.merge(d.rules, true)
	if d.has("caps"):
		for key: String in d.caps:
			c.caps[key] = int(d.caps[key]) if d.caps[key] is float else d.caps[key]
	return c


func to_dict() -> Dictionary:
	var rules_out := rules.duplicate()
	if rules_out.assists == null:
		rules_out.erase("assists")
	return {
		"schema": SCHEMA, "name": name, "port": port, "password": password, "max_players": max_players,
		"motd": motd, "admins": Array(admins), "whitelist": Array(whitelist), "bans": Array(bans),
		"lan": lan, "upnp": upnp, "state_rate": state_rate, "rotation": rotation.duplicate(true),
		"rules": rules_out, "caps": caps.duplicate(), "plausibility": plausibility,
	}


## Saves back to `path` (adds bans made at run time). Nothing happens for a menu-made config.
func save() -> Error:
	if path.is_empty():
		return OK
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "  ") + "\n")
	return OK


## The track of rotation item `i`: a track's id (built-in, or in the track library), or a path
## (.nosstrack, a track folder or a track.json) relative to the config.
func track_path(i: int) -> String:
	var t := String(rotation[i].get("track", DEFAULT_TRACK))
	if not t.contains("/") and not t.contains("\\") and not t.contains("."):
		var found := TrackLibrary.resolve(t)
		return found if found else TRACKS_DIR.path_join(t)
	if t.is_absolute_path() or path.is_empty():
		return t
	return path.get_base_dir().path_join(t)


## Rotation item `i`'s class: an official platform, or (with caps.custom_platforms) one from
## user://platforms/<id>.platform.json, sent to players by hash (PLT-09).
func platform(i: int) -> PlatformLoader.Result:
	var id := String(rotation[i].get("class", "official.track.gt"))
	if id.begins_with("official."):
		return PlatformLoader.load_official(id)
	var result := PlatformLoader.Result.new()
	if not caps.custom_platforms:
		result.errors.append("Custom platforms are off: " + id)
		return result
	return PlatformLoader.load_file(PlatformLoader.USER_DIR + id + PlatformLoader.SUFFIX)


## Rotation item `i`'s event (online: free drive or a race weekend).
func event(i: int) -> RaceEvent:
	var e := RaceEvent.from_dict(rotation[i].get("event", {}))
	if e.kind not in ["free", "race"]:
		e.kind = "free"
	return e


func is_banned(fingerprint: String) -> bool:
	return fingerprint in bans


func is_admin(fingerprint: String) -> bool:
	return fingerprint in admins


## Whether the whitelist (if any) lets `fingerprint` in.
func is_allowed(fingerprint: String) -> bool:
	return whitelist.is_empty() or fingerprint in whitelist


## Package limits lowered by the caps (PackageLoader limits).
func package_limits() -> Dictionary:
	return { "max_zip_bytes": int(caps.max_package_mb) << 20 }
