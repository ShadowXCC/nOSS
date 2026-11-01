class_name HighwayDriver
extends Node
## Drives a car along a highway's lanes (D113): players' autodrive and lane assists
## (docs/ACCESSIBILITY.md §5: on highways they follow the lanes), dev players and bots, and police
## on patrol. It keeps its lane at up to the lane's limit, following what's ahead; the native lane
## driver (NossTraffic.follow) works out steering and pedals. Held up behind something slower it
## moves to a lane beside with room (the inner one first), and after a while with a clear road it
## moves back out: it keeps to the outside. Stuck (wanting to go but not moving, or lost off the
## lanes) or on its side or roof for a while, it resets (to the shoulder). With `lateral` set
## (police after a target, D201; dev --flat-out) it goes at its own speed instead of the lane's:
## up to `want_speed`, as fast as the bends ahead allow taking `lateral` sideways and braking at
## it, on pedals of its own; the lane driver then only steers and says what's ahead. A roadblock
## ahead (D248): with every lane closed it gets by on the shoulder; held up in the queue for one,
## down the middle of an open lane (or the shoulder) past cars only nosing into it, another way if
## that one stays blocked; then back into the lanes.

## Held up this long: over a lane; not again for this long; back out after this long clear.
const OVERTAKE_AFTER_S := 1.5
const CHANGE_AGAIN_S := 4.0
const KEEP_OUT_S := 8.0
## Something slower within this far ahead holds it up (the IDM eases off from well back).
const HELD_GAP_M := 120.0
## Room a lane beside needs: this far ahead, this far behind (m).
const ROOM_AHEAD_M := 40.0
const ROOM_BEHIND_M := 15.0
## A lane closed (a roadblock, a wreck) within this far ahead is no lane to move into (m); its
## own lane closed within it, the car heads for an open one a lane at a time, this often (s).
const CLOSED_AHEAD_M := 300.0
const ESCAPE_AGAIN_S := 1.5
## Stuck this long, or on its side or roof this long (s): reset.
const STUCK_S := 6.0
const UPSET_S := 3.0
## Its own speed: behind what's ahead by this gap plus this many seconds of the lead's speed; the
## lane graph's own bend budget (m/s^2, native lane_graph.h), which a ramp's limits are made with.
const OWN_GAP_M := 6.0
const OWN_GAP_S := 0.8
const LANE_LATERAL := 2.5
## Dev --flat-out: a player's autodrive at this share of its tyres' grip, with no limit.
const FLAT_OUT_GRIP := 0.85
## A roadblock ahead (D248) with every lane closed, this far ahead or held up in the queue for it
## (as far back as SHOULDER_QUEUE_M; not the police); with a lane open, held up this far short of
## it: over to its way through (the shoulder, or an open lane's middle), at most this fast, behind
## anything there that a car this wide would touch, steering at a point at least this far on.
const SHOULDER_REACH_M := 220.0
const SHOULDER_QUEUE_M := 900.0
const QUEUE_REACH_M := 160.0
const SHOULDER_MPS := 20.0
const THROUGH_HALF_M := 1.0
const SHOULDER_LOOK_M := 14.0
## Going by: a way is clear with nothing on it this far ahead; blocked this long, it tries another,
## and with none, further than THROUGH_GIVE_UP_M from the block (a unit parked on the shoulder),
## it goes back to the lanes for THROUGH_AGAIN_S.
const THROUGH_CLEAR_M := 30.0
const THROUGH_BLOCKED_S := 2.0
const THROUGH_GIVE_UP_M := 90.0
const THROUGH_AGAIN_S := 4.0

