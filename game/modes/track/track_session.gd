class_name TrackSession
extends Node3D
## A track session (docs/GAMEMODES.md §1) for 1-4 local players (LOC-01…LOC-03) and AI racers:
## lap timer with sectors and best lap, car reset, pause and car hotswap. Each player has their
## own car, view, HUD, timer and reset spot (SessionPlayer); AI racers (AiRacer) have no view.
## The track, platform class, views, RaceField and pause are shared. Players can drop in with a
## free device and drop out from their pause menu.

const DEFAULT_TRACK := TrackLibrary.DEFAULT
const DEFAULT_PLATFORM := "official.track.gt"
const GRID_BEHIND_LINE := 40.0
const GRID_ROW_M := 8.0
## A spot is taken if another car is closer than this.
const CLEAR_M := 6.0
const GRID_SPOTS := 20
const PHYSICS_HZ := 120
## Engine sound detail for AI cars: the nearest few within FULL_M of a camera get every layer,
## the rest within DISTANT_M only their exhaust, and cars further away are silent.
const SOUND_FULL_COUNT := 3
const SOUND_FULL_M := 60.0
const SOUND_DISTANT_M := 350.0
const SOUND_UPDATE_S := 0.25
## The dedicated server shows results this long, then goes on.
const DEDICATED_RESULTS_S := 15.0

## The track: a .nosstrack, a track folder or a track.json (TrackLoader).
var track_path := DEFAULT_TRACK
## The track already loaded (a menu's load, the editor's draft); else track_path is loaded now.
var track_package: TrackPackage
## P1's car; empty: their profile's last car.
var car_path := ""
var platform_id := DEFAULT_PLATFORM
## Online: a server's own platform, from the cache (PLT-09); "" for an official one.
var platform_file := ""
## "normal", or "strict" (a server's rule): physics on the platform's reference geometry.
var fitting_mode := "normal"
## Test-driving a Fitting Bay draft: the pause menu leads back, and the car isn't remembered.
var bay_return := false
## Test-driving the track editor's draft: the pause menu (and editor_back) lead back.
var editor_return := false
## Where P1 starts (a test drive from the editor's cursor); null: the grid.
var start_at: Variant = null
## Cars can be swapped mid-drive (free drive, practice, cruise; docs/VEHICLE_PACKAGE.md §8).
var hotswap_allowed := true
## Online: the server's rule for swaps: "practice" (not in races), "never" or "always".
var hotswap_rule := "practice"
## Only P1 drives, and nobody drops in (garage and Fitting Bay drives).
var solo := false
## Dev: the line follower drives every player.
var autodrive := false
## Dev: this many extra players driven by the RacingAI.
var ai_players := 0
## AI racers (no views).
var ai_racers := 0
## AI skill, 0-100.
var ai_skill := 80.0
## AI skills spread this much around ai_skill, fastest to slowest, shuffled over the grid.
var ai_skill_spread := 10.0
## AI cars come only from the built-in cars.
var ai_builtin_cars := false
## No car-to-car contact (docs/GAMEMODES.md §1, "Collisions").
var ghosted := false
## Resets wait for a gap in traffic and rejoin at the road's edge (set when there's AI).
var safe_rejoin := false
## What's run here: free drive by default; a race weekend or a time trial.
var event := RaceEvent.free_drive()
## Grid: the first spot's distance behind the line, and the gap between cars in one column.
var grid_front_m := GRID_BEHIND_LINE
var grid_row_m := GRID_ROW_M

var track: TrackData
## The track's terrain, or null on flat ground.
var terrain: TerrainData
var platform: PlatformLoader.Result
## The mode offering this class (its tuning and assist rules).
var mode := {}
## The class's kart_arcade numbers (GameModes.arcade), or {}: every car driven here gets them.
var arcade := {}
## Whether the drift button does anything (sumo turns it off on a setting, D181).
var drift_allowed := true
var views := ViewManager.new()
var players: Array[SessionPlayer] = []
## Every car: players and AI.
var racers: Array[Racer] = []
var field := RaceField.new()
## Runs the event's sessions: grid, countdown, standings, flags, results.
var race := RaceControl.new()
## The results screen while it's up.
var results_menu: ResultsMenu
## Time trial: records each player's laps, shows their ghosts (null in other events).
var time_trial: TimeTrial
## Online, a time trial's live board (docs/UI_FLOW.md §7.7); null otherwise.
var time_trial_net: TimeTrialNet
var world_env: Environment
## The sky: time of day and weather (D153).
var env: EnvDirector
## Tracks in snow and off the road, to look at (D197); null where nothing's drawn.
var tire_tracks: TireTracks
## Who has the game paused, or null.
var paused_by: SessionPlayer
## Online (D84): the session's SESSION message ({track, class, event, roster}); {} offline.
var online := {}
## The dedicated server's session: no players of its own, nothing drawn.
var dedicated := false
## Online play in this session, or null offline.
var net: NetSession
## A highway event (docs/GAMEMODES.md §3, D113): its rules, where cars are on it, and its
## traffic; null otherwise.
var highway: HighwayControl
var highway_field: HighwayField
## A highway run's start, checkpoints and finish (event.sub == "run").
var run: RunControl
## Online: the server's boards for this track, as last sent ({board: entries}).
var server_boards := {}
## The police (event.police), where the session is decided: offline here, online the server.
var police: PoliceControl
## Kart sessions (D129): tow, slipstream, items. Null otherwise.
var kart: KartControl
## Drafting (D208): with the event's drafting on, in Track mode.
var draft: DraftControl
## Fuel use and tire wear (D209): with either on in the event, in Track mode.
var wear: WearControl
## Pit stops (D210): on a track with a pit lane, in Track mode.
var pits: PitControl
## Battles (D144): lives and hits. Null otherwise.
var battle: BattleControl
## A sumo match (docs/GAMEMODES.md §5, D162): the platforms, their rules and the HUD; the world
## is built here rather than from a track file.
var sumo: SumoControl
var sumo_world: SumoBuilder
var sumo_hud: SumoHud
var sumo_watch: SumoWatch
var sumo_net: SumoNet
## A drag match (docs/GAMEMODES.md §6, D168): the passes, the ladder and the HUD; the strip is
## built here rather than from a track file.
var drag: DragControl
var drag_world: DragBuilder
var drag_watch: DragWatch
var drag_hud: DragHud
var drag_net: DragNet
## Dev and tests: the ladder's draw seed (0: drawn freshly).
var drag_seed := 0
## A kart cup's race (D145): its standings after the results, its AI field. Null otherwise.
var cup: CupRun
## Kart sessions (D149): AI karts pick a class of their own (off: they all take the session's,
## as the balance checks want).
var ai_class_mix := true
var _classes := {} # class id -> PlatformLoader.Result
var _ai_classes := {} # AI index -> class id
var traffic: TrafficManager
## Dev and tests: the traffic's seed (-1: the track's).
var traffic_seed := -1
## Highways: each player's starting direction by player order ([] or missing: the event's).
var directions: Array = []
## An endless drive (docs/GAMEMODES.md §4, D157): its rules, its world (the road window is the
## track), the floating origin under it, and its traffic. Null otherwise.
var endless: EndlessControl
var endless_world: EndlessWorld
## Its lanes: how many, and the side they're driven on (D190).
var endless_lanes: EndlessLanes
var origin: FloatingOrigin
var endless_traffic: Node
## Its speed traps (event.speed_traps, D193), or null.
var endless_traps: EndlessTraps
## Online: the traffic's owners, slots used up and where everyone is (D159).
var endless_net: EndlessNet
## Where this game's players start on the road (m).
var endless_start_m := EndlessControl.START_M

var _default_car := ""
var _show_fps := false
var _dev_time := 0.0
var _dev_swapped := false
var _fps_time := 0.0
var _fps_frames := 0
var _sound_time := 0.0


## The sky (D153): the event's time and weather over the track's own, the style's sun; online, the
## server's (the same on every game, D159).
func _env_state(style: StyleProfile) -> EnvState:
	if drag:
		# The pass online (D175): the server runs the tree, rules on the lane and the lights, and
		# says who won; each game grades its own shifts and reports them up.
		drag_net = DragNet.new()
		drag_net.name = "DragNet"
		drag_net.session = self
		drag_net.drag = drag
		drag.net = drag_net
		add_child(drag_net)
	var sky: Dictionary = online.get("environment", {})
	var time := String(Game.dev.get("time", sky.get("time", event.time)))
	var rate := int(Game.dev.get("time-rate", sky.get("time_rate", event.time_rate)))
	var weather := String(Game.dev.get("weather", sky.get("weather", event.weather)))
	var seed := int(Game.dev.get("env-seed", sky.get("seed", event.env_seed)))
	if seed <= 0:
		seed = randi_range(1, 0x7FFFFFFF)
	var track_env: Variant = track.raw.get("environment", {})
	return EnvState.from_settings(time, rate, weather, seed, track_env if track_env is Dictionary else {}, style.data.get("sun", {}))


