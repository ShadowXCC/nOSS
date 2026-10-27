class_name SumoAI
extends Node
## The sumo AI (D165): shoves the nearest car toward the edge, and keeps itself away from it.
## A disc needs no pathfinding, so this steers straight at its target rather than through
## ArenaNav, whose grid is built once per session and a shrinking platform would invalidate every
## tick. Skill sets its speed, how late it dares turn away from the edge, how well it times its
## ram and how often it pivot-drifts round to a car behind it (D220). Out, or falling, it stops
## trying. As a guide it works out controls for a player's assists.

const PLAN_HZ := 5.0
## Speed it chases at (m/s), skill 0 -> 100, and when it is turning hard.
const SPEED := Vector2(12.0, 18.0)
const TURN_SPEED := 6.0
## Nearer the edge than its stopping distance times this, it breaks off and heads in.
const EDGE_SAFETY := Vector2(2.6, 1.5) # skill 0 -> 100: the better it is, the later it turns
## It rams when the target is this close and this nearly straight ahead.
const RAM_M := 9.0
const RAM_CONE_DEG := 26.0
## Backing out of a shove that has gone nowhere.
const STUCK_S := 0.8
const REVERSE_S := 1.5
## The pivot drift (D220): never below this skill; at each plan, this chance of being ready for
## one (skill 25 -> 100). It starts one at a target this far off its nose, going this much over the
## drift's minimum speed, with the edge this many times its usual margin away (the better it is,
## the closer it dares); and holds full steer until the target is this near its nose, or for this
## long at most.
const DRIFT_SKILL := 25.0
const DRIFT_CHANCE := Vector2(0.3, 1.0)
const DRIFT_ANGLE_DEG := Vector2(95.0, 65.0)
const DRIFT_OVER := 1.0
const DRIFT_EDGE := Vector2(2.0, 1.3)
const DRIFT_DONE_DEG := 20.0
const DRIFT_MAX_S := 1.0

var racer: Racer
var skill := 80.0
var as_guide := false
## What it's doing: "hunt", "edge" (backing off the rim) or "wait" (in the air, or out).
var intent := "wait"

var _target: Racer
var _plan_time := 0.0
var _stuck := 0.0
var _reverse := 0.0
## Seconds of the pivot drift left, and whether it may start one now.
var _drift := 0.0
var _may_drift := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_physics_priority = -50
	_rng.seed = hash(racer.number) ^ 0x50de
	_plan_time = _rng.randf() / PLAN_HZ
	if as_guide or racer.vehicle == null:
		return
	var p := racer.vehicle.platform
	var allowed: Array = p.get("assists_allowed", [])
	var assists := {}
	for a in ["abs", "tcs", "stability", "auto_gearbox"]:
		assists[a] = a in allowed
	assists.auto_clutch = true
	racer.vehicle.sim.set_assists(assists)


func _physics_process(delta: float) -> void:
	if as_guide:
		return
	var c := controls(delta)
	if c.is_empty():
		return
	var v := racer.vehicle
	v.steer = c.steer
	v.throttle = c.throttle
	v.brake = c.brake
	v.handbrake = c.handbrake
	v.drift = c.drift
	if bool(c.get("ram", false)):
		racer.session.sumo.ram(racer)


## This tick's controls: {steer, throttle, brake, handbrake, drift, ram}, or {} without a car.
func controls(delta: float) -> Dictionary:
	var v := racer.vehicle
	var sumo: SumoControl = racer.session.sumo
	if v == null or not is_instance_valid(v) or sumo == null:
		return {}
	var out := { "steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": 0.0, "drift": false, "ram": false }
	if racer.held or racer.waiting or racer.out:
		out.handbrake = 1.0 if racer.held else 0.0
		intent = "wait"
		_stuck = 0.0
		_drift = 0.0
		return out
	var layout := sumo.layout
	var tier := layout.tier_at(racer.com())
	if tier < 0:
		# In the air between platforms: nothing to steer for, ride it out.
		intent = "wait"
		_drift = 0.0
		return out
	_plan_time -= delta
	if _plan_time <= 0.0:
		_plan_time += 1.0 / PLAN_HZ
		_plan(tier)
	if not as_guide and _unstick(out, delta):
		return out
	var goal := _goal(tier)
	var angle := _angle_to(goal)
	var max_steer := deg_to_rad(float(v.platform.steering.max_road_angle_deg))
	out.steer = clampf(-angle / max_steer * 0.7, -1.0, 1.0)
	var fast := lerpf(SPEED.x, SPEED.y, clampf(skill / 100.0, 0.0, 1.0))
	var want := lerpf(fast, TURN_SPEED, clampf(absf(angle) / deg_to_rad(80.0), 0.0, 1.0))
	var speed := racer.speed
	if speed < want - 0.5:
		out.throttle = clampf(0.4 + (want - speed) * 0.3, 0.0, 1.0)
	elif speed > want + 1.5:
		out.brake = clampf((speed - want) * 0.15, 0.0, 0.8)
	if _pivot(angle, tier, delta):
		# Round on the spot: full lock toward it, on the power (D220).
		out.drift = true
		out.steer = -signf(angle)
		out.throttle = maxf(out.throttle, 0.8)
		out.brake = 0.0
	out.ram = intent == "hunt" and _should_ram(angle)
	return out