var racer: Racer
## Changes lanes to get by (autodrive, bots, police); a guide never does (the player steers).
var overtakes := true
## Works out controls for a player's access assists instead of driving (VehicleController blends
## them with the player's).
var as_guide := false
## Of the lane's limit.
var speed_factor := 1.0
## Its own speed: sideways and braking acceleration it plans with on a dry road (m/s^2; 0: off,
## the lane's limit), and the most it goes (m/s).
var lateral := 0.0
var want_speed := INF
## Over a lane when held up this long, not again for this long; back out once clear (keep_out).
var overtake_after_s := OVERTAKE_AFTER_S
var change_again_s := CHANGE_AGAIN_S
var keep_out := true
## Resets so far (checks).
var resets := 0
## The lane followed (the lane graph's index) and where along it, m; -1 until found.
var lane := -1
var _s := -1.0
var _lost := 0.0
var _held := 0.0
var _clear := 0.0
var _clock := 0.0
var _changed_at := -INF
var _stuck := 0.0
var _upset := 0.0
var _going_through := false # off its lane, by a roadblock (D248)
var _through_at := NAN # that roadblock's line, and the way by it taken (a lateral)
var _through_lat := NAN
var _blocked := 0.0
var _through_again := 0 # the physics tick from when it may go by again
var _gap := INF # the lane driver's last word on what's ahead: gap (m), its speed, and the tick
var _lead_v := 0.0
var _gap_tick := -1


func _ready() -> void:
	process_physics_priority = -50 # after the fields, before the vehicles
	if racer is SessionPlayer and Game.dev.has("speed-factor"):
		speed_factor = clampf(float(Game.dev["speed-factor"]), 0.5, 2.0) # dev: autodrive past the limit (police checks)
	if as_guide or racer.vehicle == null:
		return
	# The assists a player can use on this platform (AI-05: no other help).
	var allowed: Array = racer.vehicle.platform.get("assists_allowed", [])
	var assists := {}
	for a in ["abs", "tcs", "stability", "auto_gearbox"]:
		assists[a] = a in allowed
	assists.auto_clutch = true
	racer.vehicle.sim.set_assists(assists)
	if racer is SessionPlayer and Game.dev.has("flat-out"):
		flat_out()


## As fast as it can (dev --flat-out, checks: a player driving flat out): no limit, and bends at
## FLAT_OUT_GRIP of its tyres' grip.
func flat_out() -> void:
	lateral = FLAT_OUT_GRIP * float(racer.vehicle.platform.get("tires", {}).get("mu_peak", 1.2)) * 9.81
	want_speed = INF


func _physics_process(delta: float) -> void:
	if as_guide:
		return
	var c := controls(delta)
	if c.is_empty():
		return
	if _trouble(c, delta):
		racer.reset_car()
		lane = -1
		resets += 1
		return
	var v := racer.vehicle
	v.steer = c.steer
	v.throttle = c.throttle
	v.brake = c.brake
	v.handbrake = c.handbrake


## This tick's controls: {steer, throttle, brake, handbrake}, or {} without a car or traffic.
func controls(delta: float) -> Dictionary:
	var v := racer.vehicle
	var tm := racer.session.traffic
	if v == null or not is_instance_valid(v) or tm == null or tm.sim == null:
		return {}
	if racer.held or racer.waiting:
		return { "steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": 1.0 }
	var pos := v.global_position
	var through := _way_through()
	if _going_through and (through.is_empty() or float(through.at_m) != _through_at):
		_back_to_lanes(tm) # past it, or reset somewhere new
	if not through.is_empty() and (_going_through or Engine.get_physics_frames() >= _through_again):
		# Held up in a queue (not the police: they'd crowd the shoulder behind their target).
		var queued := not racer is PoliceRacer and _gap_tick >= Engine.get_physics_frames() - 1 and _gap < 25.0 and _lead_v < 2.0 and absf(v.speed()) < 4.0
		var to_go := float(through.to_go)
		if _going_through or (not bool(through.open) and (to_go < SHOULDER_REACH_M or queued)) or (queued and to_go < QUEUE_REACH_M):
			var c := _through_block(tm, through, delta)
			if not c.is_empty():
				return c
	if lane < 0:
		var found := tm.sim.locate(pos + Vector3.UP * 0.5)
		lane = int(found.lane)
		_s = float(found.get("s", -1.0))
		if lane < 0:
			return { "steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": 0.0 }
	var p := v.platform
	var e := v.fitted.envelope
	var own := lateral > 0.0
	var limit := minf(want_speed, _bend_cap(tm, v)) if own else tm.sim.lane_limit(lane, maxf(_s, 0.0)) * speed_factor
	if racer.pace_limit > 0.0:
		limit = minf(limit, racer.pace_limit) # a run's rolling start
	var out := tm.sim.follow(lane, _s, limit, tm.member_id(racer), pos, v.global_basis.z, v.speed(),
		float(p.geometry.wheelbase_m.ref), deg_to_rad(float(p.steering.max_road_angle_deg)), Vector2(e.size.z / 2.0, e.size.x / 2.0), _members(tm))
	_s = out[5]
	_gap = out[10]
	_lead_v = out[11]
	_gap_tick = Engine.get_physics_frames()
	if overtakes and not as_guide:
		_overtake(delta, float(out[10]), float(out[11]), limit)
	# Off the end of a ramp, or far from the lane: find the lane it's on now.
	var info := tm.sim.lane_info(lane)
	if absf(out[6]) > 6.0 or (not bool(info.closed) and _s > float(info.length) - 2.0):
		_lost += delta
		if _lost > 0.3:
			lane = -1
			_lost = 0.0
	else:
		_lost = 0.0
	if own:
		var c := _own_pedals(limit, float(out[10]), float(out[11]), v.speed(), lateral * _grip(v))
		c.steer = out[0]
		return c
	return { "steer": out[0], "throttle": out[1], "brake": out[2], "handbrake": out[3] }


