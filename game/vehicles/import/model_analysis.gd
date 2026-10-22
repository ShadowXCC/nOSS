class_name ModelAnalysis
extends RefCounted
## Works out how an imported model sits on a platform (docs/VEHICLE_PACKAGE.md §7 steps 2-6)
## and writes it as a fit.json the player can adjust: up and forward, wheels, scale, ground,
## envelope, parts to hide, paint slots, lights, steering wheel, eye point and cameras.
##
## Wheels: named FM4-style hubs if there are any; otherwise round, thin parts (whole meshes, or
## connected parts inside one) that share an axle direction, with wheel-like names counting
## as extra evidence. Wheels merged into a bigger mesh are split out into their own meshes,
## which changes the scene (scene_changed): the model then has to be re-exported.

const WHEEL_WORDS := ["wheel", "tire", "tyre", "rim", "felge", "reifen", "roue", "rueda", "ruota", "llanta"]
const NOT_WHEEL_WORDS := ["steer", "spare", "arch", "well", "house", "guard", "cover", "fender", "trim", "nut", "bolt"]
const HIDE_WORDS := ["ground", "floor", "plane", "shadow", "backdrop", "turntable", "podium", "fabric", "carpet"]
const FRONT_WORDS := ["front", "head"]
const REAR_WORDS := ["rear", "back", "tail", "exhaust", "trunk", "boot"]
const MAX_COMPONENT_TRIANGLES := 400_000
## Points sampled per part for shape tests.
const SAMPLES := 1500
const TYPICAL_WHEELBASE := 2.6
const UNITS := [1.0, 0.01, 0.001, 0.0254, 0.3048, 0.1]


class Result:
	## Wheels found: "hubs" (named hub nodes), "parts" (detected) or "" (none: stock anchors).
	var wheel_source := ""
	var fit := {}
	var paint := {}
	var family := "car"
	## The analysis split meshes; the scene has to be exported again.
	var scene_changed := false
	var notes := PackedStringArray()
	## Wheel parts per wheel id, for the Fitting Bay's markers.
	var wheel_nodes := {}
	## Materials used by wheel parts (painting them would paint the wheels).
	var wheel_materials := {}


class Part:
	var node: MeshInstance3D
	var surface := -1 # -1: the whole node
	var label := -1 # connected part within the surface, or -1
	var center := Vector3.ZERO # root space
	var normal := Vector3.ZERO # disc axis
	var radius := 0.0
	var width := 0.0
	var name_score := 0.0
	var triangles := PackedByteArray() # surface triangle mask for a connected part


