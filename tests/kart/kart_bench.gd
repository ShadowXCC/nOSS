extends Node
## Kart bench (M8, K0): the kart layer in the game's own physics (Jolt), headless.
##   tools/kart_bench.sh --scenario=loop|wall|bounce [--speeds=10,15,20,25,30] [--radius=9] [--car=res://content/cars/noss_box]
## loop    a scripted kart takes a loop (stick gravity, D133) at each speed: does it get round,
##         and does it land in the exit lane?
## wall    a kart driven along a 90° wall at each speed: how far it rides it.
## bounce  a kart into a wall at each speed: how fast it comes back, and whether it buzzes when
##         pushed against it.

const WIDTH := 5.0
const Z0 := 80.0

var opts := { "scenario": "loop", "speeds": "10,15,20,25,30", "radius": "9", "car": "res://content/cars/noss_box",
	"platform": "official.kart.medium", "shift": "6.5", "verbose": "" }
var platform: PlatformLoader.Result
var arcade: Dictionary
var pkg: VehiclePackage
var world: Node3D
var kart: Vehicle
var speeds: Array[float] = []
var results: Array[String] = []
var failed := 0
var _run := -1
var _ticks := 0
var _state := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	platform = PlatformLoader.load_official(String(opts.platform))
	arcade = GameModes.arcade(GameModes.mode_for(String(opts.platform)))
	pkg = PackageLoader.load_package(String(opts.car))
	if not platform.ok() or pkg == null or arcade.is_empty():
		print("FAIL: platform, car or layer")
		get_tree().quit(1)
		return
	for s in String(opts.speeds).split(","):
		speeds.append(float(s))
	get_tree().physics_frame.connect(_tick)
	_next.call_deferred()


func _next() -> void:
	if world:
		world.queue_free()
	_run += 1
	if _run >= speeds.size():
		print("\n".join(results))
		print("%s: %d of %d runs failed" % ["PASS" if failed == 0 else "FAIL", failed, speeds.size()])
		get_tree().quit(1 if failed else 0)
		return
	world = Node3D.new()
	add_child(world)
	_ground()
	match String(opts.scenario):
		"loop":
			_loop()
		"wall":
			_wall()
		"bounce":
			_bounce_wall()
	kart = Vehicle.create(platform, PackageLoader.copy(pkg))
	world.add_child(kart)
	kart.set_arcade(arcade)
	var v := speeds[_run]
	match String(opts.scenario):
		"loop":
			kart.reset_to(Transform3D(Basis(), Vector3(0, 0, 0)), Vector3(0, 0, v))
		"wall":
			# On the wall already, its wheels on it, going along it.
			var b := Basis(Vector3(0, 0, 1), PI / 2.0) # up = -x: the wall's face
			kart.reset_to(Transform3D(b, Vector3(10.5, 3.0, 0.0)), Vector3(0, 0, v))
		"bounce":
			kart.reset_to(Transform3D(Basis(), Vector3(0, 0, 0)), Vector3(0, 0, v))
	_ticks = 0
	_state = { "top": false, "max_y": 0.0, "min_contact": 4, "done": false, "fell": false, "back": 0.0, "buzz": 0.0, "hit": false }


func _ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Vehicle.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 600.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 200.0)
	body.add_child(shape)
	world.add_child(body)


