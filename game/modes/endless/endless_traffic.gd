class_name EndlessTraffic
extends Node
## Traffic on the endless road (docs/GAMEMODES.md §4, AI-03, D158): light to heavy, both ways
## (oncoming can be off), in one or two lanes each way (EndlessLanes, D190). Nothing is simulated
## far away: each way has a speed along the road (bends, braking before them, pulling away after,
## from the generator) and the time a car takes to get anywhere at it, and each lane runs at its
## own share of that; car j of a lane left the start at time tau_j (a steady spacing with some
## spread from the seed), so where every car is at any time is worked out, the same on every game,
## and no two in a lane ever meet. Two lanes each way, the passing lane's cars overtake the other's,
## and trucks and buses keep out of it. Garage cars (D191) drive in place of most of the stock cars
## of a type they fit, picked after a slot's own draws so the stock schedule stays as it was. Cars near a player become physics cars (EndlessTrafficCar) that keep to their
## slot unless something's in the way; knocked or left far behind, a car leaves its slot (the slot
## stays empty) and goes once nobody's near. Cars further off are drawn, one MultiMesh per type.
## Online (D159) one game drives each physics car (EndlessNet's owners) and the others show it from
## its states; a car's network id comes from its slot (car_id_of).

const UP := 0 # toward higher distances (the players' way)
const DOWN := 1 # oncoming
## A speed trap's patrol car, parked on the verge (D193): slot (PARKED, the trap's chunk).
const PARKED := 4
## Mean seconds between cars in a lane, by setting; a share of slots left empty for uneven gaps.
const HEADWAY_S := { "light": 48.0, "normal": 20.0, "heavy": 8.0 }
const SPREAD := 0.8
const EMPTY_SHARE := 0.15
## Drawn within this of a camera (at most DRAWN of a type); physics cars within PROMOTE_M of a player,
## the nearest first, back into the schedule past DEMOTE_M once on their slot; a car that left its
## slot goes past GONE_M.
const VIEW_M := 1500.0
const PROMOTE_M := 140.0
const DEMOTE_M := 220.0
const GONE_M := 260.0
const MAX_PHYSICS := 12
const DRAWN := 64
## Traffic cars' network ids run from FIRST_TRAFFIC_ID through this many.
const TRAFFIC_IDS := 59000
## Garage traffic (D191): of the slots of a type some garage car fits, this share are garage cars;
## at most this many garage cars (online, the host shares fewer).
const GARAGE_SHARE := 0.8
const GARAGE_MOST := 12
const GARAGE_SHARED := 6

var session: TrackSession
var world: EndlessWorld
var lanes := EndlessLanes.new()
var seed := 1
var density := "light"
var oncoming := true
## Seconds on the traffic's clock (online: the server's, D159). Unset: this node's own.
var clock := Callable()
## Online: who drives which car (null offline).
var net: EndlessNet
## Physics cars by slot key (Vector2i(lane, j)).
var cars := {}
## Slots left behind by cars knocked out of them (never drawn again).
var gone := {}
## The garage cars in the traffic (D191), the same on every game online: [{car (a path offline, a
## hash online), path (where it is here; "" until its files are), fits: [type index], paint}].
var garage: Array[Dictionary] = []

var _types: Array[Dictionary] = []
var _weights := 0
## The patrol type's index in _types (after the weighted ones: it never comes up in a draw).
var _patrol_type := -1
var _platforms := {}
var _packages := {}
var _views: Array[MultiMeshInstance3D] = []
var _time := 0.0
var _slots := {} # slot key -> {present, tau, type, color, garage, paint_roll} (made from the seed, kept a while)
var _draws := true
var _garage_fits := {} # type index -> [garage index]
var _garage_pkgs := {} # garage index -> VehiclePackage, once loaded
var _garage_views := {} # garage index -> MultiMeshInstance3D (its own far mesh)