## Analyzes `scene` (an imported model; split wheels are added to it).
static func analyze(scene: Node3D) -> Result:
	var r := Result.new()
	var meshes := _meshes(scene)
	var all_points := PackedVector3Array()
	for m: Dictionary in meshes:
		all_points.append_array(m.points)
	if all_points.is_empty():
		r.notes.append("No meshes found")
		r.fit = _empty_fit()
		return r
	var bounds := _aabb(all_points)
	var size := bounds.size.length()

	# Parts named like ground planes or stands are hidden.
	var hidden := {}
	for m: Dictionary in meshes:
		if _has_word(m.node.name, HIDE_WORDS):
			hidden[m.node] = true
			r.notes.append("Hid %s" % m.node.name)

	var hub_wheels := _named_hubs(scene)
	var wheels: Array = []
	if hub_wheels.size() >= 3:
		r.wheel_source = "hubs"
		wheels = hub_wheels
	else:
		var parts := _wheel_parts(meshes, hidden, size)
		wheels = _pick_wheels(parts)
		if wheels.size() >= 3:
			r.wheel_source = "parts"

	# Orientation from the wheels (or glTF's own axes without them).
	var left := Vector3.RIGHT
	var up := Vector3.UP
	var forward := Vector3.BACK # glTF +Z
	if wheels.size() >= 3:
		var shown := PackedVector3Array()
		for m: Dictionary in meshes:
			if not hidden.has(m.node):
				shown.append_array(m.points)
		var axes := _axes(wheels, shown)
		if not axes.is_empty() and r.wheel_source == "parts":
			var off := _off_ground(wheels, axes.up)
			if not off.is_empty():
				r.notes.append("Ignored %d wheel%s off the ground" % [off.size(), "s" if off.size() > 1 else ""])
				var kept := []
				for i in wheels.size():
					if i not in off:
						kept.append(wheels[i])
				wheels = kept
				axes = _axes(wheels, shown)
			if not axes.is_empty() and _match_partners(wheels, axes) > 0:
				axes = _axes(wheels, shown)
		if axes.is_empty():
			wheels = []
			r.wheel_source = ""
		else:
			left = axes.left
			up = axes.up
			forward = axes.forward
	var evidence := _forward_evidence(scene, wheels, forward)
	if evidence < 0.0:
		forward = -forward
		left = -left
	var to_vehicle := _snap(Basis(left, up, forward).transposed()) # model -> vehicle frame, unscaled

	# Hide stray big flat things under the car (display stands, ground cloth).
	if not wheels.is_empty():
		_hide_stands(meshes, hidden, wheels, to_vehicle, r)

	var visible_points := PackedVector3Array()
	for m: Dictionary in meshes:
		if not hidden.has(m.node):
			visible_points.append_array(m.points)
	var model_box := _aabb(visible_points if not visible_points.is_empty() else all_points)
	var vehicle_points := PackedVector3Array()
	for p in visible_points:
		vehicle_points.append(to_vehicle * p)
	var vehicle_box := _aabb(vehicle_points if not vehicle_points.is_empty() else PackedVector3Array([Vector3.ZERO]))

	var surface := _surface_samples(meshes, hidden, to_vehicle, 30000)

	var fit_wheels := []
	if r.wheel_source == "hubs":
		fit_wheels = _hub_fit_wheels(wheels, to_vehicle)
	elif r.wheel_source == "parts":
		fit_wheels = _part_fit_wheels(scene, wheels, to_vehicle, r)
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			node.remove_meta("noss_original_mesh")
			node.remove_meta("noss_removed")
	else:
		fit_wheels = _stock_anchors(vehicle_box, to_vehicle)
		r.notes.append("No wheels found: place them")

	# Scale from the wheelbase; snap to a common unit if one fits.
	var wheelbase := _wheelbase(fit_wheels, to_vehicle)
	var scale := _scale(wheelbase)
	var ground := ground_of(fit_wheels, to_vehicle)

	var euler := to_vehicle.get_euler()
	r.fit = {
		"schema": "noss.fit/1",
		"model_transform": {
			"scale": scale,
			"rotation_deg": [_round(rad_to_deg(euler.x), 3), _round(rad_to_deg(euler.y), 3), _round(rad_to_deg(euler.z), 3)],
			"offset_m": [0.0, 0.0, 0.0],
		},
		"ground_y": ground,
		"wheel_mode": "model" if r.wheel_source else "stock",
		"wheels": fit_wheels,
		"envelope": { "min": _arr(model_box.position), "max": _arr(model_box.end) },
		"lights": _lights(scene),
		"hide_nodes": hidden.keys().map(func(n: Node) -> String: return String(n.name)),
		"lod_distances_m": [0],
		"cameras": { "hood": null, "bumper": null },
	}
	var steering := _steering_wheel(scene)
	if steering:
		r.fit.steering_wheel = { "node": String(steering.name), "visual_lock_deg": 540 }
	_cockpit(r, scene, steering, surface, vehicle_box, to_vehicle, scale, ground)
	r.paint = _paint(meshes, hidden, r)
	r.family = _family(fit_wheels, surface, to_vehicle) if r.wheel_source else "car"
	if r.wheel_source:
		r.notes.append("%d wheels found" % fit_wheels.size())
	if not to_vehicle.is_equal_approx(Basis.IDENTITY):
		r.notes.append("Turned to face forward")
	if not is_equal_approx(scale, 1.0):
		r.notes.append("Scaled x%s" % String.num(scale, 3))
	return r


# --- meshes -------------------------------------------------------------------


