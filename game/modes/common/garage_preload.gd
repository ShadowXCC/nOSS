class_name GaragePreload
extends Node
## Garage cars in the traffic, loaded before the drive (D246). Loading them as they came near
## (D241) kept physics slow all drive: the physics-car cap fell, near cars stayed low-poly lane
## cars and stock stand-ins swapped for garage cars. Now a short pause behind the loading screen
## loads every car the traffic has, whole, and makes each one's far view from its smallest LOD;
## cars that don't fit in memory are left out of that drive. Loaded cars stay (get_car) for the
## next drive, and go at the main menu, in the garage, or when a drive without garage traffic
## starts.
##
## A node of this is one batch: it loads `items` ({path, platform}) a few at a time, says how far
## it's got (progressed), and once every car is in or left out, `finished`. Online, while the start
## waits (D127), the traffic runs one too (GarageModels.hold_for).

## Loads in flight at most: at the pause (normal priority; under half the cores, so Jolt always
## finds a worker free) and during a session (low priority).
const MOST_PAUSED := 6
const MOST_IN_SESSION := 2
## Memory (checked before each load): a load in flight takes about RAM_PER_LOAD; free RAM must stay
## above RAM_FLOOR and RAM_FLOOR_SHARE of the whole, video memory in use (the whole game's) at most
## Settings.video_limit() (Settings › Video memory, D247). Until a car is in, one is reckoned
## VIDEO_GUESS.
const RAM_PER_LOAD := 1 << 30
const RAM_FLOOR := 2 << 30
const RAM_FLOOR_SHARE := 0.15
const VIDEO_GUESS := 150 << 20
const VIEW_TIMEOUT_S := 30.0

## Cars done (in, left out or broken) of all, after each.
signal progressed(done: int, of: int)
## Every car's in or left out: how many of `items` are loaded, and how many aren't.
signal finished(loaded: int, left_out: int)
## A car is in (online, the traffic adopts it).
signal car_loaded(path: String)

## path -> {pkg (its whole model), far (its far view, or null), stamp (the file's modified time)}.
static var _cache := {}
## The highest video memory limit the loaded cars came in under (0: none loaded).
static var _limit := 0.0

## [{path, platform (the far view is fitted to it; {}: none)}]
var items: Array[Dictionary] = []
## Models are drawn here (else data only, as headless).
var draws := true
## Inside a session (online): low priority, fewer at once.
var in_session := false
## For tests: (loads in flight) -> whether one more fits. Unset: free RAM and video memory.
var room := Callable()
## Memory left some cars out.
var memory_full := false
## Which ran out: "video" (Settings › Video memory) or "memory" (free RAM; or `room`).
var full_by := ""
## Paths left out (memory) or that wouldn't load: path -> true.
var left := {}

var _queue: Array[Dictionary] = []
var _seen := {} # path -> true: every item so far
var _flight := 0
var _views: Array = [] # [path, platform] waiting for a far view
var _view_job: WorkerJob
var _done := 0
var _cached := 0
var _loaded := 0
var _trimmed := false
var _stopped := false
var _over := false
var _taking := false # _ready is taking the first items
var _t0 := 0
var _video0 := 0.0


## The loaded car at `path` ({pkg, far, stamp}), or {} if it isn't loaded or its file changed since.
static func get_car(path: String) -> Dictionary:
	var e: Dictionary = _cache.get(path, {})
	return e if not e.is_empty() and int(e.stamp) == stamp_of(path) else {}


## Lets go of every loaded car but those at `paths`.
static func keep_only(paths: Array) -> void:
	var gone := false
	for path: String in _cache.keys():
		if not path in paths:
			_drop(path)
			gone = true
	if gone:
		NossCore.trim_memory() # what they held goes back to the system (D233)
	if _cache.is_empty():
		_limit = 0.0


## Lets go of every loaded car.
static func clear() -> void:
	keep_only([])


## Settings › Video memory has gone down since the loaded cars came in: they may be over it now, so
## the next drive loads afresh (D247). Gone up, the cars left out load then anyway (missing).
static func limit_lowered() -> bool:
	return not _cache.is_empty() and Settings.video_limit() < _limit


