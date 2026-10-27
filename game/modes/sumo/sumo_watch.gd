class_name SumoWatch
extends Node
## What a player who is in the goo sees (D185). A sumo match has no respawns -- the platforms are
## the lives -- so going in ends your match but not the match, and whoever is left fights on for
## another minute or more. Without this you spent it looking at goo from underneath: the camera is
## bolted to the car, and the car is three metres under the surface.
##
## The car is left exactly where SumoControl put it -- out, frozen, ghosted, under the goo --
## because `out`, the KART_OUT bit on the wire and the authority's word all rest on that (D166).
## Only the camera moves, as a waiting drag driver's does (D176). Nothing here goes on the wire.
## Out, the Ram button runs the rest of the match on faster and back (D220), offline.

## The arena from outside and above, as a fraction of the platform in play: far enough back and
## high enough up that the whole of it is in frame, whichever platform the fight is down to.
const BACK := 1.8
const HEIGHT := 1.0
const FOV := 60.0
## The smallest platform worth framing (the sudden-death pillar is 6 m).
const LEAST_R := 10.0
## How quickly the view follows the fight about the arena.
const FOLLOW_RATE := 3.0

var session: TrackSession

## SessionPlayer -> which view: 0 the arena, else that car of the ones still in.
var _views := {}
## Where the fight is now, and how wide the platform under it is. Shared: every watching player is
## shown the same arena.
var _centre := Vector3.ZERO
var _radius := 0.0
## False until the first car is found, so the view starts on the fight rather than sliding in from
## wherever the last match left it.
var _placed := false


func _exit_tree() -> void:
	if session == null or not is_instance_valid(session):
		return
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null:
			continue
		p.camera_hook = Callable()
		if p.cameras and is_instance_valid(p.cameras):
			p.cameras.unwatch()


func _process(delta: float) -> void:
	if session.sumo == null:
		return
	var standing := session.sumo.standing()
	_follow(standing, delta)
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null or p.vehicle == null or p.cameras == null or not is_instance_valid(p.cameras):
			continue
		if not p.camera_hook.is_valid():
			p.camera_hook = _cycle.bind(p)
		if not p.out:
			# Driving again: a new match (SumoControl.reset clears `out`), their own car back.
			_views[p] = 0
			_ride(p, p.vehicle)
			continue
		# A car being watched can go in itself, which puts the arena back up.
		if int(_views.get(p, 0)) > standing.size():
			_views[p] = 0
		_watch(p, standing)


## The fast-forward reads an input edge, and edges are polled once a physics tick: in `_process`
## the same press would be seen twice on a game drawing faster than the sim steps (DragWatch).
func _physics_process(_delta: float) -> void:
	var sumo := session.sumo
	if sumo == null:
		return
	for r in session.racers:
		var p := r as SessionPlayer
		if p != null and p.out:
			_fast_forward(p, sumo)


func _fast_forward(p: SessionPlayer, sumo: SumoControl) -> void:
	if p.slot.ai or p.overlay != null or not p.slot.input.just_pressed("ram"):
		return
	if sumo.fast_forward:
		sumo.fast_forward_on(false)
		p.notify("Normal speed", 1.5)
	elif sumo.can_fast_forward():
		sumo.fast_forward_on(true)
		p.notify("Fast forward", 1.5)


## Keeps the view with the fight: the middle of whoever is left, over the widest platform any of
## them is still on.
func _follow(standing: Array[Racer], delta: float) -> void:
	var layout := session.sumo.layout
	var sum := Vector3.ZERO
	var found := 0
	var tier := 0
	for r in standing:
		var v := r.vehicle
		if v == null or not is_instance_valid(v):
			continue
		# The interpolated transform, as the rig uses, or the view stutters between ticks.
		sum += v.get_global_transform_interpolated().origin
		tier = maxi(tier, maxi(session.sumo.tier(r), 0))
		found += 1
	var at := sum / float(found) if found > 0 else Vector3.ZERO
	var radius := maxf(layout.radius_of(tier if found > 0 else maxi(layout.lowest_live(), 0)), LEAST_R)
	if found == 0:
		at.y = layout.floor_y_of(maxi(layout.lowest_live(), 0))
	if not _placed:
		_placed = true
		_centre = at
		_radius = radius
	var k := 1.0 - exp(-delta * FOLLOW_RATE)
	_centre = _centre.lerp(at, k)
	_radius = lerpf(_radius, radius, k)


## This player is out: the arena from outside and above, or one of the cars still in it.
func _watch(p: SessionPlayer, standing: Array[Racer]) -> void:
	var car := _car_of(p, standing)
	if car:
		_ride(p, car)
		return
	var pos := _centre + Vector3(0.0, _radius * HEIGHT, -_radius * BACK)
	p.cameras.watch(Transform3D(Basis.looking_at(_centre - pos, Vector3.UP), pos), FOV)
	# The rain and snow are drawn round a car (D153), so they follow somebody still in.
	for r in standing:
		if r.vehicle and is_instance_valid(r.vehicle):
			_weather_on(p, r.vehicle)
			return


## Puts this player's camera, and the weather round it, on `v`.
func _ride(p: SessionPlayer, v: Vehicle) -> void:
	p.cameras.unwatch()
	if p.cameras.vehicle != v:
		p.cameras.set_vehicle(v)
	_weather_on(p, v)


func _weather_on(p: SessionPlayer, v: Vehicle) -> void:
	if p.weather and v and is_instance_valid(v) and p.weather.vehicle != v:
		p.weather.vehicle = v


## The car this player has picked out of the ones still in, or null for the arena.
func _car_of(p: SessionPlayer, standing: Array[Racer]) -> Vehicle:
	var at := int(_views.get(p, 0))
	if at <= 0 or at > standing.size():
		return null
	var v := standing[at - 1].vehicle
	return v if v and is_instance_valid(v) else null


## What this player is being shown, for their HUD ("" while they are driving).
func watching_text(p: SessionPlayer) -> String:
	if not p.out or session.sumo == null:
		return ""
	var standing := session.sumo.standing()
	var at := int(_views.get(p, 0))
	if at <= 0 or at > standing.size():
		return "Watching the arena"
	return "Watching %s" % standing[at - 1].display_name


## The camera button, while they are watching: the next view, the arena and then each car still
## in. Driving, it is theirs again, so a camera picked to watch with is never saved over the one
## they drive with (SessionPlayer._next_camera).
func _cycle(p: SessionPlayer) -> bool:
	if not p.out:
		return false
	var standing := session.sumo.standing()
	_views[p] = (int(_views.get(p, 0)) + 1) % (standing.size() + 1)
	p.notify(watching_text(p), 1.5)
	return true
