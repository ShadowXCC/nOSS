class_name PitControl
extends Node
## Pit stops (D210) on a track with a pit lane. Each car this game drives has a request (fuel:
## Full, Finish, Half or None; tires: 4, 2 or 0; a repair slot kept empty until there's damage)
## its driver sets while driving; it's locked as the car enters the lane. Between the limit lines
## the car is held to the lane's speed (racer.pit_limit: the controls and the AI keep to it). A car
## that stops within BOX_WINDOW_M of its box (boxes in grid order) is held there for its service,
## then told "Go". With neither fuel use nor tire wear on there's nothing to service: the lane is
## a drive-through. The AI decides when to pit from its fuel and tires. Online the game that
## drives a car runs its stops: nothing new on the wire.

const FUEL := ["full", "finish", "half", "none"]
const FUEL_WORDS := { "full": "Full", "finish": "Finish", "half": "Half", "none": "No fuel" }
const TIRES := [4, 2, 0]
## "Finish": fuel for the laps to go and FINISH_LAPS more, at the last lap's use and FINISH_MARGIN
## over it (a lap in a draft uses less than one out of it).
const FINISH_LAPS := 0.6
const FINISH_MARGIN := 1.1
## Litres a second into the tank; tire changes, s; and the stop itself (in, jack, out), s.
const FUEL_RATE := 6.0
const TIRES_4_S := 11.0
const TIRES_2_S := 6.0
const STOP_S := 0.8
## A car this far either side of its box's middle, under STOPPED_MPS, is in its box.
const BOX_WINDOW_M := 6.0
const STOPPED_MPS := 1.0
## "Go" stays up this long.
const GO_S := 1.5
## The AI: pits when fuel would last fewer laps than this (plus up to AI_NOISE_LAPS), or its tires
## are down to AI_TREAD (± AI_NOISE_TREAD) with laps still to go.
const AI_FUEL_LAPS := 2.0
const AI_NOISE_LAPS := 0.4
const AI_TREAD := 0.25
const AI_NOISE_TREAD := 0.08
const AI_TIRE_LAPS_LEFT := 4

var session: TrackSession
var pit: PitLane
## Racer -> {request {fuel, tires, repair}, state ("track", "lane", "service", "leaving"), box,
## service_left, service_s, stops, go_left, noise}
var stops := {}
var _panels := {} # SessionPlayer -> PitPanel
var _limits := {} # SessionPlayer -> true while this put the pit speed on its limit sign
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "PitControl"
	process_physics_priority = -55 # after the race field, drafting and wear; before the drivers
	pit = session.track.pit
	_rng.seed = hash(session.track.id)


## Racer `r`'s stop (made the first time it's asked for).
func stop_of(r: Racer) -> Dictionary:
	if not stops.has(r):
		var order := session.racers.find(r)
		stops[r] = { "request": { "fuel": "full", "tires": 4, "repair": false }, "state": "track",
			"box": maxi(order, 0) % maxi(pit.boxes.size(), 1), "service_left": 0.0, "service_s": 0.0, "stops": 0,
			"go_left": 0.0, "noise": _rng.randf() }
	return stops[r]


## Steps `r`'s request on: "fuel" or "tires". Locked once the car is in the lane.
func cycle(r: Racer, what: String) -> void:
	var s := stop_of(r)
	if s.state != "track":
		return
	if what == "fuel":
		s.request.fuel = FUEL[(FUEL.find(s.request.fuel) + 1) % FUEL.size()]
	else:
		s.request.tires = TIRES[(TIRES.find(int(s.request.tires)) + 1) % TIRES.size()]
	var p := r as SessionPlayer
	if p:
		p.speak("Pit: " + request_text(s.request))


## Sets `r`'s request outright (the pause menu's rows).
func set_request(r: Racer, what: String, value: Variant) -> void:
	var s := stop_of(r)
	if s.state == "track":
		s.request[what] = value


## "Full · 4 tires", "No fuel · no tires".
static func request_text(request: Dictionary) -> String:
	var tires := int(request.tires)
	return "%s · %s" % [FUEL_WORDS[request.fuel], "%d tires" % tires if tires > 0 else "no tires"]


## True if the event has something to service (fuel use or tire wear).
func services() -> bool:
	return session.wear != null


## Litres `request` asks for now, for car `r`.
func litres(r: Racer, request: Dictionary) -> float:
	var w := session.wear.of(r) if session.wear else null
	if w == null or not w.uses_fuel():
		return 0.0
	var room := w.tank_l - w.fuel_l
	match String(request.fuel):
		"full":
			return room
		"half":
			return minf(w.tank_l / 2.0, room)
		"finish":
			var to_go := laps_to_go(r)
			if not is_finite(to_go) or w.lap_fuel <= 0.0:
				return room
			return clampf((to_go + FINISH_LAPS) * w.lap_fuel * FINISH_MARGIN - w.fuel_l, 0.0, room)
	return 0.0


