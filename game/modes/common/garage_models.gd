class_name GarageModels
extends Node
## Garage cars in the traffic (D191, D233; highways too, D239): the cars by registry index and
## their models, streamed. The traffic says which cars it wants (want(), each STREAM_S); sweep()
## loads a car's smallest LOD (its far view, about 1 MB of an FM4 car's 38) while it's wanted,
## its whole model while it's wanted near a player, and lets each go UNLOAD_S after the last
## (the whole one not while a physics car is it). A far view's mesh is merged on a worker, one at
## a time (on the main thread one took up to 33 ms); the traffic draws it (view_made).
## Endless traffic and highway traffic each make one as a child of theirs.
##
## Loads go a few at a time, nearest first, as low-priority tasks (D241). A glTF load waits on the
## main thread now and then (reading a texture back); some 50 at once at a highway's start took
## every worker, so Jolt's jobs, which share the pool, waited on them while they waited on the
## main thread: the game froze.

## Of the cars of a type some garage car fits, this share are garage cars.
const GARAGE_SHARE := 0.8
const UNLOAD_S := 60.0
const FAR_OPTS := { "models": "smallest", "audio": false, "low_priority": true }
## Loads in flight at most: whole models, far views (the rest wait for later sweeps).
const MOST_LOADING_WHOLE := 2
const MOST_LOADING_FAR := 1
const VIEW_TIMEOUT_S := 30.0
## Once cars have gone, the memory they had goes back to the system (NossCore.trim_memory, on a
## worker), at most every TRIM_S: a 10-minute drive grew from 3.4 to 5.3 GB without it, and stayed
## near 2 GB with it.
const TRIM_S := 10.0

## A car's far view is made (its smallest LOD merged, fitted to its first type's platform).
signal view_made(g: int, mesh: ArrayMesh)
## A car's far view goes (its smallest LOD let go).
signal view_gone(g: int)
## A car's whole model goes: physics cars waiting in a pool on it should go too.
signal whole_gone(g: int)

## The cars by registry index, the same on every game online: {car (a path offline, a hash
## online), path (where it is here; "" until all its files are), fits: [type index], paint}.
var cars := {}
## The traffic's platforms by type index (a far view is fitted to its car's first fit).
var platforms := {}
## Models are drawn here (not on a server or a headless bot).
var draws := true
## Whole models loaded at once at most, nearest first (-1: every one wanted near a player).
var most_whole := -1
## Garage index -> VehiclePackage, while loaded: its whole model (`pkgs`), its smallest LOD (`far`).
var pkgs := {}
var far := {}
## Garage index -> when it was last wanted (the traffic's clock), and near a player.
var wanted := {}
var wanted_near := {}
## Vector2i(garage index, 1 far or 0 whole) -> true.
var loading := {}
## For the dev log: the most whole models loaded at once, the longest far-view merge (ms).
var most_loaded := 0
var view_ms := 0.0

var _near_d := {} # garage index -> how near a player it was wanted this sweep (m)
var _far_d := {} # garage index -> how near a camera it was wanted this sweep (m)
var _made := {} # garage index -> true: its far view is made
var _view_queue: Array[int] = [] # loaded cars whose far view is still to be made
var _viewing := false # a far view is being merged
var _freed := false # a car went since the last trim
var _trim_at := -INF
var _trim_task := -1


func _init() -> void:
	name = "GarageModels"


func _process(_delta: float) -> void:
	if not _view_queue.is_empty() and not _viewing:
		_next_view()


func _exit_tree() -> void:
	if _trim_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_trim_task)
		_trim_task = -1
	for into: Dictionary in [pkgs, far]:
		for g: int in into:
			(into[g] as VehiclePackage).free_scenes()
		into.clear()


## Offline: every car of `pool` (EndlessTraffic.garage_pool), each one's paint read now (a
## stand-in wears it); its models load when the traffic wants them.
func set_pool(pool: Array[Dictionary]) -> void:
	cars = {}
	for g in pool.size():
		cars[g] = pool[g].duplicate()
		cars[g].paint = PackageLoader.read_json(String(pool[g].path), "paint.json")


