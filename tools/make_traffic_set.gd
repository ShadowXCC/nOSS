extends SceneTree
## Builds the original low-poly traffic set (D117, docs/ART_AUDIO.md §3) as unpacked packages in
## content/traffic/<type>/ (outside content/cars/, so they never show in the car pickers): a
## hatchback, a saloon, an SUV, a van, a box truck, a bus and a police car. Each has LOD0 (wheels on
## hubs, glass, lights) and LOD1 (a few boxes; also what distant traffic is drawn with), head,
## brake and indicator lights the game switches (fit.json), and a primary paint slot traffic
## recolours per car. The police car has a light bar (nodes "lightbar_red" and "lightbar_blue").
##   tools/godot.sh --headless -s res://tools/make_traffic_set.gd [-- --only=<type>]

const OUT := "res://content/traffic/"
## Per type: size (m), wheels, body shape, base colour, package family, id.
const TYPES := {
	"hatch": { "name": "Hatchback", "len": 4.1, "wid": 1.78, "hgt": 1.48, "wb": 2.55, "track": 1.52, "wr": 0.31, "ww": 0.2,
		"shape": "car", "belt": 0.90, "nose": 0.68, "tail": 0.95, "cab": [0.72, -1.80, 0.02, -1.62], "color": "#8f1d1d",
		"family": "car", "id": "a0c5e2d4-6f11-4b6e-9a3c-1e2f3a4b5c61" },
	"saloon": { "name": "Saloon", "len": 4.75, "wid": 1.84, "hgt": 1.45, "wb": 2.80, "track": 1.57, "wr": 0.32, "ww": 0.21,
		"shape": "car", "belt": 0.92, "nose": 0.70, "tail": 0.90, "cab": [0.85, -1.25, 0.12, -0.95], "color": "#23324f",
		"family": "car", "id": "b1d6f3e5-7a22-4c7f-8b4d-2f3a4b5c6d72" },
	"suv": { "name": "SUV", "len": 4.8, "wid": 1.95, "hgt": 1.75, "wb": 2.85, "track": 1.65, "wr": 0.37, "ww": 0.24,
		"shape": "car", "belt": 1.08, "nose": 0.98, "tail": 1.06, "cab": [0.95, -2.22, 0.30, -2.05], "color": "#3d4a3a",
		"family": "car", "id": "c2e7a4f6-8b33-4d80-9c5e-3a4b5c6d7e83" },
	"van": { "name": "Van", "len": 5.6, "wid": 2.0, "hgt": 2.45, "wb": 3.4, "track": 1.70, "wr": 0.34, "ww": 0.22,
		"shape": "van", "color": "#f2f2ee", "family": "car", "id": "d3f8b5a7-9c44-4e91-8d6f-4b5c6d7e8f94" },
	"truck": { "name": "Box truck", "len": 8.4, "wid": 2.5, "hgt": 3.6, "wb": 4.8, "track": 2.0, "wr": 0.5, "ww": 0.3,
		"shape": "truck", "color": "#1f4d8f", "family": "truck", "id": "e4a9c6b8-ad55-4fa2-9e70-5c6d7e8f9a05" },
	"bus": { "name": "Bus", "len": 12.0, "wid": 2.55, "hgt": 3.2, "wb": 6.0, "track": 2.05, "wr": 0.5, "ww": 0.3,
		"shape": "bus", "color": "#b8311f", "family": "truck", "id": "f5bad7c9-be66-40b3-8f81-6d7e8f9a0b16" },
	"police": { "name": "Police", "len": 4.9, "wid": 1.9, "hgt": 1.48, "wb": 2.85, "track": 1.60, "wr": 0.34, "ww": 0.23,
		"shape": "car", "belt": 0.94, "nose": 0.72, "tail": 0.92, "cab": [0.88, -1.30, 0.14, -1.00], "color": "#101418",
		"family": "car", "id": "06cbe8da-cf77-41c4-9092-7e8f9a0b1c27", "lightbar": true },
}
const BOTTOM := 0.24

var _materials := {}
var _t := {}


func _init() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	for id: String in TYPES:
		if only and id != only:
			continue
		_t = TYPES[id]
		var err := _make(id)
		if err:
			push_error("%s: %s" % [id, err])
			quit(1)
			return
		print("%s written to %s%s/" % [_t.name, OUT, id])
	quit()


