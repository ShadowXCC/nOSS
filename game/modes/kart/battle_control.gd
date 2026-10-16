class_name BattleControl
extends Node
## Battles (D144) on an arena: lives, hits and the end of a match. A Bolt, Seeker, Oil Slick or
## EMP hit the Shield didn't block takes a life (then a short grace in which items pass the kart
## by: one spin-out costs one life, and nobody is pinned down)
## and counts as a hit for whoever's item it was (not a kart's own). "Last one standing": a kart
## with no lives left is out (it drives on ghosted, with no items); the match ends with one kart
## left or at the time limit, ranked by lives, then hits, then who went out last. "Most hits":
## nobody goes out; at the time limit, ranked by hits dealt, then fewest taken.
## The authority decides (offline: this game); RaceControl runs the lights and the results.

signal life_lost(r: Racer, lives: int)
signal knocked_out(r: Racer)

const LIVES := 3
const LIFE_KINDS := ["bolt", "seeker", "oil_slick", "emp"]
const GRACE_S := 2.0

var session: TrackSession
var authority := true
var ended := false
var _lost := {} # racer -> lives lost
var _hits := {} # racer -> hits dealt
var _taken := {} # racer -> hits taken
var _grace := {} # racer -> seconds left
var _out_order: Array[Racer] = [] # the first out first


func _ready() -> void:
	process_physics_priority = -53
	session.kart.items.hit_landed.connect(_on_hit)
	session.race.session_started.connect(func(_kind: String) -> void: reset())


func rule() -> String:
	return session.event.battle_rule


## A new match: everyone back in with all their lives.
func reset() -> void:
	ended = false
	_lost.clear()
	_hits.clear()
	_taken.clear()
	_grace.clear()
	_out_order.clear()
	for r in session.racers:
		_set_out(r, false)


func lives(r: Racer) -> int:
	return LIVES - lives_lost(r)


## Lives `r` has lost so far (the item odds lean on it, D140). In a most-hits match, how far
## behind the most hits it is instead (0-2).
func lives_lost(r: Racer) -> int:
	if rule() == "hits":
		var most := 0
		for o: Racer in _hits:
			most = maxi(most, int(_hits[o]))
		return clampi(most - hits(r), 0, LIVES - 1)
	return int(_lost.get(r, 0))


func hits(r: Racer) -> int:
	return int(_hits.get(r, 0))


func taken(r: Racer) -> int:
	return int(_taken.get(r, 0))


## Just hit: items leave it alone for a moment.
func protected(r: Racer) -> bool:
	return float(_grace.get(r, 0.0)) > 0.0


func time_left() -> float:
	return maxf(session.event.battle_min * 60.0 - session.race.clock, 0.0)


## Karts still in.
func standing() -> Array[Racer]:
	return session.racers.filter(func(r: Racer) -> bool: return not r.out)


func _on_hit(victim: Racer, attacker: Racer, kind: String, blocked: bool) -> void:
	if blocked or not authority or ended or session.race.phase != RaceControl.Phase.RUNNING:
		return
	if kind not in LIFE_KINDS or victim.out or float(_grace.get(victim, 0.0)) > 0.0:
		return
	_grace[victim] = GRACE_S
	_taken[victim] = taken(victim) + 1
	if attacker and attacker != victim and is_instance_valid(attacker):
		_hits[attacker] = hits(attacker) + 1
	if rule() == "hits":
		return
	_lost[victim] = lives_lost(victim) + 1
	var left := lives(victim)
	life_lost.emit(victim, left)
	if left <= 0:
		_knock_out(victim)
	else:
		victim.notify("Last life" if left == 1 else "Lost a life", 2.0)


func _knock_out(r: Racer) -> void:
	_set_out(r, true)
	_out_order.append(r)
	var s := session.kart.items.slot(r)
	s.item = ""
	s.count = 0
	s.shield = 0.0
	s.magnet = 0.0
	r.notify("Out", 3.0)
	knocked_out.emit(r)


func _set_out(r: Racer, on: bool) -> void:
	r.out = on
	if r.vehicle:
		r.vehicle.kart_bits = (r.vehicle.kart_bits | CarState.KART_OUT) if on else (r.vehicle.kart_bits & ~CarState.KART_OUT)
	if on or not r.towed:
		r.set_ghost(session.ghosted) # an out kart stays a ghost (Racer.set_ghost)


func _physics_process(delta: float) -> void:
	for r: Racer in _grace.keys():
		_grace[r] = maxf(0.0, float(_grace[r]) - delta)
	for r: Racer in _out_order:
		if r.vehicle and r.vehicle.kart_bits & CarState.KART_OUT == 0:
			r.vehicle.kart_bits |= CarState.KART_OUT # a new car after a swap
	if not authority or ended or session.race.phase != RaceControl.Phase.RUNNING:
		return
	var last_one := rule() == "standing" and session.racers.size() > 1 and standing().size() <= 1
	if last_one or time_left() <= 0.0:
		ended = true
		var order := standings()
		if not order.is_empty():
			order[0].notify("Winner", 4.0)
		session.race.end_session()


## The order now (RaceControl's standings in a battle).
func standings() -> Array[Racer]:
	var out: Array[Racer] = session.racers.duplicate()
	if rule() == "hits":
		out.sort_custom(func(a: Racer, b: Racer) -> bool:
			if hits(a) != hits(b):
				return hits(a) > hits(b)
			if taken(a) != taken(b):
				return taken(a) < taken(b)
			return a.number < b.number)
		return out
	out.sort_custom(func(a: Racer, b: Racer) -> bool:
		if a.out != b.out:
			return not a.out
		if a.out:
			return _out_order.find(a) > _out_order.find(b) # out later: ahead
		if lives(a) != lives(b):
			return lives(a) > lives(b)
		if hits(a) != hits(b):
			return hits(a) > hits(b)
		return a.number < b.number)
	return out


## The battle's columns for `r`'s results row.
func row(r: Racer) -> Dictionary:
	return { "lives": lives(r) if rule() == "standing" else -1, "hits": hits(r), "taken": taken(r), "out": r.out }
