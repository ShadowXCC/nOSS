class_name HighwayControl
extends Node
## A highway session's rules (docs/GAMEMODES.md §3, D113): where players start and reset (on the
## outer shoulder of their carriageway, at rest; traffic never uses the shoulder), changing
## direction, and the sub-mode (cruise; score attack, loop laps and runs build on this).

## Players start this far behind the lap line, this far apart.
const START_BACK_M := 40.0
const START_GAP_M := 30.0
## Join friend: at most this many in the pause menu, and this far behind them.
const JOIN_MAX := 6
const JOIN_BEHIND_M := 60.0

var session: TrackSession
var _timed := {} # racers whose loop laps go on a board
var layout: HighwayLayout
var event: RaceEvent


func _ready() -> void:
	process_physics_priority = -56


func _physics_process(_delta: float) -> void:
	if Engine.get_physics_frames() % 60 == 0:
		_ready_plates() # players join; their HUDs come with them
	if session.run and session.run.state.is_empty() and not session.players.is_empty() \
			and session.players.all(func(p: SessionPlayer) -> bool: return p.vehicle != null):
		session.run.begin() # everyone's here: line up
	for r in session.racers:
		if event.sub == "loop" and r is SessionPlayer and r.timer and not _timed.has(r):
			_timed[r] = true
			r.timer.lap_completed.connect(_on_lap.bind(r))
		if r.vehicle == null or r.waiting or not is_instance_valid(r.vehicle) or r.vehicle.remote:
			continue
		var at: Dictionary = session.highway_field.at(r)
		if at.is_empty() or not at.on_road or int(at.road) < 0:
			continue
		var ramp := layout.ramps[int(at.road)]
		var d := float(at.distance)
		# Into a portal: out of the next entry on that carriageway, at the same speed.
		if ramp.to.has("portal") and d > ramp.track.length - 6.0:
			_through_portal(r, ramp)


## `r` drove into `exit`'s portal: it comes out of the first entry ramp ahead of where it left,
## on the same carriageway, at its speed.
func _through_portal(r: Racer, exit: RampData) -> void:
	var dir := int(exit.from.get("dir", r.direction))
	var left := float(exit.from.get("at_m", 0.0))
	var best: RampData = null
	var best_d := INF
	for ramp in layout.ramps:
		if not ramp.from.has("portal") or not ramp.to.has("dir") or int(ramp.to.dir) != dir:
			continue
		var ahead := layout.along(dir, float(ramp.to.at_m)) - layout.along(dir, left)
		ahead = fposmod(ahead, layout.main.length)
		if ahead < best_d:
			best_d = ahead
			best = ramp
	if best == null:
		reset(r)
		return
	var t := best.track
	var k := mini(6, t.samples.size() - 1)
	var at := Transform3D(Basis(t.lefts[k], t.ups[k], t.tangents[k]), t.samples[k])
	var speed := maxf(r.vehicle.speed(), 8.0)
	r.vehicle.reset_to(at, t.tangents[k] * speed)
	r.timer.invalidate("Off the road")
	r.notify(String(layout.portals[best.from.portal].name), 1.5)


## A loop lap done: on its direction's board (local games; a lap with a direction change, a
## reset or a portal is no lap).
func _on_lap(time: float, valid: bool, _best: bool, r: Racer) -> void:
	if not valid or session.is_online() or not (r is SessionPlayer):
		return
	var place := Leaderboard.submit(session.track.record_key(), Leaderboard.entry_of(r, { "time": time }), board(r as SessionPlayer))
	if place == 1:
		r.notify("Best lap %s" % _way(r.direction).to_lower(), 2.5)


## Player `p`'s leaderboard in this event ("" if none): score attack's, the run's, or the loop's
## for the way they're going.
func board(p: SessionPlayer) -> String:
	match event.sub:
		"score":
			return session.platform_id + "|score"
		"run":
			return "%s|run:%s" % [session.platform_id, session.run.run.id] if session.run else ""
		"loop":
			return "%s|loop%+d" % [session.platform_id, p.direction]
	return ""


## What `board(p)` is, in words.
func board_name(p: SessionPlayer) -> String:
	match event.sub:
		"score":
			return "Score attack"
		"run":
			return String(session.run.run.name) if session.run else "Run"
	return "Laps, " + _way(p.direction).to_lower()


func _way(dir: int) -> String:
	return "Clockwise" if layout.clockwise(dir) else "Anticlockwise"


