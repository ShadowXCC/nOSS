class_name SumoAI
extends Node
## The sumo AI (D165): shoves the nearest car toward the edge, and keeps itself away from it.
## A disc needs no pathfinding, so this steers straight at its target rather than through
## ArenaNav, whose grid is built once per session and a shrinking platform would invalidate every
## tick. Skill sets its speed, how late it dares turn away from the edge, and how well it times
## its ram. Out, or falling, it stops trying. As a guide it works out controls for a player's
## assists.

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

var racer: Racer
var skill := 80.0
var as_guide := false
## What it's doing: "hunt", "edge" (backing off the rim) or "wait" (in the air, or out).
var intent := "wait"

var _target: Racer
var _plan_time := 0.0
var _stuck := 0.0
var _reverse := 0.0
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
	v.drift = false
	if bool(c.get("ram", false)):
		racer.session.sumo.ram(racer)


## This tick's controls: {steer, throttle, brake, handbrake, ram}, or {} without a car.
func controls(delta: float) -> Dictionary:
	var v := racer.vehicle
	var sumo: SumoControl = racer.session.sumo
	if v == null or not is_instance_valid(v) or sumo == null:
		return {}
	var out := { "steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": 0.0, "ram": false }
	if racer.held or racer.waiting or racer.out:
		out.handbrake = 1.0 if racer.held else 0.0
		intent = "wait"
		_stuck = 0.0
		return out
	var layout := sumo.layout
	var tier := layout.tier_at(racer.com())
	if tier < 0:
		# In the air between platforms: nothing to steer for, ride it out.
		intent = "wait"
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
	out.ram = intent == "hunt" and _should_ram(angle)
	return out


## Hunt the nearest car, unless the edge is coming up: then get off the rim first.
func _plan(tier: int) -> void:
	_target = _nearest()
	intent = "edge" if _near_edge(tier) else ("hunt" if _target else "edge")


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
	var layout: SumoLayout = racer.session.sumo.layout
	var radius := layout.radius_of(tier)
	var margin := radius - Vector2(racer.com().x, racer.com().z).length()
	var safety := lerpf(EDGE_SAFETY.x, EDGE_SAFETY.y, clampf(skill / 100.0, 0.0, 1.0))
	# Roughly how far it needs to turn away at this speed, with a floor for a standing car. Never
	# more than part of the platform, or on a shrunken one every spot would count as the edge and
	# it would circle the middle instead of fighting.
	var needed := minf(maxf(absf(racer.speed) * safety, 4.0), radius * 0.45)
	return margin < needed


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