## A roadblock coming up (PoliceControl.way_through), or {}: not for a guide, which only helps.
func _way_through() -> Dictionary:
	var police: PoliceControl = racer.session.police
	if as_guide or police == null or racer is PoliceRacer and (racer as PoliceRacer).waiting:
		return {}
	return police.way_through(racer, SHOULDER_QUEUE_M)


## By a roadblock: along a way by it (the shoulder, or an open lane's middle; another once this
## one's been blocked THROUGH_BLOCKED_S) at up to SHOULDER_MPS, behind anything a car there would
## touch; steered by pure pursuit along the main road. {} once it gives up (back to the lanes).
func _through_block(tm: TrafficManager, through: Dictionary, delta: float) -> Dictionary:
	var v := racer.vehicle
	if not _going_through:
		_going_through = true
		_through_at = float(through.at_m)
		_through_lat = float(through.lat)
		_blocked = 0.0
	var main := racer.session.track
	var proj := { "distance": racer.distance, "lateral": racer.lateral } # kept by the racer (a full project() costs)
	var speed := v.speed()
	var ahead := _line_ahead(tm, proj, _through_lat)
	_blocked = _blocked + delta if ahead.x < THROUGH_CLEAR_M and absf(speed) < 1.0 else 0.0
	if _blocked > THROUGH_BLOCKED_S:
		_blocked = 0.0
		var moved := false
		for other: float in through.lats:
			if other != _through_lat and _line_ahead(tm, proj, other).x >= THROUGH_CLEAR_M:
				_through_lat = other
				ahead = _line_ahead(tm, proj, other)
				moved = true
				break
		if not moved and float(through.to_go) > THROUGH_GIVE_UP_M:
			_back_to_lanes(tm)
			_through_again = Engine.get_physics_frames() + int(THROUGH_AGAIN_S * Engine.physics_ticks_per_second)
			return {}
	var lat := _through_lat
	var way := (racer as Racer).direction if racer.session.track.highway else 1
	var aim := main.transform_at(float(proj.distance) + way * maxf(SHOULDER_LOOK_M, speed * 0.8), lat).origin
	var local := v.global_basis.inverse() * (aim - v.global_position)
	var look := maxf(Vector2(local.x, local.z).length(), 1.0)
	var alpha := atan2(local.x, maxf(local.z, 0.5))
	var p := v.platform
	var wheelbase := float(p.geometry.wheelbase_m.ref)
	var max_steer := deg_to_rad(float(p.steering.max_road_angle_deg))
	var steer := clampf(-atan(2.0 * wheelbase * sin(alpha) / look) / max_steer, -1.0, 1.0)
	var c := _own_pedals(minf(SHOULDER_MPS, want_speed), ahead.x, ahead.y, speed, 4.0 * _grip(v))
	c.steer = steer
	return c


