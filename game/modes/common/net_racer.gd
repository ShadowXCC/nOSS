class_name NetRacer
extends Racer
## A car another game drives (docs/NETWORKING.md §6, D84): a kinematic body moved to where its
## owner's states put it now. Its car loads by hash at whatever tier is here (D80): the class's
## built-in car in the player's colour until its data arrives, then a box its size, then its
## smallest LOD, then the full model, each swapped in as it lands. The dedicated server and bots
## never load models.

## Ticks without car contact after a placed car (a reset or the grid) moves.
const TELEPORT_GHOST_TICKS := 2

## The game that owns this car (the server's peer id for it).
var peer := 0
## The car package's hash ("" until picked).
var car_hash := ""
var buffer := MotionBuffer.new()
## Where server time comes from (NetSession.now).
var clock := Callable()

## Bots measure how far off what they showed was (net_check): shown positions by time, and the
## errors found when the true state for that time arrives.
static var measure := false
var errors := PackedFloat32Array()
var _shown_t := PackedFloat64Array()
var _shown_p := PackedVector3Array()

var _tier := ""
var _loading_tier := ""
var _no_contact := 0
var _was_ghost := false
var _last := 0.0


func setup() -> void:
	super()
	process_physics_priority = -70 # after the network is polled, before the RaceField


## Loads (or upgrades) the car from whatever is here.
func load_net_car() -> void:
	var at: Dictionary = Net.content.car(car_hash) if Net.content and car_hash else {}
	var path := String(at.get("path", ""))
	var tier := String(at.get("tier", ""))
	var opts := {}
	if path.is_empty():
		path = default_car
		tier = "default"
	elif Game.dedicated or Game.dev.has("bot"):
		opts = { "models": "none", "partial": true }
		tier = "data"
	elif tier != "full":
		opts = { "models": "smallest" if tier == "preview" else "none", "partial": true }
	if tier == _tier or tier == _loading_tier:
		return
	_loading_tier = tier
	PackageLoader.load_shared(path, _on_net_car.bind(tier), opts)


func _on_net_car(pkg: VehiclePackage, tier: String) -> void:
	if tier != _loading_tier:
		pkg.free_scenes()
		return
	_loading_tier = ""
	if not is_inside_tree() or not pkg.ok():
		if pkg.ok():
			pkg.free_scenes()
		elif tier != "default":
			push_warning("%s: car failed to load: %s" % [display_name, pkg.error])
		return
	_tier = tier
	if vehicle == null:
		_spawn(pkg)
	else:
		vehicle.mount(pkg) # swaps at once: nothing here drives it
	if tier == "default":
		vehicle.visual.set_paint("primary", color, "solid")
	_car_changed()


func _spawn(pkg: VehiclePackage) -> void:
	super(pkg)
	vehicle.placeholder_color = color
	vehicle.set_remote(true)
	vehicle.name = "Vehicle_net%d" % net_id
	if not buffer.is_empty():
		_apply(0.0, true)


## Nobody drives it here.
func _make_driver() -> Node:
	var n := Node.new()
	n.name = "Remote"
	return n


func push_state(s: CarState, now: float) -> void:
	if measure:
		_measure(s)
	if buffer.push(s, now) and vehicle:
		vehicle.remote_state = s


## Compares the true position at `s.time` with what was shown then (between the two ticks
## around it).
func _measure(s: CarState) -> void:
	if s.flags & (CarState.FLAG_TELEPORT | CarState.FLAG_WAITING) != 0:
		return
	for i in range(_shown_t.size() - 2, -1, -1):
		if _shown_t[i] <= s.time and s.time <= _shown_t[i + 1]:
			var u := (s.time - _shown_t[i]) / maxf(_shown_t[i + 1] - _shown_t[i], 1e-6)
			errors.append(_shown_p[i].lerp(_shown_p[i + 1], u).distance_to(s.xform.origin))
			return


func _physics_process(delta: float) -> void:
	if vehicle == null or buffer.is_empty():
		return
	_apply(delta, false)


func _apply(delta: float, snap: bool) -> void:
	var now: float = clock.call() if clock.is_valid() else ClockSync.local_now()
	var p := buffer.pose(now, delta)
	if p.is_empty():
		return
	var s: CarState = p.state
	vehicle.remote_state = s
	var placed := s.flags & CarState.FLAG_TELEPORT != 0 and s.time > _last
	_last = s.time
	if placed:
		_no_contact = TELEPORT_GHOST_TICKS
	vehicle.move_remote(p.xform, p.velocity, p.angular, snap or placed)
	if measure:
		_shown_t.append(now)
		_shown_p.append(p.xform.origin)
		if _shown_t.size() > 120:
			_shown_t = _shown_t.slice(60)
			_shown_p = _shown_p.slice(60)
	waiting = s.flags & CarState.FLAG_WAITING != 0
	vehicle.visible = not waiting
	var ghost := waiting or s.flags & CarState.FLAG_GHOSTED != 0 or _no_contact > 0
	if ghost != _was_ghost:
		_was_ghost = ghost
		ghosted = ghost
		vehicle.set_ghost(ghost, ghost and not session.ghosted and not waiting)
	if _no_contact > 0:
		_no_contact -= 1


## Where the car is on the track. Its own game runs its lap timer, track limits and resets.
func update_track(delta: float) -> void:
	var com_world := vehicle.global_transform * vehicle.center_of_mass
	var proj := track.project(com_world, track_index)
	track_index = proj.index
	distance = proj.distance
	lateral = proj.lateral
	speed = vehicle.speed()
	on_track = absf(lateral) < track.width / 2.0 + 1.0
	timer.update(track.from_start(distance), delta, vehicle.remote_velocity.length())
