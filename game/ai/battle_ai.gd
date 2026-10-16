class_name BattleAI
extends Node
## The battle AI (D144): round an arena by ArenaNav's paths, through the same controls as a
## player. With nothing in hand it goes for the nearest item boxes; with something to fire it
## hunts the nearest kart; otherwise (and once out) it roams. Items through ItemPolicy, like the
## kart AI; stuck, it backs out, and if that fails it calls the tow. Skill sets its speed, its
## aim and how soon it uses things. As a guide it works out controls for a player's assists.

const PLAN_HZ := 5.0
## Speed on the way (m/s), skill 0 -> 100, and in tight turns.
const SPEED := Vector2(13.0, 19.0)
const TURN_SPEED := 7.0
const LOOK_M := 6.0
const ATTACK := ["bolt", "seeker", "emp", "magnet"]
const STUCK_S := 0.8
const REVERSE_S := 2.0
## A goal behind it and no room ahead: a three-point turn.
const ROOM_M := 3.0
const TOW_AFTER_S := 6.0

var racer: Racer
var skill := 80.0
var as_guide := false
## What it's doing: "box", "hunt" or "roam" (tests and the check).
var intent := "roam"
var items := ItemPolicy.new()

var _nav: ArenaNav
var _path := PackedVector3Array()
var _at := 0 # the next path point
var _goal := Vector3.INF
var _plan_time := 0.0
var _stuck := 0.0
var _stuck_total := 0.0
var _reverse := 0.0
var _rng := RandomNumberGenerator.new()
var _last_intent := ""


func _ready() -> void:
	process_physics_priority = -50
	_rng.seed = hash(racer.number) ^ 0xba77
	_plan_time = _rng.randf() / PLAN_HZ
	items.racer = racer
	items.skill = skill
	items.rng.seed = hash(racer.number) ^ 0x17e5
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
	var kart := racer.session.kart
	if kart and not racer.held and not racer.out:
		var back: Variant = items.think(delta)
		if back != null:
			kart.use(racer, bool(back))


## This tick's controls: {steer, throttle, brake, handbrake}, or {} without a car.
func controls(delta: float) -> Dictionary:
	var v := racer.vehicle
	if v == null or not is_instance_valid(v) or racer.session.track.arena == null:
		return {}
	var out := { "steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": 0.0 }
	if racer.held or racer.waiting or racer.towed:
		out.handbrake = 1.0 if racer.held else 0.0
		_stuck = 0.0
		return out
	if _nav == null:
		_nav = ArenaNav.for_session(racer.session)
	_plan_time -= delta
	if _plan_time <= 0.0:
		_plan_time += 1.0 / PLAN_HZ
		_plan()
	if not as_guide and _unstick(out, delta):
		return out
	var angle := _angle_to(_aim_point())
	if not as_guide and absf(angle) > deg_to_rad(100.0) and absf(racer.speed) < 3.0:
		var fwd := v.global_basis.z.slide(Vector3.UP).normalized()
		if not _nav.open(_nav.cell_of(racer.com() + fwd * ROOM_M)):
			_reverse = REVERSE_S
			_unstick(out, 0.0)
			return out
	var max_steer := deg_to_rad(float(v.platform.steering.max_road_angle_deg))
	out.steer = clampf(-angle / max_steer * 0.7, -1.0, 1.0)
	var fast := lerpf(SPEED.x, SPEED.y, clampf(skill / 100.0, 0.0, 1.0)) * (0.6 if racer.out else 1.0)
	var want := lerpf(fast, TURN_SPEED, clampf(absf(angle) / deg_to_rad(80.0), 0.0, 1.0))
	if absf(angle) > deg_to_rad(110.0) and racer.speed < 6.0:
		want = TURN_SPEED # turning round
	var speed := racer.speed
	if speed < want - 0.5:
		out.throttle = clampf(0.4 + (want - speed) * 0.3, 0.0, 1.0)
	elif speed > want + 1.5:
		out.brake = clampf((speed - want) * 0.15, 0.0, 0.8)
	return out