func _ready() -> void:
	name = "EndlessTraffic"
	process_physics_priority = -58
	_draws = not (session.dedicated or Game.dev.has("bot"))
	for t: Dictionary in TrafficTypes.list():
		if int(t.weight) > 0:
			_types.append(t)
			_weights += int(t.weight)
	for t: Dictionary in TrafficTypes.list():
		if t.get("patrol", false):
			_patrol_type = _types.size()
			_types.append(t)
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
			mm.instance_count = DRAWN
			mm.visible_instance_count = 0
			var view := MultiMeshInstance3D.new()
			view.name = "Traffic_" + String(_types[i].id)
			view.multimesh = mm
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			view.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
			# Placed every frame from the clock: nothing for physics interpolation to smooth.
			view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(view)
			_views.append(view)


func _exit_tree() -> void:
	for t: int in _packages:
		(_packages[t] as VehiclePackage).free_scenes()
	for g: int in _garage_pkgs:
		(_garage_pkgs[g] as VehiclePackage).free_scenes()
	_garage_pkgs.clear()


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


## A slot as one number (lane, j) -> 8j + lane, for the network: lanes 0-3 are driven, 4 is a speed
## trap's parked patrol (D190, D193).
static func slot_of(key: Vector2i) -> int:
	return key.y * 8 + key.x


static func key_of(slot: int) -> Vector2i:
	return Vector2i(slot & 7, slot >> 3)


## Slot `slot`'s car's network id (CarState ids are 16 bits: slots this far apart never meet, and
## the police's ids start above them).
static func car_id_of(slot: int) -> int:
	return NetProtocol.FIRST_TRAFFIC_ID + posmod(slot, TRAFFIC_IDS)


## Slot (lane, j): whether a car's in it, when it left (s, on the lane's clock), its type and colour.
func slot(lane: int, j: int) -> Dictionary:
	var key := Vector2i(lane, j)
	if not _slots.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = (seed * 1000003 + lane * 7919 + j) & 0x7FFFFFFFFFFFFFFF
		var tau := headway() * (float(j) + SPREAD * rng.randf())
		var present := rng.randf() >= EMPTY_SHARE
		var weights := _weights_of(lane)
		var pick := rng.randi_range(0, int(weights[-1]) - 1)
		var type := 0
		for i in _types.size():
			pick -= int(weights[i])
			if pick < 0:
				type = i
				break
		var colors := TrafficTypes.colors(TrafficTypes.index_of(String(_types[type].id)))
		var sl := { "present": present, "tau": tau, "type": type, "color": colors[rng.randi_range(0, colors.size() - 1)], "garage": -1 }
		# Garage traffic: draws of its own after the stock ones, and only where a garage car fits.
		var fits: Array = _garage_fits.get(type, [])
		if not fits.is_empty() and rng.randf() < GARAGE_SHARE:
			sl.garage = fits[rng.randi_range(0, fits.size() - 1)]
			sl.paint_roll = rng.randi()
		_slots[key] = sl
	return _slots[key]


# --- garage traffic ------------------------------------------------------------------------------


