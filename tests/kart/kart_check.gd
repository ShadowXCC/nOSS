extends Node
## Kart soak check (M8, D143): a field of karts races with items, headless at a fixed 120 Hz and
## faster than real time. Fails on a kart not classified, a kart stuck over 5 s (not while spun,
## slowed or towed), a pile-up (4 or more karts linked by knocks of 2 m/s or more within 2 s and
## 20 m), fewer than 3 items used for every 4 kart-laps (a kart holds what it picked up late, or
## keeps a Shield for a Seeker), fewer than half the AI (skill 50+) drift-boosting each lap, loops
## failed more than once and more than 10% of the time (not counting karts knocked off by items),
## too many tows (1 a kart-lap on a stunt track, 0.2 elsewhere), or items left out past their time.
## A battle (--battle=standing|hits, D144; on the arena fixture unless --track says) fails on no
## winner within the time limit and a minute, lives lost that don't match the hits taken, a kart
## stuck, fewer items used than karts, or more than two tows a kart.
## Runs as a scene so the autoloads are there:
##   tools/kart_check.sh [--karts=8] [--laps=2] [--seed=1] [--skill=50-90] [--track=<id|path>]
##                       [--class=medium|light|heavy|mixed] [--odds=cycle] [--battle=standing|hits] [--minutes=5]
##                       [--verbose]

const KNOCK_DV := 2.0
const PILEUP_KARTS := 4
const PILEUP_S := 2.0
const PILEUP_M := 20.0
const STUCK_S := 5.0
const LAP_TIMEOUT_S := 150.0
const ARENA := "res://tests/fixtures/tracks/arena_small.json"
const ITEMS_PER_KART_LAP := 0.75
## A tow or a loop failure this soon after an item hit is the item's doing.
const HIT_RECENT_S := 6.0

var opts := { "karts": "8", "laps": "2", "seed": "1", "skill": "50-90", "class": "medium",
	"track": "res://tests/fixtures/tracks/kart_small.json" }
var session: TrackSession
var time := 0.0
var ticks := 0
var tick_us := 0
var started := false
var reported := false
var knocks: Array[Dictionary] = []
var stuck := {}
var stuck_events: Array[String] = []
var uses := 0
var gots := 0
var uses_by := {}
var hits_by_kind := {}
var tows := 0
var tows_after_hits := 0
var was_towed := {}
var hit_at := {} # racer -> time it was last hit
var loops_hit_off := 0 # knocked out of a loop by an item: not the loop's or the AI's doing
var was_off := {}
var drift_boosts := {} # racer -> [laps in which it drift-boosted]
var was_flags := {}
var in_loop := {}
var loops_entered := 0
var loops_done := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
		if kv[0] == "track":
			opts["track_set"] = "true"
	seed(int(opts.seed))
	Game.dev["seed"] = opts.seed
	if opts.has("odds"):
		Game.dev["odds"] = opts.odds
	get_tree().physics_frame.connect(_tick)
	_start.call_deferred()


func _start() -> void:
	Settings.use_folder("user://tests/kart_check")
	Players.clear()
	session = TrackSession.new()
	session.autodrive = true
	session.platform_id = "official.kart." + ("medium" if opts["class"] == "mixed" else String(opts["class"]))
	session.ai_class_mix = opts["class"] == "mixed" # one class unless asked (the balance checks)
	if battle() and not opts.has("track_set"):
		opts.track = ARENA
	session.track_path = TrackLibrary.resolve(String(opts.track)) if not String(opts.track).ends_with(".json") else String(opts.track)
	var skill := String(opts.skill).split("-")
	var e := RaceEvent.new()
	e.kind = "race"
	if battle():
		e = RaceEvent.battle(rule(), int(opts.get("minutes", "5" if rule() == "standing" else "3")))
	e.race_laps = int(opts.laps)
	e.ai_count = int(opts.karts) - 1
	e.ai_skill = (float(skill[0]) + float(skill[skill.size() - 1])) / 2.0
	e.ai_cars = "builtin"
	e.items = not opts.has("no-items")
	session.event = e
	session.ai_skill_spread = float(skill[skill.size() - 1]) - float(skill[0])
	add_child(session)
	session.race.session_ended.connect(_on_ended)
	if battle():
		print("kart_check: battle (%s, %d min), %d karts, %s, %s, seed %s" % [rule(), e.battle_min, int(opts.karts), opts["class"], opts.track, opts.seed])
	else:
		print("kart_check: %d karts, %d laps, %s, %s, seed %s" % [int(opts.karts), int(opts.laps), opts["class"], opts.track, opts.seed])


