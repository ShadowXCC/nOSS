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
var views := ViewManager.new()
var players: Array[SessionPlayer] = []
## Every car: players and AI.
var racers: Array[Racer] = []
var field := RaceField.new()
## Runs the event's sessions: grid, countdown, standings, flags, results.
var race := RaceControl.new()
## The results screen while it's up.
var results_menu: ResultsMenu
## Time trial: records laps, shows the ghost (null in other events).
var time_trial: TimeTrial
var world_env: Environment
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
var traffic: TrafficManager
## Dev and tests: the traffic's seed (-1: the track's).
var traffic_seed := -1
## Highways: each player's starting direction by player order ([] or missing: the event's).
var directions: Array = []

var _default_car := ""
var _show_fps := false
var _dev_time := 0.0
var _dev_swapped := false
var _fps_time := 0.0
var _fps_frames := 0
var _sound_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if track_package == null or not track_package.ok():
		track_package = TrackLoader.load_package(track_path)
	if not track_package.ok():
		push_error("Track %s: %s" % [track_path, track_package.error])
		track_package = TrackLoader.load_package(DEFAULT_TRACK)
	track = track_package.track
	terrain = track_package.terrain
	var style := StyleProfile.load_profile(track.style)
	style.apply_globals()
	var env_node := style.create_environment()
	world_env = env_node.environment
	add_child(env_node)
	add_child(style.create_sun())
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
	if is_online():
		_apply_server_rules(online.get("rules", {}))
	if event.kind == "race":
		# As many as the track's grid takes, after the players.
		ai_racers = clampi(event.ai_count, 0, maxi(int(track.grid.slots) - maxi(Players.count(), 1), 0))
		ai_skill = event.ai_skill
		ai_builtin_cars = event.ai_cars == "builtin"
		safe_rejoin = true
	ghosted = not event.collisions
	if event.kind == "time_trial":
		solo = true
	field.track = track
	field.racers = racers
	add_child(field)
	if event.kind == "highway" and track.highway:
		_ready_highway()

	add_child(views)
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
		var net_race := NetRace.new()
		net_race.name = "NetRace"
		net_race.session = self
		add_child(net_race)
	race.start()
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
	if Net.host_logic and Net.host_logic.board_requested.is_connected(_on_board_requested):
		Net.host_logic.board_requested.disconnect(_on_board_requested)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = PHYSICS_HZ
	CarVisual.lod_scale = 1.0
	PackageLoader.clear_shared()
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


func _add_player(slot: PlayerSlot, at: Variant = null) -> SessionPlayer:
	var p := SessionPlayer.new()
	p.slot = slot
	p.bay_return = bay_return
	var i := racers.size()
	if at is Transform3D:
		p.spawn_at = at
	elif highway:
		p.spawn_at = highway.spawn_for(i, direction_for(i))
	else:
		p.spawn_at = track.transform_at(_grid_distance(i), _grid_lateral(i)) if _spot_clear(_grid_distance(i), _grid_lateral(i)) else _free_grid_spot()
	p.view = views.add(slot)
	players.append(p)
	_add_racer(p)
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
			if not runs.is_empty():
				run = RunControl.new()
				run.name = "RunControl"
				run.session = self
				run.layout = track.highway
				run.run = runs[0]
				run.done.connect(_on_run_done)
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
	if count > 0:
		traffic = TrafficManager.new()
		traffic.name = "Traffic"
		traffic.session = self
		traffic.authority = not is_online() or Net.is_server()
		if traffic.setup(track, seed, count):
			add_child(traffic)
		else:
			traffic = null


## Highways: racer `i`'s starting direction.
func direction_for(i: int) -> int:
	if i < directions.size():
		return int(directions[i])
	if event.direction == 0: # both ways: turn about
		return 1 if i % 2 == 0 else -1
	return event.direction


## The node that drives `r` (an AI racer, a dev player): the racing AI on circuits, the lane
## driver on highways.
func make_driver(r: Racer) -> Node:
	if highway:
		var d := HighwayDriver.new()
		d.racer = r
		return d
	var ai := RacingAI.new()
	ai.racer = r
	ai.skill = ai_skill
	return ai


## What a player's access assists follow (ACC-07): the racing line, or a highway's lanes.
func make_guide(r: Racer) -> Node:
	if highway:
		var d := HighwayDriver.new()
		d.racer = r
		d.as_guide = true
		return d
	var ai := RacingAI.new()
	ai.racer = r
	ai.as_guide = true
	return ai


## An online session's cars (D84): this game's players drive their own (their ids are Net.my_ids,
## in local order); everyone else's car is remote. Everyone's spot is their place in the roster.
func _ready_online() -> void:
	net = NetSession.new()
	net.name = "NetSession"
	net.session = self
	add_child(net)
	if highway:
		if Net.host_logic:
			Net.host_logic.board_requested.connect(_on_board_requested)
		Net.board_received.connect(_on_board_received)
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
	var spot := highway.spawn_for(index, direction_for(index)) if highway else track.transform_at(_grid_distance(index), _grid_lateral(index))
	if d.get("ai", false) and Net.is_server(): # the server's AI cars (D88)
		var a := AiRacer.new()
		a.configure(int(d.get("local", 0)), float(d.get("skill", ai_skill)))
		a.net_id = id
		a.spawn_at = spot
		_add_racer(a)
		var path := Net.host_logic.ai_path(id) if Net.host_logic else ""
		a.load_car(path if path else _default_car)
		net.add(a, true)
		safe_rejoin = true
		return a
	var local := Array(Net.my_ids).find(id)
	if local >= 0 and local < Players.slots.size() and not dedicated:
		var slot := Players.slots[local]
		if autodrive:
			slot.ai = true
		var p := _add_player(slot, spot)
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
	r.name = "Net%d" % id
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
			if race.kind in ["practice", "qualifying", "race"] and race.phase != RaceControl.Phase.DONE:
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


