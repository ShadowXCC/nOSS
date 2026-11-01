class_name SpikeStrip
extends Node3D
## A spike strip (D192, D248): laid across lanes of the road ahead of a chased player (PoliceLanes
## picks which). A wheel that rolls over it goes flat (Vehicle.flatten) for FLAT_S, or until the
## car's reset. It lies in road space, `at_m` along the road from `lat_from` to `lat_to` across, so
## it's checked through the road's own projection wherever the scene's origin is.
##
## It's made to be seen (D249): two staggered rows of cartoon-chrome teeth on a dark base with
## yellow ends, and a star-shaped glint (spike_glint.gdshader) that pops on a tooth, then another,
## every GLINT_EVERY_S. The glint is never smaller than a share of the view, so it shows from far
## up the road. With Reduce flashing (Flash.LAYER_CALM) a dimmer star shines steadily instead.

const LENGTH_M := 0.8
const FLAT_S := 30.0
## Taken up once its player is this far past it, or this long after it went down.
const PAST_M := 120.0
const LIFE_S := 60.0
## Wheels further than this from its middle aren't looked at.
const NEAR_M := 14.0
## The teeth: this far apart across it, two rows this far either side of its middle (the second
## half a step over), each this wide at its foot and this tall, on a base this deep and tall.
const TOOTH_STEP_M := 0.12
const TOOTH_ROW_M := 0.13
const TOOTH_W := 0.07
const TOOTH_H := 0.1
const BASE_DEPTH_M := 0.5
const BASE_H := 0.04
## The glint: on a new tooth every GLINT_EVERY_S, up and gone again in GLINT_POP_S, turning
## GLINT_TWIST rad as it does (at most 1 / GLINT_EVERY_S flashes a second: under WCAG's three).
## Reduce flashing: a still star at GLINT_CALM of its brightness and GLINT_CALM_SIZE of its size.
const GLINT_EVERY_S := 0.5
const GLINT_POP_S := 0.18
const GLINT_TWIST := 0.6
const GLINT_CALM := 0.55
const GLINT_CALM_SIZE := 0.8

var road: PoliceRoad
var at_m := 0.0
var lat_from := 0.0
var lat_to := 0.0
## Whom it was laid for (none: another game's, D195), and whose cars it catches.
var for_racer: Racer
var watch: Array = []
var age := 0.0
## The teeth's tips (local), for the glint to sit on; the glint and its calm copy.
var tips := PackedVector3Array()
var glint: MeshInstance3D
var calm_glint: MeshInstance3D
var _glint_at := -1
var _rng := RandomNumberGenerator.new()
static var _chrome: ShaderMaterial
static var _glint_shader: Shader


func _ready() -> void:
	name = "SpikeStrip"
	add_to_group(&"origin_shift")
	var at := road.session.track.transform_at(at_m, (lat_from + lat_to) / 2.0)
	transform = Transform3D(at.basis, at.origin + at.basis.y * 0.03)
	var width := absf(lat_to - lat_from)
	var base := MeshInstance3D.new()
	base.name = "Base"
	var box := BoxMesh.new()
	box.size = Vector3(width, BASE_H, BASE_DEPTH_M)
	base.mesh = box
	base.position.y = BASE_H / 2.0 - 0.02
	base.material_override = WorldMaterials.get_material("spike_strip_base", null, 0.7, 0.1, false, Vector2.ONE, Color(0.1, 0.1, 0.11))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base)
	for end: float in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.3, 0.1, LENGTH_M)
		cap.mesh = cb
		cap.position = Vector3(end * width / 2.0, 0.02, 0.0)
		cap.material_override = WorldMaterials.get_material("spike_strip_end", null, 0.6, 0.2, false, Vector2.ONE, Color(1.0, 0.8, 0.1))
		add_child(cap)
	var teeth := MeshInstance3D.new()
	teeth.name = "Teeth"
	teeth.mesh = _teeth(width)
	teeth.material_override = chrome()
	teeth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(teeth)
	_rng.seed = hash([at_m, lat_from])
	glint = _glint(false)
	calm_glint = _glint(true)
	calm_glint.position = tips[tips.size() / 2] + Vector3.UP * 0.05
	_hop()