## Endless (D157): the road window is the track, made by the world from the event's seed; the
## floating origin keeps the players near the scene's centre.
func _load_endless() -> void:
	origin = FloatingOrigin.new()
	add_child(origin)
	endless_lanes = EndlessLanes.make(event.lanes, event.drive_side)
	endless_world = EndlessWorld.new()
	endless_world.lanes = endless_lanes
	endless_world.plan_traps = event.speed_traps
	endless_world.gen = EndlessGen.make(event.road_seed, event.biome)
	endless_world.origin = origin
	endless_world.visual = not (dedicated or Game.dev.has("bot")) # bots draw nothing
	endless_world.collision = not dedicated
	endless_world.focus = _endless_distances
	endless_world.focus_points = _endless_points
	origin.focus = func() -> Vector3:
		var points := _endless_points()
		var c := Vector3.ZERO
		for p in points:
			c += p
		return c / maxf(points.size(), 1)
	track = endless_world.road
	terrain = null
	safe_rejoin = false
	endless_start_m = _endless_start()
	# Start the origin by the start (a joiner may start far along): nothing's made far from it.
	var c := endless_world.gen.chunk(floori(endless_start_m / (TrackData.SAMPLE_M * NossRoadGen.chunk_samples())))
	if not c.is_empty() and Vector2(c.x[0], c.z[0]).length() > FloatingOrigin.SHIFT_AT_M:
		origin.x = snappedf(c.x[0], FloatingOrigin.SNAP_M)
		origin.z = snappedf(c.z[0], FloatingOrigin.SNAP_M)


## Sumo (D162): the platforms are generated from the match settings, so there is no track file
## and nothing of the arena goes over the wire. A stand-in TrackData carries the layout, as an
## arena track would.
func _load_sumo() -> void:
	var data := {
		"schema": TrackFormat.SCHEMA,
		"id": "sumo_arena",
		"name": "Sumo",
		"type": "arena",
		"road": { "points": [] },
		"race": { "grid": { "slots": ArenaLayout.AUTO_SPAWNS } },
	}
	for p in SumoLayout.ring(SumoLayout.RADII[0]):
		(data.road.points as Array).append({ "p": [p.x, 0.0, p.y] })
	track = TrackData.from_dict(data)
	track.arena = SumoLayout.make(track, event)
	# Below the pit, not below the top platform: falling between tiers is the game (D163).
	track.kill_y = (track.arena as SumoLayout).hazard_y - 60.0
	terrain = null
	safe_rejoin = false


## Drag (D168): the strip is generated from the match settings, so there is no track file and
## nothing of it goes over the wire. A stand-in TrackData carries the layout, as an arena would.
func _load_drag() -> void:
	var data := {
		"schema": TrackFormat.SCHEMA,
		"id": "drag_strip",
		"name": "Drag Strip",
		"type": "arena",
		"road": { "points": [] },
		"race": { "grid": { "slots": 2 } },
	}
	for p in DragLayout.outline_for(event):
		(data.road.points as Array).append({ "p": [p.x, 0.0, p.y] })
	track = TrackData.from_dict(data)
	track.arena = DragLayout.make(track, event)
	track.kill_y = -60.0
	terrain = null
	safe_rejoin = false


## Where this game's players start: online, behind whoever's furthest along (D159; the server
## stays at the start); otherwise near the road's start.
func _endless_start() -> float:
	var at: Variant = online.get("endless", {}).get("at", {})
	var best := -INF
	if at is Dictionary and not dedicated:
		for v: Variant in at.values():
			if v is Array and not (v as Array).is_empty() and (v[0] is float or v[0] is int) and is_finite(float(v[0])):
				best = maxf(best, float(v[0]))
	return maxf(best - EndlessControl.JOIN_BEHIND_M, EndlessControl.START_M) if best > -INF else EndlessControl.START_M


## Road distances to keep built round: this game's players (a dedicated server keeps only the
## start: it places nobody, D159).
func _endless_distances() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for r in racers:
		if r.vehicle and r is SessionPlayer:
			out.append(r.distance)
	if out.is_empty():
		out.append(endless_start_m)
	return out


func _endless_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for r in racers:
		if r.vehicle and (r is SessionPlayer or dedicated):
			out.append(r.vehicle.global_position)
	if out.is_empty() and endless_world and not endless_world.road.is_empty():
		out.append(endless_world.road.point_at(endless_start_m))
	return out


func _ready_endless() -> void:
	ai_racers = 0
	endless = EndlessControl.new()
	endless.session = self
	endless.world = endless_world
	endless.event = event
	endless.lanes = endless_lanes
	endless.start_m = endless_start_m
	add_child(endless)
	# Traffic (and the traps' parked patrols, and the police's patrols, even with traffic off).
	if (event.endless_traffic != "off" or event.speed_traps or event.police) and not dedicated:
		var traffic := EndlessTraffic.new()
		traffic.session = self
		traffic.world = endless_world
		traffic.lanes = endless_lanes
		traffic.seed = event.road_seed
		traffic.density = event.endless_traffic
		traffic.oncoming = event.oncoming
		endless_traffic = traffic
		add_child(traffic)
		# Garage cars in the traffic (D191): this game's own; online, the host's (_online_garage).
		if event.garage_traffic and not is_online():
			traffic.set_garage(EndlessTraffic.garage_pool(PackageLoader.list_available(), event.road_seed))
	if event.speed_traps and not dedicated:
		endless_traps = EndlessTraps.new()
		endless_traps.session = self
		endless_traps.world = endless_world
		endless_traps.lanes = endless_lanes
		endless_traps.code = EndlessCode.encode(event.road_seed, event.biome)
		add_child(endless_traps)
	# The police (D194): each game runs them for its own players.
	if event.police and not dedicated:
		endless_traffic.patrols = true
		police = PoliceControl.new()
		police.name = "PoliceControl"
		police.session = self
		police.road = EndlessPoliceRoad.make(self)
		police.police_class = String(GameModes.list().filter(func(m: Dictionary) -> bool: return m.id == "highway").map(
			func(m: Dictionary) -> String: return String(m.get("police_class", "official.highway.interceptor"))).front())
		add_child(police)
		if endless_traps:
			endless_traps.snapped.connect(police.camera_snap)
	if not dedicated and not Game.dev.has("bot"):
		var music := EndlessMusic.new()
		music.seed_base = event.road_seed
		add_child(music)


