class_name PoliceLanes
extends RefCounted
## Which lanes a roadblock or a spike strip closes (D248): any of the road's slots (its lanes,
## counted left to right as the driver sees them; PoliceRoad.block_slots), more of them as heat
## rises. Every lane closed, the shoulder (the verge on the endless road) is the way through.

## Per level, the chances of closing 1, 2 and 3 lanes. Spike strips start at heat 3, roadblocks at 4.
const COUNTS := {
	3: [0.7, 0.3, 0.0],
	4: [0.4, 0.6, 0.0],
	5: [0.0, 0.5, 0.5],
}


## How many of `slots` lanes close at heat `level`.
static func count(level: int, slots: int, rng: RandomNumberGenerator) -> int:
	var odds: Array = COUNTS[clampi(level, 3, 5)]
	var roll := rng.randf()
	var n := odds.size()
	for i in odds.size():
		roll -= float(odds[i])
		if roll < 0.0:
			n = i + 1
			break
	return clampi(n, 1, maxi(slots, 1))


## Which of `slots` lanes close at heat `level` (ascending), any set of count()'s size alike. If it
## comes out as `last`, it's drawn once more, so the same pattern rarely comes twice running.
static func pick(level: int, slots: int, rng: RandomNumberGenerator, last: Array = []) -> Array[int]:
	var n := count(level, slots, rng)
	var out := _draw(n, slots, rng)
	if n < slots and _same(out, last):
		out = _draw(n, slots, rng)
	return out


static func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return false
	return true


static func _draw(n: int, slots: int, rng: RandomNumberGenerator) -> Array[int]:
	var all: Array[int] = []
	for i in slots:
		all.append(i)
	# A partial Fisher-Yates: the first n of a shuffle.
	for i in mini(n, slots):
		var j := rng.randi_range(i, slots - 1)
		var t := all[i]
		all[i] = all[j]
		all[j] = t
	var out := all.slice(0, mini(n, slots))
	out.sort()
	return out


## The runs of side-by-side slots in `picked` (ascending): Vector2i(first, last) each.
static func runs(picked: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s: int in picked:
		if not out.is_empty() and out[-1].y == s - 1:
			out[-1].y = s
		else:
			out.append(Vector2i(s, s))
	return out
