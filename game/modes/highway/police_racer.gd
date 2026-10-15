class_name PoliceRacer
extends Racer
## A police unit (D115): an Interceptor driven by PoliceAI. PoliceControl keeps a pool of them,
## parks some at the speed traps, sends others after players with heat (out of their sight) and
## puts them back in the pool (waiting: hidden, off the road) when they're done. Online they're
## the server's cars (ids from NetProtocol.FIRST_POLICE_ID), shown as remote cars elsewhere.

const CAR := "res://content/traffic/police"
const COLOR := Color(0.08, 0.1, 0.16)

var ai: PoliceAI
## The highway mode's police class (data/modes/highway.mode.json "police_class").
var police_class := "official.highway.interceptor"


func _init() -> void:
	name = "Police"


## `index`: 0 for the first unit.
func configure(index: int) -> void:
	number = 50 + index
	display_name = "Police"
	name = "Police%d" % (index + 1)
	color = COLOR
	is_human = false


func setup() -> void:
	super()
	var p := PlatformLoader.load_official(police_class)
	if p.ok():
		platform = p
	limits = false
	wrong_way_respawn = false


func _make_driver() -> Node:
	ai = PoliceAI.new()
	ai.name = "PoliceAI"
	ai.racer = self
	return ai


## Out of play: hidden, still, off the road.
func stand_down() -> void:
	waiting = true
	if ai:
		ai.mode = PoliceAI.Mode.PARKED
		ai.target = null
	if vehicle:
		vehicle.siren = false
		vehicle.light_bar = false
		vehicle.visible = false
		vehicle.set_ghost(true, false)
		vehicle.reset_to(Transform3D(Basis(), Vector3(0, -500.0 - number * 10.0, 0)))
		vehicle.freeze = true


## Into play at `xform`, going `velocity`.
func deploy(xform: Transform3D, velocity: Vector3) -> void:
	waiting = false
	if vehicle:
		vehicle.freeze = false
		vehicle.visible = true
		vehicle.set_ghost(false)
		vehicle.reset_to(xform, velocity)
	if ai:
		ai.lane = -1
