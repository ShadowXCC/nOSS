class_name Gizmos
extends Node3D
## What the track editor draws over the track (D95): control points (the selected one bigger,
## ringed), the centreline and road edges, arrows showing the driving direction, the start line,
## the grid, the sector lines, the AI line's pins, the brush ring and the cursor. Drawn on top,
## in the player's palette, and never by colour alone (sizes, rings, shapes and labels too).

const LIFT := 0.35
const ARROW_EVERY_M := 100.0
const AI_WIDTH := 0.7

var colors := {}
## Point markers grow with the camera's distance, so they stay about the same size on screen.
var point_scale := 1.0
var _lines := ImmediateMesh.new()
var _lines_mi := MeshInstance3D.new()
var _brush := ImmediateMesh.new()
var _brush_mi := MeshInstance3D.new()
var _points := MultiMeshInstance3D.new()
var _selected := MeshInstance3D.new()
var _labels := Node3D.new()
var _ai := ImmediateMesh.new()
var _ai_mi := MeshInstance3D.new()


func _init() -> void:
	name = "Gizmos"
	var line_mat := _material(Color.WHITE, true)
	_lines_mi.mesh = _lines
	_lines_mi.material_override = line_mat
	_lines_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines_mi)
	_brush_mi.mesh = _brush
	_brush_mi.material_override = line_mat
	_brush_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_brush_mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	mm.mesh = sphere
	_points.multimesh = mm
	_points.material_override = _material(Color.WHITE, true)
	_points.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_points)
	var ring := TorusMesh.new()
	ring.inner_radius = 2.2
	ring.outer_radius = 2.8
	_selected.mesh = ring
	_selected.material_override = _material(Color.WHITE)
	_selected.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selected.visible = false
	add_child(_selected)
	add_child(_labels)
	_ai_mi.mesh = _ai
	var ai_mat := _material(Color.WHITE, true)
	ai_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ai_mi.material_override = ai_mat
	_ai_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ai_mi)


func _ready() -> void:
	var profile: PlayerProfile = Settings.primary if Settings.primary else null
	for role in ["p1", "good", "bad", "warn", "p2"]:
		colors[role] = Palette.color(profile, role) if profile else Color.WHITE
	(_selected.material_override as StandardMaterial3D).albedo_color = colors.p1


## The road's points, line and edges, the direction, start line, grid and sectors.
## `selected`: the selected point (-1 none); `hover`: the one under the cursor.
func show_track(t: TrackData, points: Array, selected := -1, hover := -1, show_grid := true) -> void:
	_lines.clear_surfaces()
	_ai.clear_surfaces()
	for child in _labels.get_children():
		child.queue_free()
	var mm := _points.multimesh
	mm.instance_count = points.size()
	for i in points.size():
		var p: Array = points[i].p
		var at := Vector3(p[0], p[1], p[2])
		if t.samples.size() > 2:
			at.y = t.samples[t.seg_first[i]].y if i < t.seg_first.size() else at.y
		var size := (1.6 if i == selected else 1.2 if i == hover else 0.8) * point_scale
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), at + Vector3.UP * (LIFT + 0.6)))
		mm.set_instance_color(i, colors.p1 if i == selected else Color(1, 1, 1, 1) if i == hover else Color(0.85, 0.85, 0.85))
		if i == selected:
			_selected.visible = true
			_selected.position = at + Vector3.UP * LIFT
			_selected.scale = Vector3.ONE * point_scale
	if selected < 0 or selected >= points.size():
		_selected.visible = false
	if t.samples.size() < 3:
		if points.size() > 1:
			_begin(Color(1, 1, 1, 0.8))
			for i in points.size():
				var p: Array = points[i].p
				_lines.surface_add_vertex(Vector3(p[0], p[1], p[2]) + Vector3.UP * LIFT)
			_lines.surface_end()
		return
	# Centreline and edges.
	var n := t.samples.size()
	_begin(Color(1, 1, 1, 0.9))
	for k in n + 1:
		_lines.surface_add_vertex(t.samples[k % n] + Vector3.UP * LIFT)
	_lines.surface_end()
	for side: float in [1.0, -1.0]:
		_begin(Color(0.7, 0.7, 0.7, 0.6))
		for k in n + 1:
			var i := k % n
			_lines.surface_add_vertex(t.samples[i] + t.lefts[i] * side * (t.half_l[i] if side > 0.0 else t.half_r[i]) + Vector3.UP * LIFT)
		_lines.surface_end()
	# Driving direction: chevrons along the centreline.
	var d := ARROW_EVERY_M / 2.0
	while d < t.length:
		var x := t.transform_at(d)
		var tip := x.origin + x.basis.z * 3.0 + Vector3.UP * LIFT
		_begin(Color(1, 1, 1, 0.9))
		_lines.surface_add_vertex(tip - x.basis.z * 3.0 + x.basis.x * 2.0)
		_lines.surface_add_vertex(tip)
		_lines.surface_add_vertex(tip - x.basis.z * 3.0 - x.basis.x * 2.0)
		_lines.surface_end()
		d += ARROW_EVERY_M
	# Start line, a chequered flag mark, then the grid and the sector lines.
	var s := t.transform_at(t.start_m)
	var i0 := t.index_at(t.start_m)
	_begin(colors.good)
	for k in 3:
		var off := s.basis.z * (k - 1) * 0.3 + Vector3.UP * LIFT
		_lines.surface_add_vertex(s.origin + s.basis.x * t.half_l[i0] + off)
		_lines.surface_add_vertex(s.origin - s.basis.x * t.half_r[i0] + off)
	_lines.surface_end()
	_label("Start", s.origin + Vector3.UP * 4.0)
	if show_grid:
		var slots := int(t.grid.slots)
		for slot in slots:
			var x := t.grid_slot(slot)
			_box(x, Vector3(1.0, 0.0, 2.2), Color(1, 1, 1, 0.7))
			if slot < 3 or slot == slots - 1:
				_label(str(slot + 1), x.origin + Vector3.UP * 1.5)
	for k in t.sectors_m.size():
		var at := t.transform_at(t.start_m + t.sectors_m[k])
		var ik := t.index_at(t.start_m + t.sectors_m[k])
		_begin(colors.warn)
		_lines.surface_add_vertex(at.origin + at.basis.x * t.half_l[ik] + Vector3.UP * LIFT)
		_lines.surface_add_vertex(at.origin - at.basis.x * t.half_r[ik] + Vector3.UP * LIFT)
		_lines.surface_end()
		_label("S%d" % (k + 1), at.origin + Vector3.UP * 3.0)


