class_name PoliceRoad
extends RefCounted
## What the police (PoliceControl, D192) know of the road they work, so the same police can work a
## highway (HighwayPoliceRoad) and the endless road (EndlessPoliceRoad): whom they watch, the limit,
## where things are along the road, where to put their cars, the traffic on it, its speed traps and
## patrols, and what being busted means there. Distances are along the road (Racer.distance); a
## way is +1 (toward higher distances) or -1.

var session: TrackSession


## The racers the police give heat to.
func watched_players() -> Array:
	return []


## The speed limit where `p` is (m/s).
func limit_mps(_p: Racer) -> float:
	return 30.0


## The way `p` drives.
func way(_p: Racer) -> int:
	return 1


## The distance `m` metres on from `p` the way they drive.
func along(p: Racer, m: float) -> float:
	return p.distance + way(p) * m


## How far `p` has gone past `at_m` the way they drive (negative: not there yet).
func past(p: Racer, at_m: float) -> float:
	return way(p) * (p.distance - at_m)


## Distance `a` less distance `b` along the road (the short way round, on a loop).
func delta_m(a: float, b: float) -> float:
	return a - b


## Lanes each way.
func lanes() -> int:
	return 1


## {distance, lateral} of a scene point.
func project(pos: Vector3) -> Dictionary:
	return session.track.project(pos)


## Whether the road the way `way` drives from `d` on is straight for `length` m (spike strips).
func straight_clear(_d: float, _way: int, _length: float) -> bool:
	return false


## A car in lane `lane` (the road's own numbering, 0 to lanes() - 1) of `way` at `d`, facing that
## way.
func lane_xform(_way: int, _lane: int, d: float) -> Transform3D:
	return session.track.transform_at(d)


## A car on the shoulder of `way` at `d`, facing that way.
func shoulder_xform(way_dir: int, d: float) -> Transform3D:
	return lane_xform(way_dir, lanes() - 1, d)


## The `i`th unit parked across `way`'s lanes at `d` (a roadblock), in lane `lane` (block_lanes).
func across_xform(way_dir: int, lane: int, d: float, i: int) -> Transform3D:
	var at := lane_xform(way_dir, lane, d)
	at.basis = Basis(Vector3.UP, PI / 2.0 * (1 if i == 0 else -1)) * at.basis
	return at


## Whether the police lay spike strips here (they must be able to catch the cars they're for).
func spikes_allowed() -> bool:
	return true


## Across the road the way `way` drives at `d`, where a spike strip lies: Vector2(from, to)
## laterals, every lane of that way but half a lane left open.
func strip_span(_way: int, _d: float) -> Vector2:
	return Vector2.ZERO


## Traffic round `v` for near misses (TrafficManager.near_rows' rows).
func near_rows(_v: Vehicle, _radius: float) -> Array:
	return []


## A roadblock for `p` at `d`: `way`'s lanes closed to traffic over `length` m, bar the one left
## open. Returns what open_lanes takes to open them again.
func close_lanes(_p: Racer, _way: int, _d: float, _length: float) -> Array:
	return []


func open_lanes(_closures: Array) -> void:
	pass


## Lanes a roadblock parks units across: [lane] (the rest stay open).
func block_lanes(_way: int) -> Array:
	return []


## Traffic gets out of the way of `units` (PoliceRacers with their sirens on).
func move_over(_units: Array) -> void:
	pass


## The speed traps: [{at_m, dir, ...}].
func traps() -> Array:
	return []


## Where a speed trap's unit parks.
func trap_spot(trap: Dictionary) -> Transform3D:
	return shoulder_xform(int(trap.get("dir", 1)), float(trap.at_m))


## Unit `i`'s network id (0: offline), and the unit made known to the network.
func unit_id(_i: int) -> int:
	return 0


func register_unit(_u: PoliceRacer) -> void:
	pass


## A unit's driver (PoliceRacer.ai): it has `mode`, `target`, `side` and `level`, and `deployed()`.
func make_driver(_u: PoliceRacer) -> Node:
	return null


## `p` was busted (at `clock`, the police's seconds): what that means here.
func after_bust(_p: Racer, _clock: float) -> void:
	pass