## Online: some of garage car `car` (a hash) is here now: its paint once its data is, its model
## once all of it is.
func car_here(car: String) -> void:
	var c: Dictionary = Net.content.car(car) if Net.content else {}
	if not c.has("path"):
		return
	for g: int in cars:
		var e: Dictionary = cars[g]
		if e.car != car:
			continue
		if (e.paint as Dictionary).is_empty():
			e.paint = PackageLoader.read_json(String(c.path), "paint.json")
		if not c.partial and String(e.path).is_empty():
			e.path = String(c.path)
			if Game.dev.has("endless-debug"):
				print("garage: car %d here (%s)" % [g, car.substr(7, 8)])


## The traffic has car `g` at `at` (its clock): within `near_m` of a player (INF: not near one),
## `far_m` from the nearest camera (its far view loads nearest first).
func want(g: int, at: float, near_m := INF, far_m := INF) -> void:
	wanted[g] = at
	_far_d[g] = minf(float(_far_d.get(g, INF)), far_m)
	if near_m < INF:
		wanted_near[g] = at
		_near_d[g] = minf(float(_near_d.get(g, INF)), near_m)


## Loads what's wanted and lets go of what hasn't been for UNLOAD_S (a whole model not while a
## physics car is it: `driven`, garage index -> true). With `most_whole`, the nearest that many
## wanted near load whole; a nearer one waiting puts out the furthest loaded one not driven.
## Loads start nearest first, MOST_LOADING_WHOLE and MOST_LOADING_FAR in flight at most.
func sweep(at: float, driven: Dictionary) -> void:
	var far_views := draws and MeshBatch.threaded()
	var far_order := []
	for g: int in wanted.keys():
		if at - float(wanted[g]) > UNLOAD_S:
			wanted.erase(g)
			_unload(g, true)
		elif far_views:
			far_order.append(g)
	_load_nearest(far_order, _far_d, true)
	if most_whole < 0:
		var order := []
		for g: int in wanted_near.keys():
			if at - float(wanted_near[g]) > UNLOAD_S and not driven.has(g):
				wanted_near.erase(g)
				_unload(g, false)
			else:
				order.append(g)
		_load_nearest(order, _near_d, false)
	else:
		_sweep_nearest(at, driven)
	_near_d.clear()
	_far_d.clear()
	most_loaded = maxi(most_loaded, pkgs.size())
	if _freed and at - _trim_at > TRIM_S:
		_freed = false
		_trim_at = at
		if _trim_task >= 0:
			WorkerThreadPool.wait_for_task_completion(_trim_task) # done long since
		_trim_task = WorkerThreadPool.add_task(NossCore.trim_memory)


func _sweep_nearest(at: float, driven: Dictionary) -> void:
	var order := _near_d.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return float(_near_d[a]) < float(_near_d[b]))
	var keep := {}
	for i in mini(most_whole, order.size()):
		keep[order[i]] = true
	for g: int in wanted_near.keys():
		if at - float(wanted_near[g]) > UNLOAD_S and not driven.has(g):
			wanted_near.erase(g)
			_unload(g, false)
	for g: int in order:
		if keep.has(g) and _whole() < most_whole and _loading(false) < MOST_LOADING_WHOLE:
			_load(g, false)
	var waiting := order.any(func(g: int) -> bool: return keep.has(g) and not _has_whole(g))
	if not waiting or _whole() < most_whole:
		return
	# One out a sweep: the loaded car not driven that's furthest (or wanted longest ago).
	var out := -1
	var out_d := -1.0
	for g: int in pkgs:
		if driven.has(g) or keep.has(g):
			continue
		var d := float(_near_d.get(g, INF))
		if d > out_d:
			out = g
			out_d = d
	if out >= 0:
		wanted_near.erase(out)
		_unload(out, false)


## Starts loading the nearest of `order` (garage indexes, by `dist`) that aren't loaded, while
## fewer than the most of that kind are in flight.
func _load_nearest(order: Array, dist: Dictionary, far_lod: bool) -> void:
	order.sort_custom(func(a: int, b: int) -> bool: return float(dist.get(a, INF)) < float(dist.get(b, INF)))
	for g: int in order:
		if _loading(far_lod) >= (MOST_LOADING_FAR if far_lod else MOST_LOADING_WHOLE):
			return
		_load(g, far_lod)


## Loads in flight: far views (`far_lod`) or whole models.
func _loading(far_lod: bool) -> int:
	return loading.keys().filter(func(k: Vector2i) -> bool: return k.y == int(far_lod)).size()


func _whole() -> int:
	return pkgs.size() + _loading(false)


