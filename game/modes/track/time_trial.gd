class_name TimeTrial
extends Node
## Time trial (docs/GAMEMODES.md §1, MODE-02): every local player laps against their own ghost,
## the others' cars ghosted too (RaceEvent.time_trial() has no collisions). Each player has a lane
## (TimeTrial.Lane): every lap of theirs is recorded; a new best valid lap becomes their ghost, is
## saved in user://ghosts/<track>/<class>/best_<profile>.json and goes on the local leaderboard
## (online, the server's: TimeTrialNet).
## Ghost files from friends dropped in that folder (and the other players' bests) can be picked
## from each player's pause menu. The live delta is measured against the player's ghost. Each
## lane's ghost sits on a visual layer of its own that only its player's camera draws.

## Where ghosts are kept (tests point it elsewhere).
static var dir := "user://ghosts/"
## Visual layers 2-5 hold the lanes' ghosts, one each.
const FIRST_LAYER := 2

var session: TrackSession
## One per player, in the order they came.
var lanes: Array[Lane] = []


func _ready() -> void:
	session.race.session_started.connect(func(_kind: String) -> void:
		for lane in lanes:
			lane.watch())
	for p in session.players:
		add(p)


## A lane for `p`: at the start, and for a player who drops in.
func add(p: SessionPlayer) -> Lane:
	var lane := Lane.new()
	lane.name = "Lane%d" % p.number
	lane.trial = self
	lane.player = p
	lane.layer = _free_layer()
	lane.keeps_old_best = p.slot.index == 0
	lanes.append(lane)
	add_child(lane)
	return lane


## `p` left: their lane and its ghost go.
func remove(p: SessionPlayer) -> void:
	var lane := lane_of(p)
	if lane:
		lanes.erase(lane)
		lane.close()


func lane_of(p: SessionPlayer) -> Lane:
	for lane in lanes:
		if lane.player == p:
			return lane
	return null


## The first ghost layer no lane has (0-3).
func _free_layer() -> int:
	var used := lanes.map(func(l: Lane) -> int: return l.layer)
	for i in Players.MAX:
		if i not in used:
			return i
	return 0


## Camera mask for the lane on ghost layer `layer`: its own ghost, not the others'.
static func cull_mask_for(layer: int, mask: int) -> int:
	for i in Players.MAX:
		var bit := 1 << (FIRST_LAYER - 1 + i)
		mask = (mask | bit) if i == layer else (mask & ~bit)
	return mask


## The ghost's lap time at every LapTimer.TRACE_M along `t`, for the live delta.
static func trace_of(t: TrackData, g: Ghost) -> PackedFloat32Array:
	var trace := PackedFloat32Array([0.0])
	var hint := -1
	var prev_d := -1.0
	var prev_t := 0.0
	for k in g.sample_count():
		var s := g.data[k * Ghost.STRIDE]
		var pos := Vector3(g.data[k * Ghost.STRIDE + 1], g.data[k * Ghost.STRIDE + 2], g.data[k * Ghost.STRIDE + 3])
		var proj := t.project(pos, hint)
		hint = proj.index
		var d := t.from_start(proj.distance)
		if prev_d >= 0.0 and d > prev_d and d - prev_d < 50.0:
			var mark := trace.size() * LapTimer.TRACE_M
			while mark <= d and mark < t.length:
				trace.append(lerpf(prev_t, s, (mark - prev_d) / (d - prev_d)))
				mark = trace.size() * LapTimer.TRACE_M
		prev_d = d
		prev_t = s
	trace.append(float(g.meta.get("time", g.duration())))
	return trace