## Player `i`'s start: on the shoulder of direction `dir`'s carriageway behind the lap line, in
## single file START_GAP_M apart, the file passing any ramp's mouth (no two on one spot).
func spawn_for(i: int, dir: int) -> Transform3D:
	var length := layout.main.length
	var d := layout.main.start_m - dir * START_BACK_M
	var found := -1
	for step in ceili(length / 5.0):
		if _in_mouth(d, dir):
			d -= dir * 5.0
			continue
		found += 1
		if found == i:
			break
		d -= dir * START_GAP_M
	return shoulder_spot(dir, fposmod(d, length))


## True if a car on direction `dir`'s shoulder at `d` would be in a ramp's mouth.
func _in_mouth(d: float, dir: int) -> bool:
	for off: float in [-6.0, 0.0, 6.0]:
		if layout.gap(layout.main.index_at(fposmod(d + off, layout.main.length)), -float(dir)):
			return true
	return false


## On direction `dir`'s outer shoulder at main-road distance `d`, facing the way it drives.
func shoulder_spot(dir: int, d: float) -> Transform3D:
	var shoulder := float(layout.settings.shoulder_out_m)
	var lat := -dir * (layout.inner + layout.lanes * layout.lane_m + shoulder / 2.0)
	var k := layout.main.index_at(d)
	# Not in a ramp's mouth (the shoulder is part of the taper there): a little further on.
	for step in 40:
		if not layout.gap(k, -float(dir)):
			break
		d = fposmod(d + dir * 10.0, layout.main.length)
		k = layout.main.index_at(d)
	var t := layout.main.transform_at(d, lat)
	if dir < 0:
		t.basis = Basis(-t.basis.x, t.basis.y, -t.basis.z)
	return t


## A reset (the player's, or after falling off): at rest on the shoulder of the carriageway it
## was on, beside where it was.
func reset(r: Racer) -> void:
	_place(r, r.direction)
	r.notify("Reset", 1.5)


## Back on the other carriageway, going the other way.
func change_direction(r: Racer) -> void:
	_place(r, -r.direction)
	r.notify("Turned round", 1.5)


func _place(r: Racer, dir: int) -> void:
	if r.vehicle == null:
		return
	r.timer.invalidate("Reset")
	r.direction = dir
	var at := shoulder_spot(dir, r.distance)
	r.vehicle.reset_to(at)
	var proj := layout.main.project(at.origin)
	r.distance = proj.distance
	r.lateral = proj.lateral
	r.track_index = -1
	r.timer.teleported(r.lap_pos(r.distance))


## Pause menu items for player `p`: [[text, callable, description]].
func pause_items(p: SessionPlayer) -> Array:
	var items := [["Change direction", func() -> void: change_direction(p), "Turn round onto the other carriageway"]]
	if event.sub != "run":
		var others := session.racers.filter(func(r: Racer) -> bool: return r != p and (r.is_human or r is SessionPlayer) and r.vehicle != null)
		others.sort_custom(func(a: Racer, b: Racer) -> bool: return a.display_name < b.display_name)
		for r: Racer in others.slice(0, JOIN_MAX):
			items.append(["Join %s" % r.display_name, func() -> void: join(p, r), "Start behind them, their way round"])
	return items


## Puts `p` at rest on `friend`'s carriageway's shoulder JOIN_BEHIND_M behind them.
func join(p: Racer, friend: Racer) -> void:
	if p.vehicle == null or friend.vehicle == null:
		return
	var dir := friend.direction
	p.timer.invalidate("Joined")
	p.direction = dir
	var at := shoulder_spot(dir, fposmod(friend.distance - dir * JOIN_BEHIND_M, layout.main.length))
	p.vehicle.reset_to(at)
	var proj := layout.main.project(at.origin)
	p.distance = proj.distance
	p.lateral = proj.lateral
	p.track_index = -1
	p.timer.teleported(p.lap_pos(p.distance))
	p.notify("Behind %s" % friend.display_name, 2.0)


## Name plates over the other players' cars on each of this game's players' HUDs.
func _ready_plates() -> void:
	for pl in session.players:
		if pl.hud and pl.hud.get_node_or_null(^"Nameplates") == null:
			var plates := Nameplates.new()
			plates.name = "Nameplates"
			plates.session = session
			plates.player = pl
			pl.hud.add_child(plates)