## The AI's line as a ribbon (`points` and the road's `lefts`, one per sample) and its pins
## (`pins`: positions; `selected` drawn bigger). An empty line hides the ribbon.
func show_ai_line(points: PackedVector3Array, lefts: PackedVector3Array, pins: Array, selected := -1) -> void:
	_ai.clear_surfaces()
	var c: Color = colors.get("p2", Color.CYAN)
	if points.size() > 2 and lefts.size() == points.size():
		_ai.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		_ai.surface_set_color(Color(c, 0.85))
		var up := Vector3.UP * (LIFT + 0.05)
		for k in points.size() + 1:
			var i := k % points.size()
			_ai.surface_add_vertex(points[i] + lefts[i] * AI_WIDTH / 2.0 + up)
			_ai.surface_add_vertex(points[i] - lefts[i] * AI_WIDTH / 2.0 + up)
		_ai.surface_end()
	# Pins: a post with a diamond on top, the selected one bigger.
	for k in pins.size():
		var at: Vector3 = pins[k]
		var s := (2.0 if k == selected else 1.2) * point_scale
		var top := at + Vector3.UP * (LIFT + 3.0 * s)
		_ai.surface_begin(Mesh.PRIMITIVE_LINES)
		_ai.surface_set_color(colors.p1 if k == selected else c)
		_ai.surface_add_vertex(at + Vector3.UP * LIFT)
		_ai.surface_add_vertex(top)
		for side: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
			var a := top + side * s
			var b := top + side.rotated(Vector3.UP, PI / 2.0) * s
			_ai.surface_add_vertex(a)
			_ai.surface_add_vertex(b)
		_ai.surface_end()


## A ring on the ground (`height` gives the ground) where a brush would touch; radius 0 hides it.
func show_brush(center: Vector3, radius: float, height: Callable, color := Color.WHITE) -> void:
	_brush.clear_surfaces()
	if radius <= 0.0:
		return
	_brush.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_brush.surface_set_color(color)
	for k in 65:
		var a := TAU * k / 64.0
		var p := center + Vector3(cos(a), 0, sin(a)) * radius
		p.y = float(height.call(p.x, p.z)) + 0.3 if height.is_valid() else center.y + 0.3
		_brush.surface_add_vertex(p)
	_brush.surface_end()
	_brush.surface_begin(Mesh.PRIMITIVE_LINES)
	_brush.surface_set_color(color)
	_brush.surface_add_vertex(center + Vector3(-1.5, 0.3, 0))
	_brush.surface_add_vertex(center + Vector3(1.5, 0.3, 0))
	_brush.surface_add_vertex(center + Vector3(0, 0.3, -1.5))
	_brush.surface_add_vertex(center + Vector3(0, 0.3, 1.5))
	_brush.surface_end()


func _begin(c: Color) -> void:
	_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_lines.surface_set_color(c)


func _box(x: Transform3D, size: Vector3, c: Color) -> void:
	var h := size / 2.0
	_begin(c)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		_lines.surface_add_vertex(x.origin + x.basis.x * corner.x * h.x + x.basis.z * corner.y * h.z + Vector3.UP * LIFT)
	_lines.surface_end()


func _label(text: String, at: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.font_size = 40
	l.outline_size = 10
	l.render_priority = 2
	_labels.add_child(l)


static func _material(c: Color, vertex_color := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = vertex_color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 1
	return m
