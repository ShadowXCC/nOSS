class_name StuntBuilder
extends RefCounted
## Builds a track's kart pieces (D137): boost pads, jump ramps, wall-rides and loops. Each is a
## static body with the surface the tires read and its tag (noss_tag, D133): boost pads boost,
## jumps open the trick window, wall-rides and loops hold a kart to them. A piece is a node of its
## own ("Stunt_<id>"), so the editor can rebuild one. Item boxes come and go: the kart session's.

const PAD_UP := 0.008 # the pad's top over the road: under a centimetre, no step to feel
const JUMP_STEP := 0.5
const WALL_STEP := 2.0
const WALL_TAPER_M := 12.0 # a wall-ride's height grows over this at either end
const LOOP_SEGMENTS := 96
const DIVIDER_H := 0.8
const POST_W := 0.6

var track: TrackData
var layout: KartLayout
var visual := true
static var _materials := {}


static func build(data: TrackData, into: Node3D, visual := true) -> void:
	if data.kart == null:
		return
	var b := StuntBuilder.new()
	b.track = data
	b.layout = data.kart
	b.visual = visual
	for p in data.kart.pieces:
		b.build_piece(p, into)


## The piece's node, built into `into` ("Stunt_<id>"); null for an item row (no geometry).
func build_piece(p: Dictionary, into: Node3D) -> Node3D:
	if p.kind == "item_row":
		return null
	var node := Node3D.new()
	node.name = "Stunt_" + String(p.get("id", p.kind))
	into.add_child(node)
	match String(p.kind):
		"boost_pad":
			_boost_pad(p, node)
		"jump":
			_jump(p, node)
		"wall_ride":
			_wall_ride(p, node)
		"loop":
			_loop(p, node)
	return node


# --- pieces --------------------------------------------------------------------------------

func _boost_pad(p: Dictionary, node: Node3D) -> void:
	var b := MeshBatch.new()
	var length := float(p.length_m)
	var half := float(p.width_m) / 2.0
	var steps := maxi(2, ceili(length / 1.0))
	for s in steps:
		var u0 := float(s) / steps
		var u1 := float(s + 1) / steps
		var a := _frame_at(p, -length / 2.0 + length * u0)
		var c := _frame_at(p, -length / 2.0 + length * u1)
		b.quad([_at(a, half, PAD_UP), _at(a, -half, PAD_UP), _at(c, -half, PAD_UP), _at(c, half, PAD_UP)],
			[Vector2(0, length * u0), Vector2(1, length * u0), Vector2(1, length * u1), Vector2(0, length * u1)])
	_body(node, "Pad", b, _pad_material(), VehicleSim.SURFACE_PAINT, VehicleSim.TAG_BOOST)