func battle() -> bool:
	return opts.has("battle")


func rule() -> String:
	return "hits" if String(opts.get("battle", "")) == "hits" else "standing"


func _tick() -> void:
	if session == null or not is_instance_valid(session) or reported:
		return
	var t0 := Time.get_ticks_usec()
	var dt := 1.0 / Engine.physics_ticks_per_second
	time += dt
	ticks += 1
	if not started:
		if session.kart and session.racers.size() == int(opts.karts) and session.racers.all(func(r: Racer) -> bool: return r.vehicle != null):
			started = true
			var items := session.kart.items
			items.got.connect(func(_r: Racer, _item: String) -> void: gots += 1)
			items.used.connect(func(r: Racer, _item: String) -> void:
				uses += 1
				uses_by[r] = int(uses_by.get(r, 0)) + 1)
			items.hit_landed.connect(func(victim: Racer, _a: Racer, kind: String, blocked: bool) -> void:
				if not blocked:
					hits_by_kind[kind] = int(hits_by_kind.get(kind, 0)) + 1
					hit_at[victim] = time)
		return
	for r in session.racers:
		_watch(r, dt)
	if not battle(): # karts in an arena meet head on: what a battle is
		_pileups()
	if battle() and time > session.event.battle_min * 60.0 + 60.0:
		_report(["no winner after %.0f s" % time])
	elif not battle() and time > LAP_TIMEOUT_S * float(opts.laps) + 60.0:
		_report(["the race didn't end"])
	tick_us += Time.get_ticks_usec() - t0