## One player's time trial: their laps recorded, their best kept, their ghost on track.
class Lane:
	extends Node

	var trial: TimeTrial
	var player: SessionPlayer
	## Which ghost layer this lane has (0-3, TimeTrial.FIRST_LAYER on).
	var layer := 0
	## P1's lane (when it was made): the best.json from before splitscreen time trials is theirs.
	var keeps_old_best := false
	## The lap being recorded now.
	var recording := Ghost.new()
	## The ghost on track, and which it is: "best", a file name in the folder, or "off".
	var ghost: Ghost
	var choice := "best"
	var car: GhostCar

	var _timer: LapTimer
	var _tick := 0


	func _ready() -> void:
		process_physics_priority = -40 # after the RaceField has moved the lap clock on
		var camera := player.cameras.camera
		camera.cull_mask = TimeTrial.cull_mask_for(layer, camera.cull_mask)
		watch()
		pick("best")


	## The ghosts of this track and the player's class (a kart player's own, D149).
	func folder() -> String:
		return TimeTrial.dir.path_join(trial.session.track.record_key()).path_join(player.platform.platform.id)


	## Where the player's best is saved: best_<profile>.json.
	func best_path() -> String:
		return folder().path_join("best_%s.json" % player.slot.profile.id)


	## The player's best: their own file, or for P1 the best.json from before splitscreen time
	## trials.
	func best() -> Ghost:
		var g := Ghost.load_file(best_path())
		if g == null and keeps_old_best:
			g = Ghost.load_file(folder().path_join("best.json"))
		return g


	## Ghosts to race: [[id, label]], the player's best first, then the folder's other files (the
	## other players' bests among them), then Off.
	func choices() -> Array:
		var out := [["best", "Your best"]]
		if DirAccess.dir_exists_absolute(folder()):
			for file in DirAccess.get_files_at(folder()):
				if not file.ends_with(".json") or file == best_path().get_file() or (file == "best.json" and keeps_old_best):
					continue
				var g := Ghost.load_file(folder().path_join(file))
				if g:
					out.append([file, "%s %s" % [String(g.meta.get("driver", file.get_basename())), Hud.format_time(float(g.meta.get("time", g.duration())))]])
		out.append(["off", "Off"])
		return out


	## Shows another ghost ("best", a file in the folder, or "off").
	func pick(id: String) -> void:
		choice = id
		var g: Ghost = null
		if id == "best":
			g = best()
		elif id != "off":
			g = Ghost.load_file(folder().path_join(id))
		_show(g)


	## Follows the player's timer (a new one each session).
	func watch() -> void:
		if _timer:
			_timer.lap_started.disconnect(_on_lap_started)
			_timer.lap_completed.disconnect(_on_lap)
		_timer = player.timer
		_timer.lap_started.connect(_on_lap_started)
		_timer.lap_completed.connect(_on_lap)
		if ghost:
			_timer.set_reference(TimeTrial.trace_of(trial.session.track, ghost), float(ghost.meta.get("time", ghost.duration())))


	## The player left: the ghost goes with the lane.
	func close() -> void:
		if car:
			car.queue_free()
			car = null
		ghost = null
		queue_free()


	func _physics_process(_delta: float) -> void:
		if player.vehicle == null or _timer.lap == 0:
			return
		_tick += 1
		if _tick % int(Engine.physics_ticks_per_second / Ghost.RATE) == 0:
			var v := player.vehicle
			recording.record(_timer.lap_time, v.global_transform, v.linear_velocity, v.steer)


	func _process(delta: float) -> void:
		if car:
			car.show_at(_timer.lap_time if _timer.lap > 0 else -1.0, delta)
			# Dev: --log-ghost prints how far the ghost is from the car every 5 s of lap time.
			if Game.dev.has("log-ghost") and car.visible and player.vehicle and int(_timer.lap_time / 5.0) != int((_timer.lap_time - delta) / 5.0):
				print("%s ghost lap %d t %.1f gap %.2f m" % [player.slot.tag(), _timer.lap, _timer.lap_time, car.global_position.distance_to(player.vehicle.global_position)])


	func _on_lap_started(_lap: int) -> void:
		recording = Ghost.new()
		if player.vehicle:
			var v := player.vehicle
			recording.record(_timer.lap_time, v.global_transform, v.linear_velocity, v.steer)


	func _on_lap(time: float, valid: bool, _best: bool) -> void:
		var g := recording
		recording = Ghost.new()
		if not valid or player.vehicle == null or g.sample_count() < 2:
			return
		var v := player.vehicle
		g.meta = {
			"time": time, "driver": player.display_name, "car_path": v.package.path, "car_hash": v.package.hash,
			"car": v.package.display_name(), "platform": v.base_platform.get("id", ""), "platform_hash": v.platform_hash,
			"track": trial.session.track.id, "version": ProjectSettings.get_setting("application/config/version"),
			"assists": PackedStringArray(player.assists_used.keys().filter(func(k: String) -> bool: return player.assists_used[k])),
			"setup": player.custom_setup, "game_speed": Engine.time_scale, "date": Time.get_datetime_string_from_system(),
			"road": Leaderboard.road_of(v),
		}
		var saved := best()
		if saved == null or time < float(saved.meta.get("time", INF)):
			g.save(best_path())
			if choice == "best":
				_show(g)
		var entry := {
			"name": player.display_name, "time": time, "car": g.meta.car, "platform": g.meta.platform,
			"platform_hash": g.meta.platform_hash, "version": g.meta.version, "assists": Array(g.meta.assists),
			"setup": g.meta.setup, "game_speed": g.meta.game_speed, "date": g.meta.date, "road": g.meta.road,
		}
		if trial.session.is_online():
			return # online the server times the laps and keeps the board (TimeTrialNet)
		var place := Leaderboard.submit(trial.session.track.record_key(), entry)
		if place > 0:
			player.notify("%s  ·  Board P%d" % [Hud.format_time(time), place], 3.0)


	## Puts `g` on track (null: none), in the car it was driven in (or the class's default car),
	## on this lane's layer.
	func _show(g: Ghost) -> void:
		ghost = g
		if car:
			car.queue_free()
			car = null
		if g == null:
			_timer.set_reference(PackedFloat32Array(), -1.0)
			return
		_timer.set_reference(TimeTrial.trace_of(trial.session.track, g), float(g.meta.get("time", g.duration())))
		var platform := player.platform.platform
		var path := String(g.meta.get("car_path", ""))
		if path.is_empty() or not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
			path = GameModes.default_car(platform)
		PackageLoader.load_shared(path, func(pkg: VehiclePackage) -> void:
			if not is_inside_tree() or ghost != g or not pkg.ok():
				pkg.free_scenes()
				return
			car = GhostCar.create(g, platform, pkg, 1 << (TimeTrial.FIRST_LAYER - 1 + layer))
			trial.session.add_child(car))
