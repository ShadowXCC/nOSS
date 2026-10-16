class_name KartBoxes
extends Node3D
## Item boxes (D139): the track's rows (KartLayout.rows), each box gone for RESPAWN_S once a
## kart drives through it. A turning crate with an original glyph; its colours shift slowly
## (never a flash).

const RESPAWN_S := 3.0
## A kart's centre this near a box's lower half takes it.
const PICK_RADIUS := 1.6
const SIZE := 0.8
const SPIN := 1.2 # rad/s

## A box went (`on` false) or came back: the online authority passes it on (KartNet).
signal changed(i: int, on: bool)

var points := PackedVector3Array()
var alive := PackedByteArray()
## Each box's place on the road (distance along it, and across), once (the AI heads for them).
var along := PackedFloat32Array()
var across := PackedFloat32Array()
var visual := true
var _timers := PackedFloat32Array()
var _nodes: Array[Node3D] = []
static var _mesh: Mesh
static var _material: ShaderMaterial


func setup(at: PackedVector3Array, with_visuals: bool) -> void:
	points = at
	visual = with_visuals
	alive.resize(at.size())
	alive.fill(1)
	_timers.resize(at.size())
	_timers.fill(0.0)
	if visual:
		for p in at:
			var mi := MeshInstance3D.new()
			mi.mesh = _crate()
			mi.material_override = _crate_material()
			mi.position = p
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_nodes.append(mi)


## Works out each box's place on `track`'s road (not in an arena).
func place_on(track: TrackData) -> void:
	along.resize(points.size())
	across.resize(points.size())
	for i in points.size():
		var proj := track.project(points[i])
		along[i] = float(proj.distance)
		across[i] = float(proj.lateral)


func count() -> int:
	return points.size()


## The nearest box still there that a kart at `pos` (its centre) takes, or -1.
func near(pos: Vector3, radius := PICK_RADIUS) -> int:
	var best := -1
	var best_d := radius
	for i in points.size():
		if not alive[i]:
			continue
		var d := pos.distance_to(points[i] - Vector3.UP * SIZE * 0.6)
		if d < best_d:
			best_d = d
			best = i
	return best


func take(i: int) -> void:
	set_alive(i, false)
	_timers[i] = RESPAWN_S


func set_alive(i: int, on: bool) -> void:
	if i < 0 or i >= alive.size():
		return
	var was := alive[i] != 0
	alive[i] = 1 if on else 0
	if was != on:
		changed.emit(i, on)
	if visual and i < _nodes.size():
		_nodes[i].visible = on
		if on:
			_nodes[i].scale = Vector3.ONE * 0.2


func _physics_process(delta: float) -> void:
	for i in _timers.size():
		if not alive[i]:
			_timers[i] -= delta
			if _timers[i] <= 0.0:
				set_alive(i, true)


func _process(delta: float) -> void:
	if not visual:
		return
	for n in _nodes:
		if n.visible:
			n.rotate_y(SPIN * delta)
			n.scale = n.scale.move_toward(Vector3.ONE, delta * 3.0)


static func _crate() -> Mesh:
	if _mesh == null:
		var b := BoxMesh.new()
		b.size = Vector3.ONE * SIZE
		_mesh = b
	return _mesh


static func _crate_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://game/modes/kart/item_box.gdshader")
	return _material