func _make(id: String) -> String:
	var dir := OUT + id + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "model"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "sound"))
	for lod in 2:
		var root := Node3D.new()
		root.name = id if lod == 0 else id + "_lod1"
		if lod == 0:
			_build(root)
		else:
			_build_lod1(root)
		var doc := GLTFDocument.new()
		doc.root_node_mode = GLTFDocument.ROOT_NODE_MODE_KEEP_ROOT
		var state := GLTFState.new()
		var err := doc.append_from_scene(root, state)
		var file := "model/body.glb" if lod == 0 else "model/lod1.glb"
		if err == OK:
			err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(dir + file))
		root.free()
		if err != OK:
			return "GLB export failed: %d" % err
		_write(dir + file + ".import", "[remap]\n\nimporter=\"keep\"\n".to_utf8_buffer())
	var files := {
		"fit.json": _json(_fit()),
		"paint.json": _json({ "schema": "noss.paint/1", "slots": { "primary": { "materials": ["Paint_Primary"], "color": _t.color, "finish": "metallic" } } }),
		"sound/profile.json": _json({ "schema": "noss.sound/1", "name": "Traffic", "base": "i4" if _t.family == "car" else "v8_crossplane" }),
	}
	for rel: String in files:
		_write(dir + rel, files[rel].to_utf8_buffer())
	var hashes := {}
	for rel: String in files.keys() + ["model/body.glb", "model/lod1.glb"]:
		hashes[rel] = "sha256:" + PlatformLoader.sha256_hex(FileAccess.get_file_as_bytes(dir + rel))
	var manifest := {
		"schema": "noss.package/1", "id": _t.id, "version": 1, "name": "nOSS " + _t.name,
		"author": "nOSS contributors", "license": "CC-BY-SA-4.0", "family": _t.family,
		"tags": ["traffic", "original"] + (["police"] if _t.get("lightbar", false) else []),
		"source": "tools/make_traffic_set.gd", "created": "2026-10-14", "game_min_version": "0.7.0", "files": hashes,
	}
	_write(dir + "manifest.json", _json(manifest).to_utf8_buffer())
	return ""


# --- LOD0 ------------------------------------------------------------------------------------


func _build(root: Node3D) -> void:
	var body := _node("body", root)
	var half := float(_t.wid) / 2.0
	match String(_t.shape):
		"car":
			_mesh_node("shell", body, _extruded("Paint_Primary", _car_profile(true), half))
			_mesh_node("cabin", body, _car_cabin())
		"van":
			_mesh_node("shell", body, _extruded("Paint_Primary", _van_profile(true), half))
			_mesh_node("glass", body, _van_glass())
		"truck":
			_truck(body, true)
		"bus":
			_mesh_node("shell", body, _extruded("Paint_Primary", _bus_profile(true), half))
			_mesh_node("glass", body, _bus_glass())
	_mesh_node("trim", body, _trim())
	_lights(body)
	if _t.get("lightbar", false):
		_lightbar(body)
	for wid in ["LF", "RF", "LR", "RR"]:
		var side := 1.0 if wid[0] == "L" else -1.0
		var z: float = float(_t.wb) / 2.0 if wid[1] == "F" else -float(_t.wb) / 2.0
		var hub := _node("hub_" + wid, root)
		hub.position = Vector3(float(_t.track) / 2.0 * side, _t.wr, z + _axle_shift())
		_mesh_node("wheel_" + wid, hub, _wheel(side, 20, true))


## Trucks and buses sit their wheels a little forward of the middle.
func _axle_shift() -> float:
	return 0.6 if _t.shape == "truck" else (0.4 if _t.shape == "bus" else 0.0)


# --- LOD1: a few boxes --------------------------------------------------------------------------


