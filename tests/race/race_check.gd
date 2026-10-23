extends Node
## Race soak check (AI-01, ROADMAP M4: "no AI pile-ups"): a full grid races on a track (the
## Proving Ground unless --track), headless at a fixed 120 Hz and faster than real time, and the
## run fails on a pile-up, a car stuck for more than 5 s, or a car that doesn't finish.
## Runs as a scene so the autoloads are there:
##   tools/race_check.sh [--cars=12] [--laps=5] [--seed=1] [--skill=60-100] [--track=<id|path|hash>]
##                       [--bad=stall|early_brake|spin] [--platform=<id>] [--builtin] [--verbose]
##                       [--start=standing|rolling|track] [--draft[=on|off|track]] [--fuel=<n>] [--tyres=<n>]
## A pile-up is 3 or more cars linked by contacts (A hits B, B hits C) within 3 s and 30 m.

const CONTACT_IMPULSE := 150.0 # N·s in one tick counts as contact
const PILEUP_CARS := 3
const PILEUP_S := 3.0
const PILEUP_M := 30.0
const STUCK_S := 5.0
const LAP_TIMEOUT_S := 150.0

var opts := { "cars": "12", "laps": "5", "seed": "1", "skill": "60-100", "bad": "", "platform": "official.track.gt" }
var session: TrackSession
var time := 0.0
var contacts: Array[Dictionary] = [] # {t, a, b, pos}
var stuck := {} # racer -> seconds
var stuck_events: Array[String] = []
var resets := {} # racer -> count
var was_waiting := {}
var finish_time := {} # racer -> race time at the finish
var laps_done := {} # racer -> laps
var lap_times := {} # racer -> [s]
var order: Array = []
var overtakes := 0
var started := false
var ticks := 0
var reported := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	seed(int(opts.seed))
	get_tree().physics_frame.connect(_tick)
	_start.call_deferred()


func _start() -> void:
	Settings.use_folder("user://tests/race_check")
	Players.clear()
	session = TrackSession.new()
	session.autodrive = true
	session.platform_id = opts.platform
	if opts.has("track"):
		session.track_path = TrackLibrary.resolve(String(opts.track))
		if session.track_path.is_empty():
			print("FAIL: no track " + String(opts.track))
			get_tree().quit(1)
			return
	var skill := String(opts.skill).split("-")
	var e := RaceEvent.new()
	e.kind = "race"
	e.race_laps = int(opts.laps)
	e.ai_count = int(opts.cars) - 1
	e.ai_skill = (float(skill[0]) + float(skill[-1])) / 2.0
	e.ai_cars = "builtin" if opts.has("builtin") else "garage"
	e.grid = "random"
	e.start = opts.get("start", "standing")
	# Track-mode rules (D207): --draft[=on|off|track], --fuel=<-1-10>, --tyres=<-1-10>; without
	# them, the track's own.
	if opts.has("draft"):
		e.draft = "on" if String(opts.draft) == "true" else String(opts.draft)
	e.fuel_x = clampi(int(opts.get("fuel", -1)), -1, RaceEvent.WEAR_X_MAX)
	e.tyre_x = clampi(int(opts.get("tyres", -1)), -1, RaceEvent.WEAR_X_MAX)
	session.event = e
	session.ai_skill_spread = absf(float(skill[-1]) - float(skill[0]))
	add_child(session)


