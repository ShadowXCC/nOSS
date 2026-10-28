class_name SceneTrack
extends RefCounted
## A track made from a 3D scene (Track Fitting, EDT-08; docs/TRACK_EDITOR.md §7.1): the scene's
## GLB and what each of its surfaces is to a car (scene/tags.json): road and other ground the
## wheels feel, walls, parts that are only seen, water that sends a car back to the road.
## A surface (one material on one mesh) takes its mesh's tag, else its material's, else the first
## rule matching its material's name, then its mesh's, else the default. Collision is concave
## shapes per tag, cut into CELL_M squares. What's under a point (ray_down) needs no physics, so
## the checks and "Measure widths" run anywhere.

const SCHEMA := "noss.scene_tags/1"
const TAGS := ["asphalt", "concrete", "curb", "paint", "grass", "gravel", "dirt", "sand", "snow", "ice", "wall", "no-collide", "water"]
## Tags a car drives on (VehicleSim surfaces, TrackFormat.SURFACES).
const DRIVABLE := ["asphalt", "concrete", "curb", "paint", "grass", "gravel", "dirt", "sand", "snow", "ice"]
const CELL_M := 256.0
const MAX_SHAPE_TRIS := 200_000
## ray_down's lookup grid, m.
const GRID_M := 8.0
## Measure widths: the sideways step, the farthest it looks, the biggest step up or down.
const WIDTH_STEP_M := 0.25
const WIDTH_MAX_M := 30.0
const WIDTH_STEP_UP_M := 0.4
## A scene's limits (TRACK_EDITOR §5); servers may lower them.
const LIMITS := {
	"max_lod0_triangles": 2_000_000, "max_nodes": 20000, "max_materials": 1024,
	"max_texture_size": 4096, "max_texture_bytes": 512 << 20, "max_zip_bytes": 100 << 20,
}
## What a new scene starts with: common words in material and mesh names.
const DEFAULT_RULES := [
	{ "match": "*water*", "tag": "water" }, { "match": "*lake*", "tag": "water" }, { "match": "*river*", "tag": "water" },
	{ "match": "*asphalt*", "tag": "asphalt" }, { "match": "*tarmac*", "tag": "asphalt" }, { "match": "*road*", "tag": "asphalt" },
	{ "match": "*kerb*", "tag": "curb" }, { "match": "*curb*", "tag": "curb" },
	{ "match": "*concrete*", "tag": "concrete" }, { "match": "*pavement*", "tag": "concrete" },
	{ "match": "*grass*", "tag": "grass" }, { "match": "*lawn*", "tag": "grass" }, { "match": "*gravel*", "tag": "gravel" },
	{ "match": "*sand*", "tag": "sand" }, { "match": "*dirt*", "tag": "dirt" }, { "match": "*mud*", "tag": "dirt" },
	{ "match": "*snow*", "tag": "snow" },
	{ "match": "*wall*", "tag": "wall" }, { "match": "*barrier*", "tag": "wall" }, { "match": "*fence*", "tag": "wall" },
	{ "match": "*leaf*", "tag": "no-collide" }, { "match": "*leaves*", "tag": "no-collide" }, { "match": "*foliage*", "tag": "no-collide" },
	{ "match": "*sky*", "tag": "no-collide" },
]

## The scene's GLB (scene/scene.glb).
var glb := PackedByteArray()
## The scene, parsed: what build() copies into the world. Freed with this object.
var scene: Node3D
## scene/tags.json.
var tags := {}
## [{mesh, material, tag, triangles}], one per material on each mesh.
var surfaces: Array[Dictionary] = []
var bounds := AABB()
var triangles := 0
var _faces := PackedVector3Array() # every triangle, 3 corners each
var _face_surface := PackedInt32Array()
var _grid := {} # Vector2i -> PackedInt32Array of triangles
var _rules: Array = [] # [[RegEx, tag]]


static func default_tags() -> Dictionary:
	return { "schema": SCHEMA, "rules": DEFAULT_RULES.duplicate(true), "materials": {}, "meshes": {}, "default": "auto", "style": "own" }


