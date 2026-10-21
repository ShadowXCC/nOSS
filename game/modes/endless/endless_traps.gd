class_name EndlessTraps
extends Node3D
## Speed traps on the endless road (docs/GAMEMODES.md §4, D193), with the event's speed_traps on.
## Planned from the seed a chunk at a time (plan(), EndlessWorld keeps them for the road window),
## so every game has the same: cameras on poles, and patrol cars parked on the verge (EndlessTraffic
## parks them, in its PARKED slots). Crossing one going the players' way shows your speed and
## whether it's your best there (kept in your profile by road code), flashes the camera (not with
## reduce flashing), says it, and emits snapped: with police about (D194) a trap raises heat.

signal snapped(r: Racer, trap: Dictionary, speed_mps: float)

## A trap may be in every EVERY_CHUNKS-th chunk from FIRST_CHUNK on, one in ODDS of them; on
## straight road (no bend tighter than BENDY) for CLEAR_SAMPLES each way, not lifted. CAMERA_SHARE
## in ten are cameras, the rest parked patrols, but a camera where a barrier runs on its side (no
## car parks behind a rail).
const EVERY_CHUNKS := 3
const FIRST_CHUNK := 8
const ODDS := 4
const CAMERA_SHARE := 6
const CLEAR_SAMPLES := 20
const BENDY := 1.0 / 400.0
## A camera's pole and a patrol car this far out from the road's edge.
const POLE_OUT_M := 1.6
const PATROL_OUT_M := 1.3
const FLASH_S := 0.15
const FLASH_ENERGY := 12.0
## Road codes whose bests a profile keeps.
const BESTS_KEPT := 30

var session: TrackSession
var world: EndlessWorld
var lanes := EndlessLanes.new()
## The road's code (the bests are kept by it).
var code := ""
## Per racer this drive: {count, top (m/s)}.
var tally := {}
var _prev := {} # Racer -> distance last tick
var _cameras := {} # trap id -> Node3D
var _flash := {} # trap id -> seconds of flash left


## Whether `a` and `b` give a trap, and where: integer mixing (the same on every machine).
static func mix(a: int, b: int) -> int:
	var h := (a * 0x9E3779B1 + b * 0x85EBCA77 + 0x165667B1) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	h = ((h ^ (h >> 12)) * 0x297A2D39) & 0xFFFFFFFF
	return h ^ (h >> 15)


## Chunk `k`'s trap ({id, at_m, kind: "camera" or "patrol"}) or {}: from the road's seed and the
## chunk itself (NossRoadGen.chunk()), driven on the side `lanes` says.
static func plan(seed_value: int, k: int, chunk: Dictionary, road_lanes: EndlessLanes) -> Dictionary:
	if k < FIRST_CHUNK or k % EVERY_CHUNKS != 0 or chunk.is_empty():
		return {}
	var h := mix(seed_value & 0x7FFFFFFF, k)
	if h % ODDS != 0:
		return {}
	var lifted: PackedByteArray = chunk.lifted
	var curvature: PackedFloat32Array = chunk.curvature
	# The side the players' way drives on: the right edge (barrier_r) driving on the right.
	var barrier: PackedByteArray = chunk.barrier_l if road_lanes.side_sign(EndlessLanes.UP) > 0.0 else chunk.barrier_r
	var mid := lifted.size() / 2
	var railed := false
	for i in range(mid - CLEAR_SAMPLES, mid + CLEAR_SAMPLES + 1):
		if lifted[i] or absf(curvature[i]) > BENDY:
			return {}
		railed = railed or barrier[i] != 0
	return { "id": k, "at_m": TrackData.SAMPLE_M * (int(chunk.first) + mid), "kind": "camera" if railed or (h >> 8) % 10 < CAMERA_SHARE else "patrol" }


func _ready() -> void:
	name = "EndlessTraps"
	process_physics_priority = -45
	add_to_group(&"origin_shift")


func _physics_process(delta: float) -> void:
	_place_cameras()
	for id: int in _flash.keys():
		_flash[id] = float(_flash[id]) - delta
		if float(_flash[id]) <= 0.0:
			_flash.erase(id)
			var cam: Node3D = _cameras.get(id)
			if cam:
				(cam.get_node(^"Flash") as OmniLight3D).visible = false
	for p in session.players:
		if p.vehicle == null or p.waiting:
			_prev.erase(p)
			continue
		var was := float(_prev.get(p, p.distance))
		_prev[p] = p.distance
		if p.distance <= was or p.distance - was > 50.0: # not going the players' way, or moved (reset, join)
			continue
		for k: int in world.traps:
			var trap: Dictionary = world.traps[k]
			if was < float(trap.at_m) and p.distance >= float(trap.at_m):
				_snap(p, trap)


