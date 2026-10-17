class_name EndlessTraffic
extends Node
## Traffic on the endless road (docs/GAMEMODES.md §4, AI-03, D158): light, both ways (oncoming can
## be off). Nothing is simulated far away: each lane has a speed along the road (bends, braking
## before them, pulling away after, from the generator) and the time a car takes to get anywhere
## at it; car j of a lane left the start at time tau_j (a steady spacing with some spread from the
## seed), so where every car is at any time is worked out, the same on every game, and no two in a
## lane ever meet. Cars near a player become physics cars (EndlessTrafficCar) that keep to their
## slot unless something's in the way; knocked or left far behind, a car leaves its slot (the slot
## stays empty) and goes once nobody's near. Cars further off are drawn, one MultiMesh per type.

const UP := 0 # toward higher distances (the players' way)
const DOWN := 1 # oncoming
## Mean seconds between cars in a lane, by setting; a share of slots left empty for uneven gaps.
const HEADWAY_S := { "light": 48.0, "normal": 20.0 }
const SPREAD := 0.8
const EMPTY_SHARE := 0.15
## Drawn within this of a camera; physics cars within PROMOTE_M of a player, back into the schedule
## past DEMOTE_M once on their slot; a car that left its slot goes past GONE_M.
const VIEW_M := 1500.0
const PROMOTE_M := 140.0
const DEMOTE_M := 220.0
const GONE_M := 260.0
const MAX_PHYSICS := 12

var session: TrackSession
var world: EndlessWorld
var seed := 1
var density := "light"
var oncoming := true
## Seconds on the traffic's clock (online: the server's, D159). Unset: this node's own.
var clock := Callable()
## Physics cars by slot key (Vector2i(lane, j)).
var cars := {}
## Slots left behind by cars knocked out of them (never drawn again).
var gone := {}

var _types: Array[Dictionary] = []
var _weights := 0
var _platforms := {}
var _packages := {}
var _views: Array[MultiMeshInstance3D] = []
var _time := 0.0
var _slots := {} # slot key -> {present, tau, type, color} (made from the seed, kept a while)
var _draws := true


func _ready() -> void:
	name = "EndlessTraffic"
	process_physics_priority = -58
	_draws = not (session.dedicated or Game.dev.has("bot"))
	for t: Dictionary in TrafficTypes.list():
		if int(t.weight) > 0:
			_types.append(t)
			_weights += int(t.weight)
	for i in _types.size():
		_platforms[i] = PlatformLoader.load_official(String(_types[i].platform))
		var pkg := PackageLoader.load_package("res://content/traffic/" + String(_types[i].model), {}, {} if _draws else { "models": "none", "audio": false })
		if pkg.ok():
			_packages[i] = pkg
	if _draws:
		for i in _types.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = TrafficModels.far_mesh(TrafficTypes.index_of(String(_types[i].id)))
			mm.instance_count = 48
			mm.visible_instance_count = 0
			var view := MultiMeshInstance3D.new()
			view.name = "Traffic_" + String(_types[i].id)
			view.multimesh = mm
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			view.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
			add_child(view)
			_views.append(view)


func _exit_tree() -> void:
	for t: int in _packages:
		(_packages[t] as VehiclePackage).free_scenes()


func now() -> float:
	return float(clock.call()) if clock.is_valid() else _time


func headway() -> float:
	return float(HEADWAY_S.get(density, 48.0))


func _physics_process(delta: float) -> void:
	_time += delta
	_promote_near()
	if _slots.size() > 2000:
		_slots.clear()


func _process(_delta: float) -> void:
	if _draws:
		_draw()


# --- the schedule --------------------------------------------------------------------------------


## Slot (lane, j): whether a car's in it, when it left (s, on the lane's clock), its type and colour.
func slot(lane: int, j: int) -> Dictionary:
	var key := Vector2i(lane, j)
	if not _slots.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = (seed * 1000003 + lane * 7919 + j) & 0x7FFFFFFFFFFFFFFF
		var tau := headway() * (float(j) + SPREAD * rng.randf())
		var present := rng.randf() >= EMPTY_SHARE
		var pick := rng.randi_range(0, _weights - 1)
		var type := 0
		for i in _types.size():
			pick -= int(_types[i].weight)
			if pick < 0:
				type = i
				break
		var colors := TrafficTypes.colors(TrafficTypes.index_of(String(_types[type].id)))
		_slots[key] = { "present": present, "tau": tau, "type": type, "color": colors[rng.randi_range(0, colors.size() - 1)] }
	return _slots[key]