## Every visible mesh: {node, xform (to root), points (sampled, root space), triangles}.
static func _meshes(scene: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := _to_root(mi, scene)
		var points := PackedVector3Array()
		var triangles := 0
		var total := 0
		for s in mi.mesh.get_surface_count():
			total += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var step := maxi(1, total / SAMPLES)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: Variant = arrays[Mesh.ARRAY_INDEX]
			triangles += (index as PackedInt32Array).size() / 3 if index is PackedInt32Array and not (index as PackedInt32Array).is_empty() else verts.size() / 3
			for i in range(0, verts.size(), step):
				points.append(xf * verts[i])
		out.append({ "node": mi, "xform": xf, "points": points, "triangles": triangles })
	return out


# --- wheels -------------------------------------------------------------------


## FM4-style hub nodes: hub_LF, hub_R2... Each {id, center (root), radius, width, hub, spin, fixed}.
static func _named_hubs(scene: Node3D) -> Array:
	var out := []
	var pattern := RegEx.create_from_string("^hub_(LF|RF|LR|RR|[LRC][1-8])$")
	for node: Node3D in scene.find_children("hub_*", "Node3D", true, false):
		var m := pattern.search(node.name)
		if m == null:
			continue
		var id := m.get_string(1)
		var spin := node.find_child("wheel_" + id, true, false) as Node3D
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in ([spin] if spin is MeshInstance3D else []) + (spin.find_children("*", "MeshInstance3D", true, false) if spin else []):
			var b := _to(mi, node) * mi.mesh.get_aabb() if mi.mesh else AABB()
			box = b if first else box.merge(b)
			first = false
		var radius := maxf(box.size.y, box.size.z) / 2.0 if not first else 0.3
		var width := box.size.x if not first else 0.2
		var fixed := []
		for child in node.get_children():
			if String(child.name).begins_with("caliper"):
				fixed.append(String(child.name))
		out.append({ "id": id, "center": _to_root(node, scene).origin, "radius": radius, "width": width,
			"hub": String(node.name), "spin": String(spin.name) if spin else "", "fixed": fixed, "normal": _to_root(node, scene).basis.x.normalized() })
	return out


## Round, thin parts that could be (part of) a wheel.
static func _wheel_parts(meshes: Array[Dictionary], hidden: Dictionary, size: float) -> Array[Part]:
	var parts: Array[Part] = []
	for m: Dictionary in meshes:
		if hidden.has(m.node):
			continue
		var mi: MeshInstance3D = m.node
		var named := _has_word(mi.name, WHEEL_WORDS) and not _has_word(mi.name, NOT_WHEEL_WORDS)
		var whole := _disc(m.points)
		if not whole.is_empty():
			var p := _part(mi, -1, -1, whole)
			p.name_score = 1.0 if named else 0.0
			parts.append(p)
			continue
		if int(m.triangles) > MAX_COMPONENT_TRIANGLES:
			continue
		# Wheels merged into a bigger mesh: look at its connected parts.
		var xf: Transform3D = m.xform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			if index.is_empty():
				index.resize(verts.size())
				for i in verts.size():
					index[i] = i
			var weld := 1e-4 * size / maxf(xf.basis.get_scale().length() / sqrt(3.0), 1e-12)
			var labels := NossMesh.components(index, verts, weld)
			var groups := {} # label -> Array of triangles (packed arrays would be copied on access)
			for t in labels.size():
				var l := labels[t]
				if not groups.has(l):
					groups[l] = []
				groups[l].append(t)
			if groups.size() < 3:
				continue
			for l: int in groups:
				var tris: Array = groups[l]
				if tris.size() < 24:
					continue
				var points := PackedVector3Array()
				var step := maxi(1, tris.size() / SAMPLES)
				for k in range(0, tris.size(), step):
					points.append(xf * verts[index[tris[k] * 3]])
					points.append(xf * verts[index[tris[k] * 3 + 1]])
				if _aabb(points).size.length() < 0.025 * size:
					continue
				var disc := _disc(points)
				if disc.is_empty():
					continue
				var p := _part(mi, s, l, disc)
				var mask := PackedByteArray()
				mask.resize(labels.size())
				for t: int in tris:
					mask[t] = 1
				p.triangles = mask
				p.name_score = 0.5 if named else 0.0
				parts.append(p)
	return parts


static func _part(mi: MeshInstance3D, surface: int, label: int, disc: Dictionary) -> Part:
	var p := Part.new()
	p.node = mi
	p.surface = surface
	p.label = label
	p.center = disc.center
	p.normal = disc.normal
	p.radius = disc.radius
	p.width = disc.width
	return p


## {center, normal, radius, width} if `points` look like a wheel (a round, thin shape), else {}.
static func _disc(points: PackedVector3Array) -> Dictionary:
	if points.size() < 12:
		return {}
	var pca: Dictionary = NossMesh.principal_axes(points)
	var axes: Array = pca.axes
	var lo := [INF, INF, INF]
	var hi := [-INF, -INF, -INF]
	for p in points:
		for k in 3:
			var d: float = (p - pca.center).dot(axes[k])
			lo[k] = minf(lo[k], d)
			hi[k] = maxf(hi[k], d)
	var extent := [hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]]
	# The disc normal is the thinnest direction.
	var thin := 0
	for k in 3:
		if extent[k] < extent[thin]:
			thin = k
	var a := (thin + 1) % 3
	var b := (thin + 2) % 3
	var diameter := maxf(extent[a], extent[b])
	if diameter <= 0.0 or minf(extent[a], extent[b]) / diameter < 0.8 or extent[thin] / diameter > 0.85:
		return {}
	var center: Vector3 = pca.center
	for k in 3:
		center += (axes[k] as Vector3) * (lo[k] + hi[k]) / 2.0
	# Round, not square: a square's corners reach 1.41 times its half-width.
	var normal := (axes[thin] as Vector3).normalized()
	var radius := diameter / 2.0
	var corners := 0
	for p in points:
		var d := p - center
		if (d - normal * d.dot(normal)).length() > 1.12 * radius:
			corners += 1
	if corners > points.size() / 20:
		return {}
	return { "center": center, "normal": normal, "radius": radius, "width": extent[thin] }


## Groups parts into wheels (tire + rim + disc around one axle) and picks the set that shares
## an axle direction. Each wheel: {center, normal, radius, width, parts: [Part]}.
static func _pick_wheels(parts: Array[Part]) -> Array:
	var wheels := []
	for p in parts:
		var joined := false
		for w: Dictionary in wheels:
			# Same axle line: close to the wheel's axis, within about a radius along it.
			var d: Vector3 = p.center - w.center
			var along := absf(d.dot(w.normal))
			var across := (d - (w.normal as Vector3) * d.dot(w.normal)).length()
			var r := maxf(w.radius, p.radius)
			if absf(p.normal.dot(w.normal)) > 0.9 and across < 0.25 * r and along < 1.0 * r:
				w.parts.append(p)
				if p.radius > w.radius:
					w.center = p.center
					w.radius = p.radius
				w.width = maxf(w.width, p.width)
				w.score = maxf(w.score, p.name_score)
				joined = true
				break
		if not joined:
			wheels.append({ "center": p.center, "normal": p.normal, "radius": p.radius, "width": p.width, "parts": [p], "score": p.name_score })
	# The biggest group with one axle direction and similar radii.
	var best := []
	var best_score := -1.0
	for w: Dictionary in wheels:
		var group := wheels.filter(func(o: Dictionary) -> bool:
			return absf(o.normal.dot(w.normal)) > 0.95 and o.radius / w.radius > 0.6 and o.radius / w.radius < 1.6)
		var score: float = group.size() + group.reduce(func(s: float, o: Dictionary) -> float: return s + o.score, 0.0) * 0.5
		score += group.reduce(func(s: float, o: Dictionary) -> float: return s + o.radius, 0.0) * 1e-3
		if group.size() >= 3 and score > best_score:
			best = group
			best_score = score
	# More than six: keep the biggest (headlights, gauges and badges can be round too).
	if best.size() > 6:
		best.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.radius > y.radius)
		var top: float = best[0].radius
		best = best.filter(func(o: Dictionary) -> bool: return o.radius > 0.75 * top).slice(0, 6)
	return best