## The cars of `paths` that can drive in the traffic (D191): each with the traffic types whose
## platform takes it as it is (its family, and its wheelbase without scaling it), shuffled by
## `seed`, at most `most`: [{car, path, fits: [type index]}] (type indexes: the weighted types, in
## TrafficTypes order).
static func garage_pool(paths: PackedStringArray, seed_value: int, most := GARAGE_MOST) -> Array[Dictionary]:
	var types: Array[Dictionary] = []
	for t: Dictionary in TrafficTypes.list():
		if int(t.weight) > 0:
			types.append(t)
	var order := Array(paths)
	order.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = order[i]
		order[i] = order[j]
		order[j] = swap
	var platforms := {} # platform id -> PlatformLoader.Result
	var out: Array[Dictionary] = []
	for path: String in order:
		if out.size() >= most:
			break
		if path.begins_with("res://content/traffic/"):
			continue
		var family := String(PackageLoader.read_manifest(path).get("family", ""))
		var fit := PackageLoader.read_json(path, "fit.json")
		if not (fit.get("wheels") is Array and fit.get("model_transform") is Dictionary and fit.get("envelope") is Dictionary):
			continue
		var fits: Array[int] = []
		var takes := {} # platform id -> bool
		for i in types.size():
			var pid := String(types[i].platform)
			if not takes.has(pid):
				if not platforms.has(pid):
					platforms[pid] = PlatformLoader.load_official(pid)
				var p: PlatformLoader.Result = platforms[pid]
				takes[pid] = p.ok() and Fitting.compatible(p.platform, family) and is_equal_approx(Fitting.fit(p.platform, fit).scale, 1.0)
			if takes[pid]:
				fits.append(i)
		if not fits.is_empty():
			out.append({ "car": path, "path": path, "fits": fits })
	return out


## The garage cars that drive in the traffic (garage_pool offline, the host's list online). Each
## loads once its files are here (have_car).
func set_garage(pool: Array[Dictionary]) -> void:
	garage = pool
	_garage_fits.clear()
	_slots.clear()
	for g in garage.size():
		for t: int in garage[g].fits:
			if not _garage_fits.has(t):
				_garage_fits[t] = []
			(_garage_fits[t] as Array).append(g)
		if String(garage[g].get("path", "")):
			_load_garage(g)


## Online: garage car `car` (a hash) is all here now, at `path`.
func have_car(car: String, path: String) -> void:
	for g in garage.size():
		if garage[g].car == car and String(garage[g].get("path", "")).is_empty():
			garage[g].path = path
			_load_garage(g)


func _load_garage(g: int) -> void:
	var path := String(garage[g].path)
	garage[g].paint = PackageLoader.read_json(path, "paint.json")
	# Its model only where it's drawn (and not headless, where models can't load on a worker).
	var whole := _draws and MeshBatch.threaded()
	PackageLoader.load_shared(path, func(pkg: VehiclePackage) -> void:
		if not pkg.ok():
			return
		_garage_pkgs[g] = pkg
		if whole:
			_garage_view(g, pkg), {} if whole else { "models": "none", "audio": false })


## A garage car's own far view, if its model is light enough (else it's drawn as a stock car of its
## type, in its paint).
func _garage_view(g: int, pkg: VehiclePackage) -> void:
	var mesh := TrafficModels.far_mesh_of(pkg, (_platforms[int(garage[g].fits[0])] as PlatformLoader.Result).platform)
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = DRAWN
	mm.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.name = "Traffic_garage_%d" % g
	view.multimesh = mm
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	_garage_views[g] = view


## A garage slot's paint, as CarVisual.random_paint picks from the car's presets ({}: its own).
func garage_paint(sl: Dictionary) -> Dictionary:
	var paint: Dictionary = garage[int(sl.garage)].get("paint", {})
	var presets: Array = (paint.get("presets", []) as Array).filter(func(p: Variant) -> bool: return p is Dictionary)
	var roll := int(sl.paint_roll)
	if presets.is_empty():
		var c: Array = CarVisual.STOCK_COLORS[roll % CarVisual.STOCK_COLORS.size()]
		return { "primary": c[0], "finish": c[1] }
	var i := roll % (presets.size() + 1)
	return CarVisual.clean_paint(presets[i]) if i < presets.size() else {}


## A slot's colour: its stock one, or a garage car's main paint once its paint is known.
func _color_of(sl: Dictionary) -> Color:
	if int(sl.garage) < 0:
		return sl.color
	if sl.has("tint"):
		return sl.tint
	var paint: Dictionary = garage[int(sl.garage)].get("paint", {})
	if paint.is_empty():
		return sl.color
	var primary: Variant = garage_paint(sl).get("primary", paint.get("slots", {}).get("primary", {}).get("color", ""))
	sl.tint = Color.html(primary) if primary is String and Color.html_is_valid(primary) else sl.color
	return sl.tint


