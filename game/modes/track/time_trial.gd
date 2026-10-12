class_name TimeTrial
extends Node
## Time trial (docs/GAMEMODES.md §1, MODE-02): P1 laps alone against a ghost. Every lap is
## recorded; a new best valid lap becomes the ghost, is saved in
## user://ghosts/<track>/<platform>/best.json and goes on the local leaderboard. Ghost files
## from friends dropped in that folder can be picked from the pause menu. The live delta is
## measured against the ghost.

## Where ghosts are kept (tests point it elsewhere).
static var dir := "user://ghosts/"

var session: TrackSession
var player: SessionPlayer
## The lap being recorded now.
var recording := Ghost.new()
## The ghost on track, and which it is: "best", a file name in the folder, or "off".
var ghost: Ghost
var choice := "best"
var car: GhostCar

var _timer: LapTimer
var _tick := 0
var _loading := ""


func _ready() -> void:
	process_physics_priority = -40 # after the RaceField has moved the lap clock on
	player = session.players[0]
	session.race.session_started.connect(func(_kind: String) -> void: _watch())
	_watch()
	pick("best")


func folder() -> String:
	return dir.path_join(session.track.record_key()).path_join(session.platform.platform.id)


func best_path() -> String:
	return folder().path_join("best.json")


## Ghosts to race: [[id, label]], the player's best first, then files from the folder, then Off.
func choices() -> Array:
	var out := [["best", "Your best"]]
	if DirAccess.dir_exists_absolute(folder()):
		for file in DirAccess.get_files_at(folder()):
			if file.ends_with(".json") and file != "best.json":
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
		g = Ghost.load_file(best_path())
	elif id != "off":
		g = Ghost.load_file(folder().path_join(id))
	_show(g)


func _watch() -> void:
	if _timer:
		_timer.lap_started.disconnect(_on_lap_started)
		_timer.lap_completed.disconnect(_on_lap)
	_timer = player.timer
	_timer.lap_started.connect(_on_lap_started)
	_timer.lap_completed.connect(_on_lap)
	if ghost:
		_timer.set_reference(_trace_of(ghost), float(ghost.meta.get("time", ghost.duration())))


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
			print("ghost lap %d t %.1f gap %.2f m" % [_timer.lap, _timer.lap_time, car.global_position.distance_to(player.vehicle.global_position)])


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
		"track": session.track.id, "version": ProjectSettings.get_setting("application/config/version"),
		"assists": PackedStringArray(player.assists_used.keys().filter(func(k: String) -> bool: return player.assists_used[k])),
		"setup": player.custom_setup, "game_speed": Engine.time_scale, "date": Time.get_datetime_string_from_system(),
	}
	var saved := Ghost.load_file(best_path())
	if saved == null or time < float(saved.meta.get("time", INF)):
		g.save(best_path())
		if choice == "best":
			_show(g)
	var entry := {
		"name": player.display_name, "time": time, "car": g.meta.car, "platform": g.meta.platform,
		"platform_hash": g.meta.platform_hash, "version": g.meta.version, "assists": Array(g.meta.assists),
		"setup": g.meta.setup, "game_speed": g.meta.game_speed, "date": g.meta.date,
	}
	var place := Leaderboard.submit(session.track.record_key(), entry)
	if place > 0:
		player.notify("%s  ·  Board P%d" % [Hud.format_time(time), place], 3.0)


## Puts `g` on track (null: none), in the car it was driven in (or the class's default car).
func _show(g: Ghost) -> void:
	ghost = g
	if car:
		car.queue_free()
		car = null
	if g == null:
		_timer.set_reference(PackedFloat32Array(), -1.0)
		return
	_timer.set_reference(_trace_of(g), float(g.meta.get("time", g.duration())))
	var path := String(g.meta.get("car_path", ""))
	if path.is_empty() or not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
		path = session.default_car()
	_loading = path
	PackageLoader.load_shared(path, func(pkg: VehiclePackage) -> void:
		if not is_inside_tree() or ghost != g or not pkg.ok():
			pkg.free_scenes()
			return
		car = GhostCar.create(g, session.platform.platform, pkg)
		session.add_child(car))


## The ghost's lap time at every LapTimer.TRACE_M along the track, for the live delta.
func _trace_of(g: Ghost) -> PackedFloat32Array:
	var t := session.track
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