func _build_lod1(root: Node3D) -> void:
	var body := _node("body", root)
	var half := float(_t.wid) / 2.0
	match String(_t.shape):
		"car":
			_mesh_node("shell", body, _extruded("Paint_Primary", _car_profile(false), half))
			var c: Array = _t.cab
			var glass := _begin("Glass")
			_box_into(glass, Vector3(0, (float(_t.belt) + float(_t.hgt)) / 2.0, (float(c[0]) + float(c[1])) / 2.0),
				Vector3(_t.wid - 0.3, float(_t.hgt) - float(_t.belt), (float(c[0]) - float(c[1])) * 0.82))
			_mesh_node("cabin", body, glass.commit())
		"van":
			_mesh_node("shell", body, _extruded("Paint_Primary", _van_profile(false), half))
		"truck":
			_truck(body, false)
		"bus":
			_mesh_node("shell", body, _extruded("Paint_Primary", _bus_profile(false), half))
	_lights(body)
	if _t.get("lightbar", false):
		_lightbar(body)
	var wheels := _begin("tire")
	for wid in ["LF", "RF", "LR", "RR"]:
		var side := 1.0 if wid[0] == "L" else -1.0
		var z: float = float(_t.wb) / 2.0 if wid[1] == "F" else -float(_t.wb) / 2.0
		_box_into(wheels, Vector3(float(_t.track) / 2.0 * side, _t.wr, z + _axle_shift()), Vector3(_t.ww, _t.wr * 1.9, _t.wr * 1.9))
	_mesh_node("wheels", body, wheels.commit())


# --- shapes ------------------------------------------------------------------------------------


## A car's side outline (z, y): bumpers, wheel arches (with `arches`), bonnet up to the windscreen,
## the boot or hatch down from the rear window.
func _car_profile(arches: bool) -> PackedVector2Array:
	var l: float = float(_t.len) / 2.0
	var c: Array = _t.cab
	var p := PackedVector2Array([Vector2(-l, 0.36), Vector2(-l + 0.08, BOTTOM)])
	_arches(p, arches)
	p.append_array([Vector2(l - 0.08, BOTTOM), Vector2(l, 0.36), Vector2(l, float(_t.nose)), Vector2(l - 0.3, float(_t.nose) + 0.06),
		Vector2(float(c[0]), float(_t.belt)), Vector2(float(c[1]), float(_t.belt)), Vector2(-l + 0.18, float(_t.tail)), Vector2(-l, float(_t.tail) - 0.06)])
	return p


func _van_profile(arches: bool) -> PackedVector2Array:
	var l: float = float(_t.len) / 2.0
	var h: float = _t.hgt
	var p := PackedVector2Array([Vector2(-l, 0.40), Vector2(-l + 0.06, BOTTOM + 0.04)])
	_arches(p, arches)
	p.append_array([Vector2(l - 0.06, BOTTOM + 0.04), Vector2(l, 0.40), Vector2(l, 1.0), Vector2(l - 0.5, 1.15), Vector2(l - 1.25, h), Vector2(-l, h)])
	return p


func _bus_profile(arches: bool) -> PackedVector2Array:
	var l: float = float(_t.len) / 2.0
	var h: float = _t.hgt
	var p := PackedVector2Array([Vector2(-l, 0.42), Vector2(-l + 0.05, 0.32)])
	_arches(p, arches)
	p.append_array([Vector2(l - 0.05, 0.32), Vector2(l, 0.42), Vector2(l, h - 0.25), Vector2(l - 0.25, h), Vector2(-l + 0.15, h), Vector2(-l, h - 0.15)])
	return p


func _arches(p: PackedVector2Array, arches: bool) -> void:
	var wr: float = _t.wr
	var r := wr + 0.08
	for zc: float in [-float(_t.wb) / 2.0 + _axle_shift(), float(_t.wb) / 2.0 + _axle_shift()]:
		if not arches:
			continue
		var bottom := p[p.size() - 1].y
		p.append(Vector2(zc - r, bottom))
		for i in range(0, 9):
			var a := PI - PI * i / 8.0
			p.append(Vector2(zc + r * cos(a), wr + r * 0.85 * sin(a)))
		p.append(Vector2(zc + r, bottom))


## The car's glasshouse: windscreens and side windows, a painted roof.
func _car_cabin() -> ArrayMesh:
	var c: Array = _t.cab
	var belt: float = _t.belt
	var h: float = _t.hgt
	var base_r := float(_t.wid) / 2.0 - 0.05
	var top_r := float(_t.wid) / 2.0 - 0.2
	var outline := [Vector2(float(c[1]), belt), Vector2(float(c[0]), belt), Vector2(float(c[2]), h), Vector2(float(c[3]), h)]
	var glass := _begin("Glass")
	var pts := outline.map(func(v: Vector2) -> Vector3: return Vector3(lerpf(base_r, top_r, (v.y - belt) / (h - belt)), v.y, v.x))
	for i in [1, 3]:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 4]
		_quad(glass, Vector3(-a.x, a.y, a.z), a, b, Vector3(-b.x, b.y, b.z))
	_tri(glass, pts[0], pts[2], pts[1])
	_tri(glass, pts[0], pts[3], pts[2])
	var m := pts.map(func(v: Vector3) -> Vector3: return Vector3(-v.x, v.y, v.z))
	_tri(glass, m[0], m[1], m[2])
	_tri(glass, m[0], m[2], m[3])
	var mesh: ArrayMesh = glass.commit()
	var roof := _begin("Paint_Primary")
	var a: Vector3 = pts[2]
	var b: Vector3 = pts[3]
	_quad(roof, Vector3(-a.x, a.y, a.z), a, b, Vector3(-b.x, b.y, b.z))
	return roof.commit(mesh)


