class_name LoopWatch
extends RefCounted
## Acceptance 3 (M7): two cars going opposite ways round a highway loop. Counts each time they
## pass, and which traffic `a` meets on the other carriageway, per lap of `a`. Used by
## tests/highway/highway_check.gd offline and by the server under --net-stats online.

## Passing within this far counts as meeting; then not again until they're this far apart.
const MEET_M := 60.0
const NEAR_M := 45.0
## Traffic is looked at every this many steps.
const LOOK_EVERY := 10

var session: TrackSession
var a: Racer
var b: Racer
## Per lap of `a` (0: before its first lap line): times they passed, and traffic id -> true.
var meetings := PackedInt32Array()
var met_by_lap: Array[Dictionary] = []
var _last_gap := INF
var _armed := true
var _steps := 0


func _init(s: TrackSession, first: Racer, second: Racer) -> void:
	session = s
	a = first
	b = second


## Once per physics tick. True if they passed each other this tick.
func step() -> bool:
	var lap := a.timer.lap
	while meetings.size() <= lap:
		meetings.append(0)
		met_by_lap.append({})
	# Their gap along the road (both on the main road): passing flips its sign.
	var half := session.track.length / 2.0
	var gap := fposmod(b.distance - a.distance + half, session.track.length) - half
	var met := _armed and is_finite(_last_gap) and signf(gap) != signf(_last_gap) and absf(gap) < MEET_M
	if met:
		meetings[lap] += 1
		_armed = false
	elif absf(gap) > MEET_M:
		_armed = true
	_last_gap = gap
	_steps += 1
	var tm := session.traffic
	if _steps % LOOK_EVERY == 0 and tm and a.vehicle and is_instance_valid(a.vehicle):
		for car in tm.sim.cars_near(a.vehicle.global_position, NEAR_M):
			var lane := int(tm.sim.car(car).lane)
			if lane >= 0 and int(tm.sim.lane_info(lane).dir) == -a.direction:
				met_by_lap[lap][car] = true
	return met


## `a`'s whole laps so far: [{lap, met, traffic, again}]; again is the share of the traffic met
## that lap met again the next (-1 until the next lap is whole too).
func rows() -> Array:
	var out := []
	var current := meetings.size() - 1
	for lap in range(1, current):
		var met := met_by_lap[lap]
		var again := -1.0
		if lap + 1 < current:
			var n := 0
			for car: int in met:
				n += 1 if met_by_lap[lap + 1].has(car) else 0
			again = float(n) / maxf(met.size(), 1.0)
		out.append({ "lap": lap, "met": meetings[lap], "traffic": met.size(), "again": again })
	return out