## What's on the line at lateral `lat` ahead that a car going down it would touch: Vector2(gap m,
## its speed), INF without: traffic and every other car.
func _line_ahead(tm: TrafficManager, proj: Dictionary, lat: float) -> Vector2:
	var v := racer.vehicle
	var way := (racer as Racer).direction if racer.session.track.highway else 1
	var speed := v.speed()
	var gap := INF
	var lead_v := 0.0
	var my_lat := float(proj.lateral)
	var reach := v.fitted.envelope.size.x / 2.0 + THROUGH_HALF_M + 0.15 if v.fitted else THROUGH_HALF_M * 2.0 + 0.15
	for row: Array in tm.near_rows(v, 80.0):
		var along: float = row[2]
		if along > 0.0 and absf(my_lat + float(row[3]) * way - lat) < reach and along - float(row[5]) < gap:
			gap = along - float(row[5])
			lead_v = speed - float(row[4])
	for r in racer.session.racers:
		if r == racer or r.vehicle == null or not is_instance_valid(r.vehicle) or r.waiting:
			continue
		var d := r.vehicle.global_position - v.global_position
		var along := d.dot(v.global_basis.z)
		if along > 0.0 and along < 80.0 and absf(r.lateral - lat) < reach and along - 5.0 < gap:
			gap = along - 5.0
			lead_v = r.vehicle.speed()
	return Vector2(gap, lead_v)


## Past the block: its lane found again where it is (off the lanes, the outer one).
func _back_to_lanes(tm: TrafficManager) -> void:
	_going_through = false
	_through_at = NAN
	var layout: HighwayLayout = racer.session.track.highway
	if layout == null:
		lane = -1
		return
	var way := (racer as Racer).direction
	var d := racer.distance
	var lat := racer.lateral
	if absf(lat) > layout.inner + layout.lanes * layout.lane_m:
		lat = layout.lane_lateral(way, 0)
	var found := tm.sim.locate(layout.main.transform_at(d, lat).origin + Vector3.UP * 0.5)
	lane = int(found.lane)
	_s = float(found.get("s", -1.0))


## The cars the lane driver follows and keeps clear of (TrafficManager.members()).
func _members(tm: TrafficManager) -> PackedFloat32Array:
	return tm.members()


## Its own speed: the most the bends ahead allow, taking `lateral` sideways and braking at it
## (less on a wet or snowy road). The main road by its bend room; a ramp by its own limits, scaled
## from the lane graph's budget.
func _bend_cap(tm: TrafficManager, v: Vehicle) -> float:
	var a := lateral * _grip(v)
	var info := tm.sim.lane_info(lane)
	var layout: HighwayLayout = racer.session.track.highway if racer.session.track else null
	if layout == null or int(info.get("road", -1)) >= 0:
		return tm.sim.lane_limit(lane, maxf(_s, 0.0)) * sqrt(a / LANE_LATERAL)
	return sqrt(a * layout.bend_room(int(info.dir))[layout.main.index_at(racer.distance)])


## Its own pedals: up to `want` m/s, slowing in time (braking at `a` m/s^2) for what's `gap` m
## ahead going `lead_v`.
func _own_pedals(want: float, gap: float, lead_v: float, speed: float, a: float) -> Dictionary:
	lead_v = maxf(lead_v, 0.0)
	if gap < 250.0:
		want = minf(want, sqrt(lead_v * lead_v + 2.0 * a * maxf(gap - OWN_GAP_M - OWN_GAP_S * lead_v, 0.0)))
	var err := want - speed
	var c := {
		"throttle": clampf(0.2 + err * 0.3, 0.0, 1.0) if err > 0.0 else 0.0,
		"brake": clampf(-err * 0.5, 0.0, 1.0) if err < -0.5 else 0.0,
		"handbrake": 0.0,
	}
	if gap < 1.5 and speed > lead_v:
		c.throttle = 0.0
		c.brake = 1.0
	if speed < 0.6 and c.throttle < 0.05: # stopped: held still (the brake would select reverse)
		c.brake = 0.0
		c.handbrake = 1.0
	return c


## Grip on the road under it now, of dry (wet and snow lower it, D153).
func _grip(v: Vehicle) -> float:
	var c := v.road_conditions()
	return VehicleSim.surface_grip(VehicleSim.SURFACE_ASPHALT, c.x, c.y)