## The class's default car (built-in).
func default_car() -> String:
	return _default_car


func _add_racer(r: Racer) -> void:
	r.session = self
	r.track = track
	r.platform = platform
	r.default_car = _default_car
	if highway:
		r.limits = false
		r.wrong_way_respawn = false
		r.direction = direction_for(racers.size())
	racers.append(r)
	add_child(r)
	r.setup()
	if race.is_inside_tree():
		race.watch(r)


## An AI racer on the next grid spot, with a random car from `pool`.
func _add_ai(index: int, pool: PackedStringArray, skill: float) -> AiRacer:
	var a := AiRacer.new()
	a.configure(index, skill)
	var i := racers.size()
	a.spawn_at = track.transform_at(_grid_distance(i), _grid_lateral(i)) if _spot_clear(_grid_distance(i), _grid_lateral(i)) else _free_grid_spot()
	_add_racer(a)
	a.load_car(pool[randi() % pool.size()] if not pool.is_empty() else _default_car)
	return a


## Cars the AI can drive in this class: the garage's and the built-ins, or only the built-ins.
func ai_car_pool() -> PackedStringArray:
	var out := PackedStringArray()
	for path in PackageLoader.list_available():
		if ai_builtin_cars and not path.begins_with("res://"):
			continue
		if Fitting.compatible(platform.platform, PackageLoader.read_manifest(path).get("family", "")):
			out.append(path)
	return out


func _on_joined(slot: PlayerSlot) -> void:
	var p := _add_player(slot)
	apply_game_speed()
	p.hud.show_message("%s joined" % slot.tag(), 2.0)


func _on_left(slot: PlayerSlot) -> void:
	if views.view(slot) == null:
		return # not in this session (a solo drive)
	for p in players:
		if p.slot == slot:
			if paused_by == p:
				_resume()
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
	Engine.time_scale = speed
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
			return { "position": row.position, "name": row.name, "laps": row.laps, "dnf": row.dnf, "time": row.time, "best": row.best, "ai": not (row.racer as Racer).is_human }) }))
		get_tree().create_timer(DEDICATED_RESULTS_S).timeout.connect(func() -> void:
			if not is_inside_tree() or race.phase != RaceControl.Phase.DONE:
				return
			if race.has_next():
				_drop_leavers()
				race.next_session()
			elif Net.host_logic:
				Net.host_logic.end_session()
				Net.host_logic.next_event())
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
	results_menu.continued.connect(func() -> void:
		_close_results()
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
	# The main window shows views at their real pixel size; menus are laid out for 1080p.
	var layer: CanvasLayer = $ResultsLayer
	var window := get_viewport().get_visible_rect().size
	var s := window.y / 1080.0 * Players.menu_text_scale()
	layer.scale = Vector2(s, s)
	results_menu.size = window / s
	layer.add_child(results_menu)


## The results go (the server began the next session).
func close_results() -> void:
	_close_results()


func _on_board_received(board: String, entries: Array) -> void:
	server_boards[board] = entries


## Server: a client asked for one of this server's boards for this track.
func _on_board_requested(peer: int, board: String) -> void:
	var entries := Leaderboard.entries(track.record_key(), board, true).map(func(e: Dictionary) -> Dictionary:
		return { "name": e.get("name", ""), "car": e.get("car", ""), "time": e.get("time", 0.0), "score": e.get("score", 0) })
	if peer == 1:
		server_boards[board] = entries # the host's own players
	else:
		Net.server.send(peer, NetProtocol.Msg.BOARD, { "board": board, "entries": entries })


## A highway run is done: its results on the main window; Restart lines everyone up again.
func _on_run_done(rows: Array) -> void:
	if dedicated or Game.dev.has("quit-after-results"):
		print("Run results: %s" % ", ".join(PackedStringArray(rows.map(func(row: Dictionary) -> String: return "%d %s" % [row.position, row.name]))))
		if Game.dev.has("quit-after-results"):
			get_tree().quit()
		return
	results_menu = ResultsMenu.new()
	results_menu.kind = "race"
	results_menu.results = rows
	results_menu.mode = "local"
	results_menu.restarted.connect(func() -> void:
		_close_results()
		run.begin())
	results_menu.quit_to_title.connect(func() -> void: Game.go_title())
	var layer: CanvasLayer = $ResultsLayer
	var window := get_viewport().get_visible_rect().size
	var s := window.y / 1080.0 * Players.menu_text_scale()
	layer.scale = Vector2(s, s)
	results_menu.size = window / s
	layer.add_child(results_menu)


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
	menu.can_restart = race.kind in ["race", "practice", "qualifying"] and not race.mirror
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
	if time_trial:
		menu.ghost_items = time_trial.choices()
		menu.ghost_current = time_trial.choice
		menu.ghost_picked.connect(time_trial.pick)
		menu.leaderboard = Leaderboard.entries(track.record_key(), platform.platform.id)
		menu.leaderboard_title = "%s · %s" % [track.display_name, platform.platform.name]
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
	if highway:
		menu.extra_items = highway.pause_items(p).map(func(item: Array) -> Array:
			return [item[0], func() -> void:
				_resume(p)
				item[1].call(), item[2]])
	menu.back_to_bay.connect(func() -> void: Game.open_fitting_bay())
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