## The service `request` takes for car `r`, s (0: none).
func service_time(r: Racer, request: Dictionary) -> float:
	var fuel_s := litres(r, request) / FUEL_RATE
	var tires := int(request.tires) if session.wear and session.wear.of(r).wears_tires() else 0
	var tire_s := TIRES_4_S if tires >= 4 else (TIRES_2_S if tires > 0 else 0.0)
	var work := maxf(fuel_s, tire_s)
	return work + STOP_S if work > 0.0 else 0.0


## Laps `r` has still to run in a race of laps (INF otherwise).
func laps_to_go(r: Racer) -> float:
	var e := session.event
	if e.kind != "race" or e.race_min > 0:
		return INF
	return float(e.race_laps - maxi(r.timer.lap - 1, 0))


## Where `r`'s box is along the lane, m.
func box_m(r: Racer) -> float:
	return pit.box_at[int(stop_of(r).box)] if not pit.box_at.is_empty() else -1.0


func _physics_process(delta: float) -> void:
	for r in session.racers:
		if r.vehicle == null or r.vehicle.remote:
			continue
		var s := stop_of(r)
		r.pit_limit = pit.speed if r.in_pit and pit.limited(r.pit_distance) else 0.0
		var ai := r.driver is RacingAI
		if ai:
			_ai_plan(r, s)
		match String(s.state):
			"track":
				if r.in_pit:
					s.state = "lane"
					_say(r, "Locked")
			"lane":
				if not r.in_pit:
					s.state = "track"
				elif services() and service_time(r, s.request) > 0.0 and (not ai or r.pit_plan) \
						and absf(r.pit_distance - box_m(r)) <= BOX_WINDOW_M and absf(r.speed) < STOPPED_MPS:
					s.state = "service"
					s.service_s = service_time(r, s.request)
					s.service_left = s.service_s
					r.pit_hold = true
			"service":
				s.service_left = maxf(float(s.service_left) - delta, 0.0)
				if s.service_left <= 0.0:
					var w := session.wear.of(r)
					var tires := int(s.request.tires)
					w.service(litres(r, s.request), tires)
					s.stops = int(s.stops) + 1
					s.state = "leaving"
					s.go_left = GO_S
					r.pit_hold = false
					r.pit_plan = false
					_say(r, "Go")
			"leaving":
				s.go_left = maxf(float(s.go_left) - delta, 0.0)
				if not r.in_pit:
					s.state = "track"


## The AI's call, as it crosses the line: in this lap if its fuel won't last much more than a lap
## (and the race isn't nearly done), or its tires are worn with laps to go. It asks to fill up
## for the rest of the race (a tank at most) and for 4 tires if they're worn, else 2.
func _ai_plan(r: Racer, s: Dictionary) -> void:
	if r.pit_plan or not services() or s.state != "track" or r.get_meta(&"pit_planned_lap", -1) == r.timer.lap:
		return
	r.set_meta(&"pit_planned_lap", r.timer.lap)
	var w := session.wear.of(r)
	var to_go := laps_to_go(r)
	var fuel_short := w.uses_fuel() and w.laps_left() < minf(to_go - 0.3, AI_FUEL_LAPS + AI_NOISE_LAPS * float(s.noise))
	var tread := AI_TREAD + AI_NOISE_TREAD * (float(s.noise) * 2.0 - 1.0)
	var tires_worn := w.wears_tires() and w.tread() < tread and to_go > AI_TIRE_LAPS_LEFT
	if not (fuel_short or tires_worn):
		return
	r.pit_plan = true
	s.request.fuel = "finish" if is_finite(to_go) else "full"
	s.request.tires = 4 if w.tread() < 0.5 else (2 if w.wears_tires() else 0)


## A word for `r`'s driver: on their panel, spoken with race narration.
func _say(r: Racer, text: String) -> void:
	var p := r as SessionPlayer
	if p:
		p.speak(text)


func _process(_delta: float) -> void:
	for r in session.racers:
		var p := r as SessionPlayer
		if p == null or p.hud == null or p.vehicle == null:
			continue
		var panel: PitPanel = _panels.get(p)
		if panel == null or not is_instance_valid(panel):
			panel = PitPanel.new()
			panel.name = "PitPanel"
			p.hud.add_child(panel)
			_panels[p] = panel
		panel.show_text(panel_text(p))
		# The lane's limit on the limit sign while it holds.
		if p.pit_limit > 0.0:
			p.hud.set_limit(p.pit_limit)
			_limits[p] = true
		elif _limits.get(p, false):
			p.hud.set_limit(0.0)
			_limits[p] = false


## What `r`'s panel says: the request on track, then "Locked · Box 120 m", "Service 8.1", "Go".
func panel_text(r: Racer) -> String:
	var s := stop_of(r)
	match String(s.state):
		"lane":
			if services() and service_time(r, s.request) > 0.0:
				var to_box := box_m(r) - r.pit_distance
				var shown := "%d ft" % roundi(to_box * 3.28084) if Settings.units == "imperial" else "%d m" % roundi(to_box)
				return "Locked · Box %s" % shown if to_box > -BOX_WINDOW_M else "Locked"
			return "Pit lane"
		"service":
			return "Service %.1f" % float(s.service_left)
		"leaving":
			return "Go" if float(s.go_left) > 0.0 else ""
	return "Pit: " + request_text(s.request) if services() else ""