## Each type's weight in lane `lane`, then their sum: four lanes, trucks and buses (types with a
## lanes_max) keep out of the passing lanes.
func _weights_of(lane: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var sum := 0
	var passing := lanes.per_dir == 2 and EndlessLanes.pos_of(lane) == 0
	for t in _types:
		var w := 0 if passing and t.has("lanes_max") else int(t.weight)
		out.append(w)
		sum += w
	out.append(sum)
	return out


## Every scheduled car in the road window now: [{key, lane, s (absolute m), speed, type, color}].
func scheduled() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var road := world.road
	if road.samples.size() < 2:
		return out
	var t := now()
	var h := headway()
	# Speed traps' patrol cars, parked.
	for k: int in world.traps:
		var trap: Dictionary = world.traps[k]
		var key := Vector2i(PARKED, k)
		if trap.kind == "patrol" and _patrol_type >= 0 and not gone.has(key) and not cars.has(key) and road.index_of(float(trap.at_m)) >= 0:
			out.append({ "key": key, "lane": PARKED, "s": float(trap.at_m), "speed": 0.0, "type": _patrol_type,
				"color": TrafficTypes.colors(TrafficTypes.index_of(String(_types[_patrol_type].id)))[0], "garage": -1 })
	for lane in lanes.ids():
		var up := EndlessLanes.dir_of(lane) == UP
		if (not up and not oncoming) or density == "off":
			continue
		var f := lanes.speed_factor(lane)
		var times := road.time_up if up else road.time_down
		var t_a := times[0]
		var t_b := times[-1]
		# The lane's clock runs f times the road's: up, tau = t - T(s) / f; down, tau = t + T(s) / f.
		var lo := (t - t_b / f) if up else (t + t_a / f)
		var hi := (t - t_a / f) if up else (t + t_b / f)
		for j in range(floori(lo / h) - 1, ceili(hi / h) + 1):
			var key := Vector2i(lane, j)
			if gone.has(key) or cars.has(key):
				continue
			var sl := slot(lane, j)
			if not sl.present:
				continue
			var tq: float = ((t - float(sl.tau)) if up else (float(sl.tau) - t)) * f
			if tq < t_a or tq > t_b:
				continue
			var i := _index_at_time(times, tq)
			var u := (tq - times[i]) / maxf(times[i + 1] - times[i], 1e-6)
			var s := road.offset_m + (i + u) * TrackData.SAMPLE_M
			var speed := lerpf((road.speed_up if up else road.speed_down)[i], (road.speed_up if up else road.speed_down)[i + 1], u) * f
			out.append({ "key": key, "lane": lane, "s": s, "speed": speed, "type": sl.type, "color": _color_of(sl), "garage": sl.garage })
	return out


## Where slot `key`'s car should be now (absolute m), or NAN outside the window.
func slot_s(key: Vector2i) -> float:
	var road := world.road
	if key.x == PARKED:
		return float(world.traps[key.y].at_m) if world.traps.has(key.y) else NAN
	var sl := slot(key.x, key.y)
	var up := EndlessLanes.dir_of(key.x) == UP
	var times := road.time_up if up else road.time_down
	var tq: float = ((now() - float(sl.tau)) if up else (float(sl.tau) - now())) * lanes.speed_factor(key.x)
	if road.samples.size() < 2 or tq < times[0] or tq > times[-1]:
		return NAN
	var i := _index_at_time(times, tq)
	var u := (tq - times[i]) / maxf(times[i + 1] - times[i], 1e-6)
	return road.offset_m + (i + u) * TrackData.SAMPLE_M


## The traffic speed of a lane at distance `s`.
func lane_speed(lane: int, s: float) -> float:
	if lane == PARKED:
		return 0.0
	var road := world.road
	var i := road.index_at(s)
	return (road.speed_up if EndlessLanes.dir_of(lane) == UP else road.speed_down)[i] * lanes.speed_factor(lane)


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


## A car in `lane` at distance `s`, facing its way, on its lane's centre (a trap's patrol: on the
## verge, facing the players' way).
func pose(lane: int, s: float) -> Transform3D:
	var road := world.road
	if lane == PARKED:
		var side := lanes.side_sign(UP)
		return road.transform_at(s, side * (road.half_width(s, side) + EndlessTraps.PATROL_OUT_M))
	var xf := road.transform_at(s, lanes.lateral(road, lane, s))
	if EndlessLanes.dir_of(lane) == DOWN:
		xf.basis = xf.basis.rotated(xf.basis.y, PI)
	return xf


# --- for drivers ---------------------------------------------------------------------------------


## The nearest car ahead of distance `d` in lane `lane` (an oncoming one, when a car passes in it):
## {gap (m), speed (m/s, its speed along the road the player's way), what}, or {}.
func ahead(d: float, lane: int, max_gap: float) -> Dictionary:
	var best := {}
	var best_gap := max_gap
	for c in scheduled() + _physics_list():
		if c.lane != lane:
			continue
		var gap := float(c.s) - d - 4.5
		if gap > -2.0 and gap < best_gap:
			best_gap = gap
			best = { "gap": maxf(gap, 0.0), "speed": float(c.speed) * (1.0 if EndlessLanes.dir_of(c.lane) == UP else -1.0), "what": c.key }
	return best


## Whether no car is in lane `lane` between d0 and d1 (a car may move over into it).
func lane_clear(lane: int, d0: float, d1: float) -> bool:
	for c in scheduled() + _physics_list():
		if c.lane == lane and float(c.s) >= d0 and float(c.s) <= d1:
			return false
	return true


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
		if EndlessLanes.dir_of(c.lane) == DOWN and float(c.s) >= d0 and float(c.s) <= d1:
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
	for n: Array in near_scheduled(players):
		if cars.size() >= MAX_PHYSICS:
			break
		_promote(n[1], n[2])
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
				if net and not car.remote:
					net.gone(slot_of(key))
			_remove(key)
			if net:
				net.drop(slot_of(key))


## Scheduled cars within PROMOTE_M of any of `players`, the nearest first: [[distance, car, pose]].
func near_scheduled(players: PackedVector3Array) -> Array:
	var out: Array = []
	for c: Dictionary in scheduled():
		var xf := pose(c.lane, c.s)
		var near := INF
		for p in players:
			near = minf(near, p.distance_to(xf.origin))
		if near < PROMOTE_M:
			out.append([near, c, xf])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


func _remove(key: Vector2i) -> void:
	var car: EndlessTrafficCar = cars[key]
	cars.erase(key)
	if session.net:
		session.net.drop_traffic(car_id_of(slot_of(key)))
	if car.vehicle and is_instance_valid(car.vehicle):
		car.vehicle.queue_free()
	car.queue_free()


func _promote(c: Dictionary, xf: Transform3D) -> void:
	var type: int = c.type
	if not _packages.has(type) or not (_platforms[type] as PlatformLoader.Result).ok():
		return
	# A garage car once it's loaded; till then the stock car, in its paint.
	var g := int(c.get("garage", -1))
	var own: VehiclePackage = _garage_pkgs.get(g)
	var v := Vehicle.create(_platforms[type], PackageLoader.copy(own if own else _packages[type]))
	v.name = "EndlessTraffic%d_%d" % [c.key.x, c.key.y]
	var slot := slot_of(c.key)
	v.traffic_id = car_id_of(slot) - NetProtocol.FIRST_TRAFFIC_ID
	v.visual_every_frame = true
	session.add_child(v)
	if v.visual:
		if own:
			v.visual.apply_choice(garage_paint(slot(c.key.x, c.key.y)))
		else:
			v.visual.set_paint("primary", c.color, "metallic")
	var car := EndlessTrafficCar.new()
	car.traffic = self
	car.key = c.key
	car.vehicle = v
	car.s = c.s
	car.speed = c.speed
	add_child(car)
	cars[c.key] = car
	# Online: driven here unless another game has it already (asking for it either way: the server
	# hands it over when its owner lets it go).
	var owner := int(net.owners.get(slot, -1)) if net else -1
	_drive_here(car, owner < 0 or net.is_mine(owner), xf, xf.basis.z * float(c.speed))
	if net:
		net.want(slot)


## Makes `car` driven here (a physics car) or shown from its owner's states (a proxy), from
## `xform` at `velocity`.
func _drive_here(car: EndlessTrafficCar, local: bool, xform: Transform3D, velocity: Vector3) -> void:
	var v := car.vehicle
	car.remote = not local
	car.buffer = MotionBuffer.new()
	v.set_remote(not local)
	if local:
		v.reset_to(xform, velocity)
	else:
		v.move_remote(xform, velocity, Vector3.ZERO, true)
	if session.net:
		var id := car_id_of(slot_of(car.key))
		if local:
			session.net.own_traffic(id, car)
		else:
			session.net.drop_traffic(id)


# --- online --------------------------------------------------------------------------------------


## Slot `slot`'s car is now driven by `owner`'s game (-1: nobody): a proxy here becomes this game's
## physics car where it is, at its speed, or this game's becomes a proxy. Nobody: whoever has it
## here drives it.
func set_driver(slot: int, owner: int) -> void:
	var car: EndlessTrafficCar = cars.get(key_of(slot))
	if car == null or car.vehicle == null or not is_instance_valid(car.vehicle):
		return
	var local := owner < 0 or net.is_mine(owner)
	if local == not car.remote:
		return
	var v := car.vehicle
	var xf := v.ground_reference()
	var vel := v.remote_velocity if car.remote else v.linear_velocity
	if car.remote:
		car.take_over()
	_drive_here(car, local, xf, vel)


## Slot `slot` is used up (its car left it on some game): never drawn from the schedule again.
func mark_gone(slot: int) -> void:
	gone[key_of(slot)] = true
	var car: EndlessTrafficCar = cars.get(key_of(slot))
	if car:
		car.left_slot = true


## A state of a car another game drives.
func push_state(st: CarState, now: float) -> void:
	var car := car_by_id(st.id)
	if car and car.remote:
		car.buffer.push(st, now)
		car.remote_flags = st.flags2


## The physics car or proxy with network id `id`, or null.
func car_by_id(id: int) -> EndlessTrafficCar:
	for key: Vector2i in cars:
		if car_id_of(slot_of(key)) == id:
			return cars[key]
	return null


# --- drawing -------------------------------------------------------------------------------------


func _draw() -> void:
	var cams := PackedVector3Array()
	for p in session.players:
		if p.cameras and p.cameras.camera:
			cams.append(p.cameras.camera.global_position)
	var lights := session.env != null and session.env.lights_on
	var counts := {} # view -> instances drawn
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
		var view: MultiMeshInstance3D = _garage_views.get(int(c.garage), _views[t])
		var mm := view.multimesh
		var n: int = counts.get(view, 0)
		if n >= mm.instance_count:
			continue
		mm.set_instance_transform(n, xf)
		mm.set_instance_color(n, c.color)
		mm.set_instance_custom_data(n, Color(float(TrafficModels.HEAD if lights else 0), 0, 0, 0))
		counts[view] = n + 1
	for view: MultiMeshInstance3D in _views:
		view.multimesh.visible_instance_count = counts.get(view, 0)
	for view: MultiMeshInstance3D in _garage_views.values():
		view.multimesh.visible_instance_count = counts.get(view, 0)