## Indices of the wheels ({center, radius}) that don't stand on the ground: a bottom more than
## the wheel's radius above the lowest wheel's, along `up` (a turret ring, a roof light). None
## if fewer than three would be left.
static func _off_ground(wheels: Array, up: Vector3) -> Array[int]:
	var bottoms := PackedFloat64Array()
	for w: Dictionary in wheels:
		bottoms.append((w.center as Vector3).dot(up) - float(w.radius))
	var low := INF
	for b in bottoms:
		low = minf(low, b)
	var off: Array[int] = []
	for i in wheels.size():
		if bottoms[i] - low > float(wheels[i].radius):
			off.append(i)
	if wheels.size() - off.size() < 3:
		off.clear()
	return off


## A wheel much bigger than its partner across the car (at the same place along it) has taken
## in something round around it, such as a wheel arch liner (the Tezeract's right rear did; the
## left one's is tilted further and stayed out). Its parts bigger than the partner are dropped
## and it's measured again from what's left. Returns how many wheels changed.
static func _match_partners(wheels: Array, axes: Dictionary) -> int:
	var left: Vector3 = axes.left
	var forward: Vector3 = axes.forward
	var mid := Vector3.ZERO
	for w: Dictionary in wheels:
		mid += w.center / wheels.size()
	var radii: Array = wheels.map(func(w: Dictionary) -> float: return w.radius) # as found
	var changed := 0
	for w: Dictionary in wheels:
		var side := signf(((w.center as Vector3) - mid).dot(left))
		for i in wheels.size():
			var q: Dictionary = wheels[i]
			var partner: float = radii[i]
			if is_same(q, w) or absf(((q.center as Vector3) - w.center).dot(forward)) > 0.5 * minf(w.radius, partner) \
					or signf(((q.center as Vector3) - mid).dot(left)) == side:
				continue
			if w.radius <= 1.25 * partner:
				break
			var kept: Array = w.parts.filter(func(p: Part) -> bool: return p.radius <= 1.1 * partner)
			if kept.is_empty():
				break
			var biggest: Part = kept[0]
			var width := 0.0
			for p: Part in kept:
				width = maxf(width, p.width)
				if p.radius > biggest.radius:
					biggest = p
			w.parts = kept
			w.center = biggest.center
			w.normal = biggest.normal
			w.radius = biggest.radius
			w.width = width
			w.score = kept.reduce(func(s: float, p: Part) -> float: return maxf(s, p.name_score), 0.0)
			changed += 1
			break
	return changed


## Ids of a fit's wheels that don't stand on the ground (older imports could take a round part on
## the roof for a wheel).
static func floating_wheels(fit: Dictionary) -> PackedStringArray:
	var r: Array = fit.model_transform.rotation_deg
	var up := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2]))).transposed() * Vector3.UP
	var wheels := (fit.wheels as Array).map(func(w: Dictionary) -> Dictionary: return { "center": _vec(w.center), "radius": float(w.radius) })
	var out := PackedStringArray()
	for i in _off_ground(wheels, up):
		out.append(String(fit.wheels[i].id))
	return out


## left / up / forward from the wheels: the axle direction, the wheelbase direction, and up
## toward the body. {} if the wheels don't span two axles.
static func _axes(wheels: Array, all_points: PackedVector3Array) -> Dictionary:
	var axle: Vector3 = wheels[0].normal
	var mean := Vector3.ZERO
	for w: Dictionary in wheels:
		var n: Vector3 = w.normal
		mean += n if n.dot(axle) >= 0.0 else -n
	axle = mean.normalized()
	var centers := PackedVector3Array()
	var mid := Vector3.ZERO
	for w: Dictionary in wheels:
		centers.append(w.center - axle * (w.center as Vector3).dot(axle))
		mid += w.center / wheels.size()
	var pca: Dictionary = NossMesh.principal_axes(centers)
	var forward: Vector3 = pca.axes[0]
	forward = (forward - axle * forward.dot(axle)).normalized()
	var spread := 0.0
	for c in centers:
		spread = maxf(spread, absf((c - pca.center).dot(forward)))
	if spread < 0.5 * float(wheels[0].radius):
		return {} # all on one axle
	# Up is the side the car reaches further from its wheels (the roof, not the floor).
	var up := forward.cross(axle).normalized()
	var above := 0.0
	var below := 0.0
	for p in all_points:
		var h := (p - mid).dot(up)
		above = maxf(above, h)
		below = maxf(below, -h)
	if below > above:
		up = -up
	var left := up.cross(forward).normalized()
	return { "left": left, "up": up, "forward": forward }


