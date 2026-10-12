extends Node
## Settings (autoload "Settings"). Machine settings live in user://settings.cfg; everything
## that follows a player (bindings, assists, cameras, comfort and accessibility options) lives
## in their profile, user://profiles/<id>.json (PlayerProfile, docs/ACCESSIBILITY.md §1, ACC-01).
## `profile` is the primary player's (P1) profile data, used by shared menus.

signal changed

const PRESETS := ["low", "medium", "high"]
## Machine settings, saved in settings.cfg as [section] key.
const MACHINE := {
	"graphics": ["graphics", "preset"],
	"units": ["game", "units"],
	"fullscreen": ["display", "fullscreen"],
	"master_volume": ["audio", "master"],
	"split_two": ["splitscreen", "two"],
	"split_three": ["splitscreen", "three"],
	"split_audio": ["splitscreen", "audio"],
	"auto_resolution": ["splitscreen", "auto_resolution"],
	"primary_profile": ["players", "primary"],
	"race_event": ["race", "last_event"],
	"vol_own_engine": ["audio", "own_engine"],
	"vol_other_engines": ["audio", "other_engines"],
	"vol_tires": ["audio", "tires"],
	"vol_effects": ["audio", "effects"],
	"vol_ambience": ["audio", "ambience"],
	"vol_music": ["audio", "music"],
	"vol_ui": ["audio", "ui"],
	"vol_spotter": ["audio", "spotter"],
	"vol_narration": ["audio", "narration"],
	"mono": ["audio", "mono"],
	"first_boot_done": ["game", "first_boot_done"],
	"net_address": ["online", "address"],
	"net_host": ["online", "host"],
}

var graphics := "medium"
var units := "metric"
var fullscreen := false
var master_volume := 0.8
## Two players: "stacked" (one above the other) or "side" (side by side).
var split_two := "stacked"
## Three players: "wide" (one wide view, two below) or "map" (2×2 with a track map).
var split_three := "wide"
## Splitscreen audio: "all" (every player's view listens) or "p1" (only P1's).
var split_audio := "all"
## Lower each view's render scale to hold the frame rate.
var auto_resolution := true
var primary_profile := "player1"
## The last race set up (RaceEvent.to_dict()).
var race_event := {}
## Volume groups, 0-1 (docs/ACCESSIBILITY.md §3), and mono audio. One output: shared by all.
var vol_own_engine := 1.0
var vol_other_engines := 0.8
var vol_tires := 0.8
var vol_effects := 1.0
var vol_ambience := 0.8
var vol_music := 0.6
var vol_ui := 0.8
var vol_spotter := 1.0
var vol_narration := 1.0
var mono := false
## The first-boot accessibility screen has been through (ACC-09).
var first_boot_done := false
## Online: the last address joined, and the last server hosted (ServerConfig.to_dict()).
var net_address := ""
var net_host := {}

var primary: PlayerProfile
var profile := {}
var settings_path := "user://settings.cfg"

var _profiles := {} # id -> PlayerProfile, so two users of one id share it


func _ready() -> void:
	load_all()
	apply_display()
	Bindings.apply()


func load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for key: String in MACHINE:
			var at: Array = MACHINE[key]
			set(key, cfg.get_value(at[0], at[1], get(key)))
	if graphics not in PRESETS:
		graphics = "medium"
	_profiles.clear()
	_set_primary(get_profile(primary_profile))


func save() -> void:
	if PlayerProfile.read_only:
		return
	var cfg := ConfigFile.new()
	for key: String in MACHINE:
		var at: Array = MACHINE[key]
		cfg.set_value(at[0], at[1], get(key))
	cfg.save(settings_path)
	primary.save()


## The last race set up, or the defaults.
func last_event() -> RaceEvent:
	var e := RaceEvent.from_dict(race_event) if race_event is Dictionary else RaceEvent.new()
	e.kind = "race"
	Game.apply_dev_event(e)
	return e


func set_last_event(e: RaceEvent) -> void:
	race_event = e.to_dict()
	save()


## Points settings, profiles and the players' memory at another folder and reloads (tests use
## "user://tests/..."; "user://" is the normal place).
func use_folder(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	settings_path = folder.path_join("settings.cfg")
	PlayerProfile.dir = folder.path_join("profiles/")
	Setup.dir = folder.path_join("setups/")
	TimeTrial.dir = folder.path_join("ghosts/")
	TrackLibrary.user_dir = folder.path_join("tracks/")
	Leaderboard.dir = folder.path_join("leaderboards/")
	Players.memory_path = folder.path_join("players.json")
	NetIdentity.dir = folder.path_join("identity/")
	Net.forget_identity()
	primary_profile = "player1"
	load_all()
	Players.load_memory()


## A profile by id, loaded once.
func get_profile(id: String) -> PlayerProfile:
	if not _profiles.has(id):
		_profiles[id] = PlayerProfile.load_id(id)
	return _profiles[id]


## Saved profile ids, the primary one included even before its first save.
func profile_ids() -> PackedStringArray:
	var ids := PlayerProfile.saved_ids()
	for id: String in _profiles:
		if id not in ids:
			ids.append(id)
	ids.sort()
	return ids


## A new profile, "Player N", saved right away.
func new_profile() -> PlayerProfile:
	var ids := profile_ids()
	var n := 1
	while "player%d" % n in ids:
		n += 1
	var p := PlayerProfile.create("player%d" % n, { "name": "Player %d" % n })
	_profiles[p.id] = p
	p.save()
	return p


func delete_profile(id: String) -> void:
	if id == primary.id:
		return
	_profiles.erase(id)
	DirAccess.remove_absolute(PlayerProfile.path_for(id))


## Makes `p` the primary (P1) profile, the one shared menus edit.
func set_primary(p: PlayerProfile) -> void:
	if p == primary:
		return
	_set_primary(p)
	set_value("primary_profile", p.id)


func _set_primary(p: PlayerProfile) -> void:
	if primary and primary.changed.is_connected(_on_profile_changed):
		primary.changed.disconnect(_on_profile_changed)
	primary = p
	primary_profile = p.id
	profile = p.data
	p.changed.connect(_on_profile_changed)


func _on_profile_changed() -> void:
	changed.emit()


func set_value(key: String, value: Variant) -> void:
	if MACHINE.has(key):
		set(key, value)
		if key in ["graphics", "fullscreen", "master_volume"]:
			apply_display()
		elif key.begins_with("vol_") or key == "mono":
			AudioMix.apply()
	else:
		profile[key] = value
	save()


func set_assist(assist: String, on: bool) -> void:
	primary.set_assist(assist, on)


## Speed in the player's units, with its label.
func speed_text(mps: float) -> String:
	return "%d" % roundi(absf(mps) * (2.23694 if units == "imperial" else 3.6))


func speed_unit() -> String:
	return "mph" if units == "imperial" else "km/h"


## Render settings of the graphics preset for one viewport (the root, or a player's view).
func apply_graphics(viewport: Viewport, scale := 1.0) -> void:
	match graphics:
		"low":
			viewport.scaling_3d_scale = 0.75 * scale
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		"medium":
			viewport.scaling_3d_scale = 1.0 * scale
			viewport.msaa_3d = Viewport.MSAA_2X
		"high":
			viewport.scaling_3d_scale = 1.0 * scale
			viewport.msaa_3d = Viewport.MSAA_4X
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X if graphics == "high" else Viewport.ANISOTROPY_4X


func apply_display() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	apply_graphics(viewport)
	RenderingServer.directional_shadow_atlas_set_size({ "low": 1024, "medium": 2048, "high": 4096 }[graphics], true)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioMix.apply()
