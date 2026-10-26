class_name GhostCar
extends Node3D
## Shows a Ghost on the track: the recorded car's model, see-through, with no collisions and no
## physics. It's placed each frame at the lap time it's given, so it runs in step with the
## player's own lap clock. It's drawn on the visual `layers` given (a time trial gives each
## player's ghost its own, which only their camera draws).

const SEE_THROUGH := 0.6

var ghost: Ghost
var visual: CarVisual
var fitted: Fitting.Result
var max_steer := 0.5
var _spin := 0.0
var _front: Array[int] = []


static func create(g: Ghost, platform: Dictionary, pkg: VehiclePackage, layers := 1) -> GhostCar:
	var car := GhostCar.new()
	car.name = "Ghost"
	car.ghost = g
	car.fitted = Fitting.fit(platform, pkg.fit)
	car.visual = CarVisual.create(pkg, car.fitted)
	car.add_child(car.visual)
	car.max_steer = deg_to_rad(float(platform.steering.max_road_angle_deg))
	for vi: VisualInstance3D in car.visual.find_children("*", "VisualInstance3D", true, false):
		vi.layers = layers
		if vi is GeometryInstance3D:
			(vi as GeometryInstance3D).transparency = SEE_THROUGH
			(vi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Front wheels steer: those on the most forward axle.
	var front_z := -INF
	for w: Dictionary in car.fitted.wheels:
		front_z = maxf(front_z, (w.center as Vector3).z)
	for i in car.fitted.wheels.size():
		if absf((car.fitted.wheels[i].center as Vector3).z - front_z) < 0.3:
			car._front.append(i)
	return car


## Puts the ghost where it was at lap time `t`; hidden before the lap or past its end.
func show_at(t: float, delta: float) -> void:
	if ghost == null or t < 0.0 or t > ghost.duration():
		visible = false
		return
	var s := ghost.sample_at(t)
	visible = true
	global_transform = s.xform
	var radius := 0.33
	_spin = fposmod(_spin + float(s.speed) / radius * delta, TAU)
	var road := -float(s.steer) * max_steer
	for i in visual.wheel_count():
		visual.set_wheel(i, road if i in _front else 0.0, _spin, 0.0)
