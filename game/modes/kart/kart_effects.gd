class_name KartEffects
extends Node3D
## What karts show (D146): drift sparks at the rear wheels (bigger and more of them each tier,
## never colour alone), a boost flame, a shield bubble, stars over a spun kart, a magnet's tether,
## and an EMP's ring. What flickers is drawn twice (Flash): flickering on the normal layer,
## steady on the calm one, so Reduce flashing keeps every effect at three flashes a second or
## fewer.

const TIER_COLORS := [Color(0.3, 0.6, 1.0), Color(1.0, 0.58, 0.12), Color(0.8, 0.35, 1.0)]
const TIER_SIZE := [0.10, 0.16, 0.24]
const TIER_SPARKS := [1, 2, 3]
const EMP_S := 0.4
const EMP_CALM_S := 0.6

var session: TrackSession
var _rigs := {} # Vehicle -> {root, sparks: [[normal, calm]...], flame: [normal, calm], shield: [normal, calm], stars, tether}
var _pulses: Array[Dictionary] = []
var _time := 0.0
static var _materials := {}


## Brightness (0..1) of `effect` at time `t`; `calm`: as drawn for Reduce flashing.
static func pattern(effect: String, t: float, calm: bool) -> float:
	match effect:
		"sparks":
			return 1.0 if calm else (1.0 if fmod(t * 12.0, 1.0) < 0.5 else 0.3)
		"flame":
			return 0.85 if calm else (1.0 if fmod(t * 15.0, 1.0) < 0.5 else 0.55)
		"shield":
			return 0.8 if calm else 0.6 + 0.4 * (1.0 if fmod(t * 4.0, 1.0) < 0.5 else 0.0)
		"emp":
			var length := EMP_CALM_S if calm else EMP_S
			var peak := 0.45 if calm else 1.0
			return peak * clampf(1.0 - fmod(t, 2.0) / length, 0.0, 1.0)
	return 1.0


func _ready() -> void:
	if session.kart:
		session.kart.items.used.connect(_on_used)


func _process(delta: float) -> void:
	_time += delta
	for r: Racer in session.racers:
		var v := r.vehicle
		if v == null or not is_instance_valid(v) or v.visual == null:
			continue
		if not _rigs.has(v):
			_rigs[v] = _rig(v)
		_show(r, v, _rigs[v])
	for p in _pulses.duplicate():
		p.age += delta
		var done := true
		for k in 2:
			var calm := k == 1
			var n: MeshInstance3D = p.nodes[k]
			var length := EMP_CALM_S if calm else EMP_S
			var u := clampf(p.age / length, 0.0, 1.0)
			n.scale = Vector3.ONE * lerpf(1.0, KartItems.EMP_RADIUS_M, u)
			n.transparency = 1.0 - pattern("emp", p.age, calm)
			done = done and u >= 1.0
		if done:
			for n: Node in p.nodes:
				n.queue_free()
			_pulses.erase(p)


func _show(r: Racer, v: Vehicle, rig: Dictionary) -> void:
	var flags := v.kart_flags()
	var drifting := flags & (VehicleSim.KART_FLAG_DRIFT_LEFT | VehicleSim.KART_FLAG_DRIFT_RIGHT) != 0
	var tier := (flags >> VehicleSim.KART_FLAG_TIER_SHIFT) & 3
	for pair: Array in rig.sparks:
		for k in 2:
			var spark: MeshInstance3D = pair[k]
			spark.visible = drifting and tier > 0
			if spark.visible:
				var t: int = tier - 1
				var s: float = TIER_SIZE[t] * pattern("sparks", _time + spark.get_index() * 0.03, k == 1)
				spark.scale = Vector3.ONE * s
				spark.material_override = _glow("tier%d" % t, TIER_COLORS[t])
				# One spark per tier, staggered behind the wheel.
				spark.visible = spark.get_meta(&"n", 0) < TIER_SPARKS[t]
	var boosting := flags & VehicleSim.KART_FLAG_BOOST != 0
	for k in 2:
		var flame: MeshInstance3D = rig.flame[k]
		flame.visible = boosting
		if boosting:
			flame.scale = Vector3(1, pattern("flame", _time, k == 1), 1) # along its length
		var shield: MeshInstance3D = rig.shield[k]
		shield.visible = flags & CarState.KART_SHIELD != 0
		if shield.visible:
			shield.transparency = 1.0 - 0.45 * pattern("shield", _time, k == 1)
	var stars: Node3D = rig.stars
	stars.visible = flags & VehicleSim.KART_FLAG_SPUN != 0
	if stars.visible:
		stars.rotation.y = _time * 6.0
	var tether: MeshInstance3D = rig.tether
	var target: Racer = session.kart.items.slot(r).magnet_target if flags & CarState.KART_MAGNET else null
	tether.visible = target != null and is_instance_valid(target) and target.vehicle != null
	if tether.visible:
		var from := v.global_position + Vector3.UP * 0.6
		var to := target.vehicle.global_position + Vector3.UP * 0.6
		var mid := (from + to) / 2.0
		tether.global_transform = Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP) * Basis.from_scale(Vector3(0.05, 0.05, from.distance_to(to))), mid)