func _tagged_body(b: MeshBatch, tag: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Vehicle.LAYER_WORLD
	body.set_meta(&"noss_surface", VehicleSim.SURFACE_CONCRETE)
	body.set_meta(&"noss_tag", tag)
	var cs := CollisionShape3D.new()
	cs.shape = b.shape()
	body.add_child(cs)
	world.add_child(body)


## A loop of radius R in the plane x = const, entered at z = Z0 on the ground; it drifts sideways
## by `shift` so the exit lies beside the entry.
func _loop() -> void:
	var r := float(opts.radius)
	var shift := float(opts.shift)
	var b := MeshBatch.new()
	var n := 96
	for i in n:
		var p0 := _loop_point(r, shift, float(i) / n)
		var p1 := _loop_point(r, shift, float(i + 1) / n)
		var x := Vector3(WIDTH * 0.5, 0, 0)
		# Seen from inside the loop (the driving face): counter-clockwise.
		b.quad([p0 + x, p0 - x, p1 - x, p1 + x], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	_tagged_body(b, VehicleSim.TAG_STICK)


func _loop_point(r: float, shift: float, t: float) -> Vector3:
	var a := TAU * t
	return Vector3(shift * t, r - r * cos(a), Z0 + r * sin(a))


## A vertical wall facing -x at x = 10.5, 8 m high, 300 m long.
func _wall() -> void:
	var b := MeshBatch.new()
	var x := 10.5
	b.quad([Vector3(x, 0, -10), Vector3(x, 0, 290), Vector3(x, 8, 290), Vector3(x, 8, -10)], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	_tagged_body(b, VehicleSim.TAG_STICK)


## A concrete barrier across the road at z = 40.
func _bounce_wall() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Vehicle.LAYER_WORLD
	body.set_meta(&"noss_surface", VehicleSim.SURFACE_CONCRETE)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.2, 1.0)
	cs.shape = box
	cs.position = Vector3(0, 0.6, 40.5)
	body.add_child(cs)
	world.add_child(body)


func _tick() -> void:
	if kart == null or not is_instance_valid(kart) or _state.is_empty() or _state.done:
		return
	_ticks += 1
	var v := speeds[_run]
	var p := kart.global_position
	var b := kart.global_basis
	var speed := kart.linear_velocity.length()
	var contacts := int(kart.sim.get_kart_state().grounded)
	match String(opts.scenario):
		"loop":
			_drive_loop(v, p, b, speed, contacts)
		"wall":
			_drive_wall(v, p, b, speed, contacts)
		"bounce":
			_drive_bounce(v, p, b)
	if opts.verbose and _ticks % 30 == 0:
		print("  t %.2f p %s up %s v %.1f contacts %d stick %.2f hull %.1f" % [_ticks / 120.0, p.snapped(Vector3.ONE * 0.01), b.y.snapped(Vector3.ONE * 0.01), speed, contacts, float(kart.sim.get_kart_state().stick), kart.wall_impulse])


func _drive_loop(v: float, p: Vector3, b: Basis, speed: float, contacts: int) -> void:
	var r := float(opts.radius)
	var shift := float(opts.shift)
	_state.max_y = maxf(_state.max_y, p.y)
	if p.y > 2.0 * r - 1.5:
		_state.top = true
	if p.y > 1.0 and p.z > Z0 - r:
		_state.min_contact = mini(_state.min_contact, contacts)
	# Where along the loop the kart is (0..1), for the lane it should be in.
	var t := 0.0
	if p.z > Z0 - 1.0 and p.y > 0.5:
		_state.in_loop = true
	if _state.get("in_loop", false):
		t = clampf(fposmod(atan2(p.z - Z0, r - p.y), TAU) / TAU, 0.0, 1.0)
		if _state.top and t < 0.5:
			t = 1.0 # back down past the bottom
	if _state.top and p.y < 0.6:
		t = 1.0
	var lane := shift * t
	# Inside the loop its path leans sideways by shift / (2 pi r) per metre.
	var lean := shift / (TAU * r) if t > 0.0 and t < 1.0 else 0.0
	kart.steer = clampf(0.3 * (p.x - lane) + 2.0 * (b.z.x - lean), -1.0, 1.0)
	_state.scrape = float(_state.get("scrape", 0.0)) + kart.wall_impulse
	if opts.verbose and _ticks % 15 == 0 and p.z > Z0 - 2.0:
		print("    t %.3f lane %.2f x %.2f heading_x %.3f lean %.3f steer %.2f" % [t, lane, p.x, b.z.x, lean, kart.steer])
	kart.throttle = clampf((v - speed) * 0.5, 0.0, 1.0)
	kart.brake = 0.0
	var ok: bool = _state.top and p.y < 0.6 and p.z > Z0 + 25.0
	var fell: bool = p.y < -2.0 or (p.y < 0.6 and not _state.top and p.z > Z0 + 25.0) or _ticks > 120 * 20
	if ok or fell:
		var lateral := p.x - shift
		var good: bool = ok and absf(lateral) < WIDTH * 0.5 and b.y.y > 0.9
		failed += 0 if (good or v < 15.0) else 1
		results.append("loop R %s at %4.1f m/s: %s, top %.1f m, exit lane %+.2f m, upright %.2f, fewest wheels down %d, end speed %.1f, hull scrape %.0f N s" % [
			opts.radius, v, "round" if good else "FAILED", _state.max_y, lateral, b.y.y, _state.min_contact, speed, _state.get("scrape", 0.0)])
		_state.done = true
		_next.call_deferred()


func _drive_wall(v: float, p: Vector3, b: Basis, speed: float, contacts: int) -> void:
	# Keep along the wall: steer away from the wall a touch if it creeps up.
	kart.steer = clampf(-0.05 * (p.y - 3.0) + 1.5 * b.z.y, -1.0, 1.0)
	kart.throttle = clampf((v - speed) * 0.5, 0.0, 1.0)
	var on_wall := absf(p.x - 10.5) < 1.5 and b.y.x < -0.8
	if not on_wall or p.z > 200.0 or _ticks > 120 * 20:
		var good := p.z >= 50.0
		failed += 0 if (good or v < 15.0) else 1
		results.append("wall at %4.1f m/s: rode %.0f m%s (height %.1f m, speed %.1f)" % [v, p.z, "" if good else " FAILED", p.y, speed])
		_state.done = true
		_next.call_deferred()


func _drive_bounce(v: float, p: Vector3, b: Basis) -> void:
	kart.steer = 0.0
	if not _state.hit:
		kart.throttle = clampf((v - kart.linear_velocity.z) * 0.5, 0.0, 1.0)
		if kart.wall_impulse > 0.0:
			_state.hit = true
			_state.hit_tick = _ticks
	else:
		var since: int = _ticks - int(_state.hit_tick)
		if since < 60:
			kart.throttle = 0.0
			_state.back = maxf(_state.back, -kart.linear_velocity.z)
		else:
			if since == 60: # now at rest against the wall, pushing into it: it shouldn't buzz
				kart.reset_to(Transform3D(Basis(), Vector3(0, 0, 40.0 - kart.fitted.envelope.end.z - 0.05)))
			kart.throttle = 1.0
			if since > 120:
				_state.buzz = maxf(_state.buzz, absf(kart.linear_velocity.z))
			if opts.verbose and since % 6 == 0:
				print("    since %d vz %.2f z %.2f wall %.1f" % [since, kart.linear_velocity.z, kart.global_position.z, kart.wall_impulse])
		if since > 300:
			var ratio: float = _state.back / v
			results.append("bounce at %4.1f m/s: back at %.1f m/s (%.2f of it), pushing against it %.2f m/s" % [v, _state.back, ratio, _state.buzz])
			_state.done = true
			_next.call_deferred()
	if _ticks > 120 * 20:
		_state.done = true
		results.append("bounce at %.1f: no hit" % v)
		failed += 1
		_next.call_deferred()