## Every scheduled car in the road window now: [{key, lane, s (absolute m), speed, type, color}].
func scheduled() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var road := world.road
	if road.samples.size() < 2:
		return out
	var t := now()
	var h := headway()
	for lane in [UP, DOWN] if oncoming else [UP]:
		var times := road.time_up if lane == UP else road.time_down
		var t_a := times[0]
		var t_b := times[-1]
		# Up: tau = t - T(s); down: tau = t + T(s).
		var lo := (t - t_b) if lane == UP else (t + t_a)
		var hi := (t - t_a) if lane == UP else (t + t_b)
		for j in range(floori(lo / h) - 1, ceili(hi / h) + 1):
			var key := Vector2i(lane, j)
			if gone.has(key) or cars.has(key):
				continue
			var sl := slot(lane, j)
			if not sl.present:
				continue
			var tq: float = (t - float(sl.tau)) if lane == UP else (float(sl.tau) - t)
			if tq < t_a or tq > t_b:
				continue
			var i := _index_at_time(times, tq)
			var u := (tq - times[i]) / maxf(times[i + 1] - times[i], 1e-6)
			var s := road.offset_m + (i + u) * TrackData.SAMPLE_M
			var speed := lerpf((road.speed_up if lane == UP else road.speed_down)[i], (road.speed_up if lane == UP else road.speed_down)[i + 1], u)
			out.append({ "key": key, "lane": lane, "s": s, "speed": speed, "type": sl.type, "color": sl.color })
	return out


## Where slot `key`'s car should be now (absolute m), or NAN outside the window.
func slot_s(key: Vector2i) -> float:
	var road := world.road
	var sl := slot(key.x, key.y)
	var times := road.time_up if key.x == UP else road.time_down
	var tq: float = (now() - float(sl.tau)) if key.x == UP else (float(sl.tau) - now())
	if road.samples.size() < 2 or tq < times[0] or tq > times[-1]:
		return NAN
	var i := _index_at_time(times, tq)
	var u := (tq - times[i]) / maxf(times[i + 1] - times[i], 1e-6)
	return road.offset_m + (i + u) * TrackData.SAMPLE_M


## The traffic speed of a lane at distance `s`.
func lane_speed(lane: int, s: float) -> float:
	var road := world.road
	var i := road.index_at(s)
	return (road.speed_up if lane == UP else road.speed_down)[i]


static func _index_at_time(times: PackedFloat64Array, t: float) -> int:
	var lo := 0
	var hi := times.size() - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if times[mid] <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


## A car in `lane` at distance `s`, facing its way, on its lane's centre.
func pose(lane: int, s: float) -> Transform3D:
	var road := world.road
	var lane_w := road.half_width(s, 1.0) - RoadWindow.SHOULDER_M
	var xf := road.transform_at(s, (-0.5 if lane == UP else 0.5) * lane_w)
	if lane == DOWN:
		xf.basis = xf.basis.rotated(xf.basis.y, PI)
	return xf


# --- for drivers ---------------------------------------------------------------------------------


## The nearest car ahead of distance `d` in the lane going the players' way (`up_lane`) or the
## other (`up_lane` false: the oncoming lane, which a passing car is in): {gap (m), speed (m/s, its
## speed along the road the player's way)}, or {}.
func ahead(d: float, up_lane: bool, max_gap: float) -> Dictionary:
	var best := {}
	var best_gap := max_gap
	for c in scheduled() + _physics_list():
		if (c.lane == UP) != up_lane:
			continue
		var gap := float(c.s) - d - 4.5
		if gap > -2.0 and gap < best_gap:
			best_gap = gap
			best = { "gap": maxf(gap, 0.0), "speed": float(c.speed) * (1.0 if c.lane == UP else -1.0), "what": c.key }
	return best


