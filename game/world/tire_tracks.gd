class_name TireTracks
extends Node3D
## Tracks behind the wheels (D197): dark lines through fallen snow, and grass, dirt, sand and
## gravel marked off the road. Only to look at: each game lays its own for every car it draws
## (its own rays under the wheels, so remote cars too), nothing goes on the wire, and they fade
## after a while. Tracks in fallen snow go as it melts. As many as the graphics preset allows.

enum Kind { NONE, SNOW_ROAD, SNOW, SNOWFIELD, GRASS, DIRT, SAND, GRAVEL }

const SHADER := preload("res://game/world/tire_tracks.gdshader")
## Each kind's colour and opacity: snow on a road shows the wet road through it.
const COLORS := {
	Kind.SNOW_ROAD: Color(0.16, 0.16, 0.17, 0.6),
	Kind.SNOW: Color(0.52, 0.56, 0.62, 0.55),
	Kind.SNOWFIELD: Color(0.6, 0.64, 0.7, 0.55),
	Kind.GRASS: Color(0.27, 0.22, 0.13, 0.5),
	Kind.DIRT: Color(0.2, 0.15, 0.1, 0.5),
	Kind.SAND: Color(0.5, 0.42, 0.28, 0.45),
	Kind.GRAVEL: Color(0.3, 0.28, 0.25, 0.45),
}
## Snow on the ground (EnvDirector's, under the car) from which wheels leave tracks in it.
const SNOW_MIN := 0.25
## How long tracks last (s); they fade over the second half.
const LIFE_SNOW_S := 60.0
const LIFE_GROUND_S := 45.0
## Cars further than this from every camera leave none; at most CARS of them at once.
const NEAR_M := 90.0
const CARS := { "low": 6, "medium": 12, "high": 20 }
## Track quads kept at once: CHUNKS of CHUNK_QUADS (the oldest chunk goes first).
const CHUNKS := { "low": 16, "medium": 32, "high": 64 }
const CHUNK_QUADS := 256
## How often each car's wheels are looked at, and which cars those are (Hz).
const SAMPLE_HZ := 20.0
const CHOOSE_HZ := 4.0
## A new point once a wheel has gone speed x STEP_S, between STEP_MIN_M and STEP_MAX_M.
const STEP_S := 0.08
const STEP_MIN_M := 0.4
const STEP_MAX_M := 3.0
## A wheel further than this from its last point starts a new strip (a reset, a jump).
const BREAK_M := 6.0
## The front wheels leave their own tracks once a car slides this much (degrees) at SLIDE_MPS.
const SLIDE_DEG := 8.0
const SLIDE_MPS := 3.0
## Lifted off the ground (m), against flicker; the ground can be this far past a wheel's radius
## (its suspension) and the wheel still on it.
const LIFT_M := 0.04
const REACH_M := 0.12
const WIDTH_M := 0.2
## Cars this near a camera have their tracks drawn right up to the wheels every frame (between
## samples a track would otherwise start a little behind them).
const TAIL_M := 40.0

## Session seconds (stops while paused); every quad is stamped with it.
var now := 0.0
var max_cars := 12
var _material: ShaderMaterial
var _chunks: Array[MeshInstance3D] = []
var _data: Array[Dictionary] = [] # per chunk: {verts, normals, colors, uvs, uv2s, quads, newest, dirty}
var _active := 0
## Per car (by instance id): {next (s), resets, fitted, widths, near (m to a camera),
## strips: {wheel: {at, n, l, r, along, kind, edges}}}.
var _cars := {}
var _marking: Array = [] # untyped: a car may be freed while it's in here
var _tails: MeshInstance3D
var _choose_in := 0.0
var _near := {} # car instance id -> m to the nearest camera, as last chosen
var _ray := PhysicsRayQueryParameters3D.new()
static var _indices := PackedInt32Array()


func _ready() -> void:
	name = "TireTracks"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"origin_shift")
	max_cars = int(CARS.get(Settings.graphics, 12))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("life_snow", LIFE_SNOW_S)
	_material.set_shader_parameter("life_ground", LIFE_GROUND_S)
	for i in int(CHUNKS.get(Settings.graphics, 32)):
		var mi := MeshInstance3D.new()
		mi.name = "Chunk%d" % i
		mi.mesh = ArrayMesh.new()
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks.append(mi)
		_data.append(_empty())
	_tails = MeshInstance3D.new()
	_tails.name = "Tails"
	_tails.mesh = ArrayMesh.new()
	_tails.material_override = _material
	_tails.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tails)
	_ray.collision_mask = Vehicle.LAYER_WORLD
	if _indices.is_empty():
		for q in CHUNK_QUADS:
			_indices.append_array([4 * q, 4 * q + 1, 4 * q + 2, 4 * q, 4 * q + 2, 4 * q + 3])


