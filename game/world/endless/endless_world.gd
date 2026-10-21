class_name EndlessWorld
extends Node3D
## The endless world round the players (docs/GAMEMODES.md §4, MODE-06, D156): the road
## (RoadWindow) from AHEAD_M ahead of the leader to BEHIND_M behind the last, its meshes and
## collision chunk by chunk; the ground in 256 m tiles within NEAR_M of the road (shaped to the
## road, painted by biome, props scattered over it; collision only near the road), and coarse
## 1 km tiles out to the horizon; the sea where there's coast. Meshes, ground and scatter are made on
## worker threads; the main thread only adds the nodes, a little each frame (BUDGET_MS). Nothing is
## kept that's out of range, so memory stays flat however far you drive.

signal built_near(distance: float)

const AHEAD_M := 3000.0
const BEHIND_M := 900.0
const TILE := 256
const NEAR_M := 420.0
## Tiles this close to the road have collision; props this close to it are solid.
const COLLIDE_M := 90.0
const SOLID_PROPS_M := 40.0
const FAR_TILE := 1024
const FAR_CELLS := 32
const FAR_RADIUS_M := 4600.0
## Far ground shows only beyond this from a camera, a little below the near ground: each of its
## vertices under the lowest near ground in the BLOCK_M squares round it.
const FAR_FROM_M := 380.0
const FAR_DROP_M := 2.5
const BLOCK_M := FAR_TILE / FAR_CELLS
## The road's bed blends back to the ground over this (gentler than a track's: deep cuttings).
const FALLOFF_M := 20.0
## Main-thread time for adding finished pieces each frame (ms).
const BUDGET_MS := 2.5
const SCAN_S := 0.4
## Bend signs on tight bends: tighter than this, every CHEVRON_EVERY_M on the outside.
const CHEVRON_CURVE := 1.0 / 110.0
const CHEVRON_EVERY_M := 24.0
const SEA_SIZE := 12000.0
## Off the road drives like a dirt road (TerrainData.LAYERS order): soft ground of every kind is
## dirt, bare rock is hard. Track grass keeps its penalty; falling snow still slips (VehicleSim).
const GROUND_SURFACES := [
	VehicleSim.SURFACE_DIRT, VehicleSim.SURFACE_DIRT, VehicleSim.SURFACE_DIRT, VehicleSim.SURFACE_DIRT,
	VehicleSim.SURFACE_CONCRETE, VehicleSim.SURFACE_DIRT, VehicleSim.SURFACE_CONCRETE, VehicleSim.SURFACE_ASPHALT,
]

var gen: NossRoadGen
var road := RoadWindow.new()
## How many lanes, and which side they're driven on (D190).
var lanes := EndlessLanes.new()
var origin: FloatingOrigin
## Off on a server (no meshes), and collision off where nothing drives (a server).
var visual := true
var collision := true
## () -> PackedFloat64Array: road distances to keep built round (the players').
var focus := Callable()
## () -> PackedVector3Array: scene points the far ground and sea follow (the players' cars).
var focus_points := Callable()
## Online (D159): each chunk's checksum as it's made ({chunk: checksum}), for EndlessNet to send
## the server (it takes them away).
var record_sums := false
var sums := {}
## Every piece's build counted, for the long-drive check: {road, tiles, far, jobs}.
var stats := { "road": 0, "tiles": 0, "far": 0, "jobs": 0, "freed_road": 0, "freed_tiles": 0, "freed_far": 0 }

var _chunk_tracks := {} # k -> RoadWindow (the chunk alone, in its maker's scene)
var _chunk_nodes := {} # k -> Node3D
var _tiles := {} # Vector2i (world tile) -> {node, terrain, map}
var _far := {} # Vector2i (world far tile) -> MeshInstance3D
var _jobs: Array[Job] = []
var _queued := {} # "road:k" / tile Vector2i / "far:..." -> true
var _scan := 0.0
var _sea: MeshInstance3D
var _far_material: ShaderMaterial
var _block_low := {} # Vector2i (world block) -> the near ground's lowest there
var _far_dirty := {} # Vector2i (world far tile) -> true: to be lowered under the near ground
var _scatter := {} # biome index -> [{prop, per_ha, near_road}]


## A piece being made on a worker.
class Job:
	var kind := ""
	var key: Variant
	var task := -1
	var ox := 0.0 # the origin it was made for
	var oz := 0.0
	var input := {}
	var result := {}