## Two staggered rows of four-sided teeth across `width`, standing on the base.
func _teeth(width: float) -> ArrayMesh:
	var b := MeshBatch.new()
	var half := width / 2.0 - 0.2 # clear of the end caps
	for row: float in [-1.0, 1.0]:
		var x := -half + (TOOTH_STEP_M / 2.0 if row > 0.0 else 0.0)
		while x <= half:
			var foot := Vector3(x, BASE_H - 0.02, row * TOOTH_ROW_M)
			var tip := foot + Vector3(0.0, TOOTH_H, 0.0)
			tips.append(tip)
			var h := TOOTH_W / 2.0
			var corners := [foot + Vector3(-h, 0, -h), foot + Vector3(h, 0, -h), foot + Vector3(h, 0, h), foot + Vector3(-h, 0, h)]
			for k in 4:
				_tri(b, corners[k], corners[(k + 1) % 4], tip)
			x += TOOTH_STEP_M
	return b.mesh()


## A flat-shaded triangle, its front the side its corners go round clockwise (Godot's way).
static func _tri(b: MeshBatch, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	var n := (p2 - p0).cross(p1 - p0).normalized()
	var i := b.vertex(p0, n, Vector2.ZERO)
	b.vertex(p1, n, Vector2(1, 0))
	b.vertex(p2, n, Vector2(0.5, 1))
	b.index.append_array([i, i + 1, i + 2])


## The teeth's cartoon chrome (spike_chrome.gdshader), shared.
static func chrome() -> ShaderMaterial:
	if _chrome == null:
		_chrome = ShaderMaterial.new()
		_chrome.shader = load("res://game/modes/police/spike_chrome.gdshader")
	return _chrome


## A glint star, on the normal layer (it pops) or the calm one (it doesn't).
func _glint(calm: bool) -> MeshInstance3D:
	if _glint_shader == null:
		_glint_shader = load("res://game/modes/police/spike_glint.gdshader")
	var g := MeshInstance3D.new()
	g.name = "GlintCalm" if calm else "Glint"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	g.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = _glint_shader
	m.set_shader_parameter(&"strength", GLINT_CALM if calm else 1.0)
	m.set_shader_parameter(&"pop", GLINT_CALM_SIZE if calm else 0.0)
	g.material_override = m
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drawn far bigger than the quad (the shader sizes it to the view): never culled for that.
	g.custom_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	add_child(g)
	Flash.put_on(g, calm)
	return g


## The glint's brightness (0..1) at `t`: a pop of GLINT_POP_S every GLINT_EVERY_S, or (calm) the
## still star's.
static func glint_pattern(t: float, calm: bool) -> float:
	if calm:
		return GLINT_CALM
	var k := fmod(t, GLINT_EVERY_S) / GLINT_POP_S
	return sin(k * PI) if k < 1.0 else 0.0


func _process(_delta: float) -> void:
	var cycle := int(age / GLINT_EVERY_S)
	if cycle != _glint_at:
		_glint_at = cycle
		_hop()
	var k := fmod(age, GLINT_EVERY_S) / GLINT_POP_S
	var m := glint.material_override as ShaderMaterial
	m.set_shader_parameter(&"pop", glint_pattern(age, false))
	m.set_shader_parameter(&"twist", GLINT_TWIST * minf(k, 1.0))


## The glint onto another tooth.
func _hop() -> void:
	if not tips.is_empty():
		glint.position = tips[_rng.randi_range(0, tips.size() - 1)] + Vector3.UP * 0.05


func _physics_process(delta: float) -> void:
	age += delta
	for r: Variant in watch:
		if r is Racer and is_instance_valid(r):
			_check(r)


## Done with: long enough down, its player well past it (or gone).
func done() -> bool:
	if for_racer == null:
		return age > LIFE_S
	return age > LIFE_S or not is_instance_valid(for_racer) or road.past(for_racer, at_m) > PAST_M


## Which of `v`'s wheels are on it now (bit i for physics wheel i).
func on_it(v: Vehicle) -> int:
	if v.fitted == null or v.global_position.distance_to(global_position) > NEAR_M:
		return 0
	var mask := 0
	for i in v.fitted.physics_wheels.size():
		var w: Dictionary = v.fitted.physics_wheels[i]
		var p := v.global_transform * (w.center as Vector3)
		var proj := road.project(p)
		if absf(road.delta_m(float(proj.distance), at_m)) < LENGTH_M / 2.0 + 0.15 \
				and float(proj.lateral) >= minf(lat_from, lat_to) and float(proj.lateral) <= maxf(lat_from, lat_to):
			mask |= 1 << i
	return mask


func _check(r: Racer) -> void:
	var v := r.vehicle
	if v == null or not is_instance_valid(v) or v.remote:
		return
	var mask := on_it(v)
	if mask & ~v.flats:
		v.flatten(mask, FLAT_S)
		r.notify("Flat tyre" if mask & (mask - 1) == 0 else "Flat tyres", 2.5)


## The world moved (FloatingOrigin): so does the strip (its road-space spot doesn't).
func origin_shifted(delta: Vector3) -> void:
	position += delta