func _van_glass() -> ArrayMesh:
	var l: float = float(_t.len) / 2.0
	var h: float = _t.hgt
	var half := float(_t.wid) / 2.0 + 0.01
	var g := _begin("Glass")
	# Windscreen on the slope, side windows in the cab.
	var a := Vector3(half - 0.1, 1.2, l - 0.55)
	var b := Vector3(half - 0.1, h - 0.15, l - 1.2)
	_quad(g, Vector3(-a.x, a.y, a.z), a, b, Vector3(-b.x, b.y, b.z))
	for side: float in [1.0, -1.0]:
		var q := [Vector3(half * side, 1.25, l - 0.6), Vector3(half * side, 1.25, l - 1.9), Vector3(half * side, h - 0.35, l - 1.9), Vector3(half * side, h - 0.35, l - 1.3)]
		if side > 0:
			_quad(g, q[0], q[1], q[2], q[3])
		else:
			_quad(g, q[1], q[0], q[3], q[2])
	return g.commit()


func _bus_glass() -> ArrayMesh:
	var l: float = float(_t.len) / 2.0
	var h: float = _t.hgt
	var half := float(_t.wid) / 2.0 + 0.01
	var g := _begin("Glass")
	for side: float in [1.0, -1.0]:
		var q := [Vector3(half * side, 1.3, l - 0.4), Vector3(half * side, 1.3, -l + 0.5), Vector3(half * side, h - 0.45, -l + 0.5), Vector3(half * side, h - 0.45, l - 0.4)]
		if side > 0:
			_quad(g, q[0], q[1], q[2], q[3])
		else:
			_quad(g, q[1], q[0], q[3], q[2])
	var f := Vector3(half - 0.1, 1.0, l + 0.01)
	var t := Vector3(half - 0.1, h - 0.3, l + 0.01)
	_quad(g, Vector3(-f.x, f.y, f.z), f, t, Vector3(-t.x, t.y, t.z))
	return g.commit()


## A box truck: a cab in front, a box body behind, dark chassis rails under it.
func _truck(body: Node3D, detail: bool) -> void:
	var l: float = float(_t.len) / 2.0
	var half := float(_t.wid) / 2.0
	var cab_len := 2.3
	var cab_h := 2.95
	var cab := PackedVector2Array([Vector2(l - cab_len, 0.55), Vector2(l, 0.55), Vector2(l, 1.25), Vector2(l - 0.25, cab_h - 0.25), Vector2(l - 0.5, cab_h), Vector2(l - cab_len, cab_h)])
	_mesh_node("cab", body, _extruded("Paint_Primary", cab, half - 0.05))
	var box := _begin("box_white")
	var box_front := l - cab_len - 0.15
	_box_into(box, Vector3(0, (1.05 + float(_t.hgt)) / 2.0, (box_front - l) / 2.0), Vector3(_t.wid, float(_t.hgt) - 1.05, box_front + l))
	_mesh_node("box", body, box.commit())
	var rails := _begin("black_trim")
	_box_into(rails, Vector3(0, 0.75, -0.3), Vector3(float(_t.track) - 0.6, 0.3, float(_t.len) - 0.8))
	_mesh_node("chassis", body, rails.commit())
	if detail:
		var g := _begin("Glass")
		var a := Vector3(half - 0.15, 1.35, l + 0.01)
		var b := Vector3(half - 0.15, cab_h - 0.35, l - 0.22)
		_quad(g, Vector3(-a.x, a.y, a.z), a, b, Vector3(-b.x, b.y, b.z))
		_mesh_node("glass", body, g.commit())


func _trim() -> ArrayMesh:
	var l: float = float(_t.len) / 2.0
	var st := _begin("black_trim")
	var w: float = float(_t.wid) - 0.06
	_box_into(st, Vector3(0, 0.33, l - 0.02), Vector3(w, 0.14, 0.08))
	_box_into(st, Vector3(0, 0.35, -l + 0.02), Vector3(w, 0.14, 0.08))
	return st.commit()


