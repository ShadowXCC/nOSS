class_name TrafficManager
extends Node
## A highway session's traffic (D108-D110, D120): the lane sim (NossTraffic) stepped 20 times a
## second; distant traffic drawn from it, one MultiMesh per type; traffic near players turned into
## physics cars (TrafficCar) and back into the lane sim when nobody is near; wrecks left where they
## stopped until towed; stand-in boxes for lane cars right next to a player that aren't physics
## cars (yet); and a cap on physics cars that drops when physics gets slow.
##
## Offline this game decides everything (authority); online the server does (NetHighway, D109).

## Lane cars this close to a player (or police) become physics cars; physics cars this far from
## everyone go back to the lane sim. A wreck stays until nobody is within R_OUT, then it's towed.
const R_IN := 150.0
const R_OUT := 200.0
## A physics car nobody has been near for this long goes back even off its lane's line (where its
## shadow is).
const FORCE_BACK_S := 3.0
## Physics cars at most: in this game, and near one player.
const CAP_GAME := 24
const CAP_PLAYER := 12
const CAP_MIN := 4
## Stand-in boxes for lane cars this close to a player.
const BOX_M := 40.0
const BOXES := 16
## Distant traffic is drawn this far from a camera.
const VIEW_M := 1500.0
const DECIDE_S := 0.25
## The lane sim's ticks a second (native traffic_sim.h TICK_HZ).
const TICK_HZ := 20
## Ids members() gives racers (their index added).
const RACER_ID := 10000
## Event kinds (NossTraffic, D109).
const PROMOTE := 1
const DEMOTE := 2
const WRECK := 4
const TOW := 5
const CLOSE := 6
const OPEN := 7
const RESHADOW := 8
## Lane-sim car flags.
const ACTIVE := 1
const AWAY := 2
const SHADOW := 4
const WRECK_FLAG := 8

var session: TrackSession
var sim: NossTraffic
## This game decides promotions (offline, and the server online).
var authority := true
var cap := CAP_GAME
## Car index -> TrafficCar (its physics car).
var cars := {}
## Totals since the session began (checks).
var promotions := 0
var demotions := 0
var tows := 0
var wrecks := 0

var _types: Array[Dictionary] = []
var _car_type := PackedInt32Array()
var _packages := {} # type -> VehiclePackage (copied for each physics car)
var _platforms := {} # type -> PlatformLoader.Result
var _pool := {} # type -> [Vehicle] not in use
var _views: Array[MultiMeshInstance3D] = []
var _boxes: Array[AnimatableBody3D] = []
var _time := 0.0
var _decide := 0.0
var _seq := 0
var _members := PackedFloat32Array()
var _members_frame := -1
var _slow_time := 0.0
var _fast_time := 0.0
var _blink := 0.0


## The lane sim for `track`'s highway: `count` cars from `seed`. False (and why, pushed) if it
## can't be set up.
func setup(track: TrackData, seed: int, count: int) -> bool:
	_types = TrafficTypes.list()
	sim = TrafficTypes.sim(track, seed, count)
	if sim == null:
		return false
	var palettes := []
	for t in _types.size():
		palettes.append(PackedColorArray(TrafficTypes.colors(t)))
	sim.set_palettes(palettes)
	_car_type.resize(sim.get_count())
	for i in sim.get_count():
		_car_type[i] = int(sim.car(i).type)
	return true


func _ready() -> void:
	process_physics_priority = -58 # after the fields, before drivers (-50)
	if sim == null:
		return
	var draws := not (session.dedicated or Game.dev.has("bot"))
	for t in _types.size():
		_platforms[t] = PlatformLoader.load_official(String(_types[t].platform))
		_pool[t] = []
		var pkg := PackageLoader.load_package("res://content/traffic/" + String(_types[t].model), {}, {} if draws else { "models": "none", "audio": false })
		if pkg.ok():
			_packages[t] = pkg
	if draws:
		_make_views()
		var sound := TrafficSound.new()
		sound.name = "TrafficSound"
		sound.manager = self
		add_child(sound)
	for i in BOXES:
		var body := AnimatableBody3D.new()
		body.name = "TrafficBox%d" % i
		body.sync_to_physics = false
		body.collision_layer = Vehicle.LAYER_VEHICLES
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		body.add_child(shape)
		body.process_mode = Node.PROCESS_MODE_DISABLED
		body.position = Vector3(0, -1000.0 - i * 10.0, 0)
		add_child(body)
		_boxes.append(body)