func _init() -> void:
	name = "EndlessWorld"


func _ready() -> void:
	add_to_group(&"origin_shift")
	for i in EndlessBiomes.all().size():
		_scatter[i] = EndlessBiomes.of(i).get("scatter", [])
	if visual:
		_far_material = ShaderMaterial.new()
		_far_material.shader = preload("res://game/world/noss_world.gdshader")
		_far_material.set_shader_parameter("albedo_texture", RetroTextures.grass())
		_far_material.set_shader_parameter("world_uv", true)
		_far_material.set_shader_parameter("uv_scale", Vector2.ONE / 8.0)
		_far_material.set_shader_parameter("roughness", 1.0)
		_far_material.set_shader_parameter("specular", 0.05)
		_make_sea()


func _exit_tree() -> void:
	for job in _jobs:
		WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()


## Builds the road round `distance` before anyone drives on it: the road (its collision too) within
## `near_m`, and the ground under it, here and now; the rest comes as usual.
func prime(distance: float, near_m := 360.0) -> void:
	_update_road(PackedFloat64Array([distance]))
	for k: int in _chunk_tracks:
		if absf((k + 0.5) * _chunk_m() - distance) <= near_m + _chunk_m():
			var job := _road_job(k)
			_run(job)
			_apply(job)
	var at := road.point_at(distance)
	for key in _wanted_tiles(PackedVector3Array([at]), 150.0):
		if not _tiles.has(key):
			_queued[key] = true
			var job := _tile_job(key)
			_run(job)
			_apply(job)


## True once the road's chunk at `distance` is built (cars may drive there).
func built_at(distance: float) -> bool:
	return _chunk_nodes.has(int(floorf(distance / _chunk_m())))


func _chunk_m() -> float:
	return TrackData.SAMPLE_M * NossRoadGen.chunk_samples()


func _process(delta: float) -> void:
	var distances: PackedFloat64Array = focus.call() if focus.is_valid() else PackedFloat64Array()
	if distances.is_empty():
		return
	_update_road(distances)
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_S
		_update_ground()
	var t0 := Time.get_ticks_usec()
	_collect()
	_lower_far(t0)
	if _sea:
		_follow_sea()


# --- the road ------------------------------------------------------------------------------------


func _update_road(distances: PackedFloat64Array) -> void:
	var lo := INF
	var hi := -INF
	for d in distances:
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var chunk_m := _chunk_m()
	var k_lo := maxi(floori((lo - BEHIND_M) / chunk_m), 0)
	var k_hi := floori((hi + AHEAD_M) / chunk_m) + 1
	# Somewhere else entirely (a player joined far off): start again there.
	if not road.is_empty() and (k_hi < road.chunks[0] or k_lo > road.chunks[-1] + 1):
		_clear()
	while road.is_empty() or road.chunks[-1] < k_hi:
		var k := k_lo if road.is_empty() else road.chunks[-1] + 1
		var data := gen.chunk(k)
		var c := RoadWindow.chunk_track(data, origin.x, origin.z, k, lanes.per_dir)
		if record_sums and sums.size() < 256:
			sums[k] = int(data.checksum)
		c.set_meta(&"ox", origin.x)
		c.set_meta(&"oz", origin.z)
		road.append(c)
		_chunk_tracks[k] = c
		if visual or collision:
			_queue(_road_job(k))
	if road.chunks.size() > 1 and road.chunks[0] < k_lo:
		var keep_from := k_lo * NossRoadGen.chunk_samples()
		road.trim_front(keep_from - road.first_index)
		for k: int in _chunk_tracks.keys():
			if k < road.chunks[0]:
				_chunk_tracks.erase(k)
				_queued.erase("road:%d" % k)
				if _chunk_nodes.has(k):
					(_chunk_nodes[k] as Node).queue_free()
					_chunk_nodes.erase(k)
					stats.freed_road += 1


func _road_job(k: int) -> Job:
	var job := Job.new()
	job.kind = "road"
	job.key = k
	var c: RoadWindow = _chunk_tracks[k]
	job.ox = float(c.get_meta(&"ox"))
	job.oz = float(c.get_meta(&"oz"))
	job.input = { "track": c, "ground": EndlessGround.of(gen, job.ox, job.oz) }
	return job