static func _drop(path: String) -> void:
	(_cache[path].pkg as VehiclePackage).free_scenes()
	_cache.erase(path)


## When the package at `path` (a .noss, or a folder: its manifest) last changed; built-ins never do.
static func stamp_of(path: String) -> int:
	if path.begins_with("res://"):
		return 0
	return FileAccess.get_modified_time(path if FileAccess.file_exists(path) else path.path_join("manifest.json"))


## Items for `pool` (EndlessTraffic.garage_pool): each car with the platform of the first traffic
## type it fits, its far view's.
static func items_of(pool: Array[Dictionary]) -> Array[Dictionary]:
	var types := EndlessTraffic.weighted_types()
	var platforms := {}
	var out: Array[Dictionary] = []
	for d in pool:
		var platform := {}
		var fits: Array = d.get("fits", [])
		if not fits.is_empty() and int(fits[0]) < types.size():
			var pid := String(types[int(fits[0])].platform)
			if not platforms.has(pid):
				platforms[pid] = PlatformLoader.load_official(pid)
			if (platforms[pid] as PlatformLoader.Result).ok():
				platform = (platforms[pid] as PlatformLoader.Result).platform
		out.append({ "path": String(d.path), "platform": platform })
	return out


## How many of `list` (items) aren't loaded.
static func missing(list: Array[Dictionary]) -> int:
	return list.filter(func(it: Dictionary) -> bool: return get_car(String(it.path)).is_empty()).size()


## Video memory in use (bytes; 0 headless).
static func video_used() -> float:
	return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)


func _init() -> void:
	name = "GaragePreload"


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_video0 = video_used()
	var first := items
	items = []
	_taking = true
	for it in first:
		add(it)
	_taking = false
	_pump()


## One more car to load (online, as its files come in): one loaded already is done at once, and
## once memory's full, it's left out.
func add(it: Dictionary) -> void:
	if not is_inside_tree():
		items.append(it) # taken in _ready
		return
	var path := String(it.path)
	if _seen.has(path):
		return
	_seen[path] = true
	items.append(it)
	_over = false
	if not get_car(path).is_empty():
		_cached += 1
		_done += 1
		car_loaded.emit(path)
	elif memory_full:
		left[path] = true
		_done += 1
	else:
		_queue.append(it)
	if not _taking:
		_pump()


## No more loads start (online, the start has gone); those in flight still land.
func stop() -> void:
	_stopped = true
	_queue.clear()
	_check_done()


func busy() -> bool:
	return _flight > 0 or _view_job != null or not _views.is_empty() or not _queue.is_empty()


func _exit_tree() -> void:
	# Leaving with loads in flight (quitting on the loading screen): they wait on the main thread now
	# and then (a texture read back), so they're seen through here (D241).
	if _flight > 0:
		PackageLoader.finish_loads()
		_flight = 0
	if _view_job and not _view_job.done:
		while not WorkerThreadPool.is_task_completed(_view_job.task):
			RenderingServer.force_sync()
			OS.delay_msec(1)


func _most() -> int:
	return MOST_IN_SESSION if in_session else clampi(floori(OS.get_processor_count() / 2.0) - 1, 1, MOST_PAUSED)


func _opts() -> Dictionary:
	var opts := {} if draws and MeshBatch.threaded() else { "models": "none", "audio": false }
	if in_session:
		opts.low_priority = true
	return opts


## Starts loads while there's room for them. Out of memory: once those in flight are in, memory
## goes back to the system once and it looks again; still none, and the rest are left out.
func _pump() -> void:
	while not _queue.is_empty() and _flight < _most() and not _stopped:
		var short := _short_of()
		if short:
			if _flight > 0:
				return # those in flight first
			if not _trimmed:
				_trimmed = true
				NossCore.trim_memory()
				continue
			memory_full = true
			full_by = short
			for it in _queue:
				left[String(it.path)] = true
				_done += 1
			_queue.clear()
			progressed.emit(_done, items.size())
			break
		_start(_queue.pop_front())
	_check_done()


