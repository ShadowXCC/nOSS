extends SceneTree
## Builds the original low-poly default cars as unpacked packages (docs/ART_AUDIO.md §3):
## "nOSS Box" (family car) in content/cars/noss_box/, and with --open "nOSS Open" (an
## open-wheeler, family open) in content/cars/noss_open/. They follow the package conventions
## (docs/VEHICLE_PACKAGE.md §3) so they exercise the same loader as player cars.
##   tools/godot.sh --headless -s res://tools/make_noss_box.gd [-- --open]

const BOX := {
	"out": "res://content/cars/noss_box/", "id": "6e0c6a51-5d0f-4a2b-9a52-3b1f0d7c2e11", "name": "nOSS Box",
	"family": "car", "wheelbase": 2.60, "track": 1.55, "wheel_r": 0.32, "wheel_w": 0.23, "sound": "v8_crossplane",
}
const OPEN := {
	"out": "res://content/cars/noss_open/", "id": "3f6c2b8e-91d4-4f0a-b7e2-5c8a1d9e4f20", "name": "nOSS Open",
	"family": "open", "wheelbase": 2.90, "track": 1.60, "wheel_r": 0.33, "wheel_w": 0.32, "sound": "flat6",
}
const HALF_W := 0.86
const ARCH_R := 0.40
const BODY_BOTTOM := 0.22

var OUT := ""
var WHEELBASE := 0.0
var TRACK := 0.0
var WHEEL_R := 0.0
var WHEEL_W := 0.0
var _car := {}
var _open := false
var _materials := {}


func _init() -> void:
	_open = "--open" in OS.get_cmdline_user_args()
	_car = OPEN if _open else BOX
	OUT = _car.out
	WHEELBASE = _car.wheelbase
	TRACK = _car.track
	WHEEL_R = _car.wheel_r
	WHEEL_W = _car.wheel_w
	var root := Node3D.new()
	root.name = OUT.trim_suffix("/").get_file()
	if _open:
		_build_open(root)
	else:
		_build(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "model"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "sound"))

	var doc := GLTFDocument.new()
	doc.root_node_mode = GLTFDocument.ROOT_NODE_MODE_KEEP_ROOT
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT + "model/body.glb"))
	root.free()
	if err != OK:
		push_error("GLB export failed: %d" % err)
		quit(1)
		return

	var files := {
		"fit.json": _json(_fit_open() if _open else _fit()),
		"paint.json": _json(_paint_open() if _open else _paint()),
		"sound/profile.json": _json({ "schema": "noss.sound/1", "name": "Default", "base": _car.sound }),
	}
	for rel: String in files:
		_write(OUT + rel, files[rel].to_utf8_buffer())
	var hashes := {}
	for rel: String in files.keys() + ["model/body.glb"]:
		hashes[rel] = "sha256:" + PlatformLoader.sha256_hex(FileAccess.get_file_as_bytes(OUT + rel))
	var manifest := {
		"schema": "noss.package/1", "id": _car.id, "version": 1, "name": _car.name,
		"author": "nOSS contributors", "license": "CC-BY-SA-4.0", "family": _car.family,
		"tags": ["default", "original"], "source": "tools/make_noss_box.gd", "created": "2026-10-10",
		"game_min_version": "0.1.0", "files": hashes,
	}
	_write(OUT + "manifest.json", _json(manifest).to_utf8_buffer())
	# Ship the GLB as-is instead of letting the editor import it.
	_write(OUT + "model/body.glb.import", "[remap]\n\nimporter=\"keep\"\n".to_utf8_buffer())
	print(_car.name, " written to ", OUT)
	quit()