func _build_road(job: Job) -> void:
	var track: RoadWindow = job.input.track
	var rb := RoadBuilder.new(track, job.input.ground)
	rb.visual = visual
	rb.markings = EndlessMarkings.new(track, lanes)
	var batches := rb._batches(0, track.samples.size() - 1)
	if visual:
		batches["chevrons"] = _chevrons(track)
	job.result = { "builder": rb, "batches": batches, "built": rb.prebuild(batches) }


## Bend signs along the outside of tight bends.
func _chevrons(track: RoadWindow) -> MeshBatch:
	var out := MeshBatch.new()
	var parts := PropLibrary.parts("chevron")
	var next := -INF
	for i in track.samples.size():
		var k := track.curvature[i]
		if absf(k) < CHEVRON_CURVE or track.lifted[i] or track.distances[i] < next:
			continue
		next = track.distances[i] + CHEVRON_EVERY_M
		var side := -signf(k) # the outside
		var half := track.half_l[i] if side > 0.0 else track.half_r[i]
		var at := track.samples[i] + track.lefts[i] * side * (half + 1.3)
		var face := Basis(Vector3.UP, atan2(track.tangents[i].x, track.tangents[i].z))
		for part: Dictionary in parts:
			PropBuilder._append(out, part.batch, Transform3D(face, at))
	return out


# --- the ground ----------------------------------------------------------------------------------


## Tiles wanted near the road, far tiles round the players, and the ones no longer wanted go.
func _update_ground() -> void:
	if road.is_empty() or not (visual or collision):
		return
	var points := PackedVector3Array()
	for i in range(0, road.samples.size(), 16):
		points.append(road.samples[i])
	var wanted := _wanted_tiles(points, NEAR_M)
	# Only tiles the road won't come back to: it moves on along its axis, so a tile well behind the
	# window's far end is final.
	var axis := Vector2(sin(gen.axis_heading()), cos(gen.axis_heading()))
	var end := road.samples[-1]
	var end_axis := axis.dot(Vector2(end.x, end.z))
	for key: Vector2i in wanted:
		if _tiles.has(key) or _queued.has(key):
			continue
		var corner := _tile_scene(key)
		var far_corner := maxf(maxf(axis.dot(corner), axis.dot(corner + Vector2(TILE, 0))), maxf(axis.dot(corner + Vector2(0, TILE)), axis.dot(corner + Vector2(TILE, TILE))))
		if far_corner + FALLOFF_M + 40.0 > end_axis:
			continue
		_queue(_tile_job(key))
	for key: Vector2i in _tiles.keys():
		if not wanted.has(key):
			(_tiles[key].node as Node).queue_free()
			_tiles.erase(key)
			_queued.erase(key)
			_set_blocks(key, PackedFloat32Array())
			stats.freed_tiles += 1
	if visual:
		_update_far()


## World tiles within `reach` of any of `points` (scene).
func _wanted_tiles(points: PackedVector3Array, reach: float) -> Dictionary:
	var out := {}
	for p in points:
		var wx := p.x + origin.x
		var wz := p.z + origin.z
		for tx in range(floori((wx - reach) / TILE), floori((wx + reach) / TILE) + 1):
			for tz in range(floori((wz - reach) / TILE), floori((wz + reach) / TILE) + 1):
				var nx := clampf(wx, tx * TILE, (tx + 1) * TILE)
				var nz := clampf(wz, tz * TILE, (tz + 1) * TILE)
				if Vector2(nx - wx, nz - wz).length() <= reach:
					out[Vector2i(tx, tz)] = true
	return out


## A world tile's corner in the scene.
func _tile_scene(key: Vector2i) -> Vector2:
	return Vector2(key.x * TILE - origin.x, key.y * TILE - origin.z)


func _tile_job(key: Vector2i) -> Job:
	var job := Job.new()
	job.kind = "tile"
	job.key = key
	job.ox = origin.x
	job.oz = origin.z
	var corner := _tile_scene(key)
	var area := Rect2(corner, Vector2(TILE, TILE))
	# The road over the tile, in runs, for its bed; and whether it's near enough to collide.
	var reach := area.grow(FALLOFF_M + 12.0)
	var samples := PackedFloat32Array()
	var near := false
	var hits := PackedVector3Array()
	var half := 0.0
	var run := false
	for i in road.samples.size():
		var p := road.samples[i]
		var inside := reach.has_point(Vector2(p.x, p.z))
		if inside:
			TerrainData._append_samples(samples, road, [i])
			hits.append(p)
			half = maxf(half, maxf(road.half_l[i], road.half_r[i]))
			run = true
			if not near and area.grow(COLLIDE_M).has_point(Vector2(p.x, p.z)):
				near = true
		elif run:
			samples[samples.size() - 1] += 2.0 # the road leaves the tile here
			run = false
	if run:
		samples[samples.size() - 1] += 2.0
	job.input = { "corner": corner, "world": Vector2(key.x * TILE, key.y * TILE), "road": samples, "road_points": hits,
		"collide": near and collision, "half": half }
	return job