## Hunt the nearest car, unless the edge is coming up: then get off the rim first.
func _plan(tier: int) -> void:
	_target = _nearest()
	intent = "edge" if _near_edge(tier) else ("hunt" if _target else "edge")
	var k := clampf((skill - DRIFT_SKILL) / (100.0 - DRIFT_SKILL), 0.0, 1.0)
	_may_drift = skill >= DRIFT_SKILL and _rng.randf() < lerpf(DRIFT_CHANCE.x, DRIFT_CHANCE.y, k)


## A pivot drift round to a target well off its nose (D220): only hunting, quick enough for the
## drift to take, with the drift allowed, and well clear of the edge. Held until the nose is on the
## target. True while it lasts.
func _pivot(angle: float, tier: int, delta: float) -> bool:
	if _drift > 0.0:
		_drift -= delta
		if _drift <= 0.0 or intent != "hunt" or absf(angle) < deg_to_rad(DRIFT_DONE_DEG):
			_drift = 0.0
			_may_drift = false # not straight into another: wait for the next plan
		return _drift > 0.0
	var v := racer.vehicle
	if not _may_drift or intent != "hunt" or not v.drift_allowed or v.arcade.is_empty():
		return false
	var k := clampf((skill - DRIFT_SKILL) / (100.0 - DRIFT_SKILL), 0.0, 1.0)
	if absf(angle) < deg_to_rad(lerpf(DRIFT_ANGLE_DEG.x, DRIFT_ANGLE_DEG.y, k)):
		return false
	if racer.speed < float(v.arcade.drift.min_speed) + DRIFT_OVER:
		return false
	var layout: SumoLayout = racer.session.sumo.layout
	if layout.edge_distance(racer.com()) < _edge_needed(tier) * lerpf(DRIFT_EDGE.x, DRIFT_EDGE.y, k):
		return false
	_drift = DRIFT_MAX_S
	return true


## Where it is heading: a little ahead of its target, or back toward the middle.
func _goal(tier: int) -> Vector3:
	var layout: SumoLayout = racer.session.sumo.layout
	var y := layout.floor_y_of(tier)
	if intent == "hunt" and _target and is_instance_valid(_target) and _target.vehicle:
		var lead := _target.com() + _target.vehicle.linear_velocity * 0.35
		return Vector3(lead.x, y, lead.z)
	return Vector3(0.0, y, 0.0)


## Too near the edge for the speed it is doing to pull away from it. The better the driver, the
## closer it will run.
func _near_edge(tier: int) -> bool:
	# The nearest edge of all: on a crumbling platform that counts the hole beside it, which is how
	# a bot keeps off a wedge bitten back under it instead of driving along the drop.
	return racer.session.sumo.layout.edge_distance(racer.com()) < _edge_needed(tier)


## Roughly how far from the edge it needs to be to turn away at this speed, with a floor for a
## standing car. Never more than part of the platform, or on a shrunken one every spot would count
## as the edge and it would circle the middle instead of fighting.
func _edge_needed(tier: int) -> float:
	var safety := lerpf(EDGE_SAFETY.x, EDGE_SAFETY.y, clampf(skill / 100.0, 0.0, 1.0))
	return minf(maxf(absf(racer.speed) * safety, 4.0), racer.session.sumo.layout.radius_of(tier) * 0.45)


## Worth spending the ram: the target is close, nearly straight ahead, and nearer the edge than
## this car is, so the shove sends it the right way.
func _should_ram(angle: float) -> bool:
	if _target == null or not is_instance_valid(_target) or _target.vehicle == null:
		return false
	if absf(angle) > deg_to_rad(RAM_CONE_DEG):
		return false
	var me := racer.com()
	if me.distance_to(_target.com()) > RAM_M:
		return false
	var layout: SumoLayout = racer.session.sumo.layout
	var tier := layout.tier_at(me)
	if tier < 0 or layout.tier_at(_target.com()) != tier:
		return false
	var mine := Vector2(me.x, me.z).length()
	var theirs := Vector2(_target.com().x, _target.com().z).length()
	return theirs >= mine


func _nearest() -> Racer:
	var me := racer.com()
	var layout: SumoLayout = racer.session.sumo.layout
	var tier := layout.tier_at(me)
	var best: Racer = null
	var best_d := INF
	for o: Racer in racer.session.racers:
		if o == racer or o.vehicle == null or not is_instance_valid(o.vehicle) or o.out or o.towed:
			continue
		# Only cars on the same platform are worth chasing.
		if layout.tier_at(o.com()) != tier:
			continue
		var d := me.distance_to(o.com())
		if d < best_d:
			best_d = d
			best = o
	return best


## Where `p` is from the car's nose (+ = to its left), radians.
func _angle_to(p: Vector3) -> float:
	var local := racer.vehicle.global_basis.inverse() * (p - racer.com())
	return atan2(local.x, local.z)


## Barely moving with the throttle on (nose to nose with someone): back off and come again.
func _unstick(out: Dictionary, delta: float) -> bool:
	if _reverse > 0.0:
		_reverse -= delta
		out.brake = 0.8 # the automatic selects reverse at a standstill
		out.steer = signf(_angle_to(_goal(racer.session.sumo.layout.tier_at(racer.com()))))
		return true
	if absf(racer.speed) < 1.0 and racer.vehicle.throttle > 0.3:
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck > STUCK_S:
		_stuck = 0.0
		_reverse = REVERSE_S
	return false