## The track's fog: light, normal or heavy.
func _fog_scale() -> float:
	var track_env: Variant = track.raw.get("environment", {})
	var fog := String(track_env.get("fog", "normal")) if track_env is Dictionary else "normal"
	return { "light": 0.5, "heavy": 2.0 }.get(fog, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if event.kind == "endless":
		_load_endless()
	elif event.kind == "sumo":
		_load_sumo()
	elif event.kind == "drag":
		_load_drag()
	else:
		if track_package == null or not track_package.ok():
			track_package = TrackLoader.load_package(track_path)
		if not track_package.ok():
			push_error("Track %s: %s" % [track_path, track_package.error])
			track_package = TrackLoader.load_package(DEFAULT_TRACK)
		track = track_package.track
		terrain = track_package.terrain
	# The track's suggested rules where the event keeps "Track's" (D207): this session races a
	# copy, so the remembered event keeps "Track's" for the next track.
	event = event.resolved(track)
	var style := StyleProfile.load_profile(track.style)
	style.apply_globals()
	var env_node := style.create_environment()
	world_env = env_node.environment
	add_child(env_node)
	var sun := style.create_sun()
	add_child(sun)
	env = EnvDirector.new()
	env.sound = not dedicated
	env.setup(style, world_env, sun, _env_state(style), _fog_scale())
	var track_env: Variant = track.raw.get("environment", {})
	env.floodlit = track_env is Dictionary and bool(track_env.get("floodlit", false))
	env.local_vehicles = func() -> Array:
		return racers.filter(func(r: Racer) -> bool: return r is SessionPlayer and r.vehicle != null).map(func(r: Racer) -> Vehicle: return r.vehicle)
	add_child(env)
	env.apply()
	if not dedicated and Vehicle.drawn and not Game.headless: # headless draws nothing (tests, checks)
		tire_tracks = TireTracks.new()
		add_child(tire_tracks)
	if event.kind == "sumo":
		sumo_world = SumoBuilder.new()
		sumo_world.name = "SumoArena"
		# The goo never flashes either way (ACC-04); Reduce flashing calms it further still.
		sumo_world.setup(track.arena as SumoLayout, not dedicated, bool(Settings.profile.get("reduce_flashing", false)))
		add_child(sumo_world)
	elif event.kind == "drag":
		drag_world = DragBuilder.new()
		drag_world.name = "DragStrip"
		drag_world.setup(track.arena as DragLayout, not dedicated, bool(Settings.profile.get("reduce_flashing", false)))
		add_child(drag_world)
	elif endless_world:
		add_child(endless_world)
		endless_world.prime(endless_start_m)
	else:
		var built := TrackBuilder.build(track, terrain, { "visual": not dedicated, "scene": track_package.scene })
		add_child(built)
		for area: Node in built.find_children("Water*", "Area3D", false, false):
			(area as Area3D).body_entered.connect(_on_water)
	platform = PlatformLoader.load_file(platform_file) if platform_file else PlatformLoader.load_official(platform_id)
	if not platform.ok():
		push_warning("Platform %s: %s" % [platform_id, platform.errors])
		platform_id = DEFAULT_PLATFORM
		platform = PlatformLoader.load_official(platform_id)
	_default_car = GameModes.default_car(platform.platform)
	mode = GameModes.mode_for(platform_id)
	arcade = GameModes.arcade(mode)
	if is_online():
		_apply_server_rules(online.get("rules", {}))
	if event.kind == "race":
		# As many as the track's grid takes, after the players.
		ai_racers = clampi(event.ai_count, 0, maxi(int(track.grid.slots) - maxi(Players.count(), 1), 0))
		ai_skill = event.ai_skill
		ai_builtin_cars = event.ai_cars == "builtin"
		safe_rejoin = true
	elif event.kind == "free":
		ai_racers = clampi(ai_racers, 0, maxi(int(track.grid.slots) - maxi(Players.count(), 1), 0))
	elif event.kind == "sumo":
		ai_racers = clampi(event.ai_count, 0, maxi(track.arena.spawns.size() - maxi(Players.count(), 1), 0))
		ai_skill = event.ai_skill
		ai_builtin_cars = event.ai_cars == "builtin"
		_apply_sumo_drift()
	elif event.kind == "drag":
		# Two cars a pass, the rest waiting their turn: the ladder takes the whole field (D170).
		ai_racers = clampi(event.ai_count, 0, maxi(NetProtocol.MAX_PLAYERS - maxi(Players.count(), 1), 0))
		ai_skill = event.ai_skill
		ai_builtin_cars = event.ai_cars == "builtin"
	elif event.kind == "battle":
		if track.arena == null or arcade.is_empty():
			push_warning("A battle needs an arena and a kart class: free drive instead")
			event = RaceEvent.free_drive()
		else:
			ai_racers = clampi(event.ai_count, 0, maxi(track.arena.spawns.size() - maxi(Players.count(), 1), 0))
			ai_skill = event.ai_skill
			ai_builtin_cars = event.ai_cars == "builtin"
	ghosted = not event.collisions
	field.track = track
	field.racers = racers
	add_child(field)
	if event.kind == "highway" and track.highway:
		_ready_highway()
	elif event.kind == "endless":
		_ready_endless()
	elif event.kind == "sumo":
		_ready_sumo()
	elif event.kind == "drag":
		_ready_drag()
	elif not arcade.is_empty():
		if event.kind == "time_trial":
			event.items = false # each lap the driver's own
		_ready_kart()
		if event.kind == "battle":
			_ready_battle()
	if event.draft == "on" and mode.get("id") == "track" and event.kind != "time_trial":
		draft = DraftControl.new()
		draft.session = self
		draft.tuning = DraftControl.tuning_for(mode)
		add_child(draft)
	if (event.fuel_x > 0 or event.tyre_x > 0) and mode.get("id") == "track" and event.kind != "time_trial":
		wear = WearControl.new()
		wear.session = self
		wear.fuel_x = event.fuel_x
		wear.tyre_x = event.tyre_x
		add_child(wear)
	if track.pit and mode.get("id") == "track" and event.kind != "time_trial":
		pits = PitControl.new()
		pits.session = self
		add_child(pits)

	add_child(views)
	if not endless: # no map of a road that never ends
		var map := TrackMap.new()
		map.track = track
		map.cars = _map_cars
		views.map = map
	views.views_changed.connect(_on_views_changed)

	if is_online():
		_ready_online()
	else:
		Players.primary_slot() # one player can just drive
		for i in ai_players:
			Players.add_ai()
		_apply_dev_layout()
		for slot in Players.slots.slice(0, 1 if solo else Players.MAX):
			if autodrive:
				slot.ai = true
			_add_player(slot, start_at if slot.index == 0 else null)
		safe_rejoin = safe_rejoin or ai_racers > 0
		var pool := ai_car_pool()
		var skills := []
		for i in ai_racers:
			skills.append(clampf(ai_skill + ai_skill_spread * (0.5 - float(i) / maxf(ai_racers - 1, 1)), 0.0, 100.0))
		skills.shuffle()
		for i in ai_racers:
			_add_ai(i, pool, skills[i])
	Players.remember_all()
	Players.joined.connect(_on_joined)
	Players.left.connect(_on_left)
	Players.joining = not solo and not is_online() # drop in mid-drive (offline)
	var layer := CanvasLayer.new()
	layer.name = "ResultsLayer"
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	race.session = self
	race.event = event
	add_child(race)
	for r in racers:
		race.watch(r)
	race.session_ended.connect(_on_session_ended)
	if is_online():
		race.mirror = Net.is_client() # the server runs the event (D85)
		race.clock_source = net.now
		if Net.host_logic:
			race.sync_state = Net.host_logic.sync_state
		var net_race := NetRace.new()
		net_race.name = "NetRace"
		net_race.session = self
		add_child(net_race)
	race.start()
	if not dedicated and not Game.dev.has("bot"):
		var tones := StartTones.new()
		tones.name = "StartTones"
		tones.race = race
		add_child(tones)
	apply_game_speed()
	if event.kind == "time_trial":
		time_trial = TimeTrial.new()
		time_trial.session = self
		add_child(time_trial)


func _exit_tree() -> void:
	if Net.roster_changed.is_connected(_on_roster):
		Net.roster_changed.disconnect(_on_roster)
	if Net.chat_line.is_connected(_on_chat):
		Net.chat_line.disconnect(_on_chat)
	if Net.content and Net.content.car_changed.is_connected(_on_net_car):
		Net.content.car_changed.disconnect(_on_net_car)
	if Net.board_received.is_connected(_on_board_received):
		Net.board_received.disconnect(_on_board_received)
	if Net.highway_event.is_connected(_on_highway_event):
		Net.highway_event.disconnect(_on_highway_event)
	if Net.env_changed.is_connected(_on_env_changed):
		Net.env_changed.disconnect(_on_env_changed)
	if Net.host_logic and Net.host_logic.board_requested.is_connected(_on_board_requested):
		Net.host_logic.board_requested.disconnect(_on_board_requested)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = PHYSICS_HZ
	CarVisual.lod_scale = 1.0
	PackageLoader.clear_shared()
	KartControl.clear_caches()
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


func _add_player(slot: PlayerSlot, at: Variant = null, kart_class := "") -> SessionPlayer:
	var p := SessionPlayer.new()
	p.slot = slot
	p.class_id = kart_class
	p.bay_return = bay_return
	var i := racers.size()
	if at is Transform3D:
		p.spawn_at = at
	elif highway:
		p.spawn_at = highway.spawn_for(i, direction_for(i))
	elif endless:
		p.spawn_at = endless.spawn_for(i)
	elif sumo or drag:
		p.spawn_at = arena_spawn(i)
	else:
		p.spawn_at = track.transform_at(_grid_distance(i), _grid_lateral(i)) if _spot_clear(_grid_distance(i), _grid_lateral(i)) else _free_grid_spot()
	p.view = views.add(slot)
	players.append(p)
	_add_racer(p)
	if endless:
		endless.apply_hud(p)
	elif sumo_hud:
		sumo_hud.apply_hud(p)
	elif drag_hud:
		drag_hud.apply_hud(p)
	elif battle:
		# A battle has no laps or sectors to show either (Changes.md).
		p.hud.session_hidden = PackedStringArray(BattleControl.HUD_HIDDEN)
		p.hud.apply_profile(p.slot.profile)
	p.pause_requested.connect(_open_pause)
	slot.profile.data.last_platform = platform_id
	var path := car_path if car_path and slot.index == 0 else String(slot.profile.data.get("last_car", ""))
	if slot.ai and slot.index > 0:
		path = String(Game.dev.get("ai-car", "")) # dev: --ai-car=<path>; else the class's default
	if path.is_empty() or not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)) \
			or not Fitting.compatible(platform.platform, PackageLoader.read_manifest(path).get("family", "")):
		path = _default_car
	p.load_car(path)
	_on_views_changed()
	return p