func _build(root: Node3D) -> void:
	var body := _node("body", root)
	_mesh_node("shell", body, _body_mesh())
	_mesh_node("cabin", body, _cabin_mesh())
	_mesh_node("trim", body, _trim_mesh())
	_mesh_node("headlight_L", body, _box(Vector3(0.58, 0.46, 2.155), Vector3(0.36, 0.12, 0.02), "head_light"))
	_mesh_node("headlight_R", body, _box(Vector3(-0.58, 0.46, 2.155), Vector3(0.36, 0.12, 0.02), "head_light"))
	_mesh_node("taillight_L", body, _box(Vector3(0.62, 0.66, -2.155), Vector3(0.30, 0.10, 0.02), "tail_light"))
	_mesh_node("taillight_R", body, _box(Vector3(-0.62, 0.66, -2.155), Vector3(0.30, 0.10, 0.02), "tail_light"))

	var interior := _node("interior", root)
	for side in [1.0, -1.0]:
		var seat := _seat_mesh()
		var n := _mesh_node("seatL" if side > 0 else "seatR", interior, seat)
		n.position = Vector3(0.38 * side, 0.30, -0.45)
	_mesh_node("dash", interior, _box(Vector3(0, 0.88, 0.45), Vector3(1.5, 0.14, 0.30), "dash_plastic"))
	var wheel := _mesh_node("steering_wheel", interior, _steering_wheel_mesh())
	wheel.position = Vector3(0.38, 0.97, 0.15)

	for id in ["LF", "RF", "LR", "RR"]:
		var side := 1.0 if id[0] == "L" else -1.0
		var z := WHEELBASE / 2.0 if id[1] == "F" else -WHEELBASE / 2.0
		var hub := _node("hub_" + id, root)
		hub.position = Vector3(TRACK / 2.0 * side, WHEEL_R, z)
		_mesh_node("wheel_" + id, hub, _wheel_mesh(side))
		var caliper := _mesh_node("caliper_" + id, hub, _box(Vector3(-0.05 * side, 0.12, -0.10), Vector3(0.06, 0.12, 0.10), "caliper"))
		caliper.position = Vector3.ZERO


## nOSS Open: a narrow tub with sidepods, wings and exposed wheels.
func _build_open(root: Node3D) -> void:
	var body := _node("body", root)
	_mesh_node("tub", body, _open_tub_mesh())
	var pods := _begin("Paint_Primary")
	for side in [1.0, -1.0]:
		_box_into(pods, Vector3(0.52 * side, 0.36, -0.35), Vector3(0.34, 0.34, 1.5))
	_mesh_node("sidepods", body, pods.commit())
	var wings := _begin("Paint_Secondary")
	_box_into(wings, Vector3(0, 0.12, 2.32), Vector3(1.62, 0.04, 0.42)) # front wing
	for side in [1.0, -1.0]:
		_box_into(wings, Vector3(0.80 * side, 0.18, 2.32), Vector3(0.02, 0.16, 0.46))
		_box_into(wings, Vector3(0.50 * side, 0.82, -1.95), Vector3(0.02, 0.30, 0.48)) # rear endplates
	_box_into(wings, Vector3(0, 0.94, -1.95), Vector3(1.00, 0.04, 0.42)) # rear wing
	_box_into(wings, Vector3(0, 0.70, -1.90), Vector3(0.06, 0.40, 0.10)) # pylon
	_mesh_node("wings", body, wings.commit())
	_mesh_node("helmet", body, _box(Vector3(0, 0.80, -0.20), Vector3(0.24, 0.26, 0.28), "helmet"))
	_mesh_node("taillight_C", body, _box(Vector3(0, 0.30, -1.92), Vector3(0.14, 0.06, 0.02), "tail_light"))

	var interior := _node("interior", root)
	_mesh_node("seatC", interior, _box(Vector3(0, 0.30, -0.35), Vector3(0.40, 0.10, 0.50), "seat"))
	var wheel := _mesh_node("steering_wheel", interior, _steering_wheel_mesh())
	wheel.position = Vector3(0, 0.62, 0.22)
	wheel.scale = Vector3.ONE * 0.75

	for id in ["LF", "RF", "LR", "RR"]:
		var side := 1.0 if id[0] == "L" else -1.0
		var z := WHEELBASE / 2.0 if id[1] == "F" else -WHEELBASE / 2.0
		var hub := _node("hub_" + id, root)
		hub.position = Vector3(TRACK / 2.0 * side, WHEEL_R, z)
		_mesh_node("wheel_" + id, hub, _wheel_mesh(side))
		# Suspension arms from the tub to the hub, painted dark.
		var arms := _begin("black_trim")
		var inner := Vector3(-side * (TRACK / 2.0 - 0.34), 0.0, 0.0)
		for dy in [-0.06, 0.08]:
			var a := Vector3(0, dy, 0)
			var mid := (a + inner) / 2.0
			_box_into(arms, mid, Vector3(absf(inner.x), 0.025, 0.04))
		_mesh_node("arms_" + id, hub, arms.commit())


