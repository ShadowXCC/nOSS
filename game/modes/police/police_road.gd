class_name PoliceRoad
extends RefCounted
## What the police (PoliceControl, D192) know of the road they work, so the same police can work a
## highway (HighwayPoliceRoad) and the endless road (EndlessPoliceRoad): whom they watch, the limit,
## where things are along the road, where to put their cars, the traffic on it, its speed traps and
## patrols, and what being busted means there. Distances are along the road (Racer.distance); a
## way is +1 (toward higher distances) or -1.

## A roadblock's units side by side stand this far apart along the road (a car is 1.9 m wide).
const STAGGER_M := 2.6

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


## The most chasing units out at once (the trap units come on top).
func chase_units() -> int:
	return PoliceControl.CHASE_UNITS


## The most units waiting ahead of players at once (on top of the chasers, D201).
func ahead_units() -> int:
	return PoliceControl.AHEAD_UNITS


## The units kept for roadblocks (D248), on top of the rest.
func roadblock_units() -> int:
	return PoliceControl.ROADBLOCK_UNITS


## Where a unit waits for `p` about `m` metres on along their way, on the side of the road facing
## their way (D201): {xform, at_m}, or {} if nowhere here now.
func ahead_spot(_p: Racer, _m: float) -> Dictionary:
	return {}


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


## The slots a roadblock or a spike strip may close for a driver going `way` (D248): lanes, counted
## from their left as they drive (PoliceLanes picks among them).
func block_slots(_way: int) -> int:
	return lanes()


## Slot `slot`'s lane across the road at `d`: Vector2(from, to) laterals, lane edge to lane edge.
func slot_span(_way: int, _slot: int, _d: float) -> Vector2:
	return Vector2.ZERO


## The `i`th unit of a roadblock at `d`, parked at lateral `lat`, `angle` off the road's line
## (PI / 2: square across it), every other one turned the other way and STAGGER_M on, so units
## side by side don't overlap.
func block_xform(way_dir: int, lat: float, d: float, i: int, angle := PI / 2.0) -> Transform3D:
	var at := session.track.transform_at(d + way_dir * STAGGER_M * (i % 2), lat)
	at.basis = Basis(at.basis.y, angle * (1 if i % 2 == 0 else -1)) * at.basis
	return at


## Where a car gets by a roadblock or a strip at `d` with every slot closed: the shoulder's
## lateral (the verge's on the endless road).
func through_lateral(_way: int, _d: float) -> float:
	return 0.0


## Whether the shoulder (the verge) at `d` is free to drive round a block there, `way`'s side.
func verge_clear(_way: int, _d: float) -> bool:
	return true


## Whether the police lay spike strips here (they must be able to catch the cars they're for).
func spikes_allowed() -> bool:
	return true




## Traffic round `v` for near misses (TrafficManager.near_rows' rows).
func near_rows(_v: Vehicle, _radius: float) -> Array:
	return []


## A roadblock for `p` at `d`: slots `slots` closed to traffic over `length` m on the way `way`
## drives. Returns what open_lanes takes to open them again.
func close_slots(_p: Racer, _way: int, _d: float, _length: float, _slots: Array) -> Array:
	return []


func open_lanes(_closures: Array) -> void:
	pass


## Traffic gets out of the way of `units` (PoliceRacers with their sirens on).
func move_over(_units: Array) -> void:
	pass


## Patrol cars in the traffic within `radius` of `pos`: [{xform, velocity, ...}]; one becomes a
## chasing unit where it is (convert_patrol takes it out of the traffic).
func patrols(_pos: Vector3, _radius: float) -> Array:
	return []


func convert_patrol(_patrol: Dictionary) -> void:
	pass


## The speed traps: [{at_m, dir, ...}].
func traps() -> Array:
	return []


## Where a speed trap's unit parks.
func trap_spot(trap: Dictionary) -> Transform3D:
	return shoulder_xform(int(trap.get("dir", 1)), float(trap.at_m))


## A spike strip went down (online, other games are told).
func strip_laid(_strip: SpikeStrip) -> void:
	pass


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


## What a bust says to the player (after after_bust).
func bust_text(_p: Racer) -> String:
	return "Busted"