func _rig(v: Vehicle) -> Dictionary:
	var root := Node3D.new()
	root.name = "KartEffects"
	v.add_child(root)
	var rig := { "root": root, "sparks": [], "flame": [], "shield": [] }
	var ground := v.fitted.ground_y if v.fitted else 0.0
	for w: Dictionary in (v.fitted.physics_wheels if v.fitted else []):
		if int(w.axle) != 2:
			continue
		var c: Vector3 = w.center
		for n in 3:
			var pair := []
			for k in 2:
				var spark := _mesh(_box(), _glow("tier0", TIER_COLORS[0]))
				spark.position = Vector3(c.x * 1.1, ground + 0.08, c.z - 0.25 - n * 0.22)
				spark.set_meta(&"n", n)
				Flash.put_on(spark, k == 1)
				root.add_child(spark)
				pair.append(spark)
			rig.sparks.append(pair)
	var exhaust := Vector3(0, ground + 0.35, (v.fitted.envelope.position.z if v.fitted else -1.0))
	if v.package and not (v.package.fit.get("exhaust_points", []) as Array).is_empty():
		var e: Array = v.package.fit.exhaust_points[0]
		exhaust = Vector3(e[0], e[1], e[2])
	var size := v.fitted.envelope.size if v.fitted else Vector3(1.5, 1.0, 2.0)
	for k in 2:
		var flame := _mesh(_cone(), _glow("flame", Color(1.0, 0.55, 0.15)))
		flame.position = exhaust + Vector3(0, 0, -0.35)
		flame.rotation = Vector3(PI / 2.0, 0, 0) # its tip backwards
		Flash.put_on(flame, k == 1)
		root.add_child(flame)
		rig.flame.append(flame)
		var shield := _mesh(_sphere(), _glass("shield", Color(0.4, 0.85, 1.0)))
		shield.position = Vector3(0, ground + size.y * 0.45, 0)
		shield.scale = Vector3(size.x, size.y * 1.1, size.z) * 0.62
		Flash.put_on(shield, k == 1)
		root.add_child(shield)
		rig.shield.append(shield)
	var stars := Node3D.new()
	stars.position = Vector3(0, ground + size.y + 0.4, 0)
	for n in 3:
		var star := _mesh(_box(), _glow("star", Color(1.0, 0.9, 0.3)))
		var a := TAU * n / 3.0
		star.position = Vector3(cos(a), 0, sin(a)) * 0.45
		star.scale = Vector3.ONE * 0.14
		star.rotation = Vector3(0.6, a, 0.6)
		stars.add_child(star)
	root.add_child(stars)
	rig.stars = stars
	var tether := _mesh(_box(), _glow("tether", Color(0.95, 0.3, 0.6)))
	tether.top_level = true
	root.add_child(tether)
	rig.tether = tether
	return rig


func _on_used(r: Racer, item: String) -> void:
	if item != "emp" or r.vehicle == null:
		return
	var nodes := []
	for k in 2:
		var ring := _mesh(_ring(), _glass("emp", Color(0.5, 0.8, 1.0)))
		ring.top_level = true
		add_child(ring)
		ring.global_position = r.com()
		Flash.put_on(ring, k == 1)
		nodes.append(ring)
	_pulses.append({ "nodes": nodes, "age": 0.0 })


# --- meshes and materials ------------------------------------------------------------------

func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _box() -> Mesh:
	if not _materials.has("box_mesh"):
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		_materials.box_mesh = b
	return _materials.box_mesh


static func _cone() -> Mesh:
	if not _materials.has("cone_mesh"):
		var c := CylinderMesh.new()
		c.top_radius = 0.14
		c.bottom_radius = 0.0
		c.height = 0.7
		_materials.cone_mesh = c
	return _materials.cone_mesh


static func _sphere() -> Mesh:
	if not _materials.has("sphere_mesh"):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		_materials.sphere_mesh = s
	return _materials.sphere_mesh


static func _ring() -> Mesh:
	if not _materials.has("ring_mesh"):
		var t := TorusMesh.new()
		t.inner_radius = 0.92
		t.outer_radius = 1.0
		_materials.ring_mesh = t
	return _materials.ring_mesh


static func _glow(key: String, color: Color) -> Material:
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		_materials[key] = m
	return _materials[key]


static func _glass(key: String, color: Color) -> Material:
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(color, 0.35)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]