## Positive if `forward` is the front: wheel, light and part names, the steering wheel, and
## glTF's +Z as a tie-breaker.
static func _forward_evidence(scene: Node3D, wheels: Array, forward: Vector3) -> float:
	var score := 0.05 * signf(forward.dot(Vector3.BACK))
	var mid := Vector3.ZERO
	var count := 0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		mid += _to_root(mi, scene).origin
		count += 1
	mid /= maxi(count, 1)
	for node: Node3D in scene.find_children("*", "Node3D", true, false):
		var n := String(node.name).to_lower()
		var side := 0.0
		if _has_word(n, FRONT_WORDS) or _token(n, ["fl", "fr", "lf", "rf"]):
			side = 1.0
		elif _has_word(n, REAR_WORDS) or _token(n, ["rl", "rr", "lr", "bl", "br"]):
			side = -1.0
		elif n.contains("steer"):
			side = 0.5
		if side == 0.0:
			continue
		var pos := _box_center(node, scene)
		var along := (pos - mid).dot(forward)
		if absf(along) > 1e-6:
			score += side * signf(along)
	return score


static func _box_center(node: Node3D, scene: Node3D) -> Vector3:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		return _to_root(mi, scene) * mi.mesh.get_aabb().get_center()
	return _to_root(node, scene).origin


static func _hub_fit_wheels(wheels: Array, _to_vehicle: Basis) -> Array:
	var out := []
	for w: Dictionary in wheels:
		var id: String = w.id
		var axle := 1 if id in ["LF", "RF"] else 2 if id in ["LR", "RR"] else int(id.substr(1))
		var entry := { "id": id, "axle": axle, "side": id[0], "node": w.hub, "center": _arr(w.center), "radius": w.radius, "width": w.width }
		if w.spin:
			entry.spin_node = w.spin
		if not w.fixed.is_empty():
			entry.fixed_nodes = w.fixed
		out.append(entry)
	return out


## Detected wheels: ids from their place in the vehicle frame; their parts get a pivot at the
## wheel's centre (pivot "insert"). Parts inside a bigger mesh are split out first.
static func _part_fit_wheels(scene: Node3D, wheels: Array, to_vehicle: Basis, r: Result) -> Array:
	var placed := []
	for w: Dictionary in wheels:
		placed.append({ "w": w, "v": to_vehicle * (w.center as Vector3) })
	placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.v.z > b.v.z)
	# Axles: gaps along the car bigger than half a wheel radius.
	var axles := [[placed[0]]]
	for i in range(1, placed.size()):
		if placed[i - 1].v.z - placed[i].v.z > 0.5 * float(placed[i].w.radius):
			axles.append([])
		axles[-1].append(placed[i])
	var mid_x := 0.0
	for p: Dictionary in placed:
		mid_x += p.v.x / placed.size()
	var half_track := 0.0
	for p: Dictionary in placed:
		half_track = maxf(half_track, absf(p.v.x - mid_x))
	var two_axle_pairs: bool = axles.size() == 2 and axles.all(func(a: Array) -> bool: return a.size() == 2)
	var out := []
	var used := {}
	for ai in axles.size():
		for p: Dictionary in axles[ai]:
			var lateral: float = p.v.x - mid_x
			var side := "C" if absf(lateral) < 0.25 * half_track else ("L" if lateral > 0.0 else "R")
			var id := "%s%s" % [side, "F" if ai == 0 else "R"] if two_axle_pairs else "%s%d" % [side, ai + 1]
			var n := ai + 1
			while used.has(id) and n < 8:
				n += 1
				id = "%s%d" % [side, n]
			used[id] = true
			var w: Dictionary = p.w
			var spin := []
			var fixed := []
			for part: Part in w.parts:
				var source: Mesh = part.node.get_meta("noss_original_mesh") if part.node.has_meta("noss_original_mesh") else part.node.mesh
				for si in source.get_surface_count():
					if (part.surface < 0 or si == part.surface) and source.surface_get_material(si):
						r.wheel_materials[source.surface_get_material(si).resource_name] = true
				var node_name := _split_or_name(scene, part, id, spin.size() + fixed.size(), r)
				(fixed if String(part.node.name).to_lower().contains("caliper") else spin).append(node_name)
			r.wheel_nodes[id] = spin
			out.append({
				"id": id, "axle": ai + 1, "side": side, "center": _arr(w.center), "radius": w.radius, "width": w.width,
				"node": "noss_hub_" + id, "spin_node": "noss_wheel_" + id, "pivot": "insert", "spin_nodes": spin,
			})
			if not fixed.is_empty():
				out[-1].fixed_nodes = fixed
	return out


