class_name Slipstream
extends RefCounted
## The slipstream (karts D139, Track D208): close behind a moving car and inside its width a car
## meets less air. How far a car is tucked in is 1 right behind the other, 0 at `reach` or out of
## its width; the drag cut grows with it. A car tucked in close behind another pushes the air off
## its tail along, so the one in front gains a little too (a lead cut).


## How far `r` is tucked in behind the nearest car ahead of it (0..1). Cars waiting, being towed
## or slower than `min_speed` (m/s) leave no slipstream.
static func tow(r: Racer, racers: Array, reach: float, half: float, min_speed: float) -> float:
	var v := r.vehicle
	var fwd := v.global_basis.z
	var left := v.global_basis.x
	var best := 0.0
	for o: Racer in racers:
		if o == r or o.vehicle == null or o.waiting or o.towed or absf(o.speed) < min_speed:
			continue
		var rel := o.vehicle.global_position - v.global_position
		var along := rel.dot(fwd)
		if along <= 0.0 or along > reach or absf(rel.dot(left)) > half:
			continue
		best = maxf(best, 1.0 - along / reach)
	return best


## How far the nearest car behind `r` is tucked in on its tail (0..1, the same measure as tow()).
static func pushed(r: Racer, racers: Array, reach: float, half: float, min_speed: float) -> float:
	var v := r.vehicle
	var fwd := v.global_basis.z
	var left := v.global_basis.x
	var best := 0.0
	for o: Racer in racers:
		if o == r or o.vehicle == null or o.waiting or o.towed or absf(o.speed) < min_speed:
			continue
		var rel := o.vehicle.global_position - v.global_position
		var behind := -rel.dot(fwd)
		if behind <= 0.0 or behind > reach or absf(rel.dot(left)) > half:
			continue
		best = maxf(best, 1.0 - behind / reach)
	return best