func _build_tile(job: Job) -> void:
	var corner: Vector2 = job.input.corner
	var world: Vector2 = job.input.world
	var n := TILE + 1
	var heights := gen.ground_heights(world.x, world.y, n, n, 1.0)
	var t := TerrainData.create(corner, Vector2i.ONE)
	t.field.set_base(heights)
	var rect := Rect2i(0, 0, n, n)
	var road_samples: PackedFloat32Array = job.input.road
	if not road_samples.is_empty():
		t.field.conform(rect, road_samples, FALLOFF_M, TerrainData.BED_DEPTH_M)
	# The ground with the road's cuttings and fills in (region_get would give it without them).
	var final := t.field.chunk_collision(0, 0, TILE)
	t.field.splat_region_set(rect, gen.tile_paint(world.x, world.y, n, n, 1.0, final))
	var result := { "terrain": t }
	if job.input.collide:
		result.collision = final
		result.map = t.field.surface_map(PackedByteArray(GROUND_SURFACES))
	if visual:
		result.scatter = _scatter_points(job, final)
		var blocks := PackedFloat32Array()
		var per := TILE / BLOCK_M
		for bz in per:
			for bx in per:
				blocks.append(t.field.chunk_range(bx, bz, BLOCK_M).x)
		result.blocks = blocks
	job.result = result


## Props over a tile by its biomes (each point's own mix), kept off the road and off steep ground.
func _scatter_points(job: Job, heights: PackedFloat32Array) -> Dictionary:
	var corner: Vector2 = job.input.corner
	var world: Vector2 = job.input.world
	var road_points: PackedVector3Array = job.input.road_points
	var half: float = job.input.half
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([gen.get_seed(), job.key])
	var n := TILE + 1
	var out := {} # prop -> {all: Array[Transform3D], solid: the ones near the road}
	var centre := gen.biome_at(world.x + TILE / 2.0, world.y + TILE / 2.0)
	var biomes := [int(centre.x)] if int(centre.x) == int(centre.y) else [int(centre.x), int(centre.y)]
	var hectares := float(TILE * TILE) / 10000.0
	for b: int in biomes:
		for spec: Dictionary in _scatter.get(b, []):
			var id := String(spec.prop)
			if not PropLibrary.TYPES.has(id):
				continue
			var info: Dictionary = PropLibrary.TYPES[id]
			var clear := half + 5.0 + float(info.get("clear_m", 0.0))
			var near_road := float(spec.get("near_road", INF))
			var count := roundi(float(spec.per_ha) * hectares)
			for c in count:
				var lx := rng.randf() * TILE
				var lz := rng.randf() * TILE
				var mix := gen.biome_at(world.x + lx, world.y + lz)
				var share := (1.0 - mix.z) if int(mix.x) == b else (mix.z if int(mix.y) == b else 0.0)
				if rng.randf() > share:
					continue
				var p := Vector3(corner.x + lx, 0.0, corner.y + lz)
				var nearest := INF
				for q in road_points:
					nearest = minf(nearest, Vector2(q.x - p.x, q.z - p.z).length())
				if road_points.is_empty():
					nearest = 1e6
				if nearest < clear or nearest > near_road:
					continue
				var ix := clampi(roundi(lx), 1, n - 2)
				var iz := clampi(roundi(lz), 1, n - 2)
				var h := heights[iz * n + ix]
				var slope := Vector2(heights[iz * n + ix + 1] - heights[iz * n + ix - 1], heights[(iz + 1) * n + ix] - heights[(iz - 1) * n + ix]).length() / 2.0
				if slope > float(info.get("slope", 0.8)) or h < 0.3:
					continue
				p.y = h
				if not out.has(id):
					out[id] = { "all": [], "solid": [] }
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), p)
				out[id].all.append(xf)
				if nearest < SOLID_PROPS_M + clear:
					out[id].solid.append(xf)
	return out