func is_online() -> bool:
	return not online.is_empty()


## A car in a fitted scene's water: back on the road.
func _on_water(body: Node3D) -> void:
	for r in racers:
		if r.vehicle == body and not r.waiting:
			r.notify("In the water", 2.0)
			r.reset_car()


## A server's rules (MP-06), narrowing the platform's and mode's: allowed assists, setups locked,
## strict fitting. (Car swaps follow its hotswap rule, RaceControl.)
func _apply_server_rules(rules: Dictionary) -> void:
	mode = mode.duplicate(true)
	if rules.get("assists") is Array:
		var server_ok: Array = rules.assists
		var allowed := AssistRules.allowed(platform.platform, mode).filter(func(a: String) -> bool: return a in server_ok)
		if not mode.has("assists"):
			mode.assists = {}
		mode.assists.allowed = allowed
	if rules.get("tuning") == "lock":
		if not mode.has("tuning"):
			mode.tuning = {}
		mode.tuning.allow = []
	if rules.get("fitting") == "strict":
		fitting_mode = "strict"
	hotswap_rule = String(rules.get("hotswap", "practice"))


## A highway event: no grid or AI racers; where cars are on the highway, its rules, its traffic.
func _ready_highway() -> void:
	ai_racers = 0
	safe_rejoin = false
	highway_field = HighwayField.new()
	highway_field.name = "HighwayField"
	highway_field.session = self
	highway_field.layout = track.highway
	add_child(highway_field)
	# Tunnels keep the weather off the players' cars.
	env.sheltered = func(v: Vehicle) -> bool:
		for r in racers:
			if r.vehicle == v:
				return r.track_index >= 0 and track.highway.in_tunnel(r.distance)
		return false
	highway = HighwayControl.new()
	highway.name = "HighwayControl"
	highway.session = self
	highway.layout = track.highway
	highway.event = event
	add_child(highway)
	match event.sub:
		"score":
			var score := HighwayScore.new()
			score.name = "HighwayScore"
			score.session = self
			add_child(score)
		"run":
			var runs: Array = track.highway.runs.filter(func(r: Dictionary) -> bool: return event.run.is_empty() or r.id == event.run)
			if runs.is_empty():
				event.sub = "cruise" # no such run here: a cruise (every game the same), not a run that never ends
			else:
				run = RunControl.new()
				run.name = "RunControl"
				run.session = self
				run.layout = track.highway
				run.run = runs[0]
				add_child(run)
	var settings: Dictionary = track.highway.settings.traffic
	var count := event.traffic if event.traffic >= 0 else int(settings.count)
	var seed := traffic_seed if traffic_seed >= 0 else int(Game.dev.get("traffic-seed", settings.get("seed", 1)))
	if is_online():
		# Online every game runs the server's traffic: its seed and count (D109).
		var hw: Dictionary = online.get("highway", {})
		if hw.is_empty():
			return
		seed = int(hw.seed)
		count = int(hw.count) if int(hw.count) >= 0 else int(settings.count)
	# The lane sim runs even with traffic off: autodrive, bots and police drive by its lanes.
	if count >= 0:
		traffic = TrafficManager.new()
		traffic.name = "Traffic"
		traffic.session = self
		traffic.authority = not is_online() or Net.is_server()
		if traffic.setup(track, seed, count, event.police):
			add_child(traffic)
		else:
			traffic = null
	if event.police and (not is_online() or Net.is_server()):
		police = PoliceControl.new()
		police.name = "PoliceControl"
		police.session = self
		police.road = HighwayPoliceRoad.make(self)
		police.police_class = String(GameModes.list().filter(func(m: Dictionary) -> bool: return m.id == "highway").map(
			func(m: Dictionary) -> String: return String(m.get("police_class", "official.highway.interceptor"))).front())
		add_child(police)


## Kart (D129): the kart node next to an ordinary session. No track limits: falling off is
## what costs time.
func _ready_kart() -> void:
	kart = KartControl.new()
	kart.name = "KartControl"
	kart.session = self
	kart.arcade = arcade
	add_child(kart)


## Battles (D144): lives and hits, and the standings RaceControl shows.
func _ready_battle() -> void:
	battle = BattleControl.new()
	battle.name = "BattleControl"
	battle.session = self
	add_child(battle)
	race.standings_source = battle.standings


## Sumo's drift setting (D181). The class's own numbers are already "drift, no boost" -- the mode
## file zeroes `boost_s`, and KartLayer gives no boost for 0 s -- so only the other two modes have
## anything to do here. "off" takes the button away rather than detuning the drift, because the hop
## fires on a press whatever the minimum speed says.
func _apply_sumo_drift() -> void:
	if arcade.is_empty():
		return
	var want := String(event.sumo_drift)
	drift_allowed = want != "off"
	if want == "boost":
		(arcade.drift as Dictionary).boost_s = (GameModes.ARCADE_DEFAULTS.drift.boost_s as Array).duplicate()


## Sumo (D162): the platforms' rules, their HUD and their sounds, and the standings RaceControl
## shows. No KartControl: there are no items, and nothing tows a car that was shoved off.
func _ready_sumo() -> void:
	sumo = SumoControl.new()
	sumo.name = "SumoControl"
	sumo.session = self
	sumo.layout = track.arena as SumoLayout
	sumo.builder = sumo_world
	add_child(sumo)
	race.standings_source = sumo.standings
	if not dedicated and not Game.dev.has("bot"):
		sumo_hud = SumoHud.new()
		sumo_hud.name = "SumoHud"
		sumo_hud.session = self
		add_child(sumo_hud)
		# The camera for a player in the goo, who has the rest of the match to watch (D185).
		sumo_watch = SumoWatch.new()
		sumo_watch.name = "SumoWatch"
		sumo_watch.session = self
		add_child(sumo_watch)
		var s := SumoSounds.new()
		s.name = "SumoSounds"
		s.session = self
		sumo.sounds = s
		add_child(s)


## Drag (D168): the passes, the ladder, their HUD and their sounds, and the standings
## RaceControl shows. No KartControl: the full sim runs, which is what gives it a gearbox.
func _ready_drag() -> void:
	drag = DragControl.new()
	drag.name = "DragControl"
	drag.session = self
	drag.layout = track.arena as DragLayout
	drag.builder = drag_world
	drag.drag_seed = drag_seed if drag_seed != 0 else int(Game.dev.get("drag-seed", "0"))
	add_child(drag)
	race.standings_source = drag.standings
	# No pass runs before its drivers have locked in (D177). The authority holds the ladder even
	# with no cards of its own to show: on a dedicated server every driver is somebody else's.
	drag.ready_gate = true
	if not dedicated and not Game.dev.has("bot"):
		drag_hud = DragHud.new()
		drag_hud.name = "DragHud"
		drag_hud.session = self
		add_child(drag_hud)
		# The cards, and the camera on a pass somebody else is running (D176-D178).
		drag_watch = DragWatch.new()
		drag_watch.name = "DragWatch"
		drag_watch.session = self
		add_child(drag_watch)
		var ds := DragSounds.new()
		ds.name = "DragSounds"
		ds.session = self
		drag.sounds = ds
		add_child(ds)


## Sumo: car `i`'s spot on the top platform's ring. The synthesised track's spline runs round
## the platform's rim, so the usual grid would drop a car straight over the edge before the
## lights; RaceControl places everyone properly again when the session begins.
func arena_spawn(i: int) -> Transform3D:
	var spawns := track.arena.spawns
	return spawns[i % spawns.size()] if not spawns.is_empty() else Transform3D.IDENTITY


## Highways: racer `i`'s starting direction.
func direction_for(i: int) -> int:
	if i < directions.size():
		return int(directions[i])
	if event.direction == 0: # both ways: turn about
		return 1 if i % 2 == 0 else -1
	return event.direction


