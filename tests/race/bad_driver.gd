class_name BadDriver
extends RacingAI
## A misbehaving stand-in for a human in the race check: it stalls on the grid, brakes far too
## early into Turn 1, or spins in a corner, so the AI's traffic rules get tested.

## "stall", "early_brake", "spin" or "" (drives normally).
var mode := ""
var _time := 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	var vehicle := racer.vehicle
	if vehicle == null or racer.held:
		super(delta)
		return
	var d := racer.track.from_start(racer.distance)
	match mode:
		"stall":
			if _time < 6.0:
				vehicle.throttle = 0.0
				vehicle.brake = 0.0
				vehicle.handbrake = 1.0
				vehicle.steer = 0.0
				return
		"early_brake":
			if racer.timer.lap == 1 and d > 330.0 and d < 420.0:
				super(delta)
				vehicle.throttle = 0.0
				vehicle.brake = 1.0
				return
		"spin":
			if racer.timer.lap == 2 and d > 880.0 and d < 900.0:
				super(delta)
				vehicle.steer = 1.0
				vehicle.handbrake = 1.0
				vehicle.throttle = 1.0
				return
	super(delta)