## Far tiles round the players: coarse, coloured by biome, a little below the near ground.
func _update_far() -> void:
	var points: PackedVector3Array = focus_points.call() if focus_points.is_valid() else PackedVector3Array()
	if points.is_empty():
		return
	var wanted := {}
	for p in points:
		var wx := p.x + origin.x
		var wz := p.z + origin.z
		var r := FAR_RADIUS_M
		for tx in range(floori((wx - r) / FAR_TILE), floori((wx + r) / FAR_TILE) + 1):
			for tz in range(floori((wz - r) / FAR_TILE), floori((wz + r) / FAR_TILE) + 1):
				var nx := clampf(wx, tx * FAR_TILE, (tx + 1) * FAR_TILE)
				var nz := clampf(wz, tz * FAR_TILE, (tz + 1) * FAR_TILE)
				if Vector2(nx - wx, nz - wz).length() <= r:
					wanted[Vector2i(tx, tz)] = true
	for key: Vector2i in wanted:
		var q := "far:%d:%d" % [key.x, key.y]
		if not _far.has(key) and not _queued.has(q):
			var job := Job.new()
			job.kind = "far"
			job.key = key
			job.ox = origin.x
			job.oz = origin.z
			_queue(job, q)
	for key: Vector2i in _far.keys():
		if not wanted.has(key):
			(_far[key] as Node).queue_free()
			_far.erase(key)
			_queued.erase("far:%d:%d" % [key.x, key.y])
			stats.freed_far += 1


func _build_far(job: Job) -> void:
	var key: Vector2i = job.key
	var cell := float(FAR_TILE) / FAR_CELLS
	var n := FAR_CELLS + 1
	var wx := float(key.x * FAR_TILE)
	var wz := float(key.y * FAR_TILE)
	var h := gen.ground_heights(wx, wz, n, n, cell)
	var colors: Array = []
	for b in EndlessBiomes.all():
		colors.append(Color.html(String(b.get("far_color", "#6f8f52"))))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var index := PackedInt32Array()
	var x0 := wx - job.ox
	var z0 := wz - job.oz
	for r in n:
		for c in n:
			var y := h[r * n + c]
			verts.append(Vector3(x0 + c * cell, y - FAR_DROP_M, z0 + r * cell))
			var hl := h[r * n + maxi(c - 1, 0)]
			var hr := h[r * n + mini(c + 1, n - 1)]
			var hd := h[maxi(r - 1, 0) * n + c]
			var hu := h[mini(r + 1, n - 1) * n + c]
			normals.append(Vector3(hl - hr, 2.0 * cell, hd - hu).normalized())
			var mix := gen.biome_at(wx + c * cell, wz + r * cell)
			var col: Color = (colors[int(mix.x)] as Color).lerp(colors[int(mix.y)], mix.z)
			if y < 1.0: # the shore
				col = col.lerp(Color(0.78, 0.72, 0.55), 0.7)
			elif int(mix.x) == NossRoadGen.biome_ids().find("alpine") and y > 230.0:
				col = col.lerp(Color(0.92, 0.94, 0.97), smoothstep(230.0, 270.0, y))
			cols.append(col)
	for r in n - 1:
		for c in n - 1:
			var a := r * n + c
			index.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n]) # facing up, as TerrainView's

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = index
	job.result = { "arrays": arrays, "heights": h, "mesh": _far_mesh(arrays) if MeshBatch.threaded() else null }


static func _far_mesh(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A near tile's lowest ground per block (empty: the tile's gone); the far tiles over it follow.
func _set_blocks(key: Vector2i, blocks: PackedFloat32Array) -> void:
	if not visual:
		return
	var per := TILE / BLOCK_M
	for bz in per:
		for bx in per:
			var b := Vector2i(key.x * per + bx, key.y * per + bz)
			if blocks.is_empty():
				_block_low.erase(b)
			else:
				_block_low[b] = blocks[bz * per + bx]
	# The far vertices on the tile's edges too, which a neighbouring far tile may hold.
	for fx in range(floori((key.x * per - 1) / float(FAR_CELLS)), floori((key.x * per + per) / float(FAR_CELLS)) + 1):
		for fz in range(floori((key.y * per - 1) / float(FAR_CELLS)), floori((key.y * per + per) / float(FAR_CELLS)) + 1):
			_far_dirty[Vector2i(fx, fz)] = true