## Head lights (white), tail lights (red), indicators (amber, by side) at the corners.
func _lights(body: Node3D) -> void:
	var l: float = float(_t.len) / 2.0
	var half := float(_t.wid) / 2.0
	var hy := (float(_t.nose) - 0.12) if _t.shape == "car" else 0.85
	var ty := (float(_t.tail) - 0.18) if _t.shape == "car" else (1.1 if _t.shape != "truck" else 1.2)
	for side: float in [1.0, -1.0]:
		var x := (half - 0.28) * side
		_mesh_node("headlight_" + ("L" if side > 0 else "R"), body, _box(Vector3(x, hy, l + 0.005), Vector3(0.36, 0.13, 0.03), "head_light"))
		_mesh_node("taillight_" + ("L" if side > 0 else "R"), body, _box(Vector3(x, ty, -l - 0.005), Vector3(0.32, 0.14, 0.03), "tail_light"))
		var ind := "indicator_L" if side > 0 else "indicator_R"
		_mesh_node(ind + "_front", body, _box(Vector3((half - 0.07) * side, hy, l + 0.004), Vector3(0.12, 0.10, 0.03), ind))
		_mesh_node(ind + "_rear", body, _box(Vector3((half - 0.07) * side, ty + 0.15, -l - 0.004), Vector3(0.12, 0.10, 0.03), ind))


## The police light bar on the roof: a red half and a blue half (D116).
func _lightbar(body: Node3D) -> void:
	var c: Array = _t.cab
	var z := (float(c[2]) + float(c[3])) / 2.0
	var y := float(_t.hgt) + 0.07
	_mesh_node("lightbar_base", body, _box(Vector3(0, y - 0.03, z), Vector3(1.1, 0.06, 0.28), "black_trim"))
	_mesh_node("lightbar_red", body, _box(Vector3(0.28, y + 0.04, z), Vector3(0.5, 0.1, 0.24), "lightbar_red"))
	_mesh_node("lightbar_blue", body, _box(Vector3(-0.28, y + 0.04, z), Vector3(0.5, 0.1, 0.24), "lightbar_blue"))
	# White doors: the classic look.
	var doors := _begin("Paint_Secondary")
	var half := float(_t.wid) / 2.0 + 0.005
	for side: float in [1.0, -1.0]:
		var q := [Vector3(half * side, 0.42, 0.75), Vector3(half * side, 0.42, -0.9), Vector3(half * side, float(_t.belt) - 0.05, -0.9), Vector3(half * side, float(_t.belt) - 0.05, 0.75)]
		if side > 0:
			_quad(doors, q[0], q[1], q[2], q[3])
		else:
			_quad(doors, q[1], q[0], q[3], q[2])
	_mesh_node("doors", body, doors.commit())


func _wheel(side: float, seg: int, rim: bool) -> ArrayMesh:
	var tire := _begin("tire")
	var wr: float = _t.wr
	var half: float = float(_t.ww) / 2.0
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(0, sin(a0), cos(a0)) * wr
		var p1 := Vector3(0, sin(a1), cos(a1)) * wr
		var x0 := Vector3(-half, 0, 0)
		var x1 := Vector3(half, 0, 0)
		_quad(tire, p0 + x1, p1 + x1, p1 + x0, p0 + x0)
		_quad(tire, p0 + x0, p1 + x0, p1 * 0.62 + x0, p0 * 0.62 + x0)
		_quad(tire, p0 * 0.62 + x1, p1 * 0.62 + x1, p1 + x1, p0 + x1)
	var mesh: ArrayMesh = tire.commit()
	if not rim:
		return mesh
	var hub := _begin("rim")
	var face := half * side * 0.9
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(face, sin(a0) * wr * 0.62, cos(a0) * wr * 0.62)
		var p1 := Vector3(face, sin(a1) * wr * 0.62, cos(a1) * wr * 0.62)
		var c := Vector3(face - 0.03 * side, 0, 0)
		if side > 0:
			_tri(hub, c, p1, p0)
		else:
			_tri(hub, c, p0, p1)
	return hub.commit(mesh)


# --- fit -----------------------------------------------------------------------------------