## The node that drives `r` (an AI racer, a dev player): the racing AI on circuits, the lane
## driver on highways, the battle AI in an arena, the sumo AI on the platforms.
func make_driver(r: Racer) -> Node:
	if endless:
		var e := EndlessDriver.new()
		e.racer = r
		e.lanes = endless_lanes
		return e
	if highway:
		var d := HighwayDriver.new()
		d.racer = r
		return d
	if sumo:
		var su := SumoAI.new()
		su.racer = r
		su.skill = ai_skill
		return su
	if drag:
		var dr := DragAI.new()
		dr.racer = r
		dr.skill = ai_skill
		return dr
	if track.arena:
		var b := BattleAI.new()
		b.racer = r
		b.skill = ai_skill
		return b
	var ai: RacingAI = KartAI.new() if kart else RacingAI.new()
	ai.racer = r
	ai.skill = ai_skill
	return ai


## What a player's access assists follow (ACC-07): the racing line, or a highway's lanes.
func make_guide(r: Racer) -> Node:
	if endless:
		var e := EndlessDriver.new()
		e.racer = r
		e.lanes = endless_lanes
		e.as_guide = true
		return e
	if highway:
		var d := HighwayDriver.new()
		d.racer = r
		d.as_guide = true
		return d
	if sumo:
		var su := SumoAI.new()
		su.racer = r
		su.as_guide = true
		return su
	if drag:
		var dr := DragAI.new()
		dr.racer = r
		dr.as_guide = true
		return dr
	if track.arena:
		var b := BattleAI.new()
		b.racer = r
		b.as_guide = true
		return b
	var ai: RacingAI = KartAI.new() if kart else RacingAI.new()
	ai.racer = r
	ai.as_guide = true
	return ai


## An online session's cars (D84): this game's players drive their own (each on the Players slot
## of their local index, Net.local_of()); everyone else's car is remote. Everyone's spot is their place in the roster.
func _ready_online() -> void:
	net = NetSession.new()
	net.name = "NetSession"
	net.session = self
	add_child(net)
	if highway:
		if Net.host_logic:
			Net.host_logic.board_requested.connect(_on_board_requested)
		Net.board_received.connect(_on_board_received)
		Net.highway_event.connect(_on_highway_event)
	if kart:
		# Items online (D141): the server's word on boxes, uses, hits and lives.
		var kn := KartNet.new()
		kn.name = "KartNet"
		kn.session = self
		kn.kart = kart
		add_child(kn)
	if sumo:
		# The platforms online (D166): the server shrinks them and rules on who is in the goo.
		sumo_net = SumoNet.new()
		sumo_net.name = "SumoNet"
		sumo_net.session = self
		sumo_net.sumo = sumo
		add_child(sumo_net)
	if drag:
		# The pass online (D175): the server runs the tree, rules on the lane and the lights, and
		# says who won; each game grades its own shifts and reports them up.
		drag_net = DragNet.new()
		drag_net.name = "DragNet"
		drag_net.session = self
		drag_net.drag = drag
		drag.net = drag_net
		add_child(drag_net)
	if event.kind == "time_trial":
		# A timed session (§7.7): the server's live board of best laps.
		time_trial_net = TimeTrialNet.new()
		time_trial_net.name = "TimeTrialNet"
		time_trial_net.session = self
		add_child(time_trial_net)
	var sky: Dictionary = online.get("environment", {})
	if not sky.is_empty():
		var t0 := float(sky.t0)
		env.clock = func() -> float: return net.now() - t0
	Net.env_changed.connect(_on_env_changed)
	if endless:
		endless_net = EndlessNet.new()
		endless_net.session = self
		endless_net.traffic = endless_traffic
		endless_world.record_sums = true
		var t0 := float(online.get("endless", {}).get("t0", 0.0))
		if endless_traffic:
			endless_traffic.net = endless_net
			endless_traffic.clock = func() -> float: return net.now() - t0
			if event.garage_traffic:
				endless_traffic.set_garage(_online_garage())
		add_child(endless_net)
	if traffic:
		var hn := HighwayNet.new()
		hn.name = "HighwayNet"
		hn.session = self
		hn.traffic = traffic
		hn.t0 = float(online.highway.t0)
		traffic.net = hn
		add_child(hn)
	if not dedicated:
		Players.primary_slot()
	var roster: Array = online.roster
	for i in roster.size():
		_add_online_racer(roster[i], i)
	Net.roster_changed.connect(_on_roster)
	Net.chat_line.connect(_on_chat)
	if Net.content:
		Net.content.car_changed.connect(_on_net_car)
	ai_racers = 0


## Where in the single file an online player starts on an endless road (D159): at the session's
## start by their place in the roster, so players on different games never land on each other;
## joining a drive under way, one behind another behind the leader.
func _endless_file_index(id: int, roster_index: int) -> int:
	var at: Variant = online.get("endless", {}).get("at", {})
	if at is Dictionary and not (at as Dictionary).is_empty():
		return maxi(Net.local_of(id), 0)
	return roster_index


## The server changed the sky mid-session (an admin's /time or /weather).
func _on_env_changed(sky: Dictionary) -> void:
	online.environment = sky
	env.state = _env_state(StyleProfile.load_profile(track.style))
	var t0 := float(sky.t0)
	env.clock = func() -> float: return net.now() - t0
	env.apply()


## Chat shows as captions for each player here, and is read out with their race narration.
func _on_chat(line: Dictionary) -> void:
	var text := "%s: %s" % [line.name, line.text] if line.kind == "chat" else String(line.text)
	for p in players:
		if p.slot.ai:
			continue
		p.hud.caption(text, 5.0)
		if Narrator.race_on(p.slot.profile):
			Narrator.say(text)


func _add_online_racer(d: Dictionary, index: int) -> Racer:
	var id := int(d.id)
	# By the roster's order, so players on different games never land on each other (D159).
	var spot := highway.spawn_for(index, direction_for(index)) if highway \
		else endless.spawn_for(_endless_file_index(id, index)) if endless \
		else arena_spawn(index) if sumo \
		else track.transform_at(_grid_distance(index), _grid_lateral(index))
	if d.get("ai", false) and Net.is_server(): # the server's AI cars (D88)
		var a := AiRacer.new()
		a.configure(int(d.get("local", 0)), float(d.get("skill", ai_skill)))
		a.net_id = id
		a.class_id = String(d.get("class", ""))
		a.paint = CarVisual.clean_paint(d.get("paint"))
		a.spawn_at = spot
		_add_racer(a)
		var path := Net.host_logic.ai_path(id) if Net.host_logic else ""
		a.load_car(path if path else _default_car)
		net.add(a, true)
		safe_rejoin = true
		return a
	var local := Net.local_of(id)
	if local >= 0 and local < Players.slots.size() and not dedicated:
		var slot := Players.slots[local]
		if autodrive:
			slot.ai = true
		var p := _add_player(slot, spot, String(d.get("class", "")))
		p.net_id = id
		net.add(p, true)
		return p
	var r := NetRacer.new()
	r.net_id = id
	r.peer = int(d.peer)
	r.display_name = NetProtocol.clean_name(String(d.name))
	r.color = Color.from_string(String(d.color), Color.WHITE)
	r.number = index + 1
	r.is_human = not d.get("ai", false)
	r.paint = CarVisual.clean_paint(d.get("paint"))
	r.name = "Net%d" % id
	r.class_id = String(d.get("class", ""))
	r.spawn_at = spot
	_add_racer(r)
	r.car_hash = String(d.car) if String(d.get("car_note", "")).is_empty() else ""
	r.load_net_car()
	net.add(r, false)
	return r


## Someone joined or left mid-session, or changed car.
func _on_roster(roster: Array) -> void:
	var ids := {}
	for i in roster.size():
		var d: Dictionary = roster[i]
		var id := int(d.id)
		ids[id] = true
		var r: Racer = net.racers.get(id)
		if r == null:
			_add_online_racer(d, _free_online_index())
		elif r is NetRacer:
			var car := String(d.car) if String(d.get("car_note", "")).is_empty() else ""
			if car != (r as NetRacer).car_hash:
				(r as NetRacer).car_hash = car
				(r as NetRacer).load_net_car()
	for id: int in net.racers.keys():
		var r: Racer = net.racers[id]
		if not ids.has(id) and r is NetRacer:
			if race.kind in ["practice", "qualifying", "race", "time_trial", "run"] and race.phase != RaceControl.Phase.DONE:
				# Gone mid-session: out of it, in the results as such, until the session ends.
				r.dnf = true
				r.set_meta(&"left", true)
				if r.vehicle:
					r.vehicle.visible = false
					r.vehicle.set_ghost(true, false)
				continue
			net.remove(id)
			racers.erase(r)
			r.remove()