func _tick() -> void:
	if session == null or not session.is_inside_tree():
		return
	var dt := 1.0 / Engine.physics_ticks_per_second
	if not started:
		if session.race.phase == RaceControl.Phase.RUNNING and session.racers.size() == int(opts.cars):
			started = true
			var p1: Racer = session.racers[0]
			if opts.bad:
				var bad := BadDriver.new()
				bad.racer = p1
				bad.mode = opts.bad
				bad.skill = 80.0
				p1.driver.queue_free()
				p1.driver = bad
				p1.add_child(bad)
			for r in session.racers:
				laps_done[r] = 0
				lap_times[r] = []
				resets[r] = 0
				r.timer.lap_completed.connect(func(t: float, _v: bool, _b: bool) -> void: lap_times[r].append(t))
			if opts.has("verbose"):
				for r in session.racers:
					var near := INF
					for o in session.racers:
						if o != r:
							near = minf(near, o.vehicle.global_position.distance_to(r.vehicle.global_position))
					print("  grid %-8s d %.1f lat %.1f nearest %.1f m  %s  hull %s" % [r.display_name, r.track.from_start(r.distance), r.lateral, near, r.vehicle.package.display_name(), r.vehicle.fitted.envelope.size])
			print("Race: %d cars, %d laps, %s, %s, skill %s, seed %s%s" % [session.racers.size(), int(opts.laps), session.track.display_name, opts.platform, opts.skill, opts.seed, ", bad driver: " + opts.bad if opts.bad else ""])
		return
	time += dt
	ticks += 1
	if opts.has("trace") and ticks % int(opts.get("trace-every", "30")) == 0:
		var r: Racer = session.racers[int(opts.trace) if String(opts.trace).is_valid_int() else 0]
		var ai := r.driver as RacingAI
		var d := r.track.from_start(r.distance)
		if ai and d >= float(opts.get("trace-from", "0")) and d <= float(opts.get("trace-to", "99999")):
			var lv := r.vehicle.global_basis.inverse() * r.vehicle.linear_velocity
			var beta := rad_to_deg(atan2(lv.x, absf(lv.z)))
			var yaw := rad_to_deg(r.vehicle.angular_velocity.y)
			var prof: PackedFloat32Array = ai._caution_profile if ai._cautious() else ai._profile
			var pit := ""
			if session.pits:
				var st: Dictionary = session.pits.stop_of(r)
				pit = " pit[%s%s%s %.0f]" % [st.state, " plan" if r.pit_plan else "", " in" if r.in_pit else "", r.pit_distance]
			if session.wear:
				var w: CarWear = session.wear.of(r)
				pit += " fuel %.1f (%.1f laps) tread %d%%" % [w.fuel_l, w.laps_left(), roundi(w.tread() * 100.0)]
			print("  L%d %5.1f s d %4.0f lat %5.1f line %5.1f v %3.0f tgt %3.0f thr %.2f brk %.2f st %+.2f gear %d slip %+5.1f yaw %+5.1f %s%s" % [r.timer.lap, time, d, r.lateral, ai._line.offset_at(r.distance), r.speed * 3.6, ai._line.speed_at(prof, r.distance) * 3.6, r.vehicle.throttle, r.vehicle.brake, r.vehicle.steer, r.vehicle.sim.get_gear(), beta, yaw, ai.intent, pit])
	var laps := int(opts.laps)
	for r in session.racers:
		var v := r.vehicle
		# Contacts between cars (each pair once).
		if v.car_impulse > CONTACT_IMPULSE and v.last_hit and v.get_instance_id() < v.last_hit.get_instance_id():
			contacts.append({ "t": time, "a": v.name, "b": v.last_hit.name, "pos": v.global_position })
			if opts.has("verbose"):
				var o: Racer = null
				for x in session.racers:
					if x.vehicle == v.last_hit:
						o = x
				print("  contact %.1f s: %s - %s (%.0f N·s) at %.0f m | %s | %s" % [time, v.name, v.last_hit.name, v.car_impulse, r.track.from_start(r.distance), _describe(r), _describe(o)])
		# Resets.
		if r.waiting and not was_waiting.get(r, false):
			resets[r] += 1
			if opts.has("verbose"):
				print("  reset %.1f s: %s at %.0f m (lateral %.1f m%s)" % [time, r.display_name, r.track.from_start(r.distance), r.lateral, ", in the pits" if r.in_pit else ""])
		was_waiting[r] = r.waiting
		# Stuck: not moving (and not waiting to rejoin) before finishing.
		if absf(r.speed) < 1.0 and not r.waiting and not r.pit_hold and not finish_time.has(r) and time > 8.0:
			stuck[r] = stuck.get(r, 0.0) + dt
			if stuck[r] > STUCK_S and stuck[r] - dt <= STUCK_S:
				stuck_events.append("%s at %.0f m (lateral %.1f m%s), %.1f s" % [r.display_name, r.track.from_start(r.distance), r.lateral, ", in the pits" if r.in_pit else "", time])
		else:
			stuck[r] = 0.0
		# Laps: crossings after the first one; the finish is race control's.
		laps_done[r] = maxi(r.timer.lap - 1, 0)
		if r.finish_time >= 0.0 and not finish_time.has(r):
			finish_time[r] = r.finish_time
	# Overtakes: changes in running order.
	if ticks % 30 == 0:
		var now := session.racers.duplicate()
		now.sort_custom(func(a: Racer, b: Racer) -> bool: return _progress(a) > _progress(b))
		if not order.is_empty():
			for i in now.size():
				var before := order.find(now[i])
				if before > i:
					overtakes += before - i
		order = now
	if session.race.phase == RaceControl.Phase.DONE or time > LAP_TIMEOUT_S * laps + 60.0:
		_report()


