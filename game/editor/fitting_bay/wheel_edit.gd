class_name WheelEdit
extends RefCounted
## Hand edits to a Fitting Bay draft's wheels (docs/VEHICLE_PACKAGE.md §7 step 3): which parts
## make up a wheel (whole meshes, or connected parts of a bigger mesh, which are split out), where
## it sits and how big it is, taking one out, making one from a part, and running the wheel finder
## again. Places and sizes are the vehicle frame in metres before a class scales the car, as the
## bay shows them; fit.json keeps them in the model's own units and frame.
##
## A part is {node (a mesh in the draft's scene), surface (-1: the whole mesh), triangles (of
## that surface, for part of one), center (root space), size (its longest side, metres)}.

## Parts listed for a wheel or a new one, at most.
const LISTED := 12
## A part further than this many wheel radii from the wheel's centre isn't near it.
const NEAR := 1.5
## Connected bits with fewer triangles aren't offered (bolts, seams).
const MIN_TRIANGLES := 24

var draft: FittingDraft
## ModelAnalysis.components() per "<mesh>:<surface>", with each part's triangles and box.
var _surfaces := {}
var _round: Array = []
var _size := -1.0


func _init(fitting: FittingDraft) -> void:
	draft = fitting


func ids() -> PackedStringArray:
	return PackedStringArray(draft.fit.wheels.map(func(w: Dictionary) -> String: return String(w.id)))


func wheel(id: String) -> Dictionary:
	for w: Dictionary in draft.fit.wheels:
		if w.id == id:
			return w
	return {}


func index_of(id: String) -> int:
	return ids().find(id)


## A wheel the model's own hub nodes carry (FM4 style): its parts and place come from the model.
func is_hub(id: String) -> bool:
	var w := wheel(id)
	return w.has("node") and w.get("pivot", "node") != "insert"


## The wheel that has the mesh named `node_name` as a part, or "".
func part_of(node_name: String) -> String:
	for w: Dictionary in draft.fit.wheels:
		if node_name in w.get("spin_nodes", []) + w.get("fixed_nodes", []):
			return String(w.id)
	return ""


## The wheel across the car from `id` (same axle, other side), or "".
func partner(id: String) -> String:
	var w := wheel(id)
	var other := String({ "L": "R", "R": "L" }.get(w.get("side", "C"), ""))
	for o: Dictionary in draft.fit.wheels:
		if o.side == other and int(o.axle) == int(w.axle):
			return String(o.id)
	return ""


## Wheels without any parts of the model (placed with sliders only).
func without_parts() -> PackedStringArray:
	var out := PackedStringArray()
	for w: Dictionary in draft.fit.wheels:
		if not is_hub(w.id) and (w.get("spin_nodes", []) + w.get("fixed_nodes", [])).is_empty():
			out.append(String(w.id))
	return out


# --- place and size ---------------------------------------------------------------


## Model space to the vehicle frame in metres, as Fitting does before a class scales the car.
static func base(fit: Dictionary) -> Transform3D:
	var mt: Dictionary = fit.model_transform
	return Transform3D(rotation(fit).scaled(Vector3.ONE * float(mt.scale)), _vec(mt.offset_m))


## The model's turn into the vehicle frame.
static func rotation(fit: Dictionary) -> Basis:
	var r: Array = fit.model_transform.rotation_deg
	return Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))


## The vehicle-frame floor under the model (its lowest point), metres.
static func floor_y(fit: Dictionary) -> float:
	var env: Dictionary = fit.envelope
	return (base(fit) * AABB(_vec(env.min), _vec(env.max) - _vec(env.min))).position.y


## Where wheel `id` is and how big: across, height (of the hub over the floor), along, radius
## and width.
func values(id: String) -> Dictionary:
	var w := wheel(id)
	var s := float(draft.fit.model_transform.scale)
	var v := base(draft.fit) * _vec(w.center)
	return { "across": v.x, "height": v.y - floor_y(draft.fit), "along": v.z, "radius": float(w.radius) * s, "width": float(w.width) * s }