## What a wheel on `surface` leaves with `snow` (0..1) lying on the ground.
static func kind(surface: int, snow: float) -> Kind:
	if surface == VehicleSim.SURFACE_SNOW or surface == VehicleSim.SURFACE_ICE:
		return Kind.SNOWFIELD
	if snow >= SNOW_MIN:
		return Kind.SNOW_ROAD if surface >= 0 and surface <= VehicleSim.SURFACE_PAINT else Kind.SNOW
	match surface:
		VehicleSim.SURFACE_GRASS:
			return Kind.GRASS
		VehicleSim.SURFACE_DIRT:
			return Kind.DIRT
		VehicleSim.SURFACE_SAND:
			return Kind.SAND
		VehicleSim.SURFACE_GRAVEL:
			return Kind.GRAVEL
	return Kind.NONE


## True for tracks in fallen snow (they go as it melts).
static func melts(k: Kind) -> bool:
	return k == Kind.SNOW_ROAD or k == Kind.SNOW


## The surface at world `point` on `collider`, read as the sim reads it: its noss_surface, or its
## surface map's cell there.
static func surface_at(collider: Object, point: Vector3) -> int:
	if collider == null:
		return -1
	var s := int(collider.get_meta(&"noss_surface", 0))
	var map: Object = collider.get_meta(&"noss_surface_map") if collider.has_meta(&"noss_surface_map") else null
	if map:
		var cell := int(map.call(&"surface_at", point.x, point.z))
		if cell >= 0:
			s = cell
	return s


## Quads drawn now.
func quad_count() -> int:
	var n := 0
	for d in _data:
		n += int(d.quads)
	return n


## Quads the chunks hold at most.
func capacity() -> int:
	return _chunks.size() * CHUNK_QUADS


func _process(delta: float) -> void:
	now += delta
	_material.set_shader_parameter("now", now)
	_choose_in -= delta
	if _choose_in <= 0.0:
		_choose_in = 1.0 / CHOOSE_HZ
		_choose()
		_expire()
	var space := get_world_3d().direct_space_state
	for entry in _marking:
		if not is_instance_valid(entry) or not (entry as Vehicle).is_inside_tree():
			continue
		var v: Vehicle = entry
		var st: Dictionary = _cars.get(v.get_instance_id(), {})
		if st.is_empty():
			# Spread the cars over the sampling interval.
			st = { "next": now + float(v.get_instance_id() % 7) / 7.0 / SAMPLE_HZ, "resets": v.reset_count, "fitted": null, "widths": PackedFloat32Array(),
				"near": 0.0, "strips": {} }
			_cars[v.get_instance_id()] = st
		st.near = float(_near.get(v.get_instance_id(), 0.0))
		if now >= float(st.next):
			st.next = now + 1.0 / SAMPLE_HZ
			_sample(v, st, space)
	_flush()
	_draw_tails()


## The cars that leave tracks for now: the nearest a camera, up to max_cars.
func _choose() -> void:
	var cams := PackedVector3Array()
	for rig in CameraRig.rigs:
		if is_instance_valid(rig) and rig.camera.is_inside_tree():
			cams.append(rig.camera.global_position)
	var near: Array = []
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var v := node as Vehicle
		if v == null or not v.is_inside_tree() or v.fitted == null:
			continue
		var d := 0.0 # with no camera (tests) every car is near
		if not cams.is_empty():
			d = INF
			for c in cams:
				d = minf(d, c.distance_to(v.global_position))
			if d > NEAR_M:
				continue
		near.append([d, v])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_marking.clear()
	_near.clear()
	var keep := {}
	for pair: Array in near.slice(0, max_cars):
		_marking.append(pair[1])
		_near[(pair[1] as Vehicle).get_instance_id()] = pair[0]
		keep[(pair[1] as Vehicle).get_instance_id()] = true
	# A car that stops leaving tracks starts afresh when it next does.
	for id: int in _cars.keys():
		if not keep.has(id):
			_cars.erase(id)