## The first grid spot no car stands on (for someone joining mid-session).
func _free_online_index() -> int:
	for i in GRID_SPOTS:
		if _spot_clear(_grid_distance(i), _grid_lateral(i)):
			return i
	return GRID_SPOTS


func _on_net_car(car_hash: String) -> void:
	for r: Racer in racers:
		if r is NetRacer and (r as NetRacer).car_hash == car_hash:
			(r as NetRacer).load_net_car()
	if endless_traffic and Net.content:
		var c := Net.content.car(car_hash)
		if not c.is_empty() and not c.get("partial", true):
			endless_traffic.have_car(car_hash, String(c.path))


## Online garage traffic (D191): the host's cars, by hash, each with the traffic types it drives
## as; fetched from the host if they aren't here.
func _online_garage() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list: Variant = online.get("endless", {}).get("traffic_cars", [])
	if not list is Array:
		return out
	var t: EndlessTraffic = endless_traffic
	for d: Variant in (list as Array).slice(0, EndlessTraffic.GARAGE_SHARED):
		if not (d is Dictionary and d.get("car") is String and ContentStore.valid_hash(d.car) and d.get("fits") is Array):
			continue
		var fits: Array[int] = []
		for id: Variant in (d.fits as Array).slice(0, 8):
			var i := t._types.find_custom(func(type: Dictionary) -> bool: return id is String and type.id == id)
			if i >= 0 and not i in fits:
				fits.append(i)
		if fits.is_empty():
			continue
		var here := Net.content.car(String(d.car)) if Net.content else {}
		var whole: bool = not here.is_empty() and not here.get("partial", true)
		out.append({ "car": String(d.car), "path": String(here.path) if whole else "", "fits": fits })
		if not whole and Net.content:
			Net.content.fetch_car(String(d.car), 1, Net.content.max_tier)
	return out


## Racer `r`'s class: in a kart session a player's own pick (their profile's `kart_class`) or an AI
## kart's (D149), online the roster's; otherwise, and for a class the mode doesn't have, the
## session's.
func platform_for(r: Racer) -> PlatformLoader.Result:
	if arcade.is_empty():
		return platform
	var id := r.class_id
	if is_online():
		pass
	elif r is SessionPlayer:
		id = String((r as SessionPlayer).slot.profile.data.get("kart_class", ""))
	elif r is AiRacer:
		id = ai_class((r as AiRacer).number - 5)
	return class_result(id)


## The class `id` if this session's mode has it, else the session's own.
func class_result(id: String) -> PlatformLoader.Result:
	if id.is_empty() or id == platform_id or id not in Array(mode.get("classes", [])):
		return platform
	if not _classes.has(id):
		var r := PlatformLoader.load_official(id)
		_classes[id] = r if r.ok() else platform
	return _classes[id]


## AI kart `index`'s class: kept through a cup, else its own pick (the session's with
## `ai_class_mix` off).
func ai_class(index: int) -> String:
	if cup and index < cup.roster.size() and (cup.roster[index] as Dictionary).has("class"):
		return String(cup.roster[index]["class"])
	if not ai_class_mix:
		return platform_id
	if not _ai_classes.has(index):
		var ids: Array = mode.get("classes", [])
		var rng := RandomNumberGenerator.new()
		if Game.dev.has("seed"):
			rng.seed = hash(int(Game.dev.seed) * 31 + index)
		else:
			rng.randomize()
		_ai_classes[index] = String(ids[rng.randi() % ids.size()]) if not ids.is_empty() else platform_id
	return _ai_classes[index]


## The class's default car (built-in).
func default_car() -> String:
	return _default_car


func _add_racer(r: Racer) -> void:
	r.session = self
	r.track = track
	r.platform = platform_for(r)
	r.default_car = _default_car
	if highway:
		r.limits = false
		r.wrong_way_respawn = false
		r.direction = direction_for(racers.size())
	elif endless:
		r.limits = false
		r.wrong_way_respawn = false
		r.laps = false
	elif sumo:
		# No laps, no limits and no wrong way on a platform (D162).
		r.limits = false
		r.wrong_way_respawn = false
		r.laps = false
	elif kart:
		r.limits = false
	racers.append(r)
	add_child(r)
	r.setup()
	if race.is_inside_tree():
		race.watch(r)


## An AI racer on the next grid spot, with a random car from `pool`.
func _add_ai(index: int, pool: PackedStringArray, skill: float) -> AiRacer:
	var a := AiRacer.new()
	# A cup keeps its field from race to race: the same car, paint and skill.
	var kept: Dictionary = cup.roster[index] if cup and index < cup.roster.size() else {}
	a.configure(index, float(kept.get("skill", skill)))
	if kept.has("paint"):
		a.paint = kept.paint
	var i := racers.size()
	a.spawn_at = arena_spawn(i) if sumo else \
		track.transform_at(_grid_distance(i), _grid_lateral(i)) if _spot_clear(_grid_distance(i), _grid_lateral(i)) else _free_grid_spot()
	_add_racer(a)
	a.load_car(String(kept.car) if kept.has("car") else pool[randi() % pool.size()] if not pool.is_empty() else _default_car)
	return a


## Cars the AI can drive in this class: the garage's and the built-ins, or only the built-ins.
func ai_car_pool() -> PackedStringArray:
	var out := PackedStringArray()
	# A mode with its own default car (kart: the nOSS Kart, D134) fields only that from the built-ins.
	if ai_builtin_cars and String(mode.get("default_car", "")) in PackageLoader.list_available():
		out.append(mode.default_car)
		return out
	for path in PackageLoader.list_available():
		if ai_builtin_cars and not path.begins_with("res://"):
			continue
		if Fitting.compatible(platform.platform, PackageLoader.read_manifest(path).get("family", "")):
			out.append(path)
	return out


func _on_joined(slot: PlayerSlot) -> void:
	var p := _add_player(slot)
	if time_trial:
		time_trial.add(p)
	apply_game_speed()
	p.hud.show_message("%s joined" % slot.tag(), 2.0)


func _on_left(slot: PlayerSlot) -> void:
	if views.view(slot) == null:
		return # not in this session (a solo drive)
	for p in players:
		if p.slot == slot:
			if paused_by == p:
				_resume()
			if time_trial:
				time_trial.remove(p)
			players.erase(p)
			racers.erase(p)
			p.remove()
			break
	views.remove(slot)
	if players.is_empty():
		Game.go_title()
		return
	apply_game_speed()


func _on_views_changed() -> void:
	EngineSound.set_listeners(views.listener_count())
	# Car LODs switch closer with more views (risk R8).
	CarVisual.lod_scale = 1.0 / (1.0 + 0.25 * (players.size() - 1))
	for p in players:
		p.update_badge(players.size())
	for r in racers:
		if r.vehicle and r.vehicle.visual:
			r.vehicle.visual.apply_lod_scale()


func _process(delta: float) -> void:
	_sound_time += delta
	if _sound_time >= SOUND_UPDATE_S:
		_sound_time = 0.0
		_update_sound_detail()
	# Dev: --swap-car=<path> --swap-at=<s> swaps P1's car mid-drive and logs the speed around it.
	var p1 := players[0] if not players.is_empty() else null
	if Game.dev.has("swap-car") and p1 and p1.vehicle and not _dev_swapped:
		_dev_time += delta
		if _dev_time >= float(Game.dev.get("swap-at", "20")):
			_dev_swapped = true
			print("Swap at %.1f km/h" % (p1.vehicle.speed() * 3.6))
			p1.load_car(Game.dev["swap-car"])
	# Dev: --pause-at=<s> opens the last player's pause menu (screenshots).
	if Game.dev.has("pause-at") and paused_by == null and not players.is_empty():
		_dev_time += delta
		if _dev_time >= float(Game.dev["pause-at"]):
			Game.dev.erase("pause-at")
			_open_pause(players[-1])
			if Game.dev.get("pause-menu", "") == "setup" and players[-1].overlay is PauseMenu: # dev: screenshots
				(players[-1].overlay as PauseMenu)._open_setup()
	if Game.dev.has("fps"):
		_fps_time += delta
		_fps_frames += 1
		if _fps_time >= 1.0:
			print("fps %.0f" % (_fps_frames / _fps_time))
			_fps_time = 0.0
			_fps_frames = 0