## Far tiles whose near ground changed sink under it, while there's time this frame.
func _lower_far(t0: int) -> void:
	for key: Vector2i in _far_dirty.keys():
		if (Time.get_ticks_usec() - t0) / 1000.0 > BUDGET_MS:
			return
		_far_dirty.erase(key)
		if _far.has(key):
			_lower(_far[key], key)


func _lower(mi: MeshInstance3D, key: Vector2i) -> void:
	var arrays: Array = mi.get_meta(&"arrays")
	var h: PackedFloat32Array = mi.get_meta(&"heights")
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := FAR_CELLS + 1
	var bx := key.x * FAR_CELLS
	var bz := key.y * FAR_CELLS
	for r in n:
		for c in n:
			var low := minf(minf(_block_low.get(Vector2i(bx + c - 1, bz + r - 1), INF), _block_low.get(Vector2i(bx + c, bz + r - 1), INF)),
				minf(_block_low.get(Vector2i(bx + c - 1, bz + r), INF), _block_low.get(Vector2i(bx + c, bz + r), INF)))
			verts[r * n + c].y = minf(h[r * n + c], low) - FAR_DROP_M
	arrays[Mesh.ARRAY_VERTEX] = verts
	mi.mesh = _far_mesh(arrays)


# --- the sea -------------------------------------------------------------------------------------


func _make_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SEA_SIZE, SEA_SIZE)
	_sea = MeshInstance3D.new()
	_sea.name = "Sea"
	_sea.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = preload("res://game/world/noss_world.gdshader")
	m.set_shader_parameter("albedo", Color(0.16, 0.34, 0.46))
	m.set_shader_parameter("roughness", 0.15)
	m.set_shader_parameter("specular", 0.7)
	m.set_shader_parameter("snow_settle", 0.0)
	_sea.material_override = m
	_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sea.visible = false
	add_child(_sea)


## The sea under the players while there's coast near (it's at the world's sea level, y = 0).
func _follow_sea() -> void:
	var points: PackedVector3Array = focus_points.call() if focus_points.is_valid() else PackedVector3Array()
	if points.is_empty() or road.is_empty():
		return
	var coast := EndlessBiomes.index_of("coast")
	var any := false
	for i in range(0, road.biome.size(), 40):
		any = any or ((road.biome[i] == coast and road.blend[i] < 0.95) or (road.biome2[i] == coast and road.blend[i] > 0.05))
	_sea.visible = any
	if any:
		_sea.position = Vector3(snappedf(points[0].x, 64.0), -0.05, snappedf(points[0].z, 64.0))


# --- jobs ----------------------------------------------------------------------------------------


func _queue(job: Job, queued_key: Variant = null) -> void:
	var key: Variant = queued_key if queued_key != null else (("road:%d" % job.key) if job.kind == "road" else job.key)
	_queued[key] = true
	job.task = WorkerThreadPool.add_task(_run.bind(job), false, "Endless " + job.kind)
	_jobs.append(job)
	stats.jobs += 1


func _run(job: Job) -> void:
	match job.kind:
		"road":
			_build_road(job)
		"tile":
			_build_tile(job)
		"far":
			_build_far(job)


## Finished pieces into the world, oldest first, while there's time this frame.
func _collect() -> void:
	var t0 := Time.get_ticks_usec()
	var i := 0
	while i < _jobs.size():
		if (Time.get_ticks_usec() - t0) / 1000.0 > BUDGET_MS:
			return
		var job := _jobs[i]
		if not WorkerThreadPool.is_task_completed(job.task):
			i += 1
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.remove_at(i)
		_apply(job)


