class_name Slipstream
extends RefCounted
## The slipstream (karts D139, Track D208, packs D228): close behind a moving car and inside its
## width a car meets less air. How far a car is tucked in is 1 right behind the other, 0 at
## `reach` or out of its width; the drag cut grows with it. A car tucked in close behind another
## pushes the air off its tail along, so the one in front gains a little too (a lead cut).


## A car's half length and width, m (side drafting).
const HALF_LENGTH := 2.3
const WIDTH := 2.0


## How far `r` is tucked in behind the nearest car ahead of it (0..1). Cars waiting, being towed
## or slower than `min_speed` (m/s) leave no slipstream.
static func tow(r: Racer, racers: Array, reach: float, half: float, min_speed: float) -> float:
	return float(tow_from(r, racers, reach, half, min_speed)[0])


## [how far `r` is tucked in (as tow()), the car it's tucked in behind (null if none)].
static func tow_from(r: Racer, racers: Array, reach: float, half: float, min_speed: float) -> Array:
	var v := r.vehicle
	var fwd := v.global_basis.z
	var left := v.global_basis.x
	var best := 0.0
	var car: Racer = null
	for o: Racer in racers:
		if o == r or o.vehicle == null or o.waiting or o.towed or absf(o.speed) < min_speed:
			continue
		var rel := o.vehicle.global_position - v.global_position
		var along := rel.dot(fwd)
		if along <= 0.0 or along > reach or absf(rel.dot(left)) > half:
			continue
		if 1.0 - along / reach > best:
			best = 1.0 - along / reach
			car = o
	return [best, car]


## Pack racing (D228): the lines cars make, each tucked in behind the next at `link` or more of a
## tow: `tows` (racer -> tow_from()) to racer -> how many cars its line has (1: on its own).
static func line_sizes(tows: Dictionary, link: float) -> Dictionary:
	var root := {}
	var find := func(find_: Callable, r: Racer) -> Racer:
		if root.get(r, r) == r:
			return r
		root[r] = find_.call(find_, root[r])
		return root[r]
	for r: Racer in tows:
		var ahead: Racer = tows[r][1]
		if ahead and tows.has(ahead) and float(tows[r][0]) >= link:
			var a: Racer = find.call(find, r)
			var b: Racer = find.call(find, ahead)
			if a != b:
				root[a] = b
	var count := {}
	for r: Racer in tows:
		var top: Racer = find.call(find, r)
		count[top] = int(count.get(top, 0)) + 1
	var out := {}
	for r: Racer in tows:
		out[r] = count[find.call(find, r)]
	return out


## Side drafting (D228): how hard a car alongside `r` takes the air off its side (0..1): within
## `gap` m of its flank, its nose between `r`'s tail and its middle, strongest right beside it.
static func side(r: Racer, racers: Array, gap: float, min_speed: float) -> float:
	var v := r.vehicle
	var fwd := v.global_basis.z
	var left := v.global_basis.x
	var best := 0.0
	for o: Racer in racers:
		if o == r or o.vehicle == null or o.waiting or o.towed or absf(o.speed) < min_speed:
			continue
		var rel := o.vehicle.global_position - v.global_position
		var nose := rel.dot(fwd) + HALF_LENGTH
		var across := absf(rel.dot(left)) - WIDTH
		if nose < -HALF_LENGTH or nose > 0.0 or across < 0.0 or across > gap:
			continue
		best = maxf(best, 1.0 - across / gap)
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
