class_name SumoTeamLook
extends Node
## Team Battle's look (D234): every car in its team's colour, with a ring of it on the ground round
## the car, so a team reads from the chase camera and from over the arena alike. Wherever there
## are words (the nameplates, the HUD, the results) the team's name goes with its colour; out here
## the colour is a second cue, not the only one. Only the primary paint changes: the trim keeps
## the car's own. Not made on a game with no screen.

const RING_NAME := &"TeamRing"
## The ring: its radius against the car's footprint, how wide its band is, and how far it sits
## off the ground.
const RING_PAD := 0.62
const RING_BAND_M := 0.4
const RING_LIFT_M := 0.06

var session: TrackSession
## racer -> [vehicle, visual, team] as it was last dressed: a car that loaded, swapped or changed
## team since is dressed again.
var _dressed := {}


func _process(_delta: float) -> void:
	var sumo := session.sumo
	for r in session.racers:
		var v := r.vehicle
		if v == null or not is_instance_valid(v):
			continue
		var t := sumo.team(r)
		var now := [v, v.visual, t]
		if _dressed.get(r) != now:
			_dressed[r] = now
			_dress(v, t)
		var ring := v.get_node_or_null(NodePath(RING_NAME)) as MeshInstance3D
		if ring:
			ring.visible = not r.out


func _dress(v: Vehicle, t: int) -> void:
	var ring := v.get_node_or_null(NodePath(RING_NAME)) as MeshInstance3D
	if t < 0:
		# Not drawn yet (a client waiting for the server's draw): the car keeps what it has.
		if ring:
			ring.queue_free()
		return
	var colour := SumoTeams.color_of(t)
	if v.visual:
		v.visual.set_paint("primary", colour)
	if ring == null:
		ring = _ring(v)
		v.add_child(ring)
	var m := ring.material_override as StandardMaterial3D
	m.albedo_color = colour
	m.emission = colour


## A flat ring on the ground round the car, sized from its footprint.
func _ring(v: Vehicle) -> MeshInstance3D:
	var radius := 2.4
	var at := Vector3(0.0, RING_LIFT_M, 0.0)
	if v.fitted:
		var box: AABB = v.fitted.envelope
		radius = maxf(box.size.x, box.size.z) * RING_PAD
		at = Vector3(box.get_center().x, box.position.y + RING_LIFT_M, box.get_center().z)
	var torus := TorusMesh.new()
	torus.outer_radius = radius
	torus.inner_radius = radius - RING_BAND_M
	torus.rings = 48
	torus.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission_energy_multiplier = 0.6
	var mi := MeshInstance3D.new()
	mi.name = RING_NAME
	mi.mesh = torus
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3(1.0, 0.15, 1.0) # flat on the ground, not a tube round the car
	return mi