## A scene track from a GLB and its tags ({} for the defaults). error() says what's wrong.
static func from_glb(bytes: PackedByteArray, tag_data := {}, limits := LIMITS) -> SceneTrack:
	var s := SceneTrack.new()
	s.glb = bytes
	var check := PackageLoader.check_glb(bytes, limits)
	if check.error:
		s._error = "Scene can't be used: " + String(check.error)
		return s
	if int(check.triangles) > int(limits.max_lod0_triangles):
		s._error = "Scene too large: %d triangles" % int(check.triangles)
		return s
	s.scene = ModelImport._parse_glb(bytes, "")
	if s.scene == null:
		s._error = "Scene failed to load"
		return s
	s._collect()
	s.set_tags(tag_data if not tag_data.is_empty() else default_tags())
	return s


var _error := ""


func error() -> String:
	return _error


func ok() -> bool:
	return _error.is_empty()


## Frees the parsed scene now (it's freed anyway when the last reference to this goes).
func free_scene() -> void:
	if scene:
		scene.free()
		scene = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(scene):
		scene.free()


## Checks tags.json's data; "" or what's wrong.
static func validate_tags(d: Dictionary) -> String:
	var errors := JsonSchema.validate(d, JsonSchema.load_schema("scene_tags"))
	return errors[0] if not errors.is_empty() else ""


## Uses `tag_data` and tags every surface again.
func set_tags(tag_data: Dictionary) -> void:
	tags = tag_data.duplicate(true)
	_rules.clear()
	for r: Dictionary in tags.get("rules", []):
		_rules.append([RegEx.create_from_string("(?i)^" + _glob(String(r.match)) + "$"), String(r.tag)])
	for s in surfaces:
		s.tag = tag_for(String(s.mesh), String(s.material))


## A surface's tag: its mesh's, its material's, the first rule matching the material's name and
## then the mesh's, else the default ("auto" stays "auto": solid, driven on as concrete).
func tag_for(mesh: String, material: String) -> String:
	if tags.get("meshes", {}).has(mesh):
		return String(tags.meshes[mesh])
	if tags.get("materials", {}).has(material):
		return String(tags.materials[material])
	for name in [material, mesh]:
		for r: Array in _rules:
			if (r[0] as RegEx).search(name):
				return r[1]
	return String(tags.get("default", "auto"))


## A material's name without the number exporters add to tell same-named ones apart ("grey2",
## "Material.001"): the scene's materials are shown and tagged by these.
static func material_group(name: String) -> String:
	var m := RegEx.create_from_string("^(.*?)[._ -]*\\d+$").search(name)
	return m.get_string(1) if m and not m.get_string(1).is_empty() else name


## The scene's materials by group, sorted: [[group, surfaces, [material names]]].
func materials() -> Array:
	var groups := {}
	for s in surfaces:
		var g := material_group(s.material)
		if not groups.has(g):
			groups[g] = [g, 0, []]
		groups[g][1] += 1
		if s.material not in groups[g][2]:
			(groups[g][2] as Array).append(s.material)
	var out := groups.values()
	out.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]).naturalnocasecmp_to(b[0]) < 0)
	return out


## The tag most of a material group's surfaces have now.
func material_tag(group: String) -> String:
	var counts := {}
	for s in surfaces:
		if material_group(s.material) == group:
			counts[s.tag] = int(counts.get(s.tag, 0)) + 1
	var best := ""
	for t: String in counts:
		if best.is_empty() or counts[t] > counts[best]:
			best = t
	return best


## The surface hit by a straight-down line through (x, z) below `from_y`, nearest first:
## {hit, position, surface (index), tag, mesh, material}. `solid`: skip parts that are only seen.
func ray_down(x: float, z: float, from_y := INF, solid := true) -> Dictionary:
	var top := minf(from_y, bounds.end.y + 1.0)
	var from := Vector3(x, top, z)
	var best := -INF
	var found := -1
	for t: int in _grid.get(_cell(x, z), PackedInt32Array()):
		var surface := _face_surface[t]
		if solid and surfaces[surface].tag == "no-collide":
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, _faces[t * 3], _faces[t * 3 + 1], _faces[t * 3 + 2])
		if hit is Vector3 and (hit as Vector3).y > best:
			best = (hit as Vector3).y
			found = surface
	if found < 0:
		return { "hit": false }
	var s := surfaces[found]
	return { "hit": true, "position": Vector3(x, best, z), "surface": found, "tag": s.tag, "mesh": s.mesh, "material": s.material }