## Picks what to go for and the way there.
func _plan() -> void:
	var goal := Vector3.INF
	var kart := racer.session.kart
	var held: String = kart.items.slot(racer).item if kart else ""
	intent = "roam"
	if not racer.out and kart:
		if held == "":
			goal = _nearest_box()
			intent = "box"
		elif held in ATTACK:
			var target := _nearest_kart()
			if target:
				# A little ahead of where it's going.
				goal = target.com() + target.vehicle.linear_velocity * 0.4
				intent = "hunt"
	if goal == Vector3.INF:
		if _goal == Vector3.INF or racer.com().distance_to(_goal) < 6.0 or intent != _last_intent:
			goal = _roam_point()
		else:
			goal = _goal
	_last_intent = intent
	if _goal == Vector3.INF or goal.distance_to(_goal) > 2.0 or _path.is_empty():
		_goal = goal
		_path = _nav.path(racer.com(), goal)
		_at = 0



## A point `LOOK_M` along the path (the goal itself near the end).
func _aim_point() -> Vector3:
	var me := racer.com()
	while _at < _path.size() - 1 and Vector2(_path[_at].x - me.x, _path[_at].z - me.z).length() < LOOK_M:
		_at += 1
	if _at < _path.size():
		return _path[_at]
	return _goal if _goal != Vector3.INF else me + racer.vehicle.global_basis.z * 10.0


func _nearest_box() -> Vector3:
	var boxes := racer.session.kart.boxes
	var me := racer.com()
	var best := Vector3.INF
	var best_d := INF
	for i in boxes.count():
		if not boxes.alive[i]:
			continue
		var d := me.distance_to(boxes.points[i])
		if d < best_d:
			best_d = d
			best = boxes.points[i]
	return best


func _nearest_kart() -> Racer:
	var me := racer.com()
	var best: Racer = null
	var best_d := INF
	for o: Racer in racer.session.racers:
		if o == racer or o.vehicle == null or o.towed or o.out:
			continue
		var d := me.distance_to(o.com())
		if d < best_d:
			best_d = d
			best = o
	return best


func _roam_point() -> Vector3:
	var a := racer.session.track.arena
	for i in 20:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		var at := a.centre + dir * a.reach(dir) * _rng.randf_range(0.2, 0.75)
		var p := Vector3(at.x, a.floor_y, at.y)
		if _nav.open(_nav.cell_of(p)):
			return p
	return Vector3(a.centre.x, a.floor_y, a.centre.y)


## Where `p` is from the kart's nose (+ = to its left), radians.
func _angle_to(p: Vector3) -> float:
	var local := racer.vehicle.global_basis.inverse() * (p - racer.com())
	return atan2(local.x, local.z)


## Barely moving with the throttle on: back out, the nose swinging toward where it's going; stuck
## for long (all told), the tow. (The automatic takes a moment to find reverse.)
func _unstick(out: Dictionary, delta: float) -> bool:
	if _reverse > 0.0:
		_reverse -= delta
		out.brake = 0.8 # the automatic selects reverse at a standstill
		out.steer = signf(_angle_to(_aim_point())) # backing up, steering right swings the nose left
		if _reverse <= 0.0:
			_path = PackedVector3Array() # a new way from here
		return true
	if absf(racer.speed) < 1.0 and racer.vehicle.throttle > 0.3:
		_stuck += delta
		_stuck_total += delta
	else:
		_stuck = 0.0
		_stuck_total = maxf(0.0, _stuck_total - delta * 0.5)
	if _stuck_total > TOW_AFTER_S:
		_stuck_total = 0.0
		_stuck = 0.0
		racer.reset_car()
		return false
	if _stuck > STUCK_S:
		_stuck = 0.0
		_reverse = REVERSE_S
	return false
