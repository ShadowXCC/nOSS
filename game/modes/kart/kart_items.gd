class_name KartItems
extends Node
## Kart items (D139-D141): each racer's one slot, the boxes that fill it, using what's in it, and
## what items do to the karts they hit. A racer this game drives takes boxes and is hit here; the
## authority (offline: this game; online: the server) rolls what a box gives and rules on hits.

signal got(racer: Racer, item: String)
signal used(racer: Racer, item: String)
## An item hit `victim` (a Shield took it if `blocked`).
signal hit_landed(victim: Racer, attacker: Racer, kind: String, blocked: bool)

const ROULETTE_S := 1.2
const NITRO_S := 1.0
const NITRO_GAP_S := 0.3
const SHIELD_S := 8.0
const EMP_RADIUS_M := 18.0
const EMP_S := 2.0
const MAGNET_S := 3.0
const MAGNET_ACCEL := 4.0
const MAGNET_RANGE_M := 60.0
const MAGNET_SLIP := 3.0
const MAGNET_DONE_M := 3.0
const KNOCK := 3.0 # m/s from a Bolt, a Seeker or the Hunter
const AHEAD_M := 2.2 # fired from this far in front of (or behind) the kart's middle
const SLICK_BEHIND_M := 2.5
## Battle: Seekers and Magnets go for the nearest kart within this half-angle ahead.
const CONE_DEG := 30.0

var control: KartControl
var session: TrackSession
var boxes: KartBoxes
var entities: KartEntities
var odds: ItemOdds
var rng := RandomNumberGenerator.new()
## Racer -> {item, count, roulette, shield, magnet, magnet_target, nitro_gap}.
var slots := {}
var _since_hunter := INF


func _ready() -> void:
	process_physics_priority = -57


func slot(r: Racer) -> Dictionary:
	if not slots.has(r):
		slots[r] = { "item": "", "count": 0, "roulette": 0.0, "shield": 0.0, "magnet": 0.0, "magnet_target": null, "nitro_gap": 0.0 }
	return slots[r]


## What `r` holds ("" if nothing, or still rolling).
func item_of(r: Racer) -> String:
	var s := slot(r)
	return s.item if s.roulette <= 0.0 else ""


## This game drives `r`'s car: it takes boxes and is hit here.
func local(r: Racer) -> bool:
	return r.vehicle != null and is_instance_valid(r.vehicle) and not r.vehicle.remote


## A battle's grace after a hit (D144): items pass it by.
func _protected(r: Racer) -> bool:
	return session.battle != null and session.battle.protected(r)


func _usable(r: Racer) -> bool:
	return r.vehicle != null and not r.waiting and not r.towed and not r.held and not r.out and r.vehicle.kart_bits & CarState.KART_OUT == 0


func _physics_process(delta: float) -> void:
	_since_hunter += delta
	entities.step(delta)
	for r: Racer in session.racers:
		var s := slot(r)
		s.roulette = maxf(0.0, s.roulette - delta)
		s.nitro_gap = maxf(0.0, s.nitro_gap - delta)
		if s.shield > 0.0:
			s.shield = maxf(0.0, s.shield - delta)
		if r.vehicle:
			r.vehicle.kart_bits = (r.vehicle.kart_bits | CarState.KART_SHIELD) if s.shield > 0.0 else (r.vehicle.kart_bits & ~CarState.KART_SHIELD)
		if not local(r) or not _usable(r):
			continue
		var com := r.com()
		var box := boxes.near(com)
		if box >= 0:
			boxes.take(box)
			pick(r, box)
		if not _protected(r):
			for e in entities.touching(r, com):
				hit(r, e)
	_magnets(delta)


# --- boxes ---------------------------------------------------------------------------------

## `r` drove through box `box` (D140): a racer with nothing gets an item after the roulette; one
## already holding something gets nothing (the box breaks).
func pick(r: Racer, _box: int) -> void:
	var s := slot(r)
	if s.item != "":
		return
	give(r, _roll(r))


func give(r: Racer, item: String) -> void:
	var s := slot(r)
	s.item = item
	s.count = ItemOdds.count_of(item)
	s.roulette = ROULETTE_S
	if item == "leader_hunter":
		_since_hunter = 0.0
	got.emit(r, item)


func _roll(r: Racer) -> String:
	if session.battle:
		return odds.roll_battle(session.battle.lives_lost(r), rng)
	var karts := session.racers.size()
	var pos := session.race.race_place(r) if session.race else 1
	var place := float(pos - 1) / maxf(karts - 1, 1)
	return odds.roll(place, karts, rng, entities.count("leader_hunter") + _held("leader_hunter"), _since_hunter)


func _held(item: String) -> int:
	var n := 0
	for s: Dictionary in slots.values():
		n += 1 if s.item == item else 0
	return n


# --- using ---------------------------------------------------------------------------------