## Side silhouette of the tub (z, y): low nose, cockpit, airbox, tapering tail.
func _open_tub_mesh() -> ArrayMesh:
	var p := PackedVector2Array([
		Vector2(-1.85, 0.20), Vector2(2.45, 0.16), Vector2(2.45, 0.24), Vector2(1.20, 0.46),
		Vector2(0.30, 0.58), Vector2(0.05, 0.62), Vector2(-0.05, 0.52), Vector2(-0.45, 0.56),
		Vector2(-0.55, 0.92), Vector2(-0.80, 0.94), Vector2(-1.85, 0.48),
	])
	var st := _begin("Paint_Primary")
	_extrude(st, p, 0.34, 0.34)
	return st.commit()


func _fit_open() -> Dictionary:
	var fit := _fit()
	fit.steering_wheel = { "node": "steering_wheel", "visual_lock_deg": 300 }
	fit.eye_point = [0.0, 0.84, -0.12]
	fit.envelope = { "min": [-0.97, 0.0, -2.18], "max": [0.97, 0.98, 2.53] }
	fit.lights = { "head": [], "brake": ["tail_light"], "reverse": [], "indicator_L": [], "indicator_R": [] }
	fit.exhaust_points = [[0.0, 0.40, -1.90]]
	return fit


func _paint_open() -> Dictionary:
	return {
		"schema": "noss.paint/1",
		"slots": {
			"primary": { "materials": ["Paint_Primary"], "color": "#1F4FB5", "finish": "pearl" },
			"secondary": { "materials": ["Paint_Secondary"], "color": "#F2F2F2", "finish": "solid" },
		},
		"presets": [
			{ "name": "Open Blue", "primary": "#1F4FB5", "secondary": "#F2F2F2", "finish": "pearl" },
			{ "name": "Open Red", "primary": "#C2261D", "secondary": "#1B1D22", "finish": "solid" },
			{ "name": "Open Yellow", "primary": "#E8B71A", "secondary": "#1B1D22", "finish": "metallic" },
		],
	}


func _fit() -> Dictionary:
	var wheels := []
	for id in ["LF", "RF", "LR", "RR"]:
		var side := 1.0 if id[0] == "L" else -1.0
		var z := WHEELBASE / 2.0 if id[1] == "F" else -WHEELBASE / 2.0
		wheels.append({
			"id": id, "axle": 1 if id[1] == "F" else 2, "side": id[0], "node": "hub_" + id,
			"spin_node": "wheel_" + id, "fixed_nodes": ["caliper_" + id],
			"center": [TRACK / 2.0 * side, WHEEL_R, z], "radius": WHEEL_R, "width": WHEEL_W,
		})
	return {
		"schema": "noss.fit/1",
		"model_transform": { "scale": 1.0, "rotation_deg": [0, 0, 0], "offset_m": [0, 0, 0] },
		"ground_y": 0.0,
		"wheel_mode": "model",
		"wheels": wheels,
		"steering_wheel": { "node": "steering_wheel", "visual_lock_deg": 540 },
		"eye_point": [0.38, 1.12, -0.42],
		"cameras": { "hood": null, "bumper": null },
		"envelope": { "min": [-0.89, 0.0, -2.16], "max": [0.89, 1.28, 2.16] },
		"lights": { "head": ["headlight*"], "brake": ["tail_light"], "reverse": [], "indicator_L": [], "indicator_R": [] },
		"exhaust_points": [[0.45, 0.25, -2.16]],
		"hide_nodes": [],
		"lod_distances_m": [0],
	}