func _exit_tree() -> void:
	for t: int in _packages:
		(_packages[t] as VehiclePackage).free_scenes()


func _physics_process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	sim.step_to(int(_time * TICK_HZ))
	if authority:
		_decide -= delta
		if _decide <= 0.0:
			_decide += DECIDE_S
			_promotions()
	_place_boxes()
	_adapt(delta)


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta * Vehicle.BLINK_HZ, 1.0)
	if not _views.is_empty():
		_draw()


## How far the sim is into its next tick (0..1), for drawing between ticks.
func alpha() -> float:
	var t := (_time + Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second) * TICK_HZ
	return clampf(t - sim.get_tick(), 0.0, 1.0)


# --- physics cars ---------------------------------------------------------------------------


## Every physics car near traffic, for the lane driver: 9 floats each (id, x, y, z, heading x,
## heading z, speed, half length, half width). Racers' ids are RACER_ID + their index, traffic
## cars' their car index. Once a physics tick.
func members() -> PackedFloat32Array:
	var frame := Engine.get_physics_frames()
	if frame == _members_frame:
		return _members
	_members_frame = frame
	_members = PackedFloat32Array()
	for i in session.racers.size():
		var r := session.racers[i]
		if r.vehicle and is_instance_valid(r.vehicle) and not r.waiting:
			_add_member(RACER_ID + i, r.vehicle)
	for car: int in cars:
		_add_member(car, (cars[car] as TrafficCar).vehicle)
	return _members


func member_id(r: Racer) -> int:
	return RACER_ID + session.racers.find(r)


func _add_member(id: int, v: Vehicle) -> void:
	var e := v.fitted.envelope
	var f := v.global_basis.z
	var p := v.global_position
	_members.append_array([id, p.x, p.y, p.z, f.x, f.z, v.speed(), e.size.z / 2.0, e.size.x / 2.0])


## Where physics cars matter: every player's car (police come in M7's police step).
func promoters() -> PackedVector3Array:
	var out := PackedVector3Array()
	for r in session.racers:
		if r.vehicle and is_instance_valid(r.vehicle) and not r.waiting and (r is SessionPlayer or r.is_human):
			out.append(r.vehicle.global_position)
	return out


func _promotions() -> void:
	var promoters := promoters()
	# Physics cars: back into the lane sim, wrecked, towed, or the lane sim told where they are.
	for car: int in cars.keys():
		var tc: TrafficCar = cars[car]
		var near := _nearest(promoters, tc.vehicle.global_position)
		if tc.wrecked:
			if near > R_OUT:
				_event(TOW, car)
				tows += 1
				_release(car)
			continue
		if tc.crashed():
			tc.wrecked = true
			wrecks += 1
			_event(WRECK, car, maxi(tc.lane, 0), tc.s, 0.0)
			continue
		tc.alone = tc.alone + DECIDE_S if near > R_OUT else 0.0
		if near > R_OUT and (tc.lane_ok() or tc.alone > FORCE_BACK_S):
			if tc.lane_ok():
				_event(DEMOTE, car, tc.lane, tc.s, maxf(tc.vehicle.speed(), 0.0))
			else:
				_event(DEMOTE, car) # back where its shadow is
			demotions += 1
			_release(car)
			continue
		if tc.drifted(DECIDE_S):
			_event(RESHADOW, car, tc.lane, tc.s, maxf(tc.vehicle.speed(), 0.0))
	# Lane cars near someone: nearest first, up to the caps.
	if promoters.is_empty() or cars.size() >= cap:
		return
	var poses := sim.poses(0.0)
	var candidates := []
	var per := PackedInt32Array()
	per.resize(promoters.size())
	for car: int in cars:
		var who := _nearest_index(promoters, (cars[car] as TrafficCar).vehicle.global_position)
		per[who] += 1
	for i in sim.get_count():
		var flags := int(poses[i * 8 + 5])
		if flags & ACTIVE == 0 or flags & SHADOW != 0:
			continue
		var at := Vector3(poses[i * 8], poses[i * 8 + 1], poses[i * 8 + 2])
		var d := _nearest(promoters, at)
		if d < R_IN:
			candidates.append([d, i, _nearest_index(promoters, at)])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for c: Array in candidates:
		if cars.size() >= cap:
			break
		if per[c[2]] >= CAP_PLAYER:
			continue
		if _promote(c[1], poses):
			per[c[2]] += 1


