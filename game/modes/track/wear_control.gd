class_name WearControl
extends Node
## Fuel use and tire wear in Track sessions (D209), when the event has either on: ten times a
## second each car this game drives burns fuel and scrubs its tires (CarWear) from what its sim
## did since (VehicleSim.take_wear); a car out of fuel only coasts, worn tires grip less. Online
## each game runs its own cars': nothing goes on the wire.

const HZ := 10.0

var session: TrackSession
var fuel_x := 0
var tyre_x := 0
## Racer -> CarWear.
var cars := {}
var _time := 0.0


func _ready() -> void:
	name = "WearControl"
	process_physics_priority = -56 # after the race field and drafting, before the drivers


## `r`'s fuel and tires (made the first time it's asked for).
func of(r: Racer) -> CarWear:
	if not cars.has(r) and r.vehicle:
		cars[r] = CarWear.make(r.vehicle.base_platform, r.vehicle.sim.get_wheel_count(), fuel_x, tyre_x)
	return cars.get(r)


func _physics_process(delta: float) -> void:
	_time += delta
	if _time < 1.0 / HZ:
		return
	_time = 0.0
	for r in session.racers:
		var v := r.vehicle
		if v == null or v.remote:
			continue
		var w := of(r)
		var done: Dictionary = v.sim.take_wear()
		if r.waiting:
			continue
		w.lap_started(r.timer.lap)
		if w.burn(float(done.engine_j)):
			r.notify("Out of fuel", 3.0)
		w.scrub(done.slide_j)
		v.sim.set_power_scale(1.0 if not w.uses_fuel() or w.fuel_l > 0.0 else 0.0)
		for i in w.wear.size():
			v.sim.set_wheel_grip(i, w.grip_of(i))
