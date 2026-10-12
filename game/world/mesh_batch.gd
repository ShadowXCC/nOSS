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


## A wall of boxes along `path` (height, thickness), standing on the path's points. Returns the
## texture coordinate it ended at, so runs can continue it.
func wall(path: PackedVector3Array, height: float, thick: float, u := 0.0, tile_m := 4.0) -> float:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var dir := b - a
		var len := dir.length()
		if len < 0.01:
			continue
		var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
		box((a + b) / 2.0 + Vector3.UP * height / 2.0, basis, Vector3(thick, height, len + thick * 0.5), Vector2(len / tile_m, 1.0), u)
		u += len / tile_m
	return u


func append(other: MeshBatch) -> void:
	var offset := verts.size()
	verts.append_array(other.verts)
	normals.append_array(other.normals)
	uvs.append_array(other.uvs)
	colors.append_array(other.colors)
	for i in other.index:
		index.append(i + offset)


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
	var faces := PackedVector3Array()
	faces.resize(index.size())
	for k in index.size():
		faces[k] = verts[index[k]]
	var s := ConcavePolygonShape3D.new()
	s.set_faces(faces)
	return s