func _paint() -> Dictionary:
	return {
		"schema": "noss.paint/1",
		"slots": {
			"primary": { "materials": ["Paint_Primary"], "color": "#E8B71A", "finish": "metallic" },
			"secondary": { "materials": ["Paint_Secondary"], "color": "#1B1D22", "finish": "solid" },
		},
		"presets": [
			{ "name": "Box Yellow", "primary": "#E8B71A", "secondary": "#1B1D22", "finish": "metallic" },
			{ "name": "Box Red", "primary": "#C2261D", "secondary": "#F2F2F2", "finish": "solid" },
			{ "name": "Box Blue", "primary": "#1F4FB5", "secondary": "#F2F2F2", "finish": "pearl" },
		],
	}


# --- geometry ------------------------------------------------------------------


## Side silhouette (z, y), counter-clockwise seen from +X, with wheel arches.
func _side_profile() -> PackedVector2Array:
	var p := PackedVector2Array([Vector2(-2.15, 0.30), Vector2(-2.08, BODY_BOTTOM)])
	for zc in [-WHEELBASE / 2.0, WHEELBASE / 2.0]:
		p.append(Vector2(zc - ARCH_R, BODY_BOTTOM))
		for i in range(0, 9):
			var a := PI - PI * i / 8.0
			p.append(Vector2(zc + ARCH_R * cos(a), WHEEL_R + ARCH_R * 0.85 * sin(a)))
		p.append(Vector2(zc + ARCH_R, BODY_BOTTOM))
	p.append_array([Vector2(2.08, BODY_BOTTOM), Vector2(2.15, 0.30), Vector2(2.15, 0.56), Vector2(1.95, 0.68),
		Vector2(0.62, 0.80), Vector2(-1.70, 0.84), Vector2(-2.10, 0.82), Vector2(-2.15, 0.64)])
	return p


func _body_mesh() -> ArrayMesh:
	var st := _begin("Paint_Primary")
	_extrude(st, _side_profile(), HALF_W, HALF_W)
	return st.commit()


func _cabin_mesh() -> ArrayMesh:
	# Glass sides and windscreens, painted roof.
	var base_r := 0.80
	var roof_r := 0.64
	var outline := [Vector2(-1.70, 0.84), Vector2(0.62, 0.80), Vector2(-0.18, 1.26), Vector2(-1.30, 1.28)]
	var glass := _begin("Glass")
	_loft_quad(glass, outline, base_r, roof_r, [1, 3]) # windscreens; the roof is painted
	var mesh: ArrayMesh = glass.commit()
	var roof := _begin("Paint_Secondary")
	var a := Vector3(roof_r, outline[2].y, outline[2].x)
	var b := Vector3(roof_r, outline[3].y, outline[3].x)
	_quad(roof, Vector3(-a.x, a.y, a.z), a, b, Vector3(-b.x, b.y, b.z))
	return roof.commit(mesh)


func _trim_mesh() -> ArrayMesh:
	var st := _begin("black_trim")
	_box_into(st, Vector3(0, 0.30, 2.13), Vector3(1.74, 0.14, 0.08))
	_box_into(st, Vector3(0, 0.32, -2.13), Vector3(1.74, 0.14, 0.08))
	_box_into(st, Vector3(0, 0.52, 2.15), Vector3(0.6, 0.10, 0.02)) # grille
	return st.commit()


