class_name DragLadder
extends RefCounted
## A drag match's ladder (D170): the field is drawn into pairs, two cars run a pass, the winner
## goes through, and the last car standing takes the match. A field that is not a power of two
## gives byes in the first round, so every round after it is full. A bye does not run a pass —
## except in a one-car field, which runs a single pass on its own (a shakedown).
##
## The ladder decides nothing about the driving; DragControl runs the passes and hands each
## result back here. Offline and online alike, the authority owns the ladder.

## racer -> the round it went out in.
var out_in := {}
## Every pass run, in order: {round, pair, cars: [racer], reaction: {}, et: {}, foul: {}, won}.
var passes: Array[Dictionary] = []
var round_index := 0
## Pairs of this round: [[a, b], ...]; `b` is null for a bye.
var pairs: Array = []
var pair_index := 0
var winner: Racer

var _rng := RandomNumberGenerator.new()
## Cars through to the next round, filled as this one runs.
var _through: Array[Racer] = []


## Draws `racers` into the first round. `seed_value` 0 shuffles freshly.
func seed_field(racers: Array[Racer], seed_value := 0) -> void:
	out_in.clear()
	passes.clear()
	_through.clear()
	round_index = 0
	pair_index = 0
	winner = null
	var field: Array[Racer] = racers.duplicate()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_shuffle(field)
	pairs = _draw(field)
	if field.size() == 1:
		winner = null # the shakedown pass still runs; it wins when it is done


## The cars of the pass about to run: two, or one for a shakedown. Empty when the ladder is done.
func current() -> Array[Racer]:
	while round_index >= 0 and pair_index < pairs.size():
		var pair: Array = pairs[pair_index]
		var a := pair[0] as Racer
		var b := pair[1] as Racer
		if a != null and b != null:
			return [a, b]
		if a != null and pairs.size() == 1 and _through.is_empty() and passes.is_empty():
			return [a] # one car in the whole field: it runs alone
		# A bye: through without a pass.
		if a != null:
			_through.append(a)
		pair_index += 1
		if pair_index >= pairs.size():
			_next_round()
	return []


## The pass just run: `won` is the winner (null: nobody, both fouled out), `rows` is each car's
## numbers for the record. Advances the ladder.
func record(cars: Array[Racer], won: Racer, rows: Dictionary) -> void:
	var entry := { "round": round_index, "pair": pair_index, "cars": cars.duplicate(), "won": won }
	entry.merge(rows)
	passes.append(entry)
	if cars.size() == 1:
		# A shakedown: the lone car takes the match whatever it did.
		_through.append(cars[0])
	else:
		for r in cars:
			if r == won:
				_through.append(r)
			else:
				out_in[r] = round_index
	pair_index += 1
	if pair_index >= pairs.size():
		_next_round()


func finished() -> bool:
	return winner != null


## How many rounds a field of this size takes (the HUD names the last one "Final").
func rounds_total() -> int:
	var n := 0
	var target := 1
	while target < maxi(passes_field_size(), 1):
		target *= 2
		n += 1
	return maxi(n, 1)


## The field the ladder started with.
func passes_field_size() -> int:
	return out_in.size() + _through.size() + _in_play()


## "Round 2/3" or "Final".
func round_text() -> String:
	var total := rounds_total()
	if round_index >= total - 1:
		return "Final"
	return "Round %d/%d" % [round_index + 1, total]


## The order now, for the results: the winner first, then the cars that lasted longest.
func standings(all_racers: Array[Racer]) -> Array[Racer]:
	var out: Array[Racer] = all_racers.duplicate()
	out.sort_custom(func(a: Racer, b: Racer) -> bool:
		var ra := _reached(a)
		var rb := _reached(b)
		if ra != rb:
			return ra > rb
		return a.number < b.number)
	return out


## The round `r` reached: a high number for one still in, so it sorts to the front.
func _reached(r: Racer) -> int:
	if r == winner:
		return 1000
	if out_in.has(r):
		return int(out_in[r])
	return 999 # still in, or never drawn


## The round `r` went out in, 1-based, or 0 while it is still in (the results column).
func round_of(r: Racer) -> int:
	if r == winner:
		return rounds_total()
	return int(out_in[r]) + 1 if out_in.has(r) else 0


## Cars drawn into this round that have not run yet.
func _in_play() -> int:
	var n := 0
	for i in range(pair_index, pairs.size()):
		for c: Variant in pairs[i]:
			if c != null:
				n += 1
	return n


## The next round from whoever came through, or the match is over.
func _next_round() -> void:
	if _through.size() <= 1:
		winner = _through[0] if not _through.is_empty() else null
		pairs = []
		pair_index = 0
		return
	round_index += 1
	pairs = _draw(_through)
	pair_index = 0
	_through = []


## `field` in pairs. A field that is not a power of two gives the first cars a bye, so every
## later round is full.
func _draw(field: Array[Racer]) -> Array:
	var n := field.size()
	if n <= 1:
		return [[field[0] if n == 1 else null, null]] if n == 1 else []
	var target := 1
	while target < n:
		target *= 2
	var byes := target - n
	var out: Array = []
	for i in byes:
		out.append([field[i], null])
	var i := byes
	while i + 1 < n:
		out.append([field[i], field[i + 1]])
		i += 2
	return out


func _shuffle(field: Array[Racer]) -> void:
	for i in range(field.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := field[i]
		field[i] = field[j]
		field[j] = tmp
