class_name DragWatch
extends Node
## What a player who is not in the pass sees (D176-D178). Pairs run back to back, so between
## their own passes the drivers are an audience: this gives them the pass to watch, a way to
## hurry a pass of bots along, and the card that locks them in before their turn comes round.
##
## The parked car is left exactly where DragControl put it — hidden, frozen, below the strip
## (D170) — because what a parked car means to the field and to the wire hangs on that. Only the
## camera moves: the rig is told to `watch` a spot on the strip instead of following the car it
## is bolted to.

## The views the camera button cycles while watching: the pass from behind both lanes, then each
## car in it through the player's own camera.
const VIEWS := ["pass", "lane 0", "lane 1"]
## The pass view: above and behind the leading car, looking down the strip. It pulls back with
## speed so both lanes stay in frame the whole way down.
const HEIGHT_M := 7.0
const BACK_M := 18.0
const BACK_AT_SPEED_M := 14.0
const SPEED_FULL := 90.0
const LOOK_AHEAD_M := 12.0
const LOOK_HEIGHT_M := 1.2
const FOV := 65.0
## How quickly the camera follows the cars down the strip.
const FOLLOW_RATE := 8.0

var session: TrackSession

## SessionPlayer -> which of VIEWS they are watching.
var _views := {}
## SessionPlayer -> their lock-in card, while it is up.
var _cards := {}
## Where the pass view sits now: how far down the strip, and how fast the cars are going. Shared,
## since every watching player is shown the same pass.
var _z := 0.0
var _speed := 0.0
## False until the first car of a pass is found, so the view starts on the line instead of
## sliding down from wherever the last pass ended.
var _placed := false


func _ready() -> void:
	session.drag.pass_started.connect(func(_cars: Array) -> void: _placed = false)


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
	var drag := session.drag
	_follow(drag, delta)
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null or p.vehicle == null or p.cameras == null or not is_instance_valid(p.cameras):
			continue
		if not p.camera_hook.is_valid():
			p.camera_hook = _cycle.bind(p)
		_card(p, drag)
		if p.parked:
			_watch(p, drag)
		else:
			_drive(p)


## The skip reads an input edge, and edges are polled once a physics tick: in `_process` the same
## press would be seen twice on a game drawing faster than the sim steps.
func _physics_process(_delta: float) -> void:
	var drag := session.drag
	for r in session.racers:
		var p := r as SessionPlayer
		if p != null and p.parked:
			_skip(p, drag)


## Keeps the pass view with the leading car.
func _follow(drag: DragControl, delta: float) -> void:
	var lead := -INF
	var speed := 0.0
	for r in drag.cars:
		var v := r.vehicle
		if v == null or not is_instance_valid(v):
			continue
		# The interpolated transform, as the rig uses, or the view stutters between ticks.
		lead = maxf(lead, v.get_global_transform_interpolated().origin.z)
		speed = maxf(speed, v.linear_velocity.length())
	if lead == -INF:
		return # between passes: the view holds where it is rather than dropping underground
	if not _placed:
		_placed = true
		_z = lead
		_speed = speed
	var k := 1.0 - exp(-delta * FOLLOW_RATE)
	_z = lerpf(_z, lead, k)
	_speed = lerpf(_speed, speed, k)


## This player is driving: their own car back under their own camera.
func _drive(p: SessionPlayer) -> void:
	_views[p] = VIEWS[0]
	_ride(p, p.vehicle)


## This player is watching: the pass from behind the lanes, or one of its cars.
func _watch(p: SessionPlayer, drag: DragControl) -> void:
	var car := _car_of(p, drag)
	if car:
		_ride(p, car) # one of the cars running, through this player's own camera
		return
	var y: float = drag.layout.floor_y if drag.layout else 0.0
	var back := BACK_M + clampf(_speed / SPEED_FULL, 0.0, 1.0) * BACK_AT_SPEED_M
	var pos := Vector3(0.0, y + HEIGHT_M, _z - back)
	var look := Vector3(0.0, y + LOOK_HEIGHT_M, _z + LOOK_AHEAD_M)
	p.cameras.watch(Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos), FOV)
	# The rain and snow are drawn round a car (D153), so they follow the one being watched.
	if not drag.cars.is_empty():
		_weather_on(p, drag.cars[0].vehicle)


## Puts this player's camera, and the weather round it, on `v`.
func _ride(p: SessionPlayer, v: Vehicle) -> void:
	p.cameras.unwatch()
	if p.cameras.vehicle != v:
		p.cameras.set_vehicle(v)
	_weather_on(p, v)


func _weather_on(p: SessionPlayer, v: Vehicle) -> void:
	if p.weather and v and is_instance_valid(v) and p.weather.vehicle != v:
		p.weather.vehicle = v


## The car this player has picked out of the pass, or null for the pass view.
func _car_of(p: SessionPlayer, drag: DragControl) -> Vehicle:
	var lane := VIEWS.find(String(_views.get(p, VIEWS[0]))) - 1
	if lane < 0 or lane >= drag.cars.size():
		return null
	var v := drag.cars[lane].vehicle
	return v if v and is_instance_valid(v) else null


## The camera button, while they are watching: the next view. Driving, it is theirs again, so the
## camera they pick for a pass is never saved over the one they drive with.
func _cycle(p: SessionPlayer) -> bool:
	if not p.parked:
		return false
	var at := VIEWS.find(String(_views.get(p, VIEWS[0])))
	_views[p] = VIEWS[(at + 1) % VIEWS.size()]
	var car := _car_of(p, session.drag)
	var who := ""
	if car:
		for r in session.drag.cars:
			if r.vehicle == car:
				who = r.display_name
	p.notify("Watching %s" % who if who else "Watching the pass", 1.5)
	return true


## Hurrying a pass of bots along: the Boost input, which a parked car has no use for (D178).
func _skip(p: SessionPlayer, drag: DragControl) -> void:
	if p.slot.ai or p.overlay != null or not p.slot.input.just_pressed("boost"):
		return
	if drag.skipping:
		drag.skip(false)
		p.notify("Watching", 1.5)
	elif drag.can_skip():
		drag.skip(true)
		p.notify("Skipping", 1.5)


## The card that holds the pass until this driver is ready (D177). It is put up and taken down
## from here every frame, so a pause menu over it brings it back when it closes.
func _card(p: SessionPlayer, drag: DragControl) -> void:
	var want := drag.needs_lock_in(p)
	var card: Control = _cards.get(p)
	if card != null and (not is_instance_valid(card) or not want or p.overlay != card):
		if is_instance_valid(card) and p.overlay == card:
			p.close_overlay()
		_cards.erase(p)
		card = null
	if not want or card != null or p.overlay != null:
		return
	var new_card := DragReadyCard.new()
	new_card.name = "DragReadyCard"
	new_card.player = p
	new_card.event = session.event
	new_card.round_name = drag.ladder.round_text() if not drag.ladder.pairs.is_empty() else ""
	new_card.lane = drag.armed.find(p)
	new_card.boosts = clampi(int(session.event.drag_boost), 0, 3)
	new_card.launch = drag.launch_action(p)
	new_card.locked_in.connect(func() -> void: drag.lock_in(p))
	new_card.paused.connect(func() -> void: p.pause_requested.emit(p))
	_cards[p] = new_card
	p.show_overlay(new_card, false)