## Lane car `car` becomes a physics car where the lane sim has it, at its speed. False if its
## spot is taken by another physics car (it tries again next time).
func _promote(car: int, poses: PackedFloat32Array) -> bool:
	var type := _car_type[car]
	if not _packages.has(type):
		return false
	var t: Dictionary = _types[type]
	var front := Vector3(poses[car * 8], poses[car * 8 + 1], poses[car * 8 + 2])
	var fwd := Vector3(poses[car * 8 + 3], 0.0, poses[car * 8 + 4]).normalized()
	var centre := front - fwd * float(t.length_m) / 2.0
	for i in range(0, members().size(), 9):
		if Vector3(_members[i + 1], _members[i + 2], _members[i + 3]).distance_to(centre) < float(t.length_m) / 2.0 + 4.0:
			return false
	var info := sim.car(car)
	var v := _take_vehicle(type)
	if v == null:
		return false
	v.traffic_id = car
	var colors := TrafficTypes.colors(type)
	if v.visual:
		v.visual.set_paint("primary", colors[int(info.color) % colors.size()], "metallic")
	var basis := Basis(Vector3(fwd.z, 0.0, -fwd.x), Vector3.UP, fwd)
	v.reset_to(Transform3D(basis, centre), fwd * float(info.v))
	var tc := TrafficCar.new()
	tc.name = "Traffic%d" % car
	tc.manager = self
	tc.car = car
	tc.vehicle = v
	tc.wrecked = int(info.flags) & WRECK_FLAG != 0 # a wreck in the lane sim stays one
	add_child(tc)
	cars[car] = tc
	_event(PROMOTE, car)
	promotions += 1
	return true


## A physics car for traffic type `type`: one from the pool, or a new one.
func _take_vehicle(type: int) -> Vehicle:
	var pool: Array = _pool[type]
	if not pool.is_empty():
		var v: Vehicle = pool.pop_back()
		v.process_mode = Node.PROCESS_MODE_INHERIT
		v.freeze = false
		v.visible = true
		v.collision_layer = Vehicle.LAYER_VEHICLES
		v.collision_mask = Vehicle.LAYER_WORLD | Vehicle.LAYER_VEHICLES
		return v
	var platform: PlatformLoader.Result = _platforms[type]
	if not platform.ok():
		return null
	var v := Vehicle.create(platform, PackageLoader.copy(_packages[type]))
	v.name = "TrafficVehicle"
	v.visual_every_frame = true
	session.add_child(v)
	return v


## Physics car `car` goes back into the pool.
func _release(car: int) -> void:
	var tc: TrafficCar = cars[car]
	cars.erase(car)
	var v := tc.vehicle
	tc.queue_free()
	v.traffic_id = -1
	v.indicators = 0
	v.freeze = true
	v.visible = false
	v.collision_layer = 0
	v.collision_mask = 0
	v.global_position = Vector3(0, -2000.0, 0)
	v.process_mode = Node.PROCESS_MODE_DISABLED
	(_pool[_car_type[car]] as Array).append(v)


