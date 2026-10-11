class_name RacingAI
extends Node
## Drives a racer's car (AI-01, AI-05) through the same controls as a player: pure-pursuit
## steering and a speed target from the curvature ahead. Reads where the car is from the
## Racer (set by the RaceField each tick), so the car is projected once.

var racer: Racer
## 0-100 (docs/GAMEMODES.md §0).
var skill := 80.0
## Line to follow, metres left (+) or right (-) of the centreline.
var lateral := 0.0


func _ready() -> void:
	process_physics_priority = -50 # after the RaceField, before the vehicles
	lateral = racer.lateral


func _physics_process(_delta: float) -> void:
	var vehicle := racer.vehicle
	if vehicle == null:
		return
	var track := racer.track
	var com := racer.com()
	var speed := maxf(vehicle.speed(), 0.0)
	var pace := 0.72 + 0.1 * clampf(skill, 0.0, 100.0) / 100.0

	# Pure pursuit toward a point ahead on the line.
	var ahead := track.transform_at(racer.distance + 8.0 + speed * 0.7, lateral).origin
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
		var kappa := absf(track.curvature[track.index_at(racer.distance + d)])
		var corner := sqrt(mu / maxf(kappa, 1e-4))
		# Speed we can still brake down to that corner from here.
		target = minf(target, sqrt(corner * corner + 2.0 * mu * 0.8 * d))
		d += step
	var error := target - speed
	vehicle.throttle = clampf(error * 0.25, 0.0, 1.0)
	vehicle.brake = clampf(-error * 0.15, 0.0, 1.0)
	vehicle.handbrake = 0.0
