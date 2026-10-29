class_name EndlessGarage
extends RefCounted
## Which garage cars an endless road's traffic draws from, and where (D191, D232). Offline every
## car is in one set. Online the server deals sets of up to ONLINE_MOST from the contributors' cars
## (the host's, or everyone's in turn) and swaps to the next set each time the leader enters a new
## biome; slots whose cars are near a player at a swap keep the set they had, so no car changes in
## sight. A slot is on the set of the newest swap that didn't pin it (set 0 if every swap did).
## That's kept folded: each lane has the stretches of slots still on an older set, and every other
## slot is on the newest. The server sends the whole state (to_dict, with a session) and each swap
## (ENDLESS_GARAGE), and every game applies them alike, so every game draws the same car in a slot.

## Cars in a set online.
const ONLINE_MOST := 12
## At a swap, slots whose cars are within this of a player keep their set (cars are drawn out to
## EndlessTraffic.VIEW_M).
const PIN_M := 2500.0
## What may come in: cars a guest offers, sets and cars a state holds, kept stretches a lane holds.
const MOST_OFFERED := 100
const MOST_SETS := 32
const MOST_CARS := MOST_SETS * ONLINE_MOST
const MOST_KEPT := 256
const LANES := 4

## Registry index -> {car: its hash (a path offline), fits: PackedStringArray of traffic type ids}.
## Indexes never change; cars no set uses any more are let go.
var cars := {}
## Set id -> registry indexes, in order.
var sets := {}
## Swaps so far: set `k` is the newest (every slot not kept is on it), set k + 1 the next.
var k := 0
## Lane -> PackedInt64Array [lo, hi, set, lo, hi, set, ...], in order: slots lo..hi (their j) of
## that lane are on that older set.
var kept := {}


## The set slot `j` of lane `lane` draws from.
func set_of(lane: int, j: int) -> int:
	var runs: PackedInt64Array = kept.get(lane, PackedInt64Array())
	for i in range(0, runs.size(), 3):
		if j < runs[i]:
			break
		if j <= runs[i + 1]:
			return int(runs[i + 2])
	return k


## The next set: slots in `pinned` ({lane: [lo, hi, lo, hi, ...]}, in order) keep the set they're
## on; every other slot moves to set k + 1.
func swap(pinned: Dictionary) -> void:
	var out := {}
	for lane: int in pinned:
		var runs: PackedInt64Array = kept.get(lane, PackedInt64Array())
		var p: PackedInt64Array = pinned[lane]
		var keep := PackedInt64Array()
		for i in range(0, p.size(), 2):
			var at := p[i]
			var hi := p[i + 1]
			for r in range(0, runs.size(), 3):
				var a := maxi(runs[r], at)
				var b := mini(runs[r + 1], hi)
				if a > b:
					continue
				if a > at:
					_run(keep, at, a - 1, k)
				_run(keep, a, b, runs[r + 2])
				at = b + 1
			if at <= hi:
				_run(keep, at, hi, k)
		if not keep.is_empty():
			out[lane] = keep
	kept = out
	k += 1
	_prune()


## Appends run lo..hi on `set_id`, joined to the last one if it carries on from it.
static func _run(runs: PackedInt64Array, lo: int, hi: int, set_id: int) -> void:
	var n := runs.size()
	if n >= 3 and runs[n - 1] == set_id and runs[n - 2] == lo - 1:
		runs[n - 2] = hi
	else:
		runs.append_array([lo, hi, set_id])


## Lets go of the sets nothing uses (the newest, the next and the kept ones stay) and their cars.
func _prune() -> void:
	var used := { k: true, k + 1: true }
	for lane: int in kept:
		var runs: PackedInt64Array = kept[lane]
		for i in range(2, runs.size(), 3):
			used[int(runs[i])] = true
	for id: int in sets.keys():
		if not used.has(id):
			sets.erase(id)
	var held := {}
	for id: int in sets:
		for i: int in sets[id]:
			held[i] = true
	for i: int in cars.keys():
		if not held.has(i):
			cars.erase(i)


# --- the server ----------------------------------------------------------------------------------


## The next set's cars (hashes): the hands ([{cars: PackedStringArray, at: cursor}], each list in
## its own shuffled order) take turns from `start`, each adding its next car not in the set yet,
## until there are `most` or no hand has one. Cursors move on, so the next deal goes on from there.
static func deal(hands: Array, start: int, most := ONLINE_MOST) -> PackedStringArray:
	var out := PackedStringArray()
	var n := hands.size()
	var done := {}
	var i := posmod(start, maxi(n, 1))
	while out.size() < most and done.size() < n:
		var hand: Dictionary = hands[i]
		if not done.has(i):
			var list: PackedStringArray = hand.cars
			var added := false
			for _t in list.size():
				var car := list[int(hand.at) % list.size()]
				hand.at = (int(hand.at) + 1) % list.size()
				if not car in out:
					out.append(car)
					added = true
					break
			if not added:
				done[i] = true
		i = (i + 1) % n
	return out


