class_name PoliceHeli
extends Node3D
## A police helicopter (D251): purely for show, over a player at heat 5 (PoliceHeliControl makes
## and drops them). Made in code (original): a dark fuselage with a white band, a tail boom and
## fin, skids, a two-bladed rotor with a faint blur disc and a tail rotor, red and green
## navigation lights and a white strobe (steady on Flash.LAYER_CALM, for Reduce flashing).
##
## It flies in from ahead (ARRIVE), then holds above and ahead of its target to one side, where a
## chase camera sees it, its searchlight turned back on the car (TRACK). While the player is getting away (their evade clock running)
## it lags and sweeps the road round where they were last seen (SEARCH). Evaded or busted, it
## climbs away and is gone in LEAVE_S (LEAVE). The searchlight (a light with no shadows, and a
## beam that fades along its length and near any camera) is on only while lights are
## (EnvDirector.lights_on: dusk, night, fog); `real_light` off keeps just the beam. Its rotor is
## heard (Effects), and shown on the HUD's sound arrows.

enum State { ARRIVE, TRACK, SEARCH, LEAVE }

## Where it holds over its target: this high, this far ahead, this far to one side.
const HEIGHT_M := 40.0
const AHEAD_M := 55.0
const SIDE_M := 16.0
## Arriving: from this far ahead of the target, this much higher; tracking once this near its
## spot. It flies at most this fast, closing on its spot at this rate (1/s; a lag searching).
const ARRIVE_FROM_M := 600.0
const ARRIVE_HIGH_M := 25.0
const ARRIVE_NEAR_M := 40.0
const MAX_MPS := 95.0
const TRACK_GAIN := 0.9
const SEARCH_GAIN := 0.25
const ACCEL_RATE := 2.5
## Leaving: climbing at this rate, flying on at this speed, gone after this long.
const LEAVE_CLIMB_MPS := 9.0
const LEAVE_MPS := 55.0
const LEAVE_S := 8.0
## The searchlight: its cone (degrees), reach and brightness; the beam stays on the car to within
## a wobble this big; searching, it sweeps this far round the last spot seen.
const BEAM_DEG := 6.0
const BEAM_RANGE_M := 140.0
const BEAM_ENERGY := 8.0
const WOBBLE_M := 0.7
const SWEEP_M := 22.0
## Rotor: turns a second (main, tail); the sound's blade slap a second.
const ROTOR_HZ := 5.5
const TAIL_ROTOR_HZ := 24.0
const SLAP_HZ := 22.0
const SOUND_S := 0.5
## The strobe: a double flash every STROBE_EVERY_S (two a second: under WCAG's three); calm, a
## steady glow at STROBE_CALM.
const STROBE_EVERY_S := 1.0
const STROBE_ON_S := 0.06
const STROBE_GAP_S := 0.18
const STROBE_CALM := 0.5

const BODY := Color(0.063, 0.078, 0.094) # the Interceptor's paint, #101418
const BAND := Color(0.92, 0.92, 0.9)
const TRIM := Color(0.05, 0.05, 0.055)
const GLASS := Color(0.12, 0.16, 0.24)
const BEAM_COLOR := Color(1.0, 0.96, 0.86)

var session: TrackSession
var target: Racer
var state := State.ARRIVE
## Set by PoliceHeliControl: the player's getting away (it searches); this one casts real light.
var searching := false
var real_light := true

var rotor: Node3D
var tail_rotor: Node3D
var spot: SpotLight3D
var beam: MeshInstance3D
var strobe: MeshInstance3D
var calm_strobe: MeshInstance3D
var sound: AudioStreamPlayer3D
var _vel := Vector3.ZERO
var _aim := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _side := 1.0
var _t := 0.0
var _leave_t := 0.0
var _strobe_mat: StandardMaterial3D
static var _rotor_sound: AudioStreamWAV
static var _beam_shader: Shader


func _ready() -> void:
	name = "PoliceHeli"
	add_to_group(&"origin_shift")
	_build()
	var tv := _target_vehicle()
	if tv:
		var fwd := _flat_forward(tv)
		position = tv.global_position + fwd * ARRIVE_FROM_M + Vector3.UP * (HEIGHT_M + ARRIVE_HIGH_M)
		_last_seen = tv.global_position
		_aim = tv.global_position
		_vel = -fwd * 40.0
		basis = Basis.looking_at(-fwd, Vector3.UP, true) # this model's front is +Z
	_side = 1.0 if randf() < 0.5 else -1.0
	sound.play()