## Sets one of values() for wheel `id`. With `mirror` its partner across the car follows, mirrored
## about the middle of the wheels.
func move(id: String, key: String, value: float, mirror := true) -> void:
	var other := partner(id) if mirror else ""
	var middle := _middle()
	_set_value(id, key, value)
	if other:
		_set_value(other, key, 2.0 * middle - value if key == "across" else value)
	_fix_ground()


func _set_value(id: String, key: String, value: float) -> void:
	var w := wheel(id)
	var s := float(draft.fit.model_transform.scale)
	if key == "radius":
		w.radius = maxf(value, 0.01) / s
	elif key == "width":
		w.width = maxf(value, 0.01) / s
	else:
		var b := base(draft.fit)
		var v := b * _vec(w.center)
		v[{ "across": 0, "height": 1, "along": 2 }[key]] = value + (floor_y(draft.fit) if key == "height" else 0.0)
		w.center = ModelAnalysis._arr(b.affine_inverse() * v)


## The vehicle-frame x halfway between the left and right wheels.
func _middle() -> float:
	var sum := 0.0
	var n := 0
	for w: Dictionary in draft.fit.wheels:
		if w.side != "C":
			sum += (base(draft.fit) * _vec(w.center)).x
			n += 1
	return sum / n if n else 0.0


# --- parts ------------------------------------------------------------------------


## Wheel `id`'s parts: the ones that spin, then the fixed ones (calipers).
func parts(id: String) -> Array:
	var out := []
	for n: String in wheel(id).get("spin_nodes", []) + wheel(id).get("fixed_nodes", []):
		var mi := _mesh(n)
		if mi:
			out.append(_whole(mi))
	return out


## Parts near wheel `id` that no wheel has, nearest first: wheel-sized meshes, and connected
## parts of bigger meshes (the body).
func nearby(id: String) -> Array:
	var w := wheel(id)
	var center := _vec(w.center)
	var radius := float(w.radius)
	var reach := NEAR * radius
	var region := AABB(center - Vector3.ONE * reach, Vector3.ONE * 2.0 * reach)
	var taken := _taken()
	var out := []
	for mi in _visible_meshes():
		if taken.has(String(mi.name)):
			continue
		var xf := ModelAnalysis._to_root(mi, draft.scene)
		var box := xf * mi.mesh.get_aabb()
		if not box.grow(radius * 0.01).intersects(region):
			continue
		if _longest(box) < 3.0 * radius:
			if box.get_center().distance_to(center) < reach:
				out.append(_whole(mi))
			continue
		for s in mi.mesh.get_surface_count():
			var surface := _surface(mi, s)
			for l: int in surface.get("tris", {}):
				var b: AABB = xf * (surface.boxes[l] as AABB)
				if surface.tris[l].size() >= MIN_TRIANGLES and _longest(b) < 3.0 * radius and b.get_center().distance_to(center) < reach:
					out.append(_component(mi, s, surface.tris[l], b))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.center as Vector3).distance_to(center) < (b.center as Vector3).distance_to(center))
	return out.slice(0, LISTED)


## Round parts no wheel has (what the wheel finder looks at), biggest first: choices for a new
## wheel.
func round_parts() -> Array:
	if _round.is_empty():
		var hidden := {}
		for mi in _hidden():
			hidden[mi] = true
		var taken := _taken()
		var scale := float(draft.fit.model_transform.scale)
		for p: ModelAnalysis.Part in ModelAnalysis._wheel_parts(ModelAnalysis._meshes(draft.scene), hidden, _model_size()):
			if p.label < 0:
				if not taken.has(String(p.node.name)):
					_round.append(_whole(p.node))
				continue
			var tris := PackedInt32Array()
			for t in p.triangles.size():
				if p.triangles[t]:
					tris.append(t)
			_round.append({ "node": String(p.node.name), "surface": p.surface, "triangles": tris, "center": p.center, "size": 2.0 * p.radius * scale })
		_round.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.size > b.size)
	return _round.slice(0, LISTED)


