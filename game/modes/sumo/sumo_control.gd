class_name SumoControl
extends Node
## Sumo matches (D162) on stacked floating platforms: the shrink, the falls, the goo and the end
## of a match. A platform starts shrinking once a car is on it; the top one at the green light.
## When a platform has gone, whoever was on it falls to the next one down, or into the lava or
## acid. Touching the goo puts a car out, timed at the moment it touched: so with the floor
## vanishing under the last two, whoever holds on a fraction longer wins. No lives and no
## respawns -- the lower tiers are the second and third chances.
## The authority decides (offline: this game); RaceControl runs the lights and the results.

signal pushed_out(r: Racer)
signal tier_reached(r: Racer, tier: int)

## The goo pulls a car under over this long, this far down.
const SINK_S := 1.0
const SINK_DEPTH_M := 3.0
## Ram boost: the lunge it adds, and how long a full charge takes to come back.
const RAM_DV := 7.0
const RAM_RECHARGE_S := 5.0
## A ram only fires above this, so it is a shove and not a standing start.
const RAM_MIN_SPEED := 2.0
## Rising or falling faster than this it is passing through, not standing on anything: a car
## dropping between platforms crosses the one above's height band on its way down.
const LAND_VY := 2.0
## A car set down again after a Reset has no contact for this long.
const GHOST_AFTER_RESET := 1.0
## HUD elements a sumo match never shows: it has no laps, no sectors and no racing line.
const HUD_HIDDEN := ["timing", "delta", "position", "standings", "flags"]

var session: TrackSession
var layout: SumoLayout
var builder: SumoBuilder
var sounds: SumoSounds
var authority := true
var ended := false
## racer -> the tier it is on now (-1: in the air, or gone)
var _tier := {}
## racer -> the lowest tier it has stood on (its results row)
var _reached := {}
## The first out first.
var _out_order: Array[Racer] = []
## racer -> the race clock when it touched the goo
var _out_at := {}
## racer -> seconds of sinking left
var _sinking := {}
## racer -> ram charge, 0..1
var _charge := {}
## tier -> what set it going ("start" for the top one at the green light, else a car's name).
## Recorded as it happens, so the soak check reads a fact rather than sampling for it.
var armed_by := {}
var _started := false


func _ready() -> void:
	process_physics_priority = -53 # after RaceControl, before the drivers
	session.race.session_started.connect(func(_kind: String) -> void: reset())


## A new match: everyone back on the top platform, every platform its full size.
func reset() -> void:
	ended = false
	_started = false
	_tier.clear()
	_reached.clear()
	_out_order.clear()
	_out_at.clear()
	_sinking.clear()
	_charge.clear()
	armed_by.clear()
	layout.restore() # a restarted match gets its platforms back
	if builder:
		builder.refresh()
	for r in session.racers:
		_charge[r] = 1.0
		_set_out(r, false)


## Cars still in.
func standing() -> Array[Racer]:
	return session.racers.filter(func(r: Racer) -> bool: return not r.out)


## The tier `r` is on (0 is the top), or -1 in the air or in the goo.
func tier(r: Racer) -> int:
	return int(_tier.get(r, -1))


## The lowest platform `r` has stood on, for its results row.
func reached(r: Racer) -> int:
	return int(_reached.get(r, 0))


## The tier `r` is standing on, or -1: down on a platform's floor and not still falling. This is
## what starts a platform shrinking, and what the soak check counts as a landing.
func standing_on(r: Racer) -> int:
	var v := r.vehicle
	if v == null or not is_instance_valid(v) or absf(v.linear_velocity.y) > LAND_VY:
		return -1
	return layout.standing_on(r.com())


## `r`'s ram charge, 0..1 (the HUD meter).
func charge(r: Racer) -> float:
	return float(_charge.get(r, 0.0))