## Off it goes: climbing away, gone in LEAVE_S.
func leave() -> void:
	if state == State.LEAVE:
		return
	state = State.LEAVE
	_leave_t = 0.0


## Whether the searchlight shines now (lights on in this weather and time, D251).
func lit() -> bool:
	return session != null and session.env != null and session.env.lights_on


func _target_vehicle() -> Vehicle:
	if target == null or not is_instance_valid(target) or target.vehicle == null or not is_instance_valid(target.vehicle):
		return null
	return target.vehicle


static func _flat_forward(v: Vehicle) -> Vector3:
	var vel := v.remote_velocity if v.remote else v.linear_velocity
	var f := Vector3(vel.x, 0.0, vel.z) if vel.length() > 3.0 else Vector3(v.global_basis.z.x, 0.0, v.global_basis.z.z)
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _process(delta: float) -> void:
	_t += delta
	var tv := _target_vehicle()
	if tv == null and state != State.LEAVE:
		leave()
	match state:
		State.ARRIVE, State.TRACK, State.SEARCH:
			if searching and state == State.TRACK:
				state = State.SEARCH
			elif not searching and state == State.SEARCH:
				state = State.TRACK
			_fly(tv, delta)
		State.LEAVE:
			_leave_t += delta
			var on := Vector3(global_basis.z.x, 0.0, global_basis.z.z)
			on = on.normalized() if on.length() > 0.01 else Vector3.FORWARD
			_vel = _vel.lerp(on * LEAVE_MPS + Vector3.UP * LEAVE_CLIMB_MPS, 1.0 - exp(-delta * 0.8))
			position += _vel * delta
			if _leave_t > LEAVE_S:
				queue_free()
				return
	_face(delta)
	_spin(delta)
	_light()
	_strobe()


## Toward its spot over the target (ARRIVE, TRACK) or where they were last seen (SEARCH), the
## beam on the car or sweeping round that spot.
func _fly(tv: Vehicle, delta: float) -> void:
	var tracking := state != State.SEARCH
	var tvel := Vector3.ZERO
	if tracking:
		_last_seen = tv.global_position
		tvel = tv.remote_velocity if tv.remote else tv.linear_velocity
	var fwd := _flat_forward(tv)
	var side := Vector3(fwd.z, 0.0, -fwd.x) * _side
	var spot_at := (tv.global_position if tracking else _last_seen) + fwd * AHEAD_M + side * SIDE_M + Vector3.UP * HEIGHT_M
	var gain := SEARCH_GAIN if not tracking else TRACK_GAIN
	var want := (tvel if tracking else Vector3.ZERO) + (spot_at - position) * gain
	if want.length() > MAX_MPS:
		want = want.normalized() * MAX_MPS
	_vel = _vel.lerp(want, 1.0 - exp(-delta * ACCEL_RATE))
	position += _vel * delta
	if state == State.ARRIVE and position.distance_to(spot_at) < ARRIVE_NEAR_M:
		state = State.SEARCH if searching else State.TRACK
	var aim := _last_seen
	if tracking:
		aim += Vector3(sin(_t * 1.3) * WOBBLE_M, 0.0, cos(_t * 0.9) * WOBBLE_M)
	else:
		aim += Vector3(sin(_t * 0.55) * SWEEP_M, 0.0, sin(_t * 0.31 + 1.0) * SWEEP_M * 0.6)
	_aim = _aim.lerp(aim, 1.0 - exp(-delta * (6.0 if tracking else 1.5)))


## Nose along its way, dipped as it goes and banked into its turns.
func _face(delta: float) -> void:
	var flat := Vector3(_vel.x, 0.0, _vel.z)
	var heading := flat.normalized() if flat.length() > 4.0 else Vector3(_aim.x - position.x, 0.0, _aim.z - position.z).normalized()
	if heading.length() < 0.01:
		return
	var want := Basis.looking_at(heading, Vector3.UP, true) # this model's front is +Z
	want = want.rotated(want.x, clampf(flat.length() / MAX_MPS, 0.0, 1.0) * 0.28) # nose down as it goes
	basis = basis.orthonormalized().slerp(want.orthonormalized(), 1.0 - exp(-delta * 2.0))