## A wedge whose foot meets the road (its height grows as u^1.6 from 0 at the foot to the lip),
## the width of the road unless set; sides and the back drop straight down.
func _jump(p: Dictionary, node: Node3D) -> void:
	var length := float(p.length_m)
	var h := float(p.height_m)
	var top := MeshBatch.new()
	var sides := MeshBatch.new()
	var steps := maxi(4, ceili(length / JUMP_STEP))
	var prev := {}
	for s in steps + 1:
		var u := float(s) / steps
		var f := _frame_at(p, -length / 2.0 + length * u)
		var w := _jump_half_widths(p, f)
		var y := h * pow(u, 1.6)
		var cur := { "tl": _at(f, w.x, y), "tr": _at(f, -w.y, y), "bl": _at(f, w.x, 0.0), "br": _at(f, -w.y, 0.0), "u": u }
		if not prev.is_empty():
			top.quad([prev.tl, prev.tr, cur.tr, cur.tl], [Vector2(0, prev.u), Vector2(1, prev.u), Vector2(1, u), Vector2(0, u)])
			sides.quad([prev.bl, prev.tl, cur.tl, cur.bl], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			sides.quad([prev.tr, prev.br, cur.br, cur.tr], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		prev = cur
	sides.quad([prev.br, prev.bl, prev.tl, prev.tr], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]) # the back, under the lip
	_body(node, "Ramp", top, _material("jump", Color(0.95, 0.58, 0.12)), VehicleSim.SURFACE_CONCRETE, VehicleSim.TAG_JUMP)
	_body(node, "RampSides", sides, _material("jump_side", Color(0.32, 0.33, 0.36)), VehicleSim.SURFACE_CONCRETE, 0)


## Its half widths to the left and right of its centre (x left, y right).
func _jump_half_widths(p: Dictionary, f: Transform3D) -> Vector2:
	var w := float(p.width_m)
	if w > 0.0 or layout.on_arena():
		var half := (w if w > 0.0 else 6.0) / 2.0
		return Vector2(half, half)
	# The whole road: out to its edges from the piece's centre.
	var i := track.index_at(float(p.at_m))
	var lat := float(p.lateral_m)
	return Vector2(track.half_l[i] - lat, track.half_r[i] + lat)


## A quarter-pipe from the road's edge to vertical, then straight up (D137); it tapers in height
## at its ends. Its face looks at the road.
func _wall_ride(p: Dictionary, node: Node3D) -> void:
	var side := 1.0 if p.side == "left" else -1.0
	var length := float(p.length_m)
	var height := float(p.height_m)
	var b := MeshBatch.new()
	var steps := maxi(2, ceili(length / WALL_STEP))
	var prev: Array = []
	for s in steps + 1:
		var d := float(p.at_m) + length * s / steps
		var taper := clampf(minf(length * s / steps, length - length * s / steps) / WALL_TAPER_M, 0.0, 1.0)
		var cur := _wall_profile(d, side, lerpf(KartLayout.WALL_CURVE_M, height, taper))
		if not prev.is_empty():
			for m in cur.size() - 1:
				var q := [prev[m + 1], prev[m], cur[m], cur[m + 1]] if side > 0.0 else [prev[m], prev[m + 1], cur[m + 1], cur[m]]
				b.quad(q, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		prev = cur
	_body(node, "Wall", b, _material("stick", Color(0.16, 0.46, 0.86), true), VehicleSim.SURFACE_CONCRETE, VehicleSim.TAG_STICK)


## The wall's cross-section at `d`: from the road's edge out round the curve, then up.
func _wall_profile(d: float, side: float, height: float) -> Array:
	var i := track.index_at(d)
	var f := track.transform_at(d)
	var edge := (track.half_l[i] if side > 0.0 else track.half_r[i]) + 0.02
	var r := KartLayout.WALL_CURVE_M
	var out := []
	for k in 7:
		var a := PI / 2.0 * k / 6.0
		out.append(_at(f, side * (edge + r * sin(a)), r * (1.0 - cos(a))))
	out.append(_at(f, side * (edge + r), maxf(height, r + 0.05))) # every section the same shape
	return out


## The loop's ribbon (its face looks inward), two posts and a beam over it, and a divider that
## keeps the exit lane clear where the loop comes back down.
func _loop(p: Dictionary, node: Node3D) -> void:
	var half := float(p.width_m) / 2.0
	var ribbon := MeshBatch.new()
	for s in LOOP_SEGMENTS:
		var t0 := float(s) / LOOP_SEGMENTS
		var t1 := float(s + 1) / LOOP_SEGMENTS
		ribbon.quad([layout.loop_point(p, t0, half), layout.loop_point(p, t0, -half), layout.loop_point(p, t1, -half), layout.loop_point(p, t1, half)],
			[Vector2(0, t0 * 20.0), Vector2(1, t0 * 20.0), Vector2(1, t1 * 20.0), Vector2(0, t1 * 20.0)])
	_body(node, "Loop", ribbon, _material("stick", Color(0.16, 0.46, 0.86), true), VehicleSim.SURFACE_CONCRETE, VehicleSim.TAG_STICK)
	# Posts beside it and a beam over the top, upright.
	var r := float(p.radius_m)
	var lanes := layout.loop_lanes(p)
	var f := track.transform_at(float(p.at_m))
	var level := Basis(f.basis.x.slide(Vector3.UP).normalized(), Vector3.UP, f.basis.z.slide(Vector3.UP).normalized())
	var frame := MeshBatch.new()
	var outer := [lanes.x + half + 1.2, lanes.y - half - 1.2]
	for lat: float in outer:
		var foot := f.origin + f.basis.x * lat
		frame.box(foot + Vector3.UP * (r + 0.6), level, Vector3(POST_W, 2.0 * r + 1.2, POST_W))
	var mid: Vector3 = f.origin + f.basis.x * ((outer[0] + outer[1]) / 2.0) + Vector3.UP * (2.0 * r + 1.4)
	frame.box(mid, level, Vector3(outer[0] - outer[1] + POST_W, 0.5, POST_W))
	# The divider: the exit lane from before the loop up to where the ribbon comes down over it.
	var lip := sqrt(maxf(2.0 * DIVIDER_H * r - DIVIDER_H * DIVIDER_H, 0.0)) + 0.5
	var from := float(p.at_m) - r - KartLayout.LOOP_DIVIDER_M
	var to := float(p.at_m) - lip
	var steps := maxi(2, ceili((to - from) / 1.0))
	for s in steps:
		var d := lerpf(from, to, (s + 0.5) / steps)
		var x := track.transform_at(d, lanes.y)
		var nose := clampf((d - from) / 2.5, 0.25, 1.0) # a sloped nose that turns karts aside
		frame.box(x.origin + x.basis.y * DIVIDER_H * nose / 2.0, x.basis, Vector3(half * 2.0, DIVIDER_H * nose, (to - from) / steps))
	_body(node, "LoopFrame", frame, _material("frame", Color(0.85, 0.85, 0.82)), VehicleSim.SURFACE_CONCRETE, 0)


# --- helpers -------------------------------------------------------------------------------

## The piece's frame `along` metres from its middle: the road's (banked) on a circuit, or its
## own on an arena's flat floor.
func _frame_at(p: Dictionary, along: float) -> Transform3D:
	if layout.on_arena() or not p.has("at_m"):
		var f: Transform3D = p.frame
		return Transform3D(f.basis, f.origin + f.basis.z * along)
	return track.transform_at(float(p.at_m) + along, float(p.get("lateral_m", 0.0)))


func _at(f: Transform3D, lateral: float, up: float) -> Vector3:
	return f.origin + f.basis.x * lateral + f.basis.y * up


func _body(node: Node3D, part: String, b: MeshBatch, material: Material, surface: int, tag: int) -> void:
	if b.is_empty():
		return
	if visual:
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = b.mesh()
		mi.material_override = material
		node.add_child(mi)
	var body := StaticBody3D.new()
	body.name = part + "Body"
	body.set_meta(&"noss_surface", surface)
	if tag:
		body.set_meta(&"noss_tag", tag)
	var cs := CollisionShape3D.new()
	cs.shape = b.shape()
	body.add_child(cs)
	node.add_child(body)


static func _material(key: String, color: Color, both_sides := false) -> Material:
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.6
		if both_sides:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


static func _pad_material() -> Material:
	if not _materials.has("pad"):
		var m := ShaderMaterial.new()
		m.shader = load("res://game/world/kart/boost_pad.gdshader")
		_materials["pad"] = m
	return _materials["pad"]