## What one more load would run short of: "" (nothing), "memory" (free RAM) or "video".
func _short_of() -> String:
	if room.is_valid():
		return "" if bool(room.call(_flight)) else "memory"
	var mem := OS.get_memory_info()
	var free_ram := int(mem.get("available", -1))
	var physical := int(mem.get("physical", -1))
	if free_ram >= 0 and physical > 0 and free_ram - (_flight + 1) * RAM_PER_LOAD < maxi(RAM_FLOOR, int(physical * RAM_FLOOR_SHARE)):
		return "memory"
	var video := video_used()
	return "" if video <= 0.0 or video + _per_car() * (_flight + 1) <= Settings.video_limit() else "video"


## Video memory a car takes, from those loaded so far.
func _per_car() -> float:
	var grown := video_used() - _video0
	return maxf(grown / _loaded, 32 << 20) if _loaded > 0 and grown > 0.0 else float(VIDEO_GUESS)


func _start(it: Dictionary) -> void:
	_flight += 1
	var path := String(it.path)
	PackageLoader.load_async(path, func(pkg: VehiclePackage) -> void:
		_flight -= 1
		if pkg.ok():
			_store(path, pkg, it.platform)
		else:
			left[path] = true
			_car_done(path)
		_pump(), {}, _opts())


func _store(path: String, pkg: VehiclePackage, platform: Dictionary) -> void:
	if _cache.has(path):
		_drop(path) # an older one (its file changed)
	_cache[path] = { "pkg": pkg, "far": null, "stamp": stamp_of(path) }
	_limit = maxf(_limit, Settings.video_limit())
	_loaded += 1
	if draws and not pkg.lods.is_empty() and not platform.is_empty():
		_views.append([path, platform])
		_next_view()
	else:
		_car_done(path)


## The next far view: the car's smallest LOD merged on a worker, from a copy (the loaded one stays
## as it is), one at a time.
func _next_view() -> void:
	if _view_job != null or _views.is_empty():
		return
	var next: Array = _views.pop_front()
	var path: String = next[0]
	var platform: Dictionary = next[1]
	var pkg: VehiclePackage = _cache.get(path, {}).get("pkg")
	if pkg == null:
		_car_done(path)
		_next_view()
		return
	var own := VehiclePackage.new()
	own.fit = pkg.fit
	own.paint = pkg.paint
	own.lods.append(pkg.lods[pkg.lods.size() - 1].duplicate() as Node3D)
	_view_job = WorkerJob.start(self, func() -> Variant: return TrafficModels.far_mesh_of(own, platform),
		func(mesh: Variant) -> void:
			_view_job = null
			if typeof(mesh) != TYPE_BOOL: # not timed out (then the copy goes when the merge ends)
				own.free_scenes()
				if mesh is ArrayMesh and _cache.get(path, {}).get("pkg") == pkg:
					_cache[path].far = mesh
			_car_done(path)
			_next_view(),
		VIEW_TIMEOUT_S, func() -> Variant: return false, own.free_scenes.unbind(1))


func _car_done(path: String) -> void:
	_done += 1
	progressed.emit(_done, items.size())
	if not left.has(path):
		car_loaded.emit(path)
	_check_done()


func _check_done() -> void:
	if _over or busy() or items.is_empty() or _done < items.size() and not _stopped:
		return
	_over = true
	var loaded := items.filter(func(it: Dictionary) -> bool: return not get_car(String(it.path)).is_empty()).size()
	if _loaded > 0 or not left.is_empty():
		var mem := OS.get_memory_info()
		var limit := Settings.video_limit()
		print("garage preload: %d/%d (%d cached) in %.1f s, video %d MB of %s (+%d for %d), ram free %d GB%s" % [loaded, items.size(), _cached,
			(Time.get_ticks_msec() - _t0) / 1000.0, roundi(video_used() / 1048576.0), "%d" % roundi(limit / 1048576.0) if is_finite(limit) else "no limit",
			roundi((video_used() - _video0) / 1048576.0), _loaded, roundi(float(mem.get("available", 0)) / 1073741824.0),
			", out of " + full_by if memory_full else ""])
	finished.emit(loaded, items.size() - loaded)