func _event(kind: int, car: int, lane := -1, s := 0.0, v := 0.0) -> void:
	_seq = (_seq + 1) % 65536
	sim.schedule(NossTraffic.pack_event(kind, _seq, sim.get_tick(), car, 0, lane, s, v, -1, 0, 0, 0))


static func _nearest(points: PackedVector3Array, at: Vector3) -> float:
	var best := INF
	for p in points:
		best = minf(best, p.distance_to(at))
	return best


static func _nearest_index(points: PackedVector3Array, at: Vector3) -> int:
	var best := INF
	var out := 0
	for i in points.size():
		var d := points[i].distance_to(at)
		if d < best:
			best = d
			out = i
	return out


## Lane cars right beside a player that aren't physics cars get a solid box where the lane sim has
## them, so nobody drives through traffic while the cap is reached.
func _place_boxes() -> void:
	var players := PackedVector3Array()
	for p in session.players:
		if p.vehicle and is_instance_valid(p.vehicle):
			players.append(p.vehicle.global_position)
	var used := 0
	var pose := PackedFloat32Array()
	for p in players:
		for car in sim.cars_near(p, BOX_M):
			if used >= _boxes.size():
				break
			if cars.has(car) or int(sim.car(car).flags) & SHADOW != 0:
				continue
			if pose.is_empty():
				pose = sim.poses(alpha())
			var t: Dictionary = _types[_car_type[car]]
			var fwd := Vector3(pose[car * 8 + 3], 0.0, pose[car * 8 + 4]).normalized()
			var centre := Vector3(pose[car * 8], pose[car * 8 + 1], pose[car * 8 + 2]) - fwd * float(t.length_m) / 2.0
			var body := _boxes[used]
			body.process_mode = Node.PROCESS_MODE_INHERIT
			((body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = Vector3(float(t.width_m), 1.4, float(t.length_m))
			body.global_transform = Transform3D(Basis(Vector3(fwd.z, 0.0, -fwd.x), Vector3.UP, fwd), centre + Vector3.UP * 0.9)
			body.set_meta(&"noss_traffic", car)
			used += 1
	for i in range(used, _boxes.size()):
		if _boxes[i].process_mode != Node.PROCESS_MODE_DISABLED:
			_boxes[i].process_mode = Node.PROCESS_MODE_DISABLED
			_boxes[i].global_position = Vector3(0, -1000.0 - i * 10.0, 0)



## Fewer physics cars while physics runs slow (over 6 ms a frame for 2 s), more again once there's
## room (under 3 ms for 10 s).
func _adapt(delta: float) -> void:
	var ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_slow_time = _slow_time + delta if ms > 6.0 else 0.0
	_fast_time = _fast_time + delta if ms < 3.0 else 0.0
	if _slow_time > 2.0:
		_slow_time = 0.0
		cap = maxi(CAP_MIN, cap - 2)
	elif _fast_time > 10.0:
		_fast_time = 0.0
		cap = mini(CAP_GAME, cap + 1)


# --- drawing --------------------------------------------------------------------------------


func _make_views() -> void:
	var counts := PackedInt32Array()
	counts.resize(_types.size())
	for t in _car_type:
		counts[t] += 1
	for t in _types.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = TrafficModels.far_mesh(t)
		mm.instance_count = maxi(counts[t], 1)
		mm.visible_instance_count = 0
		var view := MultiMeshInstance3D.new()
		view.name = "Traffic_" + String(_types[t].id)
		view.multimesh = mm
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
		add_child(view)
		_views.append(view)


func _draw() -> void:
	var cameras := PackedVector3Array()
	for p in session.players:
		if p.cameras and p.cameras.camera:
			cameras.append(p.cameras.camera.global_position)
	var bufs := sim.buffers(alpha(), cameras, VIEW_M, _blink < 0.5)
	for t in _views.size():
		var mm := _views[t].multimesh
		var buf: PackedFloat32Array = bufs[t][0]
		var count: int = bufs[t][1]
		buf.resize(mm.instance_count * 20)
		mm.buffer = buf
		mm.visible_instance_count = count