## The node name to use for a wheel part: a whole mesh keeps its (unique) name; a part of a
## bigger mesh is split out into a new mesh named noss_split_<id>_<n>.
static func _split_or_name(scene: Node3D, part: Part, id: String, n: int, r: Result) -> String:
	if part.label < 0:
		if scene.find_children(part.node.name, "", true, false).size() == 1:
			return String(part.node.name)
		part.node.name = "noss_part_%s_%d" % [id, n]
		r.scene_changed = true
		return String(part.node.name)
	# Every split of a mesh cuts from its original, so earlier splits don't shift the triangles.
	var original: Mesh = part.node.get_meta("noss_original_mesh") if part.node.has_meta("noss_original_mesh") else part.node.mesh
	part.node.set_meta("noss_original_mesh", original)
	var removed: Dictionary = part.node.get_meta("noss_removed", {})
	var mask: PackedByteArray = removed.get(part.surface, PackedByteArray())
	if mask.is_empty():
		mask.resize(part.triangles.size())
	for i in part.triangles.size():
		if part.triangles[i]:
			mask[i] = 1
	removed[part.surface] = mask
	part.node.set_meta("noss_removed", removed)
	var rebuilt := ArrayMesh.new()
	rebuilt.resource_name = original.resource_name
	for s in original.get_surface_count():
		var a := original.surface_get_arrays(s)
		if removed.has(s):
			var rest: PackedByteArray = (removed[s] as PackedByteArray).duplicate()
			for i in rest.size():
				rest[i] = 1 - rest[i]
			a = NossMesh.extract_surface(a, rest)
			if (a[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
				continue
		rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, original.surface_get_material(s))
	part.node.mesh = rebuilt
	var keep := NossMesh.extract_surface(original.surface_get_arrays(part.surface), part.triangles)
	var mesh := original
	var wheel_mesh := ArrayMesh.new()
	wheel_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, keep)
	wheel_mesh.surface_set_material(0, mesh.surface_get_material(part.surface))
	var split := MeshInstance3D.new()
	split.name = "noss_split_%s_%d" % [id, n]
	split.mesh = wheel_mesh
	split.transform = part.node.transform
	part.node.get_parent().add_child(split)
	split.owner = scene
	r.scene_changed = true
	return String(split.name)


## Four anchors at the corners when no wheels were found (wheel_mode "stock").
static func _stock_anchors(box: AABB, to_vehicle: Basis) -> Array:
	var to_model := to_vehicle.inverse()
	var length := box.size.z
	var radius := clampf(box.size.y * 0.24, 0.05 * length, 0.09 * length)
	var out := []
	for id in ["LF", "RF", "LR", "RR"]:
		var x: float = (box.size.x / 2.0 - 0.6 * radius) * (1.0 if id[0] == "L" else -1.0) + box.get_center().x
		var z: float = box.get_center().z + (0.3 * length if id[1] == "F" else -0.3 * length)
		var v := Vector3(x, box.position.y + radius, z)
		out.append({ "id": id, "axle": 1 if id[1] == "F" else 2, "side": id[0], "center": _arr(to_model * v), "radius": radius, "width": radius * 0.7 })
	return out


static func _wheelbase(fit_wheels: Array, to_vehicle: Basis) -> float:
	var front := 0.0
	var rear := 0.0
	var nf := 0
	var nr := 0
	var last := 1
	for w: Dictionary in fit_wheels:
		last = maxi(last, int(w.axle))
	for w: Dictionary in fit_wheels:
		var z := (to_vehicle * _vec(w.center)).z
		if int(w.axle) == 1:
			front += z
			nf += 1
		elif int(w.axle) == last:
			rear += z
			nr += 1
	return front / maxi(nf, 1) - rear / maxi(nr, 1) if nf and nr else 0.0


## Where the wheels touch down, in the vehicle frame (model units): their mean bottom on the
## first and last axles, the ones a platform drives (Fitting).
static func ground_of(fit_wheels: Array, to_vehicle: Basis) -> float:
	var last := 1
	for w: Dictionary in fit_wheels:
		last = maxi(last, int(w.axle))
	var ground := 0.0
	var n := 0
	for w: Dictionary in fit_wheels:
		if int(w.axle) == 1 or int(w.axle) == last:
			ground += (to_vehicle * _vec(w.center)).y - float(w.radius)
			n += 1
	return ground / maxi(n, 1)


## Model units to metres: a common unit if the wheelbase then looks like a car's, otherwise
## whatever gives a typical wheelbase.
static func _scale(wheelbase: float) -> float:
	if wheelbase <= 0.0:
		return 1.0
	for unit: float in UNITS:
		var l := wheelbase * unit
		if l >= 1.8 and l <= 3.6:
			return unit
	return _round(TYPICAL_WHEELBASE / wheelbase, 6)


# --- other parts ----------------------------------------------------------------


## Big, flat things the car stands on: much wider and longer than the wheels' footprint.
static func _hide_stands(meshes: Array[Dictionary], hidden: Dictionary, wheels: Array, to_vehicle: Basis, r: Result) -> void:
	var foot := AABB(to_vehicle * (wheels[0].center as Vector3), Vector3.ZERO)
	var radius := 0.0
	for w: Dictionary in wheels:
		foot = foot.expand(to_vehicle * (w.center as Vector3))
		radius = maxf(radius, w.radius)
	var area := (foot.size.x + 2.0 * radius) * (foot.size.z + 2.0 * radius)
	for m: Dictionary in meshes:
		if hidden.has(m.node):
			continue
		var pts := PackedVector3Array()
		for p in m.points:
			pts.append(to_vehicle * p)
		var box := _aabb(pts)
		if box.size.x * box.size.z > 3.0 * area and box.get_center().y < foot.get_center().y + radius:
			hidden[m.node] = true
			r.notes.append("Hid %s" % m.node.name)


static func _steering_wheel(scene: Node3D) -> Node3D:
	for node: Node3D in scene.find_children("*", "Node3D", true, false):
		var n := String(node.name).to_lower()
		if n.contains("steer") and (n.contains("wheel") or n.contains("ing")):
			return node
	return null