## Game speed (ACC-08, docs/ACCESSIBILITY.md §6): 50-100% with one player (offline). Time and
## the physics tick rate scale together, so the sim still steps 1/120 s of game time. Laps at
## less than full speed are marked in results and kept off leaderboards.
func apply_game_speed() -> void:
	var humans := players.filter(func(p: SessionPlayer) -> bool: return not p.slot.ai)
	var speed := 1.0
	if humans.size() == 1 and not is_online():
		speed = clampf(float(humans[0].slot.profile.data.get("game_speed", 1.0)), 0.5, 1.0)
	# A pass of bots being hurried along (D178) takes the clock with it, and only the clock: the
	# tick rate stays, so the sim steps the same slice of game time a driven pass does.
	Engine.time_scale = speed * (DragControl.SKIP_SPEED if drag and drag.skipping else 1.0)
	Engine.physics_ticks_per_second = roundi(PHYSICS_HZ * speed)
	if speed < 1.0:
		for p: SessionPlayer in humans:
			p.assists_used["game_speed"] = true


## A session ended: its results go up on the main window while the cars take a cool-down lap.
## Online the host decides what's next (the dedicated server goes on by itself); clients wait.
func _on_session_ended(kind: String, results: Array) -> void:
	if paused_by:
		_resume()
	if dedicated:
		print("%s results: %s" % [kind.capitalize(), ", ".join(PackedStringArray(results.map(func(row: Dictionary) -> String: return "%d %s" % [row.position, row.name])))])
		print("NETCHECK_RESULTS " + JSON.stringify({ "kind": kind, "rows": results.map(func(row: Dictionary) -> Dictionary:
			return { "position": row.position, "name": row.name, "laps": row.laps, "dnf": row.dnf, "time": row.time, "best": row.best,
				"ai": not (row.racer as Racer).is_human, "lives": row.get("lives", -1), "hits": row.get("hits", 0),
				"tier": row.get("tier", 0), "lasted": row.get("lasted", 0.0), "out": row.get("out", false),
				"reaction": row.get("reaction", -1.0), "et": row.get("et", -1.0), "round": row.get("round", 0) }) }))
		var sn := get_node_or_null(^"SumoNet") as SumoNet
		if sn:
			print("NETCHECK_SUMO_SERVER " + JSON.stringify({ "outs": sn.outs, "tiers": sumo.layout.count() }))
		var dn := get_node_or_null(^"DragNet") as DragNet
		if dn:
			print("NETCHECK_DRAG_SERVER " + JSON.stringify({ "events": dn.events, "grades": dn.grades_taken,
				"passes": drag.passes_run, "winner": drag.ladder.winner.display_name if drag.ladder.winner else "" }))
		var kn := get_node_or_null(^"KartNet") as KartNet
		if kn:
			print("NETCHECK_KART_SERVER " + JSON.stringify({ "validated": kn.validated, "rejected": kn.rejected, "forced": kn.forced,
				"rejected_picks": kn.rejected_picks, "rejected_uses": kn.rejected_uses, "contested": kn.contested }))
		get_tree().create_timer(DEDICATED_RESULTS_S).timeout.connect(func() -> void:
			if not is_inside_tree() or race.phase != RaceControl.Phase.DONE:
				return
			if race.has_next():
				_drop_leavers()
				race.next_session()
			elif Net.host_logic:
				Net.host_logic.end_session()) # a playlist moves on
		return
	print("%s results: %s" % [kind.capitalize(), ", ".join(PackedStringArray(results.map(func(row: Dictionary) -> String: return "%d %s" % [row.position, row.name])))])
	if Game.dev.has("quit-after-results") or (Game.dev.has("auto-continue") and not race.has_next()):
		get_tree().quit()
		return
	if Game.dev.has("auto-continue"): # dev: straight on to the next session
		race.next_session.call_deferred()
		return
	results_menu = ResultsMenu.new()
	results_menu.kind = kind
	results_menu.results = results
	results_menu.mode = "client" if race.mirror else "host" if is_online() else "local"
	results_menu.has_next = race.has_next()
	results_menu.next_name = race.event.sessions()[race.index + 1].capitalize() if race.has_next() else ""
	if cup and kind == "race" and not is_online(): # online the server keeps the cup's standings
		cup.keep_roster(self)
		cup.add_results(results)
		results_menu.has_next = true
		results_menu.next_name = "Cup standings"
	results_menu.continued.connect(func() -> void:
		_close_results()
		if cup and kind == "race" and not is_online():
			_open_cup_standings()
			return
		_drop_leavers()
		race.next_session())
	results_menu.restarted.connect(func() -> void:
		_close_results()
		_drop_leavers()
		race.restart_session())
	results_menu.to_lobby.connect(func() -> void:
		if Net.host_logic:
			Net.host_logic.end_session())
	results_menu.quit_to_title.connect(func() -> void:
		if is_online():
			Net.leave()
		Game.go_title())
	_offer_event_menu(results_menu)
	# The main window shows views at their real pixel size; menus are laid out for 1080p.
	var layer: CanvasLayer = $ResultsLayer
	var window := get_viewport().get_visible_rect().size
	var s := window.y / 1080.0 * Players.menu_text_scale()
	layer.scale = Vector2(s, s)
	results_menu.size = window / s
	layer.add_child(results_menu)


## Results of an event started from the event pages offer "Event menu": its Settings page again
## (docs/UI_FLOW.md §5.9).
func _offer_event_menu(menu: ResultsMenu) -> void:
	menu.event_menu = menu.mode == "local" and not Game.flow_return.is_empty() and cup == null
	menu.to_event_menu.connect(func() -> void: Game.go_event_menu())


## A cup's table after its race; on to the next race, or back to the main menu after the last.
func _open_cup_standings() -> void:
	var menu := CupStandingsMenu.new()
	menu.run = cup
	menu.next_race.connect(func() -> void: Game.start_cup_race(cup))
	menu.quit_to_title.connect(func() -> void: Game.go_title())
	var layer: CanvasLayer = $ResultsLayer
	var window := get_viewport().get_visible_rect().size
	var s := window.y / 1080.0 * Players.menu_text_scale()
	layer.scale = Vector2(s, s)
	menu.size = window / s
	layer.add_child(menu)


## The results go (the server began the next session).
func close_results() -> void:
	_close_results()


func _on_board_received(board: String, entries: Array) -> void:
	server_boards[board] = entries


## Online client: one of the server's police units, shown from its states.
func add_police_proxy(id: int) -> NetRacer:
	var r := NetRacer.new()
	r.net_id = id
	r.peer = 1
	r.display_name = "Police"
	r.color = PoliceRacer.COLOR
	r.is_human = false
	r.name = "Net%d" % id
	r.number = 50 + (id % NetProtocol.POLICE_PER_GAME if NetProtocol.is_endless_police(id) else id - NetProtocol.FIRST_POLICE_ID)
	r.spawn_at = Transform3D(Basis(), Vector3(0, -500.0, 0))
	_add_racer(r)
	r.default_car = PoliceRacer.CAR
	r.load_net_car()
	net.add(r, false)
	return r


## Online client: police news for one of this game's cars (heat, busted, evaded).
func _on_highway_event(data: Dictionary) -> void:
	for p in players:
		if p.net_id != int(data.id):
			continue
		var panel := p.hud.get_node_or_null(^"HeatPanel") as HeatPanel
		if panel == null:
			panel = HeatPanel.new()
			panel.name = "HeatPanel"
			p.hud.add_child(panel)
		panel.show_heat(int(data.level), float(data.evading))
		if String(data.text):
			p.notify(String(data.text), 2.5)
			if Narrator.race_on(p.slot.profile):
				Narrator.say(String(data.text))
		if data.kind == "busted":
			var score := get_node_or_null(^"HighwayScore") as HighwayScore
			if score:
				score.rules_for(p).contact(INF, 0.0)
			highway.reset(p)


## Server: a client asked for one of this server's boards for this track.
func _on_board_requested(peer: int, board: String) -> void:
	var entries := Leaderboard.entries(track.record_key(), board, true).map(func(e: Dictionary) -> Dictionary:
		return { "name": e.get("name", ""), "car": e.get("car", ""), "time": e.get("time", 0.0), "score": e.get("score", 0) })
	if peer == 1:
		server_boards[board] = entries # the host's own players
	else:
		Net.server.send(peer, NetProtocol.Msg.BOARD, { "board": board, "entries": entries })