## Looks under the wheels of `v` and lays any track they've made since last time.
func _sample(v: Vehicle, st: Dictionary, space: PhysicsDirectSpaceState3D) -> void:
	var f := v.fitted
	if f == null or f.physics_wheels.is_empty():
		return
	var strips: Dictionary = st.strips
	if v.reset_count != int(st.resets):
		st.resets = v.reset_count
		strips.clear()
	if st.fitted != f:
		st.fitted = f
		st.widths = _widths(f)
	var widths: PackedFloat32Array = st.widths
	var xf := v.get_global_transform_interpolated()
	var up := xf.basis.y.normalized()
	var vel := v.remote_velocity if v.remote else v.linear_velocity
	var flat := vel - up * vel.dot(up)
	var speed := flat.length()
	var heading := xf.basis.z if flat.dot(xf.basis.z) >= 0.0 else -xf.basis.z
	var sliding := speed > SLIDE_MPS and rad_to_deg(flat.angle_to(heading)) > SLIDE_DEG
	var rear := 0
	for pw: Dictionary in f.physics_wheels:
		rear = maxi(rear, int(pw.axle))
	var snow := v.road_conditions().y
	var step := clampf(speed * STEP_S, STEP_MIN_M, STEP_MAX_M)
	var own: Array[RID] = [v.get_rid()]
	_ray.exclude = own
	for i in f.physics_wheels.size():
		var pw: Dictionary = f.physics_wheels[i]
		# The rear wheels always; the front ones too once the car slides off their line.
		if int(pw.axle) != rear and not sliding:
			strips.erase(i)
			continue
		if not v.remote and v.sim.get_wheel_visual(i).w < 0.5: # in the air
			strips.erase(i)
			continue
		var hub: Vector3 = xf * (pw.center as Vector3)
		_ray.from = hub + up * 0.1
		_ray.to = hub - up * (float(pw.radius) + REACH_M)
		var hit := space.intersect_ray(_ray)
		var k := Kind.NONE
		if not hit.is_empty():
			k = kind(surface_at(hit.collider, hit.position), snow)
		if k == Kind.NONE:
			strips.erase(i)
			continue
		var n: Vector3 = hit.normal
		var at: Vector3 = hit.position + n * LIFT_M
		var prev: Dictionary = strips.get(i, {})
		if prev.is_empty() or int(prev.kind) != k or at.distance_to(prev.at) > BREAK_M:
			strips[i] = { "at": at, "n": n, "l": at, "r": at, "along": 0.0, "kind": k, "edges": false }
			continue
		var d := at.distance_to(prev.at)
		if d < step:
			continue
		var across := n.cross((at - prev.at) / d).normalized() * (widths[i] * 0.5)
		var l: Vector3 = prev.l if prev.edges else prev.at + across
		var r: Vector3 = prev.r if prev.edges else prev.at - across
		var along: float = prev.along
		_quad(l, r, at - across, at + across, n, along, along + d, k)
		strips[i] = { "at": at, "n": n, "l": at + across, "r": at - across, "along": along + d, "kind": k, "edges": true }


## Each physics wheel's width: the widest model wheel that shows it.
static func _widths(f: Fitting.Result) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(f.physics_wheels.size())
	out.fill(0.0)
	for w in f.wheels.size():
		if w >= f.wheel_map.size():
			break
		for j in f.wheel_map[w]:
			out[j] = maxf(out[j], float(f.wheels[w].get("width", 0.0)))
	for j in out.size():
		out[j] = clampf(out[j] if out[j] > 0.0 else WIDTH_M, 0.08, 0.6)
	return out


## One quad of track from edge (l0, r0) to (r1, l1), lying on `n`, `along0` to `along1` metres.
func _quad(l0: Vector3, r0: Vector3, r1: Vector3, l1: Vector3, n: Vector3, along0: float, along1: float, k: Kind) -> void:
	var d: Dictionary = _data[_active]
	if int(d.quads) >= CHUNK_QUADS:
		_active = (_active + 1) % _chunks.size()
		d = _empty()
		_data[_active] = d
	var mi := _chunks[_active]
	if int(d.quads) == 0:
		mi.position = l0 # near its tracks, so its vertices stay small
	_append(d, mi.position, [l0, r0, r1, l1], n, along0, along1, k)
	d.newest = now
	d.dirty = true