## Fires `r`'s ram: a lunge forward, spending the charge. Nothing if it is not full, if the car
## is too slow, or if the match is not running.
func ram(r: Racer) -> bool:
	if r.out or r.vehicle == null or not is_instance_valid(r.vehicle):
		return false
	if session.race.phase != RaceControl.Phase.RUNNING or float(_charge.get(r, 0.0)) < 1.0:
		return false
	var v := r.vehicle
	if absf(v.speed()) < RAM_MIN_SPEED:
		return false
	_charge[r] = 0.0
	# Mass-scaled, so the lunge is the same change in speed whatever the car weighs (KartItems).
	var dir := v.global_basis.z.slide(Vector3.UP).normalized()
	if dir.length() < 0.5:
		return false
	v.apply_central_impulse(dir * v.mass * RAM_DV)
	v.knocked_at = Time.get_ticks_msec() / 1000.0
	if sounds:
		sounds.ram(v.global_position)
	return true


func _physics_process(delta: float) -> void:
	_forget_gone()
	_hold_out()
	# Over every racer, not just the table's keys: a car that joined after the start has none yet.
	for r in session.racers:
		_charge[r] = minf(1.0, float(_charge.get(r, 1.0)) + delta / RAM_RECHARGE_S)
	_sink(delta)
	var running := session.race.phase == RaceControl.Phase.RUNNING
	if running and not _started:
		_started = true
		if not layout.armed(0):
			armed_by[0] = "start"
		layout.arm(0) # the top platform goes from the green light
	if running and authority and not ended:
		layout.advance(delta)
	if builder:
		builder.refresh()
	_follow_tiers(running)
	if not authority or ended or not running:
		return
	_check_goo()
	# One car left (or none: the goo took the last of them on the same tick).
	if session.racers.size() > 1 and standing().size() <= 1:
		ended = true
		var order := standings()
		if not order.is_empty() and not order[0].out:
			order[0].notify("Winner", 4.0)
		session.race.end_session()


## The authority's word stands. A remote car takes its `out` from the states its own game sends
## (NetRacer), so one still in flight when the server put the car out would clear the flag again;
## without a time limit to fall back on, that alone could leave a match with nobody to declare.
func _hold_out() -> void:
	if not authority:
		return
	for r: Racer in _out_order:
		if is_instance_valid(r) and not r.out:
			_set_out(r, true)


## Cars that left the game drop out of the tables (they stay in the results they were in).
func _forget_gone() -> void:
	_out_order.assign(_out_order.filter(func(r: Variant) -> bool: return is_instance_valid(r)))
	for d: Dictionary in [_tier, _reached, _out_at, _sinking, _charge]:
		for k: Variant in d.keys():
			if not is_instance_valid(k):
				d.erase(k)


## Where everyone is: a car that has just landed on a platform starts it shrinking.
func _follow_tiers(running: bool) -> void:
	for r in session.racers:
		if r.out or r.vehicle == null or not is_instance_valid(r.vehicle):
			continue
		var com := r.com()
		var at := layout.tier_at(com)
		# Down on the floor, not just falling past: that is what sets a platform going.
		if authority and running:
			var on := standing_on(r)
			if on >= 0 and not layout.armed(on):
				armed_by[on] = r.display_name
			layout.arm(on)
		var was := int(_tier.get(r, -1))
		_tier[r] = at
		if at < 0 or at == was:
			continue
		_reached[r] = maxi(reached(r), at)
		if was >= 0 or at > 0:
			tier_reached.emit(r, at)
			if at > 0:
				r.notify("Tier %d" % (at + 1), 2.0)


## A car in the goo is pulled under, then left there out of sight.
func _sink(delta: float) -> void:
	for r: Racer in _sinking.keys():
		var v: Variant = r.vehicle
		if not is_instance_valid(v):
			_sinking.erase(r)
			continue
		if (v as Vehicle).remote:
			_sinking.erase(r) # its own game sinks it; moving it here only fights the states coming in
			continue
		var left := float(_sinking[r]) - delta
		var car := v as Vehicle
		var to := layout.hazard_y - SINK_DEPTH_M
		var at := clampf(1.0 - maxf(left, 0.0) / SINK_S, 0.0, 1.0)
		var p := car.global_position
		car.global_transform = Transform3D(car.global_basis, Vector3(p.x, lerpf(layout.hazard_y, to, at), p.z))
		if left <= 0.0:
			_sinking.erase(r)
		else:
			_sinking[r] = left