func _watch(r: Racer, dt: float) -> void:
	var v := r.vehicle
	if v == null:
		return
	if r.towed and not was_towed.get(r, false):
		# Spun off by an item: not the AI's own doing.
		if time - float(hit_at.get(r, -INF)) < HIT_RECENT_S:
			tows_after_hits += 1
		else:
			tows += 1
		if opts.has("verbose"):
			var road := session.track.point_at(r.distance)
			print("  tow: %s at %.0f m (lap %d, %.1f s): up %.2f, speed %.1f, %.1f m over the road, lateral %.1f" % [r.display_name, r.last_valid,
				r.timer.lap, time, v.global_basis.y.y, v.linear_velocity.length(), r.com().y - road.y, r.lateral])
	was_towed[r] = r.towed
	var flags := v.kart_flags()
	var before: int = was_flags.get(r, flags)
	was_flags[r] = flags
	var drift_mask := VehicleSim.KART_FLAG_DRIFT_LEFT | VehicleSim.KART_FLAG_DRIFT_RIGHT
	if before & drift_mask and not flags & drift_mask and flags & VehicleSim.KART_FLAG_BOOST:
		var laps: Array = drift_boosts.get(r, [])
		if not r.timer.lap in laps:
			laps.append(r.timer.lap)
		drift_boosts[r] = laps
	# Loops: in, then out the far side (round), or towed off.
	if r.towed and in_loop.get(r, 0) != 0:
		in_loop[r] = 0
		_hit_off_loop(r)
		if opts.has("verbose"):
			print("  loop failed: %s" % r.display_name)
	elif session.track.kart and not r.towed:
		var loop := session.track.kart.loop_progress(r.com())
		var state: int = in_loop.get(r, 0) # 0 out, 1 in, 2 past the top
		if not loop.is_empty():
			if state == 0 and float(loop.t) < 0.3:
				loops_entered += 1
				state = 1
				if opts.has("verbose"):
					print("  loop in: %s t %.2f lat %.1f speed %.1f" % [r.display_name, float(loop.t), r.lateral, r.speed])
			elif state == 1 and float(loop.t) > 0.4 and float(loop.t) < 0.6:
				state = 2
		elif state == 2:
			loops_done += 1
			state = 0
		elif state == 1:
			# Out again without getting round: off the side, or never really on it.
			_hit_off_loop(r)
			if opts.has("verbose"):
				print("  loop off: %s at %.0f m lat %.1f speed %.1f" % [r.display_name, r.distance, r.lateral, r.speed])
			state = 0
		in_loop[r] = state
	# Off the road (verbose): what it was doing as it left.
	var off_road := absf(r.lateral) > session.track.half_width(r.distance, r.lateral) + 1.0 and session.track.arena == null
	if opts.has("verbose") and off_road and not was_off.get(r, false) and not r.towed:
		var curv := session.track.curvature[session.track.index_at(r.distance)]
		print("  off: %s at %.0f m lateral %.1f speed %.1f drift %d tier %d boost %s spun %s knock %.1f R %.0f m" % [r.display_name, r.distance,
			r.lateral, r.speed, 1 if flags & drift_mask else 0, (flags >> VehicleSim.KART_FLAG_TIER_SHIFT) & 3,
			flags & VehicleSim.KART_FLAG_BOOST != 0, flags & VehicleSim.KART_FLAG_SPUN != 0, time - v.knocked_at if v.knocked_at > 0 else -1.0,
			1.0 / maxf(absf(curv), 1e-4)])
	was_off[r] = off_road
	var window := String(opts.get("trace_at", "")).split("-")
	if window.size() == 2 and time >= float(window[0]) and time <= float(window[1]) and ticks % int(opts.get("trace_every", "15")) == 0 and r.display_name == String(opts.get("trace_kart", r.display_name)):
		var heading := v.global_basis.z.dot(session.track.tangents[maxi(r.track_index, 0)])
		print("    %s %.2f s: d %.0f lat %.1f speed %.1f yaw %.2f heading %.2f steer %.2f thr %.2f brk %.2f drift %s flags %d pos %s up %.2f valid %.0f" % [r.display_name, time, r.distance, r.lateral,
			r.speed, v.angular_velocity.y, heading, v.steer, v.throttle, v.brake, v.drift, flags, v.global_position.snapped(Vector3.ONE * 0.1), v.global_basis.y.y, r.last_valid])
	var span := String(opts.get("trace_d", "")).split("-")
	if span.size() == 2 and r.distance >= float(span[0]) and r.distance <= float(span[1]) and ticks % int(opts.get("trace_every", "15")) == 0 and r.driver is KartAI:
		var ai := r.driver as KartAI
		var heading := v.global_basis.z.dot(session.track.tangents[maxi(r.track_index, 0)])
		print("    %s %.2f s: d %.1f lat %.1f line %.1f off %.1f want %.1f %s speed %.1f yaw %.2f heading %.2f steer %.2f thr %.2f brk %.2f exit %.2f" % [r.display_name, time, r.distance, r.lateral,
			ai._line.offset_at(r.distance), ai.offset, ai._want, ai.intent, r.speed, v.angular_velocity.y, heading, v.steer, v.throttle, v.brake, ai._loop_exit])
		print("      y %.1f up %s vel %s grounded %d drift %s flags %d" % [v.global_position.y, v.global_basis.y.snapped(Vector3.ONE * 0.01), v.linear_velocity.snapped(Vector3.ONE * 0.1),
			int(v.sim.get_kart_state().grounded), v.drift, v.kart_flags()])
	if opts.has("trace") and off_road and not r.towed and ticks % 60 == 0:
		var heading := v.global_basis.z.dot(session.track.tangents[maxi(r.track_index, 0)])
		print("    %s %.1f s: lat %.1f speed %.1f heading %.2f steer %.2f thr %.2f brk %.2f want %.2f" % [r.display_name, time, r.lateral,
			r.speed, heading, v.steer, v.throttle, v.brake, (r.driver as RacingAI)._want if r.driver is RacingAI else 0.0])
	# Knocks.
	var dv := (v.car_impulse) / v.mass
	if dv >= KNOCK_DV and v.last_hit:
		knocks.append({ "t": time, "a": v, "b": v.last_hit, "pos": v.global_position })
	# Stuck: barely moving, not held, spun, towed or finished.
	var spun := flags & (VehicleSim.KART_FLAG_SPUN | VehicleSim.KART_FLAG_SLOWED) != 0 # an item's doing
	if r.held or r.finished or r.towed or spun or absf(r.speed) > 1.0:
		stuck[r] = 0.0
	else:
		stuck[r] = float(stuck.get(r, 0.0)) + dt
		if stuck[r] > STUCK_S:
			var where := "%s" % r.com().snapped(Vector3.ONE * 0.1) if session.track.arena else "%.0f m" % r.distance
			var doing := ""
			if r.driver is BattleAI:
				var b := r.driver as BattleAI
				doing = " (vel %s flags %d, %s, out %s, up %s, grounded %d, path %d at %d, goal %s, thr %.2f brk %.2f steer %.2f)" % [v.linear_velocity.snapped(Vector3.ONE * 0.01), v.kart_flags(), b.intent, r.out, v.global_basis.y.snapped(Vector3.ONE * 0.01), int(v.sim.get_kart_state().grounded), b._path.size(), b._at,
					b._goal.snapped(Vector3.ONE * 0.1), v.throttle, v.brake, v.steer]
			stuck_events.append("%s stuck at %s%s" % [r.display_name, where, doing])
			stuck[r] = -INF