## The part a click on the model means (`hit` from BayPreview.pick_ray): the whole mesh if a
## wheel has it or it's wheel-sized, otherwise the connected part of its surface that was hit.
func pick(hit: Dictionary) -> Dictionary:
	var mi := _mesh(String(hit.get("node", "")))
	if mi == null:
		return {}
	var whole := _whole(mi)
	if part_of(whole.node) or whole.size < 3.0 * _typical_radius() * float(draft.fit.model_transform.scale):
		return whole
	var surface := _surface(mi, int(hit.surface))
	if surface.is_empty() or int(hit.triangle) >= (surface.labels as PackedInt32Array).size():
		return whole
	var l: int = surface.labels[hit.triangle]
	return _component(mi, int(hit.surface), surface.tris[l], ModelAnalysis._to_root(mi, draft.scene) * (surface.boxes[l] as AABB))


## Adds `part` to wheel `id`, or drops it if the wheel has it; then the wheel is measured again
## from its parts. A part of a bigger mesh is split out into a mesh of its own first. A wheel
## that had no parts becomes one of the model's (and so do the wheels, if they were stock).
## Returns what happened, for the status line.
func toggle(id: String, part: Dictionary) -> String:
	var w := wheel(id)
	if w.is_empty() or part.is_empty():
		return ""
	if is_hub(id):
		return "Set by the model's hubs"
	var node_name: String = part.node
	if part.surface < 0 and _drop(w, node_name):
		_measure(w)
		_fix_ground()
		return "Dropped from " + id
	var owner := part_of(node_name) if part.surface < 0 else ""
	if owner:
		_drop(wheel(owner), node_name)
		_measure(wheel(owner))
	if part.surface >= 0:
		node_name = _split(part, id)
	if w.get("pivot", "") != "insert":
		w.node = "noss_hub_" + id
		w.spin_node = "noss_wheel_" + id
		w.pivot = "insert"
		draft.fit.wheel_mode = "model"
	var list := "fixed_nodes" if node_name.to_lower().contains("caliper") else "spin_nodes"
	var names: Array = w.get(list, [])
	names.append(node_name)
	w[list] = names
	_measure(w)
	_fix_ground()
	return "Added to " + id


## A new wheel made from `part`, placed and sized from it. Returns its id, or "" if the part
## isn't round (or the car's wheels are the model's own hubs).
func add(part: Dictionary) -> String:
	if part.is_empty() or draft.fit.wheels.any(func(w: Dictionary) -> bool: return is_hub(w.id)) or draft.fit.wheels.size() >= 16:
		return ""
	var m := ModelAnalysis.measure([_points(part)])
	if m.is_empty():
		return ""
	var node_name: String = part.node
	var owner := part_of(node_name) if part.surface < 0 else ""
	if owner:
		_drop(wheel(owner), node_name)
		_measure(wheel(owner))
	if part.surface >= 0:
		node_name = _split(part, "new")
	var w := {
		"id": "new", "axle": 1, "side": "C", "center": ModelAnalysis._arr(m.center), "radius": m.radius, "width": m.width,
		"node": "noss_hub_new", "spin_node": "noss_wheel_new", "pivot": "insert", "spin_nodes": [node_name],
	}
	if draft.fit.wheels.all(func(o: Dictionary) -> bool: return not o.has("node")):
		draft.fit.wheel_mode = "model"
	draft.fit.wheels.append(w)
	relabel()
	_fix_ground()
	return String(w.id)


## Takes wheel `id` out (its parts stay on the body). Not if that leaves fewer than two wheels or
## one axle: the car needs wheels front and back. Returns what happened.
func remove(id: String) -> String:
	var rest: Array = draft.fit.wheels.filter(func(w: Dictionary) -> bool: return w.id != id)
	var axles := {}
	for w: Dictionary in rest:
		axles[int(w.axle)] = true
	if rest.size() < 2 or axles.size() < 2:
		return "Need wheels front and back"
	draft.fit.wheels = rest
	_fix_ground()
	return id + " removed"