## Light groups from node and material names (CarVisual matches materials for brake lights).
static func _lights(scene: Node3D) -> Dictionary:
	var out := { "head": [], "brake": [], "reverse": [], "indicator_L": [], "indicator_R": [] }
	var groups := {
		"head": ["headlight", "head_light", "headlamp", "head-light"],
		"brake": ["taillight", "tail_light", "brakelight", "brake_light", "tail-light", "rearlight", "rear_light"],
		"reverse": ["reverse"],
	}
	var names := {}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		names[String(mi.name)] = true
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name:
				names[m.resource_name] = true
	for name: String in names:
		var n := name.to_lower()
		for group: String in groups:
			if groups[group].any(func(w: String) -> bool: return n.contains(w)) and name not in out[group]:
				out[group].append(name)
	return out


## Eye point from the steering wheel, hood and bumper cameras from the body's shape. Model space.
static func _cockpit(r: Result, scene: Node3D, steering: Node3D, points: PackedVector3Array, box: AABB, to_vehicle: Basis, scale: float, ground: float) -> void:
	var to_model := to_vehicle.inverse()
	var roof := box.end.y
	var eye := Vector3.ZERO
	var has_eye := false
	if steering:
		var sw := to_vehicle * _box_center(steering, scene)
		eye = Vector3(sw.x, minf(sw.y + 0.28 / scale, roof - 0.14 / scale), sw.z - 0.42 / scale)
		has_eye = true
		r.fit.eye_point = _arr(to_model * eye)
	else:
		r.fit.eye_point = null
		eye = Vector3(0.0, roof - 0.18 / scale, box.get_center().z - 0.1 / scale)
	# Hood: above the body's centre strip, between the eye and the nose. Bumper: at the nose.
	var front := box.end.z
	var hood_z := lerpf(eye.z, front, 0.62)
	var hood_y := -INF
	for p in points:
		if absf(p.x - box.get_center().x) < 0.3 * box.size.x and absf(p.z - hood_z) < 0.05 * box.size.z and p.y < eye.y:
			hood_y = maxf(hood_y, p.y)
	if hood_y > -INF:
		r.fit.cameras.hood = _arr(to_model * Vector3(box.get_center().x, hood_y + 0.12 / scale, hood_z))
	r.fit.cameras.bumper = _arr(to_model * Vector3(box.get_center().x, ground + 0.42 / scale, front + 0.03 / scale))
	if not has_eye:
		r.notes.append("Check the driver's eye point")


## Paint_* materials become slots. Otherwise the body's main material is suggested as primary
## if it isn't also on the wheels, glass or lights.
static func _paint(meshes: Array[Dictionary], hidden: Dictionary, r: Result) -> Dictionary:
	var slots := {}
	var area := {}
	var on_wheels := {}
	var wheel_meshes := {}
	for id: String in r.wheel_nodes:
		for n: String in r.wheel_nodes[id]:
			wheel_meshes[n] = true
	for m: Dictionary in meshes:
		var mi: MeshInstance3D = m.node
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat == null:
				continue
			var n := mat.resource_name
			for slot in ["Primary", "Secondary", "Tertiary"]:
				if n == "Paint_" + slot:
					slots[slot.to_lower()] = { "materials": [n], "color": _hex(mat), "finish": "metallic" }
			if wheel_meshes.has(String(mi.name)) or _has_word(mi.name, WHEEL_WORDS) or r.wheel_materials.has(n):
				on_wheels[n] = true
			if not hidden.has(mi):
				area[n] = float(area.get(n, 0.0)) + _surface_area(_aabb(m.points))
	if slots.is_empty():
		var total := 0.0
		var best := ""
		for n: String in area:
			total += area[n]
			if best == "" or area[n] > area[best]:
				best = n
		var excluded := ["glass", "window", "tire", "tyre", "rim", "light", "lamp", "chrome", "black", "interior", "seat", "rubber"]
		if best and area[best] > 0.35 * total and not on_wheels.has(best) and not excluded.any(func(w: String) -> bool: return best.to_lower().contains(w)):
			slots.primary = { "materials": [best], "color": "#FFFFFF", "finish": "metallic" }
			r.notes.append("Paint: %s" % best)
	return { "schema": "noss.paint/1", "slots": slots, "presets": [] }


## "open" when most wheels stand outside the body's sides where they are, "car" otherwise.
static func _family(fit_wheels: Array, points: PackedVector3Array, to_vehicle: Basis) -> String:
	if fit_wheels.size() < 3:
		return "car"
	var wheels := []
	for w: Dictionary in fit_wheels:
		wheels.append({ "c": to_vehicle * _vec(w.center), "r": float(w.radius), "w": float(w.width) })
	var mid := 0.0
	for w: Dictionary in wheels:
		mid += w.c.x / wheels.size()
	var outside := 0
	for w: Dictionary in wheels:
		var body := 0.0
		for p in points:
			if absf(p.z - w.c.z) > 0.5 * w.r:
				continue
			var in_wheel := false
			for o: Dictionary in wheels:
				if Vector2(p.y - o.c.y, p.z - o.c.z).length() < 1.1 * o.r and absf(p.x - o.c.x) < 0.6 * o.w + 0.05 * o.r:
					in_wheel = true
					break
			if not in_wheel:
				body = maxf(body, absf(p.x - mid))
		if absf(w.c.x - mid) - 0.25 * w.w > body:
			outside += 1
	return "open" if outside >= wheels.size() - 1 else "car"