## Slot spans ([[lo, hi], ...]) joined where they meet or overlap, in order: [lo, hi, lo, hi, ...].
static func merged(spans: Array) -> PackedInt64Array:
	var sorted := spans.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := PackedInt64Array()
	for s: Array in sorted:
		var n := out.size()
		if n >= 2 and int(s[0]) <= out[n - 1] + 1:
			out[n - 1] = maxi(out[n - 1], int(s[1]))
		else:
			out.append_array([int(s[0]), int(s[1])])
	return out


# --- on the wire ---------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	return { "k": k, "cars": cars.duplicate(true), "sets": sets.duplicate(true), "kept": kept.duplicate(true) }


## A session's state as it came, or null if it isn't one.
static func from_dict(d: Variant) -> EndlessGarage:
	if not (d is Dictionary and d.get("k") is int and int(d.k) >= 0 and d.get("kept") is Dictionary):
		return null
	var g := EndlessGarage.new()
	g.k = d.k
	if not (g._take(d) and g.sets.has(g.k)):
		return null
	var kept_in: Variant = _pins(d.kept, 3)
	if kept_in == null:
		return null
	for lane: int in kept_in:
		var runs: PackedInt64Array = kept_in[lane]
		for i in range(2, runs.size(), 3):
			if not g.sets.has(int(runs[i])):
				return null
	g.kept = kept_in
	return g


## A swap from the server ({k, cars, sets, pinned}): whether it was taken. One this state has had
## already (a late joiner's) is left.
func apply(d: Dictionary) -> bool:
	if not (d.get("k") is int and int(d.k) > k and d.get("pinned") is Dictionary):
		return false
	var pinned: Variant = _pins(d.pinned, 2)
	if pinned == null or not _take(d) or not sets.has(int(d.k)):
		return false
	k = int(d.k) - 1
	swap(pinned)
	return true


## The cars and sets of `d`, if they're well formed (each set's cars among them or here already).
func _take(d: Dictionary) -> bool:
	var c: Variant = d.get("cars")
	var s: Variant = d.get("sets")
	if not (c is Dictionary and s is Dictionary and (c as Dictionary).size() <= MOST_CARS and (s as Dictionary).size() <= MOST_SETS):
		return false
	var new_cars := {}
	for i: Variant in c:
		var e: Variant = c[i]
		if not (i is int and int(i) >= 0 and e is Dictionary and e.get("car") is String and ContentStore.valid_hash(e.car)):
			return false
		var fits: Variant = e.get("fits")
		if not ((fits is PackedStringArray or fits is Array) and Array(fits).size() <= 8 and Array(fits).all(func(t: Variant) -> bool: return t is String and (t as String).length() <= 32)):
			return false
		new_cars[i] = { "car": String(e.car), "fits": PackedStringArray(fits) }
	var new_sets := {}
	for id: Variant in s:
		var list: Variant = s[id]
		if not (id is int and int(id) >= 0 and list is PackedInt32Array and (list as PackedInt32Array).size() <= ONLINE_MOST):
			return false
		for i: int in list:
			if not (new_cars.has(i) or cars.has(i)):
				return false
		new_sets[id] = (list as PackedInt32Array).duplicate()
	cars.merge(new_cars, true)
	sets.merge(new_sets, true)
	return true


## Slot stretches by lane as they came ({lane: PackedInt64Array}, `stride` numbers each: lo, hi
## and maybe a set), in order and not overlapping; or null.
static func _pins(v: Variant, stride: int) -> Variant:
	if not (v is Dictionary and (v as Dictionary).size() <= LANES):
		return null
	var out := {}
	for lane: Variant in v:
		var runs: Variant = v[lane]
		if not (lane is int and int(lane) >= 0 and int(lane) < LANES and runs is PackedInt64Array):
			return null
		var r: PackedInt64Array = runs
		if r.size() % stride != 0 or r.size() > MOST_KEPT * stride:
			return null
		for i in range(0, r.size(), stride):
			if r[i] > r[i + 1] or (i > 0 and r[i] <= r[i - stride + 1]):
				return null
		out[lane] = r.duplicate()
	return out