func _apply(job: Job) -> void:
	# Made for an origin since moved: everything it made moves by as much.
	var offset := Vector3(job.ox - origin.x, 0.0, job.oz - origin.z)
	match job.kind:
		"road":
			var k: int = job.key
			if not _chunk_tracks.has(k) or _chunk_nodes.has(k):
				return
			var node := Node3D.new()
			node.name = "Road_%d" % k
			add_child(node)
			node.position = offset
			var rb: RoadBuilder = job.result.builder
			rb.add_built(node, job.result.batches, job.result.built)
			_chunk_nodes[k] = node
			stats.road += 1
			built_near.emit((k + 0.5) * _chunk_m())
		"tile":
			var key: Vector2i = job.key
			if not _queued.has(key) or _tiles.has(key):
				return
			var t: TerrainData = job.result.terrain
			var node := Node3D.new()
			node.name = "Tile_%d_%d" % [key.x, key.y]
			add_child(node)
			node.position = offset
			var corner: Vector2 = job.input.corner + Vector2(offset.x, offset.z)
			t.field.set_origin(corner)
			t.meta.origin = [corner.x, corner.y]
			if visual:
				var view := TerrainView.build(t, false)
				view.position = -offset # the view places itself at the terrain's origin
				node.add_child(view)
			var map: NossSurfaceMap = job.result.get("map")
			if job.result.has("collision"):
				map.set_origin(corner)
				var body := StaticBody3D.new()
				body.name = "Ground"
				body.set_meta(&"noss_surface", VehicleSim.SURFACE_DIRT)
				body.set_meta(&"noss_surface_map", map)
				var shape := HeightMapShape3D.new()
				shape.map_width = TILE + 1
				shape.map_depth = TILE + 1
				shape.map_data = job.result.collision
				var cs := CollisionShape3D.new()
				cs.shape = shape
				body.add_child(cs)
				body.position = Vector3(job.input.corner.x + TILE / 2.0, 0.0, job.input.corner.y + TILE / 2.0)
				node.add_child(body)
			for id: String in job.result.get("scatter", {}):
				var lists: Dictionary = job.result.scatter[id]
				_add_scatter(node, id, lists.all, lists.solid if job.result.has("collision") else [])
			_tiles[key] = { "node": node, "terrain": t, "map": map }
			_set_blocks(key, job.result.get("blocks", PackedFloat32Array()))
			stats.tiles += 1
		"far":
			var key: Vector2i = job.key
			if _far.has(key):
				return
			var mi := MeshInstance3D.new()
			mi.name = "Far_%d_%d" % [key.x, key.y]
			mi.mesh = job.result.mesh if job.result.mesh else _far_mesh(job.result.arrays)
			mi.set_meta(&"arrays", job.result.arrays)
			mi.set_meta(&"heights", job.result.heights)
			mi.material_override = _far_material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_begin = FAR_FROM_M
			mi.visibility_range_begin_margin = 30.0
			add_child(mi)
			mi.position = offset
			_far[key] = mi
			_far_dirty[key] = true
			stats.far += 1


func _add_scatter(parent: Node3D, id: String, list: Array, solid: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PropLibrary.mesh(id)
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Scatter_" + id
	mmi.multimesh = mm
	mmi.visibility_range_end = PropBuilder.SCATTER_RANGE
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mmi)
	var shape := PropLibrary.scatter_shape(id)
	if not solid.is_empty() and not shape.is_empty():
		var body := StaticBody3D.new()
		body.name = "Scatter_%s_Body" % id
		body.set_meta(&"noss_surface", VehicleSim.SURFACE_CONCRETE)
		for t: Transform3D in solid:
			var cs := CollisionShape3D.new()
			cs.shape = shape.shape
			cs.transform = t * Transform3D(Basis(), shape.offset)
			body.add_child(cs)
		parent.add_child(body)


# --- the floating origin -------------------------------------------------------------------------


## The world moved (D155): every piece and the road move with it; the ground's maps too.
func origin_shifted(delta: Vector3) -> void:
	for child in get_children():
		if child is Node3D:
			(child as Node3D).position += delta
	road.shift(delta)
	var d2 := Vector2(delta.x, delta.z)
	for key: Vector2i in _tiles:
		var t: TerrainData = _tiles[key].terrain
		var o := t.origin() + d2
		t.meta.origin = [o.x, o.y]
		t.field.set_origin(o)
		if _tiles[key].map:
			(_tiles[key].map as NossSurfaceMap).set_origin(o)
	reset_physics_interpolation()


## Everything goes (a jump far along the road).
func _clear() -> void:
	for job in _jobs:
		WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()
	_queued.clear()
	for k: int in _chunk_nodes:
		(_chunk_nodes[k] as Node).queue_free()
	for key: Vector2i in _tiles:
		(_tiles[key].node as Node).queue_free()
	_chunk_nodes.clear()
	_chunk_tracks.clear()
	_tiles.clear()
	_block_low.clear()
	for key: Vector2i in _far:
		_far_dirty[key] = true
	road.clear()


## Pieces in the world now: {road, tiles, far, jobs} (the long-drive check watches them).
func counts() -> Dictionary:
	return { "road": _chunk_nodes.size(), "tiles": _tiles.size(), "far": _far.size(), "jobs": _jobs.size(), "samples": road.samples.size() }