func _fit() -> Dictionary:
	var wheels := []
	for wid in ["LF", "RF", "LR", "RR"]:
		var side := 1.0 if wid[0] == "L" else -1.0
		var z: float = (float(_t.wb) / 2.0 if wid[1] == "F" else -float(_t.wb) / 2.0) + _axle_shift()
		wheels.append({ "id": wid, "axle": 1 if wid[1] == "F" else 2, "side": wid[0], "node": "hub_" + wid, "spin_node": "wheel_" + wid,
			"center": [snappedf(float(_t.track) / 2.0 * side, 0.001), _t.wr, snappedf(z, 0.001)], "radius": _t.wr, "width": _t.ww })
	var l: float = float(_t.len) / 2.0
	var half := float(_t.wid) / 2.0
	var top := float(_t.hgt) + (0.15 if _t.get("lightbar", false) else 0.0)
	return {
		"schema": "noss.fit/1",
		"model_transform": { "scale": 1.0, "rotation_deg": [0, 0, 0], "offset_m": [0, 0, 0] },
		"ground_y": 0.0,
		"wheel_mode": "model",
		"wheels": wheels,
		"steering_wheel": null,
		"eye_point": [snappedf(half * 0.45, 0.01), snappedf(minf(top - 0.3, float(_t.get("belt", 1.0)) + 0.35), 0.01), snappedf(l * 0.15, 0.01)],
		"cameras": { "hood": null, "bumper": null },
		"envelope": { "min": [-half, 0.0, -l], "max": [half, top, l] },
		"lights": { "head": ["head_light"], "brake": ["tail_light"], "reverse": [], "indicator_L": ["indicator_L"], "indicator_R": ["indicator_R"] },
		"exhaust_points": [[snappedf(half * 0.5, 0.01), 0.3, -l]],
		"hide_nodes": [],
		"lod_distances_m": [0, 45],
	}


# --- mesh helpers ----------------------------------------------------------------------------


func _extruded(material: String, outline: PackedVector2Array, half: float) -> ArrayMesh:
	var st := _begin(material)
	if Geometry2D.is_polygon_clockwise(outline):
		outline.reverse()
	var tris := Geometry2D.triangulate_polygon(outline)
	for i in range(0, tris.size(), 3):
		var a := outline[tris[i]]
		var b := outline[tris[i + 1]]
		var c := outline[tris[i + 2]]
		_tri(st, Vector3(half, a.y, a.x), Vector3(half, c.y, c.x), Vector3(half, b.y, b.x))
		_tri(st, Vector3(-half, a.y, a.x), Vector3(-half, b.y, b.x), Vector3(-half, c.y, c.x))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		_quad(st, Vector3(-half, a.y, a.x), Vector3(half, a.y, a.x), Vector3(half, b.y, b.x), Vector3(-half, b.y, b.x))
	return st.commit()


func _box(center: Vector3, size: Vector3, material: String) -> ArrayMesh:
	var st := _begin(material)
	_box_into(st, center, size)
	return st.commit()


func _box_into(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size / 2.0
	var c := []
	for i in 8:
		c.append(center + Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
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
			m.albedo_color = Color(_t.color)
			m.metallic = 0.5
			m.roughness = 0.35
		"Paint_Secondary":
			m.albedo_color = Color(0.95, 0.95, 0.95)
			m.roughness = 0.35
		"Glass":
			m.albedo_color = Color(0.07, 0.09, 0.11)
			m.metallic = 0.3
			m.roughness = 0.08
		"black_trim", "tire":
			m.albedo_color = Color(0.05, 0.05, 0.055)
			m.roughness = 0.85
		"box_white":
			m.albedo_color = Color(0.9, 0.9, 0.88)
			m.roughness = 0.6
		"rim":
			m.albedo_color = Color(0.7, 0.72, 0.74)
			m.metallic = 0.8
			m.roughness = 0.35
		"head_light":
			m.albedo_color = Color(0.92, 0.92, 0.86)
			m.roughness = 0.2
		"tail_light":
			m.albedo_color = Color(0.45, 0.02, 0.02)
			m.roughness = 0.2
		"indicator_L", "indicator_R":
			m.albedo_color = Color(0.55, 0.32, 0.02)
			m.roughness = 0.2
		"lightbar_red":
			m.albedo_color = Color(0.5, 0.04, 0.04)
			m.roughness = 0.2
		"lightbar_blue":
			m.albedo_color = Color(0.04, 0.1, 0.55)
			m.roughness = 0.2
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
