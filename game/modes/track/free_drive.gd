class_name FreeDrive
extends Node3D
## Track free-drive (MODE-01) for 1-4 local players (LOC-01…LOC-03): lap timer with sectors and
## best lap, car reset, pause and car hotswap (docs/GAMEMODES.md §1). Each player has their own
## car, view, HUD, timer and reset spot (SessionPlayer); the track, platform class, views and
## pause are shared. Players can drop in with a free device and drop out from their pause menu.

const DEFAULT_TRACK := "res://content/tracks/proving_ground/track.json"
const DEFAULT_PLATFORM := "official.track.gt"
const GRID_BEHIND_LINE := 40.0
const GRID_ROW_M := 8.0
## A spot is taken if another car is closer than this.
const CLEAR_M := 6.0

var track_path := DEFAULT_TRACK
## P1's car; empty: their profile's last car.
var car_path := ""
var platform_id := DEFAULT_PLATFORM
## Test-driving a Fitting Bay draft: the pause menu leads back, and the car isn't remembered.
var bay_return := false
## Cars can be swapped mid-drive (free drive, practice, cruise; docs/VEHICLE_PACKAGE.md §8).
var hotswap_allowed := true
## Dev: the line follower drives every player.
var autodrive := false
## Dev: this many extra players driven by the line follower.
var ai_players := 0

var track: TrackData
var platform: PlatformLoader.Result
var views := ViewManager.new()
var players: Array[SessionPlayer] = []
var world_env: Environment
## Who has the game paused, or null.
var paused_by: SessionPlayer

var _default_car := ""
var _show_fps := false
var _dev_time := 0.0
var _dev_swapped := false
var _fps_time := 0.0
var _fps_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	track = TrackData.load_file(track_path)
	var style := StyleProfile.load_profile(track.style)
	style.apply_globals()
	var env_node := style.create_environment()
	world_env = env_node.environment
	add_child(env_node)
	add_child(style.create_sun())
	add_child(TrackBuilder.build(track))
	platform = PlatformLoader.load_official(platform_id)
	if not platform.ok():
		push_warning("Platform %s: %s" % [platform_id, platform.errors])
		platform_id = DEFAULT_PLATFORM
		platform = PlatformLoader.load_official(platform_id)
	_default_car = GameModes.default_car(platform.platform)

	add_child(views)
	var map := TrackMap.new()
	map.track = track
	map.cars = _map_cars
	views.map = map
	views.views_changed.connect(_on_views_changed)

	Players.primary_slot() # one player can just drive
	for i in ai_players:
		Players.add_ai()
	_apply_dev_layout()
	for slot in Players.slots:
		if autodrive:
			slot.ai = true
		_add_player(slot)
	Players.remember_all()
	Players.joined.connect(_on_joined)
	Players.left.connect(_on_left)
	Players.joining = not bay_return # drop in mid-drive


func _exit_tree() -> void:
	Players.joining = false
	Players.joined.disconnect(_on_joined)
	Players.left.disconnect(_on_left)
	for slot in Players.slots:
		slot.menu_target = null
		slot.ai = false
	Players.remove_ai()


## Dev: --screens=0,0,1,1 puts players on monitors; --split=side|stacked and --three=wide|map
## pick the layouts for this run.
func _apply_dev_layout() -> void:
	if Game.dev.has("screens"):
		var screens := String(Game.dev.screens).split(",")
		for i in mini(screens.size(), Players.count()):
			Players.slots[i].screen = int(screens[i])
	if Game.dev.has("split"):
		Settings.split_two = Game.dev.split
	if Game.dev.has("three"):
		Settings.split_three = Game.dev.three


func _add_player(slot: PlayerSlot) -> SessionPlayer:
	var p := SessionPlayer.new()
	p.slot = slot
	p.session = self
	p.track = track
	p.platform = platform
	p.bay_return = bay_return
	p.default_car = _default_car
	var i := players.size()
	p.spawn_at = track.transform_at(_grid_distance(i), _grid_lateral(i)) if _spot_clear(_grid_distance(i), _grid_lateral(i)) else _free_grid_spot()
	p.view = views.add(slot)
	players.append(p)
	add_child(p)
	p.setup(world_env)
	p.pause_requested.connect(_open_pause)
	slot.profile.data.last_platform = platform_id
	var path := car_path if car_path and slot.index == 0 else String(slot.profile.data.get("last_car", ""))
	if slot.ai and slot.index > 0:
		path = ""
	if path.is_empty() or not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)) \
			or not Fitting.compatible(platform.platform, PackageLoader.read_manifest(path).get("family", "")):
		path = _default_car
	p.load_car(path)
	_on_views_changed()
	return p