func _seat_mesh() -> ArrayMesh:
	var st := _begin("seat")
	_box_into(st, Vector3(0, 0.0, 0.05), Vector3(0.48, 0.12, 0.50))
	_box_into(st, Vector3(0, 0.36, -0.22), Vector3(0.48, 0.62, 0.10))
	return st.commit()


func _steering_wheel_mesh() -> ArrayMesh:
	var st := _begin("wheel_leather")
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(20.0)) # rim top leans forward, like a real column
	var ring := 0.18
	var tube := 0.022
	var seg := 24
	var sides := 6
	for i in seg:
		for j in sides:
			var pts := []
			for di in [0, 1]:
				for dj in [0, 1]:
					var u: float = TAU * (i + di) / seg
					var v: float = TAU * (j + dj) / sides
					var center := Vector3(cos(u) * ring, sin(u) * ring, 0)
					var outward := Vector3(cos(u), sin(u), 0)
					pts.append(tilt * (center + (outward * cos(v) + Vector3(0, 0, 1) * sin(v)) * tube))
			_quad(st, pts[0], pts[2], pts[3], pts[1])
	for k in 3:
		var a := PI * 0.5 + TAU * k / 3.0
		var dir := Vector3(cos(a), sin(a), 0)
		var c := tilt * (dir * ring * 0.5)
		var spoke_basis := tilt * Basis(Vector3(0, 0, 1), a)
		_box_into(st, c, Vector3(ring, 0.03, 0.02), spoke_basis)
	return st.commit()


func _wheel_mesh(side: float) -> ArrayMesh:
	var tire := _begin("tire")
	var seg := 20
	var half := WHEEL_W / 2.0
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(0, sin(a0), cos(a0)) * WHEEL_R
		var p1 := Vector3(0, sin(a1), cos(a1)) * WHEEL_R
		var x0 := Vector3(-half, 0, 0)
		var x1 := Vector3(half, 0, 0)
		_quad(tire, p0 + x1, p1 + x1, p1 + x0, p0 + x0) # tread
		var q0 := p0 * 0.66
		var q1 := p1 * 0.66
		_quad(tire, p0 + x0, p1 + x0, q1 + x0, q0 + x0) # inner sidewall
		_quad(tire, q0 + x1, q1 + x1, p1 + x1, p0 + x1) # outer sidewall
	var mesh: ArrayMesh = tire.commit()
	var rim := _begin("rim")
	var face := half * side * 0.9
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var r := WHEEL_R * 0.66
		var p0 := Vector3(face, sin(a0) * r, cos(a0) * r)
		var p1 := Vector3(face, sin(a1) * r, cos(a1) * r)
		var c := Vector3(face - 0.04 * side, 0, 0)
		if side > 0:
			_tri(rim, c, p1, p0)
		else:
			_tri(rim, c, p0, p1)
	for k in 5:
		var a := TAU * k / 5.0
		var spoke_basis := Basis(Vector3.RIGHT, a)
		_box_into(rim, Vector3(face + 0.012 * side, 0, 0) + spoke_basis * Vector3(0, WHEEL_R * 0.33, 0), Vector3(0.02, WHEEL_R * 0.62, 0.05), spoke_basis)
	return rim.commit(mesh)


## Extrudes a closed (z, y) outline across x in [-left, right].
func _extrude(st: SurfaceTool, outline: PackedVector2Array, left: float, right: float) -> void:
	if Geometry2D.is_polygon_clockwise(outline):
		outline.reverse()
	var tris := Geometry2D.triangulate_polygon(outline)
	for i in range(0, tris.size(), 3):
		var a := outline[tris[i]]
		var b := outline[tris[i + 1]]
		var c := outline[tris[i + 2]]
		_tri(st, Vector3(right, a.y, a.x), Vector3(right, c.y, c.x), Vector3(right, b.y, b.x))
		_tri(st, Vector3(-left, a.y, a.x), Vector3(-left, b.y, b.x), Vector3(-left, c.y, c.x))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		_quad(st, Vector3(-left, a.y, a.x), Vector3(right, a.y, a.x), Vector3(right, b.y, b.x), Vector3(-left, b.y, b.x))