## Adds a quad (corners in world space) to `d`, whose mesh sits at `o`.
func _append(d: Dictionary, o: Vector3, corners: Array, n: Vector3, along0: float, along1: float, k: Kind) -> void:
	var c: Color = COLORS[k]
	var stamp := Vector2(now, 1.0 if melts(k) else 0.0)
	# Packed arrays come out of a dictionary as copies: append, then put them back.
	var verts: PackedVector3Array = d.verts
	for p: Vector3 in corners:
		verts.append(p - o)
	d.verts = verts
	var normals: PackedVector3Array = d.normals
	normals.append_array([n, n, n, n])
	d.normals = normals
	var colors: PackedColorArray = d.colors
	colors.append_array([c, c, c, c])
	d.colors = colors
	var uvs: PackedVector2Array = d.uvs
	uvs.append_array([Vector2(0.0, along0), Vector2(1.0, along0), Vector2(1.0, along1), Vector2(0.0, along1)])
	d.uvs = uvs
	var uv2s: PackedVector2Array = d.uv2s
	uv2s.append_array([stamp, stamp, stamp, stamp])
	d.uv2s = uv2s
	d.quads = int(d.quads) + 1


## The last bit of each near car's tracks, from its last point to under the wheel now.
func _draw_tails() -> void:
	var d := _empty()
	var o := Vector3.ZERO
	for entry in _marking:
		if not is_instance_valid(entry) or not (entry as Vehicle).is_inside_tree():
			continue
		var v: Vehicle = entry
		var st: Dictionary = _cars.get(v.get_instance_id(), {})
		if st.is_empty() or float(st.near) > TAIL_M or st.fitted != v.fitted or st.strips.is_empty():
			continue
		var xf := v.get_global_transform_interpolated()
		var up := xf.basis.y.normalized()
		var widths: PackedFloat32Array = st.widths
		for i: int in st.strips:
			var s: Dictionary = st.strips[i]
			var pw: Dictionary = v.fitted.physics_wheels[i]
			var at: Vector3 = xf * (pw.center as Vector3) - up * (float(pw.radius) - LIFT_M)
			var from: Vector3 = s.at
			var gap := at.distance_to(from)
			if gap < 0.05 or gap > BREAK_M:
				continue
			var n: Vector3 = s.n
			var across := n.cross((at - from) / gap).normalized() * (widths[i] * 0.5)
			if int(d.quads) == 0:
				o = from
			var l: Vector3 = s.l if s.edges else from + across
			var r: Vector3 = s.r if s.edges else from - across
			_append(d, o, [l, r, at - across, at + across], n, float(s.along), float(s.along) + gap, s.kind)
	_tails.position = o
	_build(_tails.mesh as ArrayMesh, d)


## Rebuilds the chunks that changed.
func _flush() -> void:
	for i in _chunks.size():
		var d: Dictionary = _data[i]
		if not d.dirty:
			continue
		d.dirty = false
		_build(_chunks[i].mesh as ArrayMesh, d)


func _build(mesh: ArrayMesh, d: Dictionary) -> void:
	mesh.clear_surfaces()
	if int(d.quads) == 0:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d.verts
	arrays[Mesh.ARRAY_NORMAL] = d.normals
	arrays[Mesh.ARRAY_COLOR] = d.colors
	arrays[Mesh.ARRAY_TEX_UV] = d.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = d.uv2s
	arrays[Mesh.ARRAY_INDEX] = _indices.slice(0, int(d.quads) * 6)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Empties chunks whose tracks have all faded.
func _expire() -> void:
	for i in _chunks.size():
		var d: Dictionary = _data[i]
		if int(d.quads) > 0 and now - float(d.newest) > LIFE_SNOW_S:
			_data[i] = _empty()
			_data[i].dirty = true


## The floating origin moved (D155): the tracks move with the world.
func origin_shifted(delta: Vector3) -> void:
	for mi in _chunks:
		mi.position += delta
	for st: Dictionary in _cars.values():
		for s: Dictionary in st.strips.values():
			s.at += delta
			s.l += delta
			s.r += delta
	_tails.position += delta


static func _empty() -> Dictionary:
	return { "verts": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "uvs": PackedVector2Array(),
		"uv2s": PackedVector2Array(), "quads": 0, "newest": -INF, "dirty": false }