## Where slot `key`'s car is now: its physics car's spot, or its slot's; NAN if gone.
func position_of(key: Vector2i) -> float:
	if cars.has(key):
		var c: EndlessTrafficCar = cars[key]
		return c.s if c.vehicle and is_instance_valid(c.vehicle) else NAN
	if gone.has(key):
		return NAN
	return slot_s(key)


## Whether an oncoming car is anywhere between d0 and d1 (passing isn't safe then).
func oncoming_within(d0: float, d1: float) -> bool:
	if not oncoming:
		return false
	for c in scheduled() + _physics_list():
		if c.lane == DOWN and float(c.s) >= d0 and float(c.s) <= d1:
			return true
	return false


func _physics_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: Vector2i in cars:
		var c: EndlessTrafficCar = cars[key]
		if c.vehicle and is_instance_valid(c.vehicle):
			out.append({ "key": key, "lane": key.x, "s": c.s, "speed": c.speed })
	return out


# --- physics cars --------------------------------------------------------------------------------


func _players() -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in session.players:
		if p.vehicle and is_instance_valid(p.vehicle):
			out.append(p.vehicle.global_position)
	return out


func _promote_near() -> void:
	var players := _players()
	if players.is_empty():
		return
	for c: Dictionary in scheduled():
		if cars.size() >= MAX_PHYSICS:
			break
		var xf := pose(c.lane, c.s)
		var near := INF
		for p in players:
			near = minf(near, p.distance_to(xf.origin))
		if near < PROMOTE_M:
			_promote(c, xf)
	for key: Vector2i in cars.keys():
		var car: EndlessTrafficCar = cars[key]
		if car.vehicle == null or not is_instance_valid(car.vehicle):
			cars.erase(key)
			continue
		var near := INF
		for p in players:
			near = minf(near, p.distance_to(car.vehicle.global_position))
		var on_slot := not car.left_slot and absf(car.s - slot_s(key)) < 4.0
		if (on_slot and near > DEMOTE_M) or (car.left_slot and near > GONE_M) or is_nan(slot_s(key)) and near > DEMOTE_M:
			if car.left_slot:
				gone[key] = true
			car.vehicle.queue_free()
			car.queue_free()
			cars.erase(key)


func _promote(c: Dictionary, xf: Transform3D) -> void:
	var type: int = c.type
	if not _packages.has(type) or not (_platforms[type] as PlatformLoader.Result).ok():
		return
	var v := Vehicle.create(_platforms[type], PackageLoader.copy(_packages[type]))
	v.name = "EndlessTraffic%d_%d" % [c.key.x, c.key.y]
	v.visual_every_frame = true
	session.add_child(v)
	if v.visual:
		v.visual.set_paint("primary", c.color, "metallic")
	v.reset_to(xf, xf.basis.z * float(c.speed))
	var car := EndlessTrafficCar.new()
	car.traffic = self
	car.key = c.key
	car.vehicle = v
	car.s = c.s
	car.speed = c.speed
	add_child(car)
	cars[c.key] = car


# --- drawing -------------------------------------------------------------------------------------


func _draw() -> void:
	var cams := PackedVector3Array()
	for p in session.players:
		if p.cameras and p.cameras.camera:
			cams.append(p.cameras.camera.global_position)
	var lights := session.env != null and session.env.lights_on
	var counts := PackedInt32Array()
	counts.resize(_views.size())
	for c: Dictionary in scheduled():
		var t: int = c.type
		if t >= _views.size():
			continue
		var xf := pose(c.lane, c.s)
		var seen := cams.is_empty()
		for cam in cams:
			seen = seen or cam.distance_to(xf.origin) < VIEW_M
		if not seen:
			continue
		var mm := _views[t].multimesh
		var n := counts[t]
		if n >= mm.instance_count:
			continue
		mm.set_instance_transform(n, xf)
		mm.set_instance_color(n, c.color)
		mm.set_instance_custom_data(n, Color(float(TrafficModels.HEAD if lights else 0), 0, 0, 0))
		counts[t] = n + 1
	for t in _views.size():
		_views[t].multimesh.visible_instance_count = counts[t]