static func _empty_fit() -> Dictionary:
	return {
		"schema": "noss.fit/1",
		"model_transform": { "scale": 1.0, "rotation_deg": [0.0, 0.0, 0.0], "offset_m": [0.0, 0.0, 0.0] },
		"ground_y": 0.0, "wheel_mode": "stock", "wheels": [],
		"envelope": { "min": [-0.9, 0.0, -2.0], "max": [0.9, 1.3, 2.0] },
	}


# --- helpers ---------------------------------------------------------------------


## About `budget` points spread over the visible surfaces by area, in the vehicle frame
## (unscaled). Unlike vertices, they also cover big flat faces.
static func _surface_samples(meshes: Array[Dictionary], hidden: Dictionary, to_vehicle: Basis, budget: int) -> PackedVector3Array:
	var tris := []
	var total := 0.0
	for m: Dictionary in meshes:
		if hidden.has(m.node):
			continue
		var mi: MeshInstance3D = m.node
		var xf: Transform3D = m.xform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var count := index.size() / 3 if not index.is_empty() else verts.size() / 3
			var step := maxi(1, count / 20000)
			for t in range(0, count, step):
				var a := to_vehicle * (xf * verts[index[t * 3] if not index.is_empty() else t * 3])
				var b := to_vehicle * (xf * verts[index[t * 3 + 1] if not index.is_empty() else t * 3 + 1])
				var c := to_vehicle * (xf * verts[index[t * 3 + 2] if not index.is_empty() else t * 3 + 2])
				var area := (b - a).cross(c - a).length() / 2.0 * step
				if area > 0.0:
					tris.append([a, b, c, area])
					total += area
	var out := PackedVector3Array()
	if total <= 0.0:
		return out
	var spacing := total / budget
	var carry := 0.0
	for t: Array in tris:
		carry += t[3]
		var n := int(carry / spacing)
		carry -= n * spacing
		for k in n:
			# Spread over the triangle on a fixed pattern (deterministic).
			var u := fposmod(0.618034 * (k + 1), 1.0)
			var v := fposmod(0.754878 * (k + 1), 1.0)
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			out.append(t[0] + (t[1] - t[0]) * u + (t[2] - t[0]) * v)
	return out


## How low `scene`'s meshes reach along `dir` (root space): the least `dir`·vertex, leaving out
## the nodes in `skip` and everything under them. INF without any.
static func lowest_along(scene: Node3D, dir: Vector3, skip: Dictionary) -> float:
	var low := INF
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or _under(mi, scene, skip):
			continue
		var xf := _to_root(mi, scene)
		# dir·(xf * v) is a·v + b.
		var a := xf.basis.transposed() * dir
		var mesh_low := INF
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				mesh_low = minf(mesh_low, a.dot(v))
		low = minf(low, mesh_low + xf.origin.dot(dir))
	return low


## True if `node` or one of its parents below `root` is in `nodes`.
static func _under(node: Node, root: Node, nodes: Dictionary) -> bool:
	while node and node != root:
		if nodes.has(node):
			return true
		node = node.get_parent()
	return false


## Rounds a rotation to exact 90 degree steps when it's within 3 degrees of one.
static func _snap(b: Basis) -> Basis:
	var cols := [b.x, b.y, b.z]
	var snapped := []
	for c: Vector3 in cols:
		var axis := c.abs().max_axis_index()
		if absf(c[axis]) < cos(deg_to_rad(3.0)):
			return b
		var v := Vector3.ZERO
		v[axis] = signf(c[axis])
		snapped.append(v)
	return Basis(snapped[0], snapped[1], snapped[2])



static func _has_word(name: String, words: Array) -> bool:
	var n := name.to_lower()
	return words.any(func(w: String) -> bool: return n.contains(w))


## True if `name` has one of `tokens` as a separate word (between non-letters).
static func _token(name: String, tokens: Array) -> bool:
	for t: String in tokens:
		var re := RegEx.create_from_string("(^|[^a-z])%s([^a-z]|$)" % t)
		if re.search(name):
			return true
	return false


static func _aabb(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


static func _surface_area(box: AABB) -> float:
	var s := box.size
	return 2.0 * (s.x * s.y + s.y * s.z + s.z * s.x)


static func _to_root(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while node and node != root:
		if node is Node3D:
			t = (node as Node3D).transform * t
		node = node.get_parent()
	return t


## `node`'s transform relative to `ancestor`.
static func _to(node: Node, ancestor: Node) -> Transform3D:
	return _to_root(node, ancestor)


static func _hex(material: Material) -> String:
	var c := (material as BaseMaterial3D).albedo_color if material is BaseMaterial3D else Color.WHITE
	return "#" + c.to_html(false).to_upper()


static func _arr(v: Vector3) -> Array:
	return [_round(v.x, 6), _round(v.y, 6), _round(v.z, 6)]


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _round(x: float, digits: int) -> float:
	var k := pow(10.0, digits)
	return roundf(x * k) / k