func _pileups() -> void:
	while not knocks.is_empty() and time - float(knocks[0].t) > PILEUP_S:
		knocks.pop_front()
	if knocks.size() < PILEUP_KARTS - 1:
		return
	# Karts linked by knocks within the window and near each other.
	var groups := {}
	for k: Dictionary in knocks:
		var a: Vehicle = k.a
		var b: Vehicle = k.b
		groups[a] = groups.get(a, { a: true })
		groups[b] = groups.get(b, { b: true })
		var merged: Dictionary = groups[a]
		merged.merge(groups[b])
		for member in merged:
			groups[member] = merged
	for g: Dictionary in groups.values():
		if g.size() >= PILEUP_KARTS:
			var spots: Array = knocks.filter(func(k: Dictionary) -> bool: return g.has(k.a)).map(func(k: Dictionary) -> Vector3: return k.pos)
			var far := 0.0
			for p: Vector3 in spots:
				far = maxf(far, p.distance_to(spots[0]))
			if far <= PILEUP_M:
				var where := session.track.project(spots[0] as Vector3)
				_report(["a pile-up of %d karts at %.0f s, %.0f m" % [g.size(), time, float(where.distance)]])
				return


func _on_ended(kind: String, results: Array) -> void:
	if kind == "battle":
		_battle_ended(results)
		return
	if kind != "race":
		return
	var problems: Array[String] = []
	for row: Dictionary in results:
		if row.dnf:
			problems.append("%s not classified" % (row.racer as Racer).display_name)
	_report(problems)


## Out of a loop just after a hit: counted apart.
func _hit_off_loop(r: Racer) -> void:
	if time - float(hit_at.get(r, -INF)) < HIT_RECENT_S:
		loops_entered -= 1
		loops_hit_off += 1