## Ids, axles and sides from where the wheels are now (ModelAnalysis.wheel_ids), front first.
## Wheels on the model's own hubs keep theirs.
func relabel() -> void:
	var wheels: Array = draft.fit.wheels
	if wheels.any(func(w: Dictionary) -> bool: return is_hub(w.id)):
		return
	var turn := rotation(draft.fit)
	var out := []
	for label: Dictionary in ModelAnalysis.wheel_ids(wheels.map(func(w: Dictionary) -> Vector3: return turn * _vec(w.center)),
			wheels.map(func(w: Dictionary) -> float: return float(w.radius))):
		var w: Dictionary = wheels[label.index]
		w.id = label.id
		w.axle = label.axle
		w.side = label.side
		if w.get("pivot", "") == "insert":
			w.node = "noss_hub_" + label.id
			w.spin_node = "noss_wheel_" + label.id
		out.append(w)
	draft.fit.wheels = out


## Runs the wheel finder on the model again (for a car fitted before it improved) and takes its
## wheels; the rest of the fit stays as it is. Returns how many it found; with none the wheels
## are left as they were.
func find_again() -> int:
	var had_parts: bool = draft.fit.wheels.any(func(w: Dictionary) -> bool: return w.has("node"))
	var a := ModelAnalysis.analyze(draft.scene)
	if a.scene_changed:
		draft.scene_changed = true
	_forget()
	if a.wheel_source == "":
		return 0
	draft.fit.wheels = a.fit.wheels
	if not had_parts:
		draft.fit.wheel_mode = a.fit.wheel_mode
	relabel()
	_fix_ground()
	return draft.fit.wheels.size()


## How a part is listed: its own name if it has a readable one, else "Part <n>", and its size.
static func label(part: Dictionary, n: int) -> String:
	var node_name: String = part.node
	var own := int(part.surface) < 0 and not node_name.begins_with("noss_")
	return "%s · %.2f m" % [node_name if own else "Part %d" % n, float(part.size)]


# --- helpers ------------------------------------------------------------------------


func _drop(w: Dictionary, node_name: String) -> bool:
	for list in ["spin_nodes", "fixed_nodes"]:
		var names: Array = w.get(list, [])
		if node_name in names:
			names.erase(node_name)
			if list == "fixed_nodes" and names.is_empty():
				w.erase(list)
			return true
	return false


## Centre and size from the wheel's parts, if any of them is round.
func _measure(w: Dictionary) -> void:
	var sets := []
	for n: String in w.get("spin_nodes", []) + w.get("fixed_nodes", []):
		var mi := _mesh(n)
		if mi:
			sets.append(ModelAnalysis.sample(mi, ModelAnalysis._to_root(mi, draft.scene)))
	var m := ModelAnalysis.measure(sets)
	if not m.is_empty():
		w.center = ModelAnalysis._arr(m.center)
		w.radius = m.radius
		w.width = m.width


## The ground line follows the wheels (as the import works it out).
func _fix_ground() -> void:
	draft.fit.ground_y = ModelAnalysis.ground_of(draft.fit.wheels, rotation(draft.fit))


## Splits a part of a bigger mesh out into its own mesh (the model has to be exported again).
func _split(part: Dictionary, id: String) -> String:
	var mi := _mesh(part.node)
	var mask := PackedByteArray()
	mask.resize((_surface(mi, part.surface).labels as PackedInt32Array).size())
	for t: int in part.triangles:
		mask[t] = 1
	var node_name := ModelAnalysis.split_out(draft.scene, mi, part.surface, mask, id)
	draft.scene_changed = true
	_forget()
	return node_name


func _forget() -> void:
	_surfaces.clear()
	_round.clear()


func _points(part: Dictionary) -> PackedVector3Array:
	var mi := _mesh(part.node)
	if mi == null:
		return PackedVector3Array()
	var xf := ModelAnalysis._to_root(mi, draft.scene)
	if part.surface < 0:
		return ModelAnalysis.sample(mi, xf)
	return ModelAnalysis.triangle_points(_surface(mi, part.surface), xf, Array(part.triangles))