## Anyone down in the goo is out. This is a height test rather than the hazard's Area3D, so it
## rules the same way on a dedicated server, where every car is a remote one the physics never
## really touches, as it does on a game driving its own.
func _check_goo() -> void:
	for r in session.racers:
		if r.out or r.vehicle == null or not is_instance_valid(r.vehicle):
			continue
		if r.com().y <= layout.hazard_y:
			_knock_out(r)


## Out: timed now, whatever the sinking looks like afterwards.
func _knock_out(r: Racer) -> void:
	if r.out:
		return
	_out_order.append(r)
	_out_at[r] = session.race.clock
	_tier[r] = -1
	_set_out(r, true)
	_start_sinking(r)
	r.notify("Out", 2.5)
	if sounds and r.vehicle:
		sounds.splash(r.vehicle.global_position)
	pushed_out.emit(r)
	if standing().size() == 1:
		var last := standing()[0]
		if not last.out:
			last.notify("Last one", 2.0)


func _start_sinking(r: Racer) -> void:
	var v := r.vehicle
	if v == null or not is_instance_valid(v) or v.remote:
		return # a car another game drives is sunk there, and its states say where it is
	_sinking[r] = SINK_S
	v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	v.freeze = true


func _set_out(r: Racer, on: bool) -> void:
	r.out = on
	if r.vehicle:
		r.vehicle.kart_bits = (r.vehicle.kart_bits | CarState.KART_OUT) if on else (r.vehicle.kart_bits & ~CarState.KART_OUT)
		if not on and r.vehicle.freeze:
			r.vehicle.freeze = false
	r.set_ghost(session.ghosted) # an out car stays a ghost (Racer.set_ghost)


## Nothing tows a car back onto a platform it was shoved off: that is the whole game. A Reset
## while still over one only sets the car down again, upright, where it last stood; off the
## platforms there is nowhere to put it, so it goes in.
func recover(r: Racer) -> void:
	if r.out:
		return
	var tier := layout.tier_at(r.com())
	if tier >= 0 and r.vehicle and is_instance_valid(r.vehicle) and not r.vehicle.remote:
		var at := r.last_valid_xform
		if layout.tier_at(at.origin) != tier:
			at = Transform3D(at.basis, Vector3(r.com().x, layout.floor_y_of(tier), r.com().z))
		r.vehicle.reset_to(at)
		r.ghost_for(GHOST_AFTER_RESET)
		return
	_knock_out(r)


## The order now (RaceControl's standings in a sumo match): cars still in first, by how high they
## are; then the ones that are out, the last one in ahead of the rest.
func standings() -> Array[Racer]:
	var out: Array[Racer] = session.racers.duplicate()
	out.sort_custom(func(a: Racer, b: Racer) -> bool:
		if a.out != b.out:
			return not a.out
		if a.out:
			return _out_order.find(a) > _out_order.find(b) # out later: ahead
		if tier(a) != tier(b):
			return tier(a) < tier(b) # higher platform: ahead
		return a.number < b.number)
	return out


## The sumo columns for `r`'s results row.
func row(r: Racer) -> Dictionary:
	return { "tier": reached(r) + 1, "lasted": float(_out_at.get(r, session.race.clock)), "out": r.out }


## Online client: car `r`'s tier and out as the server has them (SumoNet).
func apply_net(r: Racer, at_tier: int, is_out: bool) -> void:
	_tier[r] = at_tier
	if at_tier >= 0:
		_reached[r] = maxi(reached(r), at_tier)
	if is_out and not r.out:
		_knock_out(r)
	elif not is_out and r.out:
		_out_order.erase(r)
		_sinking.erase(r)
		_set_out(r, false)