## Measure widths: the road's width each side of `t`'s centreline at each control point, on the
## scene. From the centreline it steps sideways WIDTH_STEP_M at a time while the ground stays
## the tag it is at the centre and doesn't step more than WIDTH_STEP_UP_M; each point takes the
## median over its segment. {point index: {width_l, width_r}} (points it can't measure are left out).
func measure_widths(t: TrackData) -> Dictionary:
	var out := {}
	for seg in t.seg_first.size():
		var span := t.segment_samples(seg)
		var sides := { "width_l": [], "width_r": [] }
		for k in range(span.x, span.y):
			var i := k % t.samples.size()
			var p := t.samples[i]
			var centre := ray_down(p.x, p.z, p.y + 2.0)
			if not centre.hit or String(centre.tag) not in DRIVABLE:
				continue
			var left := Vector3(t.lefts[i].x, 0.0, t.lefts[i].z).normalized()
			for side: Array in [["width_l", 1.0], ["width_r", -1.0]]:
				var y := (centre.position as Vector3).y
				var o := 0.0
				while o < WIDTH_MAX_M:
					var q := p + left * (o + WIDTH_STEP_M) * float(side[1])
					var hit := ray_down(q.x, q.z, y + 1.0)
					if not hit.hit or hit.tag != centre.tag or absf((hit.position as Vector3).y - y) > WIDTH_STEP_UP_M:
						break
					y = (hit.position as Vector3).y
					o += WIDTH_STEP_M
				(sides[side[0]] as Array).append(o)
		if (sides.width_l as Array).is_empty():
			continue
		var widths := {}
		for key: String in sides:
			var list: Array = sides[key]
			list.sort()
			widths[key] = clampf(snappedf(list[list.size() / 2], 0.1), 2.0, 30.0)
		out[seg] = widths
	return out


## The VehicleSim surface id a tag drives as.
static func surface_id(tag: String) -> int:
	return TrackFormat.surface_id(tag) if tag in DRIVABLE else TrackFormat.surface_id("concrete")


