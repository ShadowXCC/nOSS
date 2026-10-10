class_name LineFollower
extends Node
## Drives a vehicle along a track's centreline: pure-pursuit steering and a speed target
## from the curvature ahead. Used for dev autodrive and tests; groundwork for racing AI
## (AI-01, M4). It drives through the same controls as a player (AI-05).

@export var vehicle: Vehicle
var track: TrackData
## Fraction of the grip-limited corner speed to aim for.
var pace := 0.8
## Line to follow, metres left (+) or right (-) of the centreline.
var lateral := 0.0

var _hint := -1


func _physics_process(_delta: float) -> void:
	if vehicle == null or track == null:
		return
	# Everything is measured from the centre of mass, which the platform places; the model's
	# origin is wherever its author put it, so the line would change with the car.
	var com := vehicle.global_transform * vehicle.center_of_mass
	var proj := track.project(com, _hint)
	_hint = proj.index
	var speed := maxf(vehicle.speed(), 0.0)

	# Pure pursuit toward a point ahead on the line.
	var ahead := track.transform_at(proj.distance + 8.0 + speed * 0.7, lateral).origin
	var local := vehicle.global_basis.inverse() * (ahead - com)
	var angle := atan2(local.x, maxf(local.z, 0.1)) # + = target is to the left
	var max_steer := deg_to_rad(float(vehicle.platform.steering.max_road_angle_deg))
	vehicle.steer = clampf(-angle * 1.6 / max_steer, -1.0, 1.0)

	# Slowest corner within braking range sets the target speed.
	var mu := float(vehicle.platform.tires.mu_peak) * 9.81 * pace
	var target := 90.0
	var look := 15.0 + speed * speed / (2.0 * mu * 0.8)
	var step := 10.0
	var d := 0.0
	while d < look:
		var kappa := absf(track.curvature[track.index_at(proj.distance + d)])
		var corner := sqrt(mu / maxf(kappa, 1e-4))
		# Speed we can still brake down to that corner from here.
		target = minf(target, sqrt(corner * corner + 2.0 * mu * 0.8 * d))
		d += step
	var error := target - speed
	vehicle.throttle = clampf(error * 0.25, 0.0, 1.0)
	vehicle.brake = clampf(-error * 0.15, 0.0, 1.0)
	vehicle.handbrake = 0.0