func _has_whole(g: int) -> bool:
	return pkgs.has(g) or loading.has(Vector2i(g, 0))


## A whole model only where it's drawn (and not headless, where models can't load on a worker).
func load_opts() -> Dictionary:
	return { "low_priority": true } if draws and MeshBatch.threaded() else { "models": "none", "audio": false, "low_priority": true }


## Loads garage car `g`'s smallest LOD (`far_lod`, for its far view) or its whole model, if its
## files are here and it isn't loaded or loading.
func _load(g: int, far_lod: bool) -> void:
	var into := far if far_lod else pkgs
	var key := Vector2i(g, int(far_lod))
	if into.has(g) or loading.has(key) or not cars.has(g) or String(cars[g].path).is_empty() or cars[g].get("broken", false):
		return
	loading[key] = true
	PackageLoader.load_shared(String(cars[g].path), func(pkg: VehiclePackage) -> void:
		loading.erase(key)
		if not pkg.ok():
			cars[g].broken = true
			return
		into[g] = pkg
		if far_lod:
			_view_queue.append(g), FAR_OPTS if far_lod else load_opts())


func _unload(g: int, far_lod: bool) -> void:
	var into := far if far_lod else pkgs
	var pkg: VehiclePackage = into.get(g)
	if pkg == null:
		return
	into.erase(g)
	pkg.free_scenes()
	_freed = true
	if far_lod:
		_view_queue.erase(g)
		if _made.has(g):
			_made.erase(g)
			view_gone.emit(g)
	else:
		whole_gone.emit(g)
	PackageLoader.drop_shared(String(cars[g].path), FAR_OPTS if far_lod else load_opts())


## The next queued far view, merged on a worker from a copy of the car's smallest LOD (its loaded
## one stays as it is).
func _next_view() -> void:
	var g: int = _view_queue.pop_front()
	var pkg: VehiclePackage = far.get(g)
	if pkg == null or _made.has(g) or pkg.lods.is_empty():
		return
	var own := VehiclePackage.new()
	own.fit = pkg.fit
	own.paint = pkg.paint
	own.lods.append(pkg.lods[pkg.lods.size() - 1].duplicate() as Node3D)
	var platform: Dictionary = (platforms[int(cars[g].fits[0])] as PlatformLoader.Result).platform
	_viewing = true
	WorkerJob.start(self, func() -> Array:
		var t0 := Time.get_ticks_usec()
		return [TrafficModels.far_mesh_of(own, platform), (Time.get_ticks_usec() - t0) / 1000.0],
		func(made: Variant) -> void:
			_viewing = false
			if not made is Array:
				return # timed out: the copy goes when the merge ends (discard)
			own.free_scenes()
			view_ms = maxf(view_ms, float(made[1]))
			if made[0] and far.get(g) == pkg and not _made.has(g):
				_made[g] = true
				view_made.emit(g, made[0]),
		VIEW_TIMEOUT_S, func() -> Variant: return null, own.free_scenes.unbind(1))


## Garage car `g`'s paint for a car whose paint draw is `roll`, as CarVisual.random_paint picks
## from the car's presets ({}: its own).
func paint_of(g: int, roll: int) -> Dictionary:
	var paint: Dictionary = cars[g].get("paint", {})
	var presets: Array = (paint.get("presets", []) as Array).filter(func(p: Variant) -> bool: return p is Dictionary)
	if presets.is_empty():
		var c: Array = CarVisual.STOCK_COLORS[roll % CarVisual.STOCK_COLORS.size()]
		return { "primary": c[0], "finish": c[1] }
	var i := roll % (presets.size() + 1)
	return CarVisual.clean_paint(presets[i]) if i < presets.size() else {}


## Garage car `g`'s main colour in that paint (a far view's tint), once its paint is known;
## `fallback` till then.
func tint_of(g: int, roll: int, fallback: Color) -> Color:
	var paint: Dictionary = cars[g].get("paint", {}) if cars.has(g) else {}
	if paint.is_empty():
		return fallback
	var primary: Variant = paint_of(g, roll).get("primary", paint.get("slots", {}).get("primary", {}).get("color", ""))
	return Color.html(primary) if primary is String and Color.html_is_valid(primary) else fallback


## Whether car `g`'s paint is known yet (its tint won't change once it is).
func has_paint(g: int) -> bool:
	return cars.has(g) and not (cars[g].get("paint", {}) as Dictionary).is_empty()