## `r` uses what it holds; `back`: the Bolt backwards, the Slick thrown ahead (D135).
func use(r: Racer, back := false) -> void:
	var s := slot(r)
	var item: String = s.item
	if item == "" or s.roulette > 0.0 or not _usable(r):
		return
	var v := r.vehicle
	var fwd := v.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var com := r.com()
	match item:
		"nitro", "nitro_x3":
			if s.nitro_gap > 0.0:
				return
			v.sim.kart_effect(VehicleSim.KART_BOOST, NITRO_S)
			s.nitro_gap = NITRO_GAP_S
		"oil_slick":
			if back:
				entities.spawn("oil_slick", r, com + Vector3.UP * 0.6, fwd, null, 0, true)
			else:
				entities.spawn("oil_slick", r, com - fwd * SLICK_BEHIND_M, fwd)
		"bolt":
			var dir := -fwd if back else fwd
			entities.spawn("bolt", r, com + dir * AHEAD_M, dir)
		"seeker":
			entities.spawn("seeker", r, com + fwd * AHEAD_M, fwd, _ahead_of(r, session.track.length / 2.0))
		"leader_hunter":
			entities.spawn("leader_hunter", r, com + fwd * AHEAD_M, fwd, _leader_for(r))
		"shield":
			s.shield = SHIELD_S
		"emp":
			for o: Racer in session.racers:
				if o != r and o.vehicle and not o.towed and not o.out and not _protected(o) and o.com().distance_to(com) <= EMP_RADIUS_M:
					hit_by(o, "emp", r)
		"magnet":
			s.magnet = MAGNET_S
			s.magnet_target = _ahead_of(r, MAGNET_RANGE_M)
	s.count -= 1
	if s.count <= 0:
		s.item = ""
	used.emit(r, item)


## The next car ahead of `r` within `reach` m: along the road on a track, the nearest within a
## cone ahead in an arena.
func _ahead_of(r: Racer, reach: float) -> Racer:
	if session.track.arena:
		var best: Racer = null
		var best_d := reach
		var fwd := r.vehicle.global_basis.z
		for o: Racer in session.racers:
			if o == r or o.vehicle == null or o.towed or o.out:
				continue
			var to := o.com() - r.com()
			var d := to.length()
			if d < best_d and fwd.dot(to / maxf(d, 0.01)) > cos(deg_to_rad(CONE_DEG)):
				best_d = d
				best = o
		return best
	for c in session.field.around(r, reach, 0.0):
		var o: Racer = c.racer
		if c.gap > 0.0 and not o.towed and not o.out and o.vehicle:
			return o
	return null


## The race's leader, or second place for the leader's own Hunter.
func _leader_for(r: Racer) -> Racer:
	var order := session.race.race_order() if session.race else session.racers
	for o: Racer in order:
		if o != r and o.vehicle:
			return o
	return null


# --- hits ----------------------------------------------------------------------------------

## Entity `e` reached `victim`'s car.
func hit(victim: Racer, e: Dictionary) -> void:
	entities.remove(e.id)
	hit_by(victim, String(e.kind), e.owner, e.vel)


## What an item does to `victim` (D139): a Shield takes the hit and goes; else a spin-out (and a
## knock from a Bolt, a Seeker or the Hunter), or EMP's power cut.
func hit_by(victim: Racer, kind: String, attacker: Racer, from_vel := Vector3.ZERO) -> void:
	var s := slot(victim)
	var v := victim.vehicle
	if v == null:
		return
	if s.shield > 0.0:
		s.shield = 0.0
		hit_landed.emit(victim, attacker, kind, true)
		return
	var arcade: Dictionary = v.arcade
	match kind:
		"emp":
			v.sim.kart_effect(VehicleSim.KART_SLOW, EMP_S, float(arcade.slow.power))
		_:
			v.sim.kart_effect(VehicleSim.KART_SPIN, float(arcade.spin.s), 1.0 if rng.randf() < 0.5 else -1.0)
			if kind != "oil_slick" and from_vel.length() > 0.1 and not v.remote:
				var dir := from_vel.normalized()
				dir.y = 0.0
				v.apply_central_impulse(dir.normalized() * v.mass * KNOCK)
	s.magnet = 0.0
	hit_landed.emit(victim, attacker, kind, false)


# --- magnets -------------------------------------------------------------------------------

## A Magnet pulls toward the tail of the car ahead with three times the slipstream, until it
## touches or its time is up (D139).
func _magnets(delta: float) -> void:
	for r: Racer in session.racers:
		var s := slot(r)
		if r.vehicle == null:
			continue
		var on: bool = s.magnet > 0.0
		if on:
			s.magnet = maxf(0.0, s.magnet - delta)
			var target: Racer = s.magnet_target
			if target == null or not is_instance_valid(target) or target.vehicle == null:
				target = _ahead_of(r, MAGNET_RANGE_M)
				s.magnet_target = target
			if target:
				var tail := target.vehicle.global_position - target.vehicle.global_basis.z * 2.5
				var to := tail - r.vehicle.global_position
				to.y = 0.0
				if to.length() < MAGNET_DONE_M or r.vehicle.last_hit == target.vehicle:
					s.magnet = 0.0
				elif local(r):
					r.vehicle.sim.set_kart_pull(to.normalized() * MAGNET_ACCEL)
		on = s.magnet > 0.0
		if not on and local(r) and control.slip_boost.has(r):
			r.vehicle.sim.set_kart_pull(Vector3.ZERO)
		if on:
			control.slip_boost[r] = MAGNET_SLIP
		else:
			control.slip_boost.erase(r)
		r.vehicle.kart_bits = (r.vehicle.kart_bits | CarState.KART_MAGNET) if on else (r.vehicle.kart_bits & ~CarState.KART_MAGNET)