## `p` went by `trap` going the players' way.
func _snap(p: SessionPlayer, trap: Dictionary) -> void:
	var speed := absf(p.vehicle.speed())
	var t: Dictionary = tally.get(p, { "count": 0, "top": 0.0 })
	t.count = int(t.count) + 1
	t.top = maxf(float(t.top), speed)
	tally[p] = t
	var best := _best(p, int(trap.id), speed)
	var text := "Trap: %s %s%s" % [Settings.speed_text(speed), Settings.speed_unit(), " · Best" if best else ""]
	p.notify(text, 2.5)
	if Narrator.race_on(p.slot.profile):
		Narrator.say(text.replace(" · ", ", "))
	if trap.kind == "camera" and not _reduce_flashing():
		var cam: Node3D = _cameras.get(int(trap.id))
		if cam:
			(cam.get_node(^"Flash") as OmniLight3D).visible = true
			_flash[int(trap.id)] = FLASH_S
	snapped.emit(p, trap, speed)


## A new best for `p` at trap `id` on this road (kept in their profile)?
func _best(p: SessionPlayer, id: int, speed: float) -> bool:
	var profile := p.slot.profile
	var all: Dictionary = profile.data.get("trap_bests", {})
	var mine: Dictionary = all.get(code, {})
	var key := str(id)
	var before := float(mine.get(key, 0.0))
	if speed <= before:
		return false
	mine[key] = snappedf(speed, 0.01)
	all.erase(code) # newest last
	all[code] = mine
	while all.size() > BESTS_KEPT:
		all.erase(all.keys()[0])
	profile.data["trap_bests"] = all
	if not p.slot.ai:
		profile.save()
	return true


## Any player here asked for no flashing: no camera flash for anyone.
func _reduce_flashing() -> bool:
	for p in session.players:
		if bool(p.slot.profile.data.get("reduce_flashing", false)):
			return true
	return false


## "Traps: 6, top 186 km/h" for `p` this drive.
func tally_text(p: Racer) -> String:
	var t: Dictionary = tally.get(p, { "count": 0, "top": 0.0 })
	if int(t.count) == 0:
		return "Traps: 0"
	return "Traps: %d, top %s %s" % [int(t.count), Settings.speed_text(float(t.top)), Settings.speed_unit()]


## A camera at each camera trap in the road window (the patrols are the traffic's).
func _place_cameras() -> void:
	if not world.visual:
		return
	for id: int in _cameras.keys():
		if not world.traps.has(id):
			(_cameras[id] as Node).queue_free()
			_cameras.erase(id)
			_flash.erase(id)
	for k: int in world.traps:
		var trap: Dictionary = world.traps[k]
		if trap.kind != "camera" or _cameras.has(k) or world.road.index_of(float(trap.at_m)) < 0:
			continue
		var cam := Node3D.new()
		cam.name = "Camera_%d" % k
		var mi := MeshInstance3D.new()
		mi.mesh = PropLibrary.mesh("speed_camera")
		cam.add_child(mi)
		var light := OmniLight3D.new()
		light.name = "Flash"
		light.light_energy = FLASH_ENERGY
		light.omni_range = 18.0
		light.position = Vector3(0.0, 3.35, 0.6)
		light.visible = false
		cam.add_child(light)
		add_child(cam)
		cam.transform = camera_spot(trap)
		_cameras[k] = cam


## Where a camera trap's pole stands: off the edge on the players' way's side, facing the cars
## coming.
func camera_spot(trap: Dictionary) -> Transform3D:
	var road := world.road
	var d := float(trap.at_m)
	var side := lanes.side_sign(EndlessLanes.UP)
	var at := road.transform_at(d, side * (road.half_width(d, side) + POLE_OUT_M))
	return Transform3D(Basis(Vector3.UP, atan2(at.basis.z.x, at.basis.z.z) + PI), at.origin)


## The world moved (FloatingOrigin): the cameras with it.
func origin_shifted(delta: Vector3) -> void:
	for c in get_children():
		if c is Node3D:
			(c as Node3D).position += delta