func _spin(delta: float) -> void:
	rotor.rotate_y(TAU * ROTOR_HZ * delta)
	tail_rotor.rotate_x(TAU * TAIL_ROTOR_HZ * delta)


## The searchlight and its beam: on while lights are, the beam from the nose to where it aims.
func _light() -> void:
	var on := lit() and state != State.LEAVE
	beam.visible = on
	spot.visible = on and real_light
	if not on:
		return
	var from := spot.global_position
	var to_aim := _aim - from
	var length := minf(to_aim.length(), BEAM_RANGE_M)
	if length < 1.0:
		return
	var dir := to_aim.normalized()
	spot.look_at(from + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	spot.spot_range = minf(to_aim.length() + 25.0, BEAM_RANGE_M)
	var r := tan(deg_to_rad(BEAM_DEG)) * length
	beam.global_transform = Transform3D(Basis(Quaternion(Vector3.DOWN, dir)) * Basis.from_scale(Vector3(r, length, r)), from)


func _strobe() -> void:
	var b := strobe_pattern(_t, false)
	_strobe_mat.albedo_color = Color(b, b, b)


## The strobe's brightness (0..1) at `t`: a double flash every STROBE_EVERY_S, or (calm) steady.
static func strobe_pattern(t: float, calm: bool) -> float:
	if calm:
		return STROBE_CALM
	var c := fmod(t, STROBE_EVERY_S)
	return 1.0 if c < STROBE_ON_S or (c >= STROBE_GAP_S and c < STROBE_GAP_S + STROBE_ON_S) else 0.0


## The world moved (FloatingOrigin): so does it, and the spots it keeps.
func origin_shifted(delta: Vector3) -> void:
	position += delta
	_aim += delta
	_last_seen += delta


func _build() -> void:
	var body := MeshBatch.new()
	body.box(Vector3(0, 0, 0.3), Basis(), Vector3(1.8, 1.7, 3.2)) # cabin
	body.box(Vector3(0, 0.1, -1.6), Basis(), Vector3(1.4, 1.3, 1.0)) # behind the cabin
	body.box(Vector3(0, 1.05, -0.4), Basis(), Vector3(1.1, 0.5, 2.0)) # engine
	body.box(Vector3(0, 0.35, -4.4), Basis(), Vector3(0.36, 0.36, 4.8)) # tail boom
	body.box(Vector3(0, 1.0, -6.6), Basis(), Vector3(0.12, 1.4, 0.9)) # fin
	body.box(Vector3(0, 0.4, -5.6), Basis(), Vector3(1.8, 0.08, 0.5)) # tailplane
	_part("Body", body, _mat(BODY, 0.45, 0.35))
	var band := MeshBatch.new()
	band.box(Vector3(0, -0.25, 0.3), Basis(), Vector3(1.84, 0.34, 3.24))
	band.box(Vector3(0, 0.35, -2.4), Basis(), Vector3(0.4, 0.12, 1.4))
	_part("Band", band, _mat(BAND, 0.4, 0.0))
	var glass := MeshBatch.new()
	glass.box(Vector3(0, -0.1, 2.15), Basis(), Vector3(1.5, 1.2, 1.1))
	_part("Glass", glass, _mat(GLASS, 0.1, 0.6))
	var trim := MeshBatch.new()
	for x: float in [-0.95, 0.95]:
		trim.box(Vector3(x, -1.25, 0.2), Basis(), Vector3(0.1, 0.1, 3.6)) # skids
		for z: float in [1.0, -0.6]:
			trim.box(Vector3(x * 0.8, -1.0, z), Basis(), Vector3(0.08, 0.55, 0.08))
	trim.box(Vector3(0, 1.45, 0), Basis(), Vector3(0.2, 0.4, 0.2)) # mast
	_part("Trim", trim, _mat(TRIM, 0.6, 0.2))
	# The rotors.
	rotor = Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0, 1.7, 0)
	add_child(rotor)
	var blades := MeshBatch.new()
	blades.box(Vector3.ZERO, Basis(), Vector3(10.0, 0.05, 0.32))
	blades.box(Vector3.ZERO, Basis(Vector3.UP, PI / 2.0), Vector3(10.0, 0.05, 0.32))
	_part("Blades", blades, _mat(TRIM, 0.6, 0.2), rotor)
	var disc := MeshInstance3D.new()
	disc.name = "Blur"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.0
	cyl.bottom_radius = 5.0
	cyl.height = 0.02
	cyl.radial_segments = 32
	cyl.rings = 1
	disc.mesh = cyl
	var blur := StandardMaterial3D.new()
	blur.albedo_color = Color(0.1, 0.1, 0.12, 0.14)
	blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blur.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = blur
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	disc.position = rotor.position
	tail_rotor = Node3D.new()
	tail_rotor.name = "TailRotor"
	tail_rotor.position = Vector3(0.12, 1.1, -6.6)
	add_child(tail_rotor)
	var tail_blades := MeshBatch.new()
	tail_blades.box(Vector3.ZERO, Basis(), Vector3(0.04, 1.7, 0.16))
	tail_blades.box(Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.04, 1.7, 0.16))
	_part("TailBlades", tail_blades, _mat(TRIM, 0.6, 0.2), tail_rotor)
	# Navigation lights: red on its left (+X), green on its right; the strobe on the fin.
	_lamp("NavRed", Vector3(0.92, 0.4, -5.6), Color(1.0, 0.1, 0.08))
	_lamp("NavGreen", Vector3(-0.92, 0.4, -5.6), Color(0.1, 1.0, 0.25))
	strobe = _lamp("Strobe", Vector3(0, 1.75, -6.6), Color.WHITE)
	_strobe_mat = strobe.material_override as StandardMaterial3D
	Flash.put_on(strobe, false)
	calm_strobe = _lamp("StrobeCalm", Vector3(0, 1.75, -6.6), Color.WHITE * STROBE_CALM)
	Flash.put_on(calm_strobe, true)
	# The searchlight under the nose, and its beam.
	spot = SpotLight3D.new()
	spot.name = "Searchlight"
	spot.position = Vector3(0, -0.75, 2.3)
	spot.spot_angle = BEAM_DEG
	spot.spot_range = BEAM_RANGE_M
	spot.light_energy = BEAM_ENERGY
	spot.light_color = BEAM_COLOR
	spot.shadow_enabled = false
	spot.spot_attenuation = 0.6
	add_child(spot)
	beam = MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = _shifted(cone)
	var bm := ShaderMaterial.new()
	if _beam_shader == null:
		_beam_shader = load("res://game/modes/police/heli_beam.gdshader")
	bm.shader = _beam_shader
	bm.set_shader_parameter(&"color", BEAM_COLOR)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.top_level = true
	add_child(beam)
	# The rotor's sound.
	sound = AudioStreamPlayer3D.new()
	sound.name = "Rotor"
	sound.stream = rotor_stream()
	sound.bus = &"Effects"
	sound.unit_size = 30.0
	sound.max_distance = 700.0
	sound.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
	add_child(sound)