## A battle's end: a winner, and lives lost that add up to the hits taken.
func _battle_ended(results: Array) -> void:
	var problems: Array[String] = []
	var b := session.battle
	var lost := 0
	var taken := 0
	var dealt := 0
	for r in session.racers:
		lost += b.lives_lost(r) if rule() == "standing" else 0
		taken += b.taken(r)
		dealt += b.hits(r)
	if results.is_empty():
		problems.append("no results")
	elif rule() == "standing":
		if lost != taken:
			problems.append("%d lives lost, %d hits taken" % [lost, taken])
		if b.time_left() > 0.0 and b.standing().size() != 1:
			problems.append("ended early with %d karts in" % b.standing().size())
	if dealt > taken:
		problems.append("%d hits dealt, %d taken" % [dealt, taken])
	var w: Racer = results[0].racer if not results.is_empty() else null
	print("Battle: %.0f s, %s; winner %s (lives %d, hits %d); hits dealt %d, taken %d; out: %s" % [session.race.clock, rule(),
		w.display_name if w else "-", b.lives(w) if w else 0, b.hits(w) if w else 0, dealt, taken,
		", ".join(PackedStringArray(b._out_order.map(func(r: Racer) -> String: return r.display_name)))])
	_report(problems)


func e_items() -> bool:
	return session.event.items


func _report(problems: Array) -> void:
	if reported:
		return
	reported = true
	var karts := int(opts.karts)
	var laps := int(opts.laps)
	var out: Array[String] = []
	out.append_array(problems)
	out.append_array(stuck_events)
	var want_uses := ceili(ITEMS_PER_KART_LAP * karts * laps) if not battle() else karts
	if uses < want_uses and e_items():
		out.append("%d items used (want %d)" % [uses, want_uses])
	var skilled := session.racers.filter(func(r: Racer) -> bool: return r.driver is KartAI and (r.driver as KartAI).skill >= 50.0)
	for lap in range(1, laps + 1):
		var n := skilled.filter(func(r: Racer) -> bool: return lap in drift_boosts.get(r, [])).size()
		if skilled.size() > 0 and n * 2 < skilled.size():
			out.append("lap %d: %d of %d skilled karts drift-boosted" % [lap, n, skilled.size()])
	var stunts := session.track.kart != null and not session.track.kart.pieces.is_empty()
	var tow_limit := (1.0 if stunts else 0.2) * karts * laps if not battle() else 2.0 * karts
	if tows > tow_limit:
		out.append("%d tows (most %.1f), and %d after hits" % [tows, tow_limit, tows_after_hits])
	if loops_entered > 0 and float(loops_done) / loops_entered < 0.9 and loops_entered - loops_done > 1:
		out.append("loops: %d of %d round" % [loops_done, loops_entered])
	for e: Dictionary in session.kart.entities.list.values():
		if float(e.age) > float(e.life) + 1.0:
			out.append("a %s left out" % e.kind)
	print("Race: %.0f s simulated, %d items got, %d used, hits %s, %d tows (and %d after hits), loops %d/%d (and %d hit off), drift boosts %s" % [time, gots, uses, hits_by_kind,
		tows, tows_after_hits, loops_done, loops_entered, loops_hit_off, ", ".join(drift_boosts.keys().map(func(r: Racer) -> String: return "%s %s" % [r.display_name, drift_boosts[r]]))])
	var laps_s: Array = session.racers.map(func(r: Racer) -> float: return r.timer.best_lap).filter(func(t: float) -> bool: return t > 0.0)
	if not laps_s.is_empty():
		var mean: float = laps_s.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / laps_s.size()
		print("Laps: best %.2f s, mean %.2f s over %d karts" % [laps_s.min(), mean, laps_s.size()])
	print("Time: %.1f µs a tick in the check's own work, %d ticks" % [float(tick_us) / maxf(ticks, 1), ticks])
	if out.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in out:
			print("  " + line)
		print("FAIL")
		get_tree().quit(1)