## Adds the scene to `root`: what's seen (unless not `visual`), a static body per tag with the
## surface the wheels read, and an Area3D over each water surface (meta noss_water).
func build(root: Node3D, visual := true) -> void:
	if visual and scene:
		var shown := scene.duplicate() as Node3D
		shown.name = "Scene"
		if tags.get("style", "own") == "retro":
			_retro(shown)
		root.add_child(shown)
	var bodies := {}
	for group: Dictionary in collision_groups():
		if not bodies.has(group.tag):
			var body := StaticBody3D.new()
			body.name = "Scene_" + String(group.tag).replace("-", "_")
			body.set_meta(&"noss_surface", surface_id(group.tag))
			body.set_meta(&"scene_tag", group.tag)
			root.add_child(body)
			bodies[group.tag] = body
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(group.faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		(bodies[group.tag] as StaticBody3D).add_child(cs)
	for box in water_boxes():
		var area := Area3D.new()
		area.name = "Water"
		area.set_meta(&"noss_water", true)
		area.monitorable = false
		area.collision_layer = 0
		area.collision_mask = Vehicle.LAYER_VEHICLES # cars aren't on the default layer
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = box.size
		cs.shape = b
		cs.position = box.get_center()
		area.add_child(cs)
		root.add_child(area)


## Triangles that collide, by tag and CELL_M square, at most MAX_SHAPE_TRIS each: [{tag, faces}].
func collision_groups() -> Array[Dictionary]:
	var buckets := {} # [tag, cell] -> PackedVector3Array
	for t in _face_surface.size():
		var tag := String(surfaces[_face_surface[t]].tag)
		if tag in ["no-collide", "water"]:
			continue
		var c := (_faces[t * 3] + _faces[t * 3 + 1] + _faces[t * 3 + 2]) / 3.0
		var key := [tag, Vector2i(floori(c.x / CELL_M), floori(c.z / CELL_M))]
		if not buckets.has(key):
			buckets[key] = PackedVector3Array()
		var faces: PackedVector3Array = buckets[key]
		faces.append_array([_faces[t * 3], _faces[t * 3 + 1], _faces[t * 3 + 2]])
		buckets[key] = faces
	var out: Array[Dictionary] = []
	for key: Array in buckets:
		var faces: PackedVector3Array = buckets[key]
		for from in range(0, faces.size(), MAX_SHAPE_TRIS * 3):
			out.append({ "tag": key[0], "faces": faces.slice(from, from + MAX_SHAPE_TRIS * 3) })
	return out


## A box under each water surface: from its top down, deep enough to catch a car.
func water_boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	for i in surfaces.size():
		if surfaces[i].tag != "water":
			continue
		var box := AABB()
		var first := true
		for t in _face_surface.size():
			if _face_surface[t] != i:
				continue
			for k in 3:
				box = AABB(_faces[t * 3 + k], Vector3.ZERO) if first else box.expand(_faces[t * 3 + k])
				first = false
		if not first:
			box.position.y -= 6.0
			box.size.y += 6.0
			out.append(box)
	return out


## tags.json's bytes.
func tags_bytes() -> PackedByteArray:
	return (JSON.stringify(tags, "  ") + "\n").to_utf8_buffer()


# --- internals ----------------------------------------------------------------------------


## Every mesh's triangles in the scene's space, one surface per material.
func _collect() -> void:
	surfaces.clear()
	_faces = PackedVector3Array()
	_face_surface = PackedInt32Array()
	var first := true
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := _to_scene(mi)
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mi.get_active_material(s)
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if index.is_empty():
				index.resize(verts.size())
				for k in verts.size():
					index[k] = k
			var id := surfaces.size()
			surfaces.append({ "mesh": String(mi.name), "material": String(mat.resource_name) if mat else "", "tag": "", "triangles": index.size() / 3 })
			for k in range(0, index.size() - 2, 3):
				for j in 3:
					var p := xf * verts[index[k + j]]
					_faces.append(p)
					bounds = AABB(p, Vector3.ZERO) if first else bounds.expand(p)
					first = false
				_face_surface.append(id)
	triangles = _face_surface.size()
	_index()


func _index() -> void:
	_grid.clear()
	for t in _face_surface.size():
		var a := _faces[t * 3]
		var b := _faces[t * 3 + 1]
		var c := _faces[t * 3 + 2]
		var lo := _cell(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
		var hi := _cell(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cz)
				if not _grid.has(key):
					_grid[key] = PackedInt32Array()
				var list: PackedInt32Array = _grid[key]
				list.append(t)
				_grid[key] = list


func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / GRID_M), floori(z / GRID_M))


func _to_scene(n: Node3D) -> Transform3D:
	var t := Transform3D()
	var c: Node = n
	while c and c != scene:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


## Small, sharp textures (retro_ps2), on copies of the materials.
static func _retro(root: Node3D) -> void:
	var done := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null:
				continue
			if not done.has(m):
				var copy := m.duplicate() as BaseMaterial3D
				copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				var tex := copy.albedo_texture
				if tex and maxi(tex.get_width(), tex.get_height()) > 256:
					var image := tex.get_image()
					if image.is_compressed():
						image.decompress()
					var k := 256.0 / maxi(image.get_width(), image.get_height())
					image.resize(maxi(1, int(image.get_width() * k)), maxi(1, int(image.get_height() * k)), Image.INTERPOLATE_BILINEAR)
					copy.albedo_texture = ImageTexture.create_from_image(image)
				done[m] = copy
			mi.set_surface_override_material(s, done[m])


static func _glob(pattern: String) -> String:
	var out := ""
	for c in pattern:
		out += ".*" if c == "*" else ("\\" + c if c in ".+?^$()[]{}|\\" else c)
	return out