## Players who left during the last session go before the next one.
func _drop_leavers() -> void:
	if net == null:
		return
	for id: int in net.racers.keys():
		var r: Racer = net.racers[id]
		if r.has_meta(&"left"):
			net.remove(id)
			racers.erase(r)
			r.remove()


func _close_results() -> void:
	if results_menu:
		results_menu.queue_free()
		results_menu = null


## Players' own cars always sound in full; AI cars by distance to the nearest camera.
func _update_sound_detail() -> void:
	var cameras: Array[Vector3] = []
	for p in players:
		cameras.append(p.cameras.camera.global_position)
	var ranked := []
	for r in racers:
		if r.sound == null or r.vehicle == null:
			continue
		if r is SessionPlayer:
			r.sound.detail = EngineSound.Detail.FULL
			continue
		var nearest := INF
		for c in cameras:
			nearest = minf(nearest, c.distance_to(r.vehicle.global_position))
		ranked.append([nearest, r])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in ranked.size():
		var d: float = ranked[k][0]
		var sound: EngineSound = ranked[k][1].sound
		if k < SOUND_FULL_COUNT and d < SOUND_FULL_M:
			sound.detail = EngineSound.Detail.FULL
		elif d < SOUND_DISTANT_M:
			sound.detail = EngineSound.Detail.DISTANT
		else:
			sound.detail = EngineSound.Detail.OFF


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_show_fps = not _show_fps
		for p in players:
			p.hud.show_fps = _show_fps


## Grid spot `i`: two staggered columns behind the line, the first `front` metres back and each
## column's cars `row` metres apart; the second column back by the track's stagger.
func grid_transform(i: int, front: float, row: float) -> Transform3D:
	var d := track.start_m - front - (i / 2) * row - (i % 2) * row * float(track.grid.stagger)
	return track.transform_at(d, _grid_lateral(i, d))


## Grid spots behind the start line: two columns, a row every GRID_ROW_M.
func _grid_distance(i: int) -> float:
	return track.start_m - grid_front_m - (i / 2) * grid_row_m - (i % 2) * grid_row_m * 0.5


## Columns half way to each edge (the narrower side's), pole on the track's pole side.
func _grid_lateral(i: int, distance := INF) -> float:
	var d := _grid_distance(i) if is_inf(distance) else distance
	var column := 1.0 if i % 2 == 0 else -1.0
	if track.grid.pole == "right":
		column = -column
	return 0.5 * minf(track.half_width(d, 1.0), track.half_width(d, -1.0)) * column


func _spot_clear(distance: float, lateral: float, except: Racer = null) -> bool:
	var at := track.transform_at(distance, lateral).origin
	for r in racers:
		if r != except and r.vehicle and r.vehicle.global_position.distance_to(at) < CLEAR_M:
			return false
	return true


## The first grid spot nobody is on (for players who drop in mid-drive).
func _free_grid_spot() -> Transform3D:
	for i in GRID_SPOTS:
		if _spot_clear(_grid_distance(i), _grid_lateral(i)):
			return track.transform_at(_grid_distance(i), _grid_lateral(i))
	return track.transform_at(_grid_distance(GRID_SPOTS), 0.0)


## A reset spot at or behind `distance` with no other car on it.
func free_spot_near(distance: float, who: Racer) -> float:
	for step in 10:
		var d := distance - step * GRID_ROW_M
		if _spot_clear(d, 0.0, who):
			return d
	return distance


func _map_cars() -> Array:
	var out := []
	for r in racers:
		if r.vehicle:
			out.append([r.number, r.color, r.vehicle.global_position])
	return out


func _open_pause(p: SessionPlayer) -> void:
	if paused_by:
		return
	paused_by = p
	for other in players:
		if other != p and not is_online():
			other.hud.show_message("Paused by %s" % p.slot.tag(), 1e9)
			if not other.slot.ai:
				other.slot.input.wheel.stop_ffb()
				other.stop_rumble()
	if is_online():
		paused_by = null # online the game never stops (D86): only this player's menu opens
	var menu := PauseMenu.new()
	menu.slot = p.slot
	menu.bay_return = bay_return
	menu.editor_return = editor_return
	menu.can_leave = p.slot.index > 0 and not is_online()
	menu.can_change_car = hotswap_allowed
	menu.can_end_session = race.kind in ["practice", "qualifying"]
	menu.allowed_assists = AssistRules.allowed(platform.platform, mode)
	menu.can_restart = race.kind in ["race", "practice", "qualifying", "drag", "run"] and not race.mirror
	if race.kind == "drag":
		# A ladder is a long thing to lose to a stray press, so this one asks first (D179).
		menu.restart_text = "Restart event"
		menu.confirm_restart = true
	menu.can_end_session = menu.can_end_session and not race.mirror
	menu.online = is_online()
	menu.is_host = is_online() and Net.is_server()
	menu.to_lobby.connect(func() -> void:
		_resume(p)
		if Net.host_logic:
			Net.host_logic.end_session())
	menu.can_setup = race.kind != "race" and p.car_setup != null and not p.car_setup.allowed.is_empty()
	menu.setup = p.car_setup
	menu.setup_closed.connect(func() -> void: p.setup_changed())
	if pits and pits.services():
		# The pit service by menu (D210), for every preset (some have no keys to spare for it).
		var request: Dictionary = pits.stop_of(p).request
		var fuel := PitControl.FUEL.map(func(f: String) -> Array: return [f, PitControl.FUEL_WORDS[f]])
		var tires := PitControl.TIRES.map(func(t: int) -> Array: return [t, "%d" % t if t > 0 else "None"])
		menu.extra_rows.append(UiKit.spinner("Pit fuel", fuel, String(request.fuel), func(v: String) -> void: pits.set_request(p, "fuel", v),
			"What the next stop puts in"))
		menu.extra_rows.append(UiKit.spinner("Pit tires", tires, int(request.tires), func(v: int) -> void: pits.set_request(p, "tires", v),
			"How many tires the next stop changes"))
	if time_trial and time_trial.lane_of(p):
		var lane := time_trial.lane_of(p)
		menu.ghost_items = lane.choices()
		menu.ghost_current = lane.choice
		menu.ghost_picked.connect(lane.pick)
		if time_trial_net:
			menu.leaderboard = time_trial_net.entries # this session's, the server's
			menu.leaderboard_title = "%s · this session" % track.display_name
		else:
			menu.leaderboard = Leaderboard.entries(track.record_key(), p.platform.platform.id)
			menu.leaderboard_title = "%s · %s" % [track.display_name, p.platform.platform.name]
	elif highway and highway.board(p):
		var board := highway.board(p)
		if is_online():
			# The server's board, as it last sent it; asked again for next time.
			menu.leaderboard = server_boards.get(board, [])
			Net.request(NetProtocol.Msg.BOARD_REQUEST, { "board": board })
		else:
			menu.leaderboard = Leaderboard.entries(track.record_key(), board)
		menu.leaderboard_title = "%s · %s · %s%s" % [track.display_name, platform.platform.name, highway.board_name(p), " · this server" if is_online() else ""]
		menu.leaderboard_scores = Leaderboard.by_score(board)
	menu.end_session.connect(func() -> void:
		_resume(p)
		race.end_session())
	menu.restart.connect(func() -> void:
		_resume(p)
		_close_results()
		race.restart_session())
	menu.resumed.connect(_resume.bind(p))
	menu.reset_car.connect(func() -> void:
		_resume(p)
		p.reset_car())
	menu.change_car.connect(func() -> void:
		_resume(p)
		p.open_picker(true))
	menu.leave.connect(func() -> void:
		_resume(p)
		Players.leave(p.slot))
	menu.quit_to_title.connect(func() -> void:
		if is_online():
			Net.leave()
		Game.go_title())
	var mode_items: Array = highway.pause_items(p) if highway else endless.pause_items(p) if endless else []
	if not mode_items.is_empty():
		menu.extra_items = mode_items.map(func(item: Array) -> Array:
			return [item[0], func() -> void:
				_resume(p)
				item[1].call(), item[2]])
	menu.back_to_bay.connect(func() -> void: Game.open_fitting_bay("", "", Game.bay_from))
	menu.back_to_editor.connect(func() -> void: Game.return_to_editor())
	p.show_overlay(menu, not is_online())


## Closes `who`'s pause menu (online nobody holds the pause, so the menu's owner is passed in).
func _resume(who: SessionPlayer = null) -> void:
	var p := who if who else paused_by
	paused_by = null
	get_tree().paused = false
	for other in players:
		other.hud.show_message("", 0.0)
	if p and is_instance_valid(p):
		p.close_overlay()