func _on_joined(slot: PlayerSlot) -> void:
	var p := _add_player(slot)
	p.hud.show_message("%s joined" % slot.tag(), 2.0)


func _on_left(slot: PlayerSlot) -> void:
	for p in players:
		if p.slot == slot:
			if paused_by == p:
				_resume()
			players.erase(p)
			p.remove()
			break
	views.remove(slot)
	if players.is_empty():
		Game.go_title()


func _on_views_changed() -> void:
	EngineSound.set_listeners(views.listener_count())
	for p in players:
		p.update_badge(players.size())


func _process(delta: float) -> void:
	# Dev: --swap-car=<path> --swap-at=<s> swaps P1's car mid-drive and logs the speed around it.
	var p1 := players[0] if not players.is_empty() else null
	if Game.dev.has("swap-car") and p1 and p1.vehicle and not _dev_swapped:
		_dev_time += delta
		if _dev_time >= float(Game.dev.get("swap-at", "20")):
			_dev_swapped = true
			print("Swap at %.1f km/h" % (p1.vehicle.speed() * 3.6))
			p1.load_car(Game.dev["swap-car"])
	if Game.dev.has("fps"):
		_fps_time += delta
		_fps_frames += 1
		if _fps_time >= 1.0:
			print("fps %.0f" % (_fps_frames / _fps_time))
			_fps_time = 0.0
			_fps_frames = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_show_fps = not _show_fps
		for p in players:
			p.hud.show_fps = _show_fps


## Grid spots behind the start line: two columns, a row every GRID_ROW_M.
func _grid_distance(i: int) -> float:
	return track.start_m - GRID_BEHIND_LINE - (i / 2) * GRID_ROW_M - (i % 2) * GRID_ROW_M * 0.5


func _grid_lateral(i: int) -> float:
	return track.width / 4.0 * (1.0 if i % 2 == 0 else -1.0)


func _spot_clear(distance: float, lateral: float, except: SessionPlayer = null) -> bool:
	var at := track.transform_at(distance, lateral).origin
	for p in players:
		if p != except and p.vehicle and p.vehicle.global_position.distance_to(at) < CLEAR_M:
			return false
	return true


## The first grid spot nobody is on (for players who drop in mid-drive).
func _free_grid_spot() -> Transform3D:
	for i in 12:
		if _spot_clear(_grid_distance(i), _grid_lateral(i)):
			return track.transform_at(_grid_distance(i), _grid_lateral(i))
	return track.transform_at(_grid_distance(12), 0.0)


## A reset spot at or behind `distance` with no other car on it.
func free_spot_near(distance: float, who: SessionPlayer) -> float:
	for step in 10:
		var d := distance - step * GRID_ROW_M
		if _spot_clear(d, 0.0, who):
			return d
	return distance


func _map_cars() -> Array:
	var out := []
	for p in players:
		if p.vehicle:
			out.append([p.slot.number(), p.slot.color(), p.vehicle.global_position])
	return out


func _open_pause(p: SessionPlayer) -> void:
	if paused_by:
		return
	paused_by = p
	for other in players:
		if other != p:
			other.hud.show_message("Paused by %s" % p.slot.tag(), 1e9)
			if not other.slot.ai:
				other.slot.input.wheel.stop_ffb()
	var menu := PauseMenu.new()
	menu.slot = p.slot
	menu.bay_return = bay_return
	menu.can_leave = p.slot.index > 0
	menu.resumed.connect(_resume)
	menu.reset_car.connect(func() -> void:
		_resume()
		p.reset_car())
	menu.change_car.connect(func() -> void:
		_resume()
		p.open_picker(true))
	menu.leave.connect(func() -> void:
		_resume()
		Players.leave(p.slot))
	menu.quit_to_title.connect(func() -> void: Game.go_title())
	menu.back_to_bay.connect(func() -> void: Game.open_fitting_bay())
	p.show_overlay(menu, true)


func _resume() -> void:
	var p := paused_by
	paused_by = null
	get_tree().paused = false
	for other in players:
		other.hud.show_message("", 0.0)
	if p and is_instance_valid(p):
		p.close_overlay()