## Tapered prism: x half-width goes from base_r (at the outline's lowest y) to top_r.
func _loft_quad(st: SurfaceTool, outline: Array, base_r: float, top_r: float, edges: Array) -> void:
	var y0: float = outline.map(func(v: Vector2) -> float: return v.y).min()
	var y1: float = outline.map(func(v: Vector2) -> float: return v.y).max()
	var pts := outline.map(func(v: Vector2) -> Vector3: return Vector3(lerpf(base_r, top_r, (v.y - y0) / (y1 - y0)), v.y, v.x))
	for i in edges:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		_quad(st, Vector3(-a.x, a.y, a.z), a, b, Vector3(-b.x, b.y, b.z))
	# Side windows.
	_tri(st, pts[0], pts[2], pts[1])
	_tri(st, pts[0], pts[3], pts[2])
	var m := pts.map(func(v: Vector3) -> Vector3: return Vector3(-v.x, v.y, v.z))
	_tri(st, m[0], m[1], m[2])
	_tri(st, m[0], m[2], m[3])


func _box(center: Vector3, size: Vector3, material: String) -> ArrayMesh:
	var st := _begin(material)
	_box_into(st, center, size)
	return st.commit()


func _box_into(st: SurfaceTool, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var h := size / 2.0
	var c := []
	for i in 8:
		c.append(center + basis * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		_quad(st, c[f[0]], c[f[1]], c[f[2]], c[f[3]])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## Godot's front faces are clockwise; this takes counter-clockwise (outward) triangles.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for p in [a, c, b]:
		st.set_normal(n)
		st.set_uv(Vector2(p.z, p.y) * 0.5)
		st.add_vertex(p)


func _begin(material: String) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material(material))
	return st


func _material(material_name: String) -> StandardMaterial3D:
	if _materials.has(material_name):
		return _materials[material_name]
	var m := StandardMaterial3D.new()
	m.resource_name = material_name
	match material_name:
		"Paint_Primary":
			m.albedo_color = Color("#E8B71A")
			m.metallic = 0.6
			m.roughness = 0.3
		"Paint_Secondary":
			m.albedo_color = Color("#1B1D22")
			m.roughness = 0.35
		"Glass":
			m.albedo_color = Color(0.08, 0.10, 0.12, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.2
			m.roughness = 0.05
		"black_trim", "tire":
			m.albedo_color = Color(0.05, 0.05, 0.055)
			m.roughness = 0.85
		"rim":
			m.albedo_color = Color(0.72, 0.74, 0.76)
			m.metallic = 0.9
			m.roughness = 0.3
		"caliper":
			m.albedo_color = Color(0.75, 0.12, 0.08)
			m.roughness = 0.5
		"head_light":
			m.albedo_color = Color(0.95, 0.95, 0.85)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.97, 0.85)
			m.emission_energy_multiplier = 0.6
		"tail_light":
			m.albedo_color = Color(0.45, 0.02, 0.02)
			m.roughness = 0.2
		"helmet":
			m.albedo_color = Color(0.92, 0.92, 0.94)
			m.roughness = 0.25
		"seat", "dash_plastic", "wheel_leather":
			m.albedo_color = Color(0.12, 0.12, 0.13)
			m.roughness = 0.8
	_materials[material_name] = m
	return m


func _node(node_name: String, parent: Node3D) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	n.owner = parent.owner if parent.owner else parent
	return n


func _mesh_node(node_name: String, parent: Node3D, mesh: ArrayMesh) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = node_name
	n.mesh = mesh
	parent.add_child(n)
	n.owner = parent.owner if parent.owner else parent
	return n


func _json(data: Dictionary) -> String:
	return JSON.stringify(data, "  ", true) + "\n"


func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