func _describe(r: Racer) -> String:
	if r == null:
		return "?"
	var ai := r.driver as RacingAI
	return "%s lat %.1f v %.0f %s want %.1f" % [r.display_name, r.lateral, r.speed * 3.6, ai.intent if ai else "-", (ai._want + ai._line.offset_at(r.distance)) if ai else 0.0]


func _progress(r: Racer) -> float:
	return r.timer.lap * r.track.length + r.track.from_start(r.distance)


func _report() -> void:
	if reported:
		return
	reported = true
	var pileups := _pileups()
	var fails := PackedStringArray()
	for p in pileups:
		fails.append("pile-up: " + p)
	for s in stuck_events:
		fails.append("stuck: " + s)
	for r in session.racers:
		if not finish_time.has(r):
			fails.append("didn't finish: %s (%d laps)" % [r.display_name, laps_done[r]])
	if session.race.phase != RaceControl.Phase.DONE:
		fails.append("the race didn't end")
	var total_resets := 0
	for r in session.racers:
		total_resets += resets[r]
	var best := INF
	var worst := 0.0
	for r in session.racers:
		var times: Array = lap_times[r]
		for t: float in times.slice(1):
			best = minf(best, t)
		if times.size() > 1:
			worst = maxf(worst, times.slice(1).min())
	print("Time %.0f s, contacts %d, resets %d, overtakes %d, best lap %.2f s, slowest car's best %.2f s" % [time, contacts.size(), total_resets, overtakes, best, worst])
	var finishers := finish_time.keys()
	finishers.sort_custom(func(a: Racer, b: Racer) -> bool: return finish_time[a] < finish_time[b])
	for i in finishers.size():
		var r: Racer = finishers[i]
		var worn := ""
		if session.wear and session.wear.cars.has(r):
			var w: CarWear = session.wear.cars[r]
			worn = "  fuel %.1f L (%.2f L a lap)  tread %d%%" % [w.fuel_l, w.lap_fuel, roundi(w.tread() * 100.0)]
		if session.pits and session.pits.stops.has(r):
			worn += "  stops %d" % int(session.pits.stops[r].stops)
		print("  P%d %-8s %6.1f s  resets %d  laps %s%s" % [i + 1, r.display_name, finish_time[r], resets[r], ", ".join(PackedStringArray((lap_times[r] as Array).map(func(t: float) -> String: return "%.1f" % t))), worn])
	if fails.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for f in fails:
			print("FAIL " + f)
		get_tree().quit(1)


## Groups of 3+ cars linked by contacts (A hits B, B hits C) within PILEUP_S and PILEUP_M.
func _pileups() -> PackedStringArray:
	var out := PackedStringArray()
	var used := {}
	for i in contacts.size():
		if used.has(i):
			continue
		# Grow the group from this contact through shared cars.
		var cars := { contacts[i].a: true, contacts[i].b: true }
		var group: Array[int] = [i]
		var grew := true
		while grew:
			grew = false
			for j in contacts.size():
				if j in group:
					continue
				var c: Dictionary = contacts[j]
				var linked: bool = cars.has(c.a) or cars.has(c.b)
				if linked and absf(c.t - contacts[i].t) <= PILEUP_S and (c.pos as Vector3).distance_to(contacts[i].pos) <= PILEUP_M:
					cars[c.a] = true
					cars[c.b] = true
					group.append(j)
					grew = true
		for j in group:
			used[j] = true
		if cars.size() >= PILEUP_CARS:
			out.append("%d cars at %.1f s (%s)" % [cars.size(), contacts[i].t, ", ".join(PackedStringArray(cars.keys()))])
	return out