## True once it has wanted to go but not moved (against a barrier or a wreck; a queue isn't
## stuck: it isn't asking to go), been lost off the lanes, or been on its side or roof for long
## enough.
func _trouble(c: Dictionary, delta: float) -> bool:
	var v := racer.vehicle
	if racer.held or racer.waiting:
		_stuck = 0.0
		_upset = 0.0
		return false
	_upset = _upset + delta if v.global_basis.y.y < 0.3 else 0.0
	_stuck = _stuck + delta if absf(v.speed()) < 1.0 and (float(c.throttle) > 0.3 or lane < 0) else 0.0
	if _upset > UPSET_S or _stuck > STUCK_S:
		_upset = 0.0
		_stuck = 0.0
		return true
	return false


## Its lane closed ahead: a lane towards an open one (through closed ones if need be). Held up
## (`gap` m to what's ahead, going `lead_v`): over a lane with room; clear for a while: back out
## a lane. Never into a lane closed ahead otherwise.
func _overtake(delta: float, gap: float, lead_v: float, limit: float) -> void:
	_clock += delta
	var held := gap < HELD_GAP_M and lead_v < limit * 0.9
	_held = _held + delta if held else 0.0
	_clear = _clear + delta if not held else 0.0
	var tm := racer.session.traffic
	var since := _clock - _changed_at
	if since < ESCAPE_AGAIN_S:
		return
	var info := tm.sim.lane_info(lane)
	var to := -1
	if tm.sim.closed_ahead(lane, maxf(_s, 0.0), CLOSED_AHEAD_M):
		var side := _open_side(info)
		if not side.is_empty() and _room(side == "inner"):
			to = int(info[side])
	elif since < change_again_s:
		return
	elif _held > overtake_after_s:
		for side: String in ["inner", "outer"]:
			if int(info.get(side, -1)) >= 0 and not _closed(int(info[side])) and _room(side == "inner"):
				to = int(info[side])
				break
	elif keep_out and _clear > KEEP_OUT_S and int(info.get("outer", -1)) >= 0 and not _closed(int(info.outer)) and _room(false):
		to = int(info.outer)
	if to >= 0:
		lane = to
		_s = -1.0 # found again on the new lane
		_changed_at = _clock
		_held = 0.0
		_clear = 0.0


## True if lane `l` (beside this one, so about as far along) is closed within CLOSED_AHEAD_M.
func _closed(l: int) -> bool:
	return racer.session.traffic.sim.closed_ahead(l, maxf(_s, 0.0) - ROOM_BEHIND_M, CLOSED_AHEAD_M)


## Which way ("outer" or "inner", from this lane's `info`) the nearest lane not closed ahead is;
## "" if every lane is.
func _open_side(info: Dictionary) -> String:
	var sim := racer.session.traffic.sim
	for side: String in ["outer", "inner"]:
		var l := int(info.get(side, -1))
		while l >= 0:
			if not _closed(l):
				return side
			l = int(sim.lane_info(l).get(side, -1))
	return ""


## True if the lane beside (to the driver's left if `left`) is clear from ROOM_BEHIND_M behind to
## ROOM_AHEAD_M ahead: traffic, and every other car (players, police).
func _room(left: bool) -> bool:
	var tm := racer.session.traffic
	var v := racer.vehicle
	var lane_m := racer.session.track.highway.lane_m if racer.session.track.highway else 3.6
	var lo := lane_m * 0.5 if left else -lane_m * 1.5
	var hi := lane_m * 1.5 if left else -lane_m * 0.5
	for row: Array in tm.near_rows(v, ROOM_AHEAD_M + 10.0):
		var along: float = row[2]
		var across: float = row[3]
		if across > lo and across < hi and along > -ROOM_BEHIND_M - float(row[5]) and along < ROOM_AHEAD_M:
			return false
	var fwd := Vector3(v.global_basis.z.x, 0.0, v.global_basis.z.z).normalized()
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	for r in racer.session.racers:
		if r == racer or r.vehicle == null or not is_instance_valid(r.vehicle) or r.waiting:
			continue
		var d := r.vehicle.global_position - v.global_position
		var along := d.dot(fwd)
		var across := d.dot(side)
		if across > lo and across < hi and along > -ROOM_BEHIND_M - 5.0 and along < ROOM_AHEAD_M:
			return false
	return true
