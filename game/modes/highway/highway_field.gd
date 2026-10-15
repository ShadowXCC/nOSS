class_name HighwayField
extends Node
## Where every car is on a highway (D113), once per physics tick, after the RaceField: which road
## (the main road or a ramp), carriageway, lane and distance. Sets each racer's direction (laps
## count along it; changing carriageway at a crossover starts the lap again) and whether it's
## driving against the traffic.

## Against the traffic faster than this for this long: wrong way.
const WRONG_WAY_SPEED := 4.0
const WRONG_WAY_S := 1.5
## Each car is looked at every this many ticks, in turn (plenty for its direction and wrong way);
## on a client, another game's car (its own game and the server rule on it) only this often.
const UPDATE_EVERY := 2
const REMOTE_EVERY := 16

var session: TrackSession
var layout: HighwayLayout
## Racer -> HighwayLayout.locate() result, when it was last looked at.
var where := {}
var _against := {}
var _ticks := 0


func _ready() -> void:
	process_physics_priority = -59 # after the RaceField (-60), before drivers (-50)


func _physics_process(delta: float) -> void:
	_ticks += 1
	var client := session.is_online() and not Net.is_server()
	var i := 0
	for r in session.racers:
		i += 1
		var every := REMOTE_EVERY if client and r is NetRacer else UPDATE_EVERY
		if r.vehicle == null or not is_instance_valid(r.vehicle) or r.waiting or (i + _ticks) % every != 0:
			continue
		update(r, delta * every)


func update(r: Racer, delta: float) -> void:
	# The RaceField has put it on the main road this tick already.
	var mp := { "index": r.track_index, "distance": r.distance, "lateral": r.lateral } if r.track_index >= 0 else {}
	var at := layout.locate(r.vehicle.global_position + Vector3.UP * 0.5, where.get(r, {}), mp)
	where[r] = at
	var vel := r.vehicle.remote_velocity if r.vehicle.remote else r.vehicle.linear_velocity
	var along := 0.0
	if at.on_road and at.road < 0:
		if int(at.dir) != r.direction:
			r.direction = int(at.dir)
			r.timer.invalidate("Direction changed")
			r.timer.teleported(r.lap_pos(r.distance))
		along = vel.dot(layout.main.tangents[at.index] * float(at.dir))
	elif at.on_road:
		along = vel.dot(layout.ramps[at.road].track.tangents[at.index])
	_against[r] = float(_against.get(r, 0.0)) + delta if along < -WRONG_WAY_SPEED else 0.0
	r.wrong_way = float(_against[r]) > WRONG_WAY_S


## The racer's spot: {road, index, distance, lateral, dir, lane, on_road}.
func at(r: Racer) -> Dictionary:
	return where.get(r, {})