## A cone from its tip at the origin down -Y one unit (CylinderMesh's is centred).
static func _shifted(cone: CylinderMesh) -> ArrayMesh:
	var arrays := cone.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y -= 0.5
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _part(part_name: String, b: MeshBatch, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = b.mesh()
	mi.material_override = m
	(parent if parent else self).add_child(mi)
	return mi


func _lamp(lamp_name: String, at: Vector3, color: Color) -> MeshInstance3D:
	var b := MeshBatch.new()
	b.box(Vector3.ZERO, Basis(), Vector3(0.16, 0.16, 0.16))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	var mi := _part(lamp_name, b, m)
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## The rotor's loop, made once: blade slaps (SLAP_HZ) through filtered noise over a low hum,
## SOUND_S long and a whole number of slaps and hum cycles, so it loops cleanly.
static func rotor_stream() -> AudioStreamWAV:
	if _rotor_sound:
		return _rotor_sound
	var n := int(EngineSound.RATE * SOUND_S)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4E11
	var low := 0.0
	var band := 0.0
	for i in range(-2000, n): # a run-in, so the filters are going at the loop's start
		var t := float(i) / EngineSound.RATE
		var ph := fposmod(t * SLAP_HZ, 1.0)
		var slap := exp(-ph * 12.0)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.16)
		band = lerpf(band, low, 0.3)
		var hum := sin(TAU * 44.0 * t) * 0.35 + sin(TAU * 88.0 * t) * 0.12
		var v := clampf(band * 2.4 * (0.2 + slap) + hum * (0.55 + 0.45 * slap), -1.0, 1.0)
		if i >= 0:
			data.encode_s16(i * 2, int(v * 0.6 * 32767.0))
	_rotor_sound = EngineSound._wav(data, true)
	return _rotor_sound
