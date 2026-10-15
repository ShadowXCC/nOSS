class_name NearMiss
extends RefCounted
## One car's passes through traffic (D114). For each traffic car it comes up on, it keeps the
## smallest hull-to-hull gap while the two are alongside and how much faster it was going then;
## once that car is behind, the pass is done: {id, gap, relative_kmh, side}. Two close passes
## on opposite sides within SPLIT_S are a lane split. A car that pulls away again, or goes out
## of reach, was never passed.

## Alongside: within this much of touching, end to end.
const ALONGSIDE_M := 3.0
const SPLIT_S := 0.6

var _passing := {} # traffic id -> {gap, relative, side}
var _recent: Array = [] # [time, side] of close passes, for lane splits


## The traffic round the car now, as rows [id, gap (m, hull to hull), along (m, its centre ahead
## of this car's, + ahead), left (m, + to the left), relative speed (m/s, this car faster: +),
## half lengths added (m)]. Returns the passes done: [{id, gap, relative_kmh, side}] and, for a
## lane split, one {split: true}.
func step(rows: Array, now: float) -> Array:
	var done := []
	var seen := {}
	for row: Array in rows:
		var id: int = row[0]
		var gap: float = row[1]
		var along: float = row[2]
		var reach: float = row[5] + ALONGSIDE_M
		seen[id] = true
		if _passing.has(id):
			var p: Dictionary = _passing[id]
			if along < -reach:
				done.append({ "id": id, "gap": p.gap, "relative_kmh": float(p.relative) * 3.6, "side": p.side })
				_passing.erase(id)
			elif along > reach:
				_passing.erase(id) # it pulled away
			elif gap < float(p.gap):
				p.gap = gap
				p.relative = row[4]
				p.side = signf(row[3])
		elif along > 0.0 and along <= reach:
			_passing[id] = { "gap": gap, "relative": row[4], "side": signf(row[3]) }
	for id: int in _passing.keys():
		if not seen.has(id):
			_passing.erase(id)
	var splits := []
	for d: Dictionary in done:
		if float(d.gap) >= ScoreAttack.NEAR_M:
			continue
		var split := _recent.any(func(r: Array) -> bool: return now - float(r[0]) <= SPLIT_S and signf(r[1]) == -signf(d.side))
		if split:
			splits.append({ "split": true })
			_recent.clear() # each pass counts in one split at most
		else:
			_recent.append([now, d.side])
	_recent = _recent.filter(func(r: Array) -> bool: return now - float(r[0]) <= SPLIT_S)
	done.append_array(splits)
	return done
