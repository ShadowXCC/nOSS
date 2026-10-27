class_name MeshBatch
extends RefCounted
## Triangles gathered for one world piece (a road segment's asphalt, a barrier run), then made
## into a mesh and a collision shape. Quads are given counter-clockwise as seen from their front.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
var index := PackedInt32Array()


func is_empty() -> bool:
	return index.is_empty()


func vertex(p: Vector3, n: Vector3, uv: Vector2, c := Color.WHITE) -> int:
	verts.append(p)
	normals.append(n)
	uvs.append(uv)
	colors.append(c)
	return verts.size() - 1


## A quad from four vertex indices, counter-clockwise from the front (Godot's fronts are clockwise).
func quad_i(a: int, b: int, c: int, d: int) -> void:
	index.append_array([a, c, b, a, d, c])


## A flat-shaded quad from corners (counter-clockwise from the front).
func quad(p: Array, uv: Array, c := Color.WHITE) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	var first := verts.size()
	for k in 4:
		vertex(p[k], n, uv[k], c)
	quad_i(first, first + 1, first + 2, first + 3)


## An oriented box; `size` along the basis' x, y, z. UVs run `uv_scale` along each face from u0.
func box(center: Vector3, basis: Basis, size: Vector3, uv_scale := Vector2.ONE, u0 := 0.0) -> void:
	var h := size / 2.0
	var c := []
	for i in 8:
		c.append(center + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f: Array in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		quad([c[f[0]], c[f[1]], c[f[2]], c[f[3]]], [Vector2(u0, 1), Vector2(u0, 0), Vector2(u0 + uv_scale.x, 0), Vector2(u0 + uv_scale.x, 1)])


## How far a wall's end narrows to its nose (D218).
const WALL_TAPER_M := 1.5
## An end that runs on into another piece narrows each face 1 m in this many, and goes on that far
## past its point (at least WALL_TAPER_M). Gently enough that a car sliding over the join isn't
## kicked off the wall: a 1.5 m run-on in a parapet knocked it 2 m/s, a full-width one 7 m/s
## (wall_grind_test).
const RUN_ON_SLOPE := 20.0
## What's left of a wall's thickness at its nose.
const WALL_NOSE := 0.02
## A mitered corner keeps the wall's thickness down to this cosine of half its turn (a 120° turn);
## sharper ones come out thinner instead of spiking.
const MITER_MIN_COS := 0.5


## A wall along `path` (height, thickness), standing on the path's points: one strip, mitered at
## each point, its sides and top shared from segment to segment, so a car sliding along it meets
## no edge to catch on (D218). A closed path (its last point on its first) goes round with no
## ends. An open one narrows to a nose over its last WALL_TAPER_M at each end, so a car brushing
## past glances off; an end that runs on into a piece built apart (`run_on_start`, `run_on_end`)
## goes on past its point instead (RUN_ON_SLOPE), narrowing inside that piece's wall, so the join
## neither shows nor catches. Returns the texture coordinate it ended at, so runs can continue it.
func wall(path: PackedVector3Array, height: float, thick: float, u := 0.0, tile_m := 4.0, run_on_start := false, run_on_end := false) -> float:
	var pts := PackedVector3Array()
	for p in path:
		if pts.is_empty() or p.distance_to(pts[-1]) >= 0.01:
			pts.append(p)
	if pts.size() < 2:
		return u
	var closed := pts.size() > 3 and pts[0].distance_to(pts[-1]) < 0.02
	var lead := 0.0 # the run-on before the path's first point
	var tail := 0.0
	var taper := minf(WALL_TAPER_M, _length(pts) / 2.0)
	var run_on := maxf(WALL_TAPER_M, (thick - WALL_NOSE) / 2.0 * RUN_ON_SLOPE)
	if closed:
		pts[-1] = pts[0]
	else:
		# A point where a real end's narrowing stops, if its segment is longer.
		if not run_on_start and pts[0].distance_to(pts[1]) > taper + 0.05:
			pts.insert(1, pts[0].move_toward(pts[1], taper))
		if not run_on_end and pts[-1].distance_to(pts[-2]) > taper + 0.05:
			pts.insert(pts.size() - 1, pts[-1].move_toward(pts[-2], taper))
		if run_on_start:
			lead = run_on
			pts.insert(0, pts[0] + (pts[0] - pts[1]).normalized() * lead)
		if run_on_end:
			tail = run_on
			pts.append(pts[-1] + (pts[-1] - pts[-2]).normalized() * tail)
	var count := pts.size()
	var segs := count - 1
	# Along the wall, and each segment's level side (+: left, going along).
	var at := PackedFloat32Array([0.0])
	var sides: Array[Vector3] = []
	for i in segs:
		at.append(at[i] + pts[i].distance_to(pts[i + 1]))
		var side := Vector3.UP.cross(pts[i + 1] - pts[i])
		sides.append(side.normalized() if side.length() > 0.0001 else (sides[-1] if i > 0 else Vector3.RIGHT))
	var total := at[-1]
	var ease_in := lead if run_on_start else taper
	var ease_out := tail if run_on_end else taper
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in count:
		var before := sides[(i - 1 + segs) % segs] if closed or i > 0 else sides[0]
		var after := sides[i % segs] if closed or i < segs else sides[segs - 1]
		var miter := (before + after).normalized()
		if miter.length() < 0.5: # turning right back
			miter = after
		miter /= maxf(miter.dot(after), MITER_MIN_COS)
		var width := thick
		if not closed:
			width = lerpf(WALL_NOSE, thick, clampf(minf(at[i] / ease_in, (total - at[i]) / ease_out), 0.0, 1.0))
		left.append(pts[i] + miter * width / 2.0)
		right.append(pts[i] - miter * width / 2.0)
	var up := Vector3.UP * height
	for i in segs:
		var u0 := u + (at[i] - lead) / tile_m
		var u1 := u + (at[i + 1] - lead) / tile_m
		var l0 := left[i]
		var l1 := left[i + 1]
		var r0 := right[i]
		var r1 := right[i + 1]
		quad([l0, l0 + up, l1 + up, l1], [Vector2(u0, 1), Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1)])
		quad([r0, r1, r1 + up, r0 + up], [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)])
		quad([r0 + up, r1 + up, l1 + up, l0 + up], [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)])
	if not closed: # the noses
		var u0 := u - lead / tile_m
		var u1 := u + (total - lead) / tile_m
		quad([left[0], right[0], right[0] + up, left[0] + up], [Vector2(u0, 1), Vector2(u0, 1), Vector2(u0, 0), Vector2(u0, 0)])
		quad([right[-1], left[-1], left[-1] + up, right[-1] + up], [Vector2(u1, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u1, 0)])
	return u + (total - lead - tail) / tile_m


static func _length(path: PackedVector3Array) -> float:
	var out := 0.0
	for i in path.size() - 1:
		out += path[i].distance_to(path[i + 1])
	return out


func append(other: MeshBatch) -> void:
	var offset := verts.size()
	verts.append_array(other.verts)
	normals.append_array(other.normals)
	uvs.append_array(other.uvs)
	colors.append_array(other.colors)
	for i in other.index:
		index.append(i + offset)


## Whether meshes may be made on a worker: not headless, where the stand-in renderer's mesh store
## isn't thread-safe (making them on two threads at once corrupts it).
static func threaded() -> bool:
	return DisplayServer.get_name() != "headless"


func mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## The triangles as a collision shape (faces in the mesh's winding).
func shape() -> ConcavePolygonShape3D:
	var s := ConcavePolygonShape3D.new()
	s.set_faces(faces())
	return s


## The triangles as a list of corners, three per face (no engine calls: safe on a worker).
func faces() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(index.size())
	for k in index.size():
		out[k] = verts[index[k]]
	return out