## Surface `s` of `mi` in connected parts: ModelAnalysis.components() plus each part's triangles
## and box (mesh space). {} for a mesh too big to split up.
func _surface(mi: MeshInstance3D, s: int) -> Dictionary:
	var key := "%d:%d" % [mi.mesh.get_instance_id(), s]
	if not _surfaces.has(key):
		var triangles := 0
		for i in mi.mesh.get_surface_count():
			triangles += _triangle_count(mi.mesh, i)
		if triangles > ModelAnalysis.MAX_COMPONENT_TRIANGLES:
			_surfaces[key] = {}
			return {}
		var c := ModelAnalysis.components(mi, s, ModelAnalysis._to_root(mi, draft.scene), _model_size())
		var verts: PackedVector3Array = c.verts
		var index: PackedInt32Array = c.index
		var labels: PackedInt32Array = c.labels
		var boxes := {}
		var tris := {} # label -> Array of triangles (packed arrays would be copied on access)
		for t in labels.size():
			var l := labels[t]
			var box := AABB(verts[index[t * 3]], Vector3.ZERO) if not boxes.has(l) else boxes[l] as AABB
			if not tris.has(l):
				tris[l] = []
			boxes[l] = box.expand(verts[index[t * 3]]).expand(verts[index[t * 3 + 1]]).expand(verts[index[t * 3 + 2]])
			tris[l].append(t)
		c.boxes = boxes
		c.tris = tris
		_surfaces[key] = c
	return _surfaces[key]


static func _triangle_count(mesh: Mesh, s: int) -> int:
	var arrays := mesh.surface_get_arrays(s)
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	return (index as PackedInt32Array).size() / 3 if index is PackedInt32Array and not (index as PackedInt32Array).is_empty() \
			else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func _whole(mi: MeshInstance3D) -> Dictionary:
	var box := ModelAnalysis._to_root(mi, draft.scene) * mi.mesh.get_aabb()
	return { "node": String(mi.name), "surface": -1, "triangles": PackedInt32Array(), "center": box.get_center(),
		"size": _longest(box) * float(draft.fit.model_transform.scale) }


func _component(mi: MeshInstance3D, s: int, tris: Array, box: AABB) -> Dictionary:
	return { "node": String(mi.name), "surface": s, "triangles": PackedInt32Array(tris), "center": box.get_center(),
		"size": _longest(box) * float(draft.fit.model_transform.scale) }


## Node names any wheel uses, and the meshes the fit hides.
func _taken() -> Dictionary:
	var out := {}
	for w: Dictionary in draft.fit.wheels:
		for n: String in w.get("spin_nodes", []) + w.get("fixed_nodes", []) + [w.get("node", ""), w.get("spin_node", "")]:
			out[n] = true
	for mi in _hidden():
		out[String(mi.name)] = true
	return out


func _hidden() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for pattern: String in draft.fit.get("hide_nodes", []):
		for mi: MeshInstance3D in draft.scene.find_children(pattern, "MeshInstance3D", true, false):
			out.append(mi)
	return out


func _visible_meshes() -> Array[MeshInstance3D]:
	var hidden := _hidden()
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in draft.scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh and mi not in hidden:
			out.append(mi)
	return out


func _mesh(node_name: String) -> MeshInstance3D:
	var mi := draft.scene.find_child(node_name, true, false) as MeshInstance3D if node_name else null
	return mi if mi and mi.mesh else null


func _typical_radius() -> float:
	var sum := 0.0
	for w: Dictionary in draft.fit.wheels:
		sum += float(w.radius)
	return sum / draft.fit.wheels.size() if not draft.fit.wheels.is_empty() else 0.3


func _model_size() -> float:
	if _size < 0.0:
		_size = ModelAnalysis.model_size(draft.scene)
	return _size


static func _longest(box: AABB) -> float:
	return box.size[box.size.max_axis_index()]


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
