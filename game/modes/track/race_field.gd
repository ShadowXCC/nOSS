class_name RaceField
extends Node
## Where every car is on the track, updated once per physics tick before anyone drives
## (docs/GAMEMODES.md §1): each Racer's along-track distance, lateral offset and speed, and its
## lap timer. Drivers, the spotter, flags and standings read this instead of projecting cars
## themselves.

## On a client, another game's car is put on the track every this many ticks.
const REMOTE_EVERY := 4

var racers: Array[Racer] = []
var track: TrackData
var _ticks := 0


func _ready() -> void:
	process_physics_priority = -60 # after player input (-90), before drivers (-50) and vehicles (0)


func _physics_process(delta: float) -> void:
	_ticks += 1
	var client := Net.client != null and not Net.is_server()
	var i := 0
	for r in racers:
		i += 1
		if r.vehicle == null or not is_instance_valid(r.vehicle) or r.waiting: # waiting: off the track
			continue
		if client and r is NetRacer:
			# Another game's car: its game and the server time it; here it's for the HUD.
			if (i + _ticks) % REMOTE_EVERY == 0:
				r.update_track(delta * REMOTE_EVERY)
		else:
			r.update_track(delta)


## Along-track gap from `from` to `to`, metres, in (-length/2, length/2]: + = `to` is ahead.
func gap(from: Racer, to: Racer) -> float:
	var d := to.distance - from.distance
	if not track.closed: # an open road (endless): no wrapping
		return d
	var half := track.length / 2.0
	if d > half:
		d -= track.length
	elif d <= -half:
		d += track.length
	return d


## Cars within `behind` m behind and `ahead` m ahead of `racer`, nearest first:
## [{racer, gap (m, + = ahead), lateral (theirs)}].
func around(racer: Racer, ahead: float, behind: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in racers:
		if r == racer or r.vehicle == null:
			continue
		var g := gap(racer, r)
		if g <= ahead and g >= -behind:
			out.append({ "racer": r, "gap": g, "lateral": r.lateral })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a.gap) < absf(b.gap))
	return out
