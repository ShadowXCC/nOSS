extends GdUnitTestSuite
## Sumo matches (D162) with four cars on generated platforms: they start on the top one, held
## until three lights go out; the top platform shrinks from the green light and a lower one only
## once a car has landed on it; touching the goo puts a car out, ghosted, timed at that moment;
## the last one not in the goo wins and the standings put the one that went in latest ahead of
## the rest; the results carry the tier reached and how long each lasted; the ram boost spends
## its charge and lunges the car forward.

var s: TrackSession
var sumo: SumoControl
var a: Racer
var b: Racer
var c: Racer
var d: Racer
var ended := []


func before() -> void:
	Settings.use_folder("user://tests/sumo_control")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _start(tiers := 2, hazard := "lava", pillar := false, drift := "drift") -> void:
	Players.clear()
	ended = []
	s = TrackSession.new()
	s.platform_id = "official.sumo.standard"
	s.event = RaceEvent.sumo(tiers, hazard)
	s.event.sumo_pillar = pillar
	s.event.sumo_drift = drift
	s.event.ai_count = 3
	s.event.ai_cars = "builtin"
	add_child(s)
	for i in 900:
		if s.racers.size() == 4 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	for r in s.racers:
		r.driver.process_mode = Node.PROCESS_MODE_DISABLED
	s.race.session_ended.connect(func(kind: String, rows: Array) -> void: ended.append([kind, rows]))
	sumo = s.sumo
	a = s.racers[0]
	b = s.racers[1]
	c = s.racers[2]
	d = s.racers[3]


func after_test() -> void:
	if s and is_instance_valid(s):
		s.queue_free()
	await get_tree().process_frame


func _running() -> void:
	for i in 120 * 6:
		if s.race.phase == RaceControl.Phase.RUNNING:
			return
		await get_tree().physics_frame


## Drops `r` into the goo, as being shoved off would.
func _goo(r: Racer) -> void:
	r.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, sumo.layout.hazard_y - 1.0, 0.0)))
	sumo._check_goo()


func test_the_arena_is_generated_with_no_track_file() -> void:
	await _start(3)
	assert_str(s.track_path).is_equal(TrackSession.DEFAULT_TRACK) # never loaded
	assert_object(sumo.layout).is_instanceof(SumoLayout)
	assert_int(sumo.layout.count()).is_equal(3)
	# Each one below is wider, so a car knocked off lands on the next (D163).
	assert_float(sumo.layout.radius_of(0)).is_less(sumo.layout.radius_of(1))
	assert_float(sumo.layout.radius_of(1)).is_less(sumo.layout.radius_of(2))
	assert_float(sumo.layout.floor_y_of(1)).is_less(sumo.layout.floor_y_of(0))
	assert_float(sumo.layout.hazard_y).is_less(sumo.layout.floor_y_of(2))


func test_cars_start_on_the_top_platform_held_until_the_lights() -> void:
	await _start()
	for r in s.racers:
		assert_bool(r.held).override_failure_message("%s held" % r.display_name).is_true()
		assert_int(sumo.layout.tier_at(r.com())).is_equal(0)
	assert_int(s.race.light_count).is_equal(RaceControl.SHORT_LIGHTS)
	await _running()
	for r in s.racers:
		assert_bool(r.held).is_false()


func test_the_top_platform_shrinks_from_the_green_light() -> void:
	await _start()
	assert_bool(sumo.layout.armed(0)).override_failure_message("armed before the green").is_false()
	var full := sumo.layout.radius_of(0)
	await _running()
	for i in 120:
		await get_tree().physics_frame
	assert_bool(sumo.layout.armed(0)).is_true()
	assert_float(sumo.layout.radius_of(0)).is_less(full)
	# Nobody has landed on the one below, so it is still its full size.
	assert_bool(sumo.layout.armed(1)).is_false()
	assert_float(sumo.layout.radius_of(1)).is_equal_approx(SumoLayout.RADII[1], 0.01)


func test_a_lower_platform_only_shrinks_once_a_car_lands_on_it() -> void:
	await _start()
	await _running()
	assert_bool(sumo.layout.armed(1)).is_false()
	# Put a car down on the second platform, at rest.
	var at := Vector3(2.0, sumo.layout.floor_y_of(1) + 0.1, 0.0)
	a.vehicle.reset_to(Transform3D(Basis.IDENTITY, at))
	for i in 20:
		await get_tree().physics_frame
	assert_bool(sumo.layout.armed(1)).override_failure_message("landing did not set it going").is_true()
	assert_str(String(sumo.armed_by.get(1, ""))).is_equal(a.display_name)


func test_the_goo_puts_a_car_out_ghosted() -> void:
	await _start()
	await _running()
	assert_bool(a.out).is_false()
	_goo(a)
	assert_bool(a.out).is_true()
	assert_bool(a.ghosted).is_true()
	assert_int(a.vehicle.kart_bits & CarState.KART_OUT).is_not_equal(0)
	assert_int(sumo.standing().size()).is_equal(3)
	# Out once: going in again changes nothing.
	_goo(a)
	assert_int(sumo.standing().size()).is_equal(3)


func test_the_last_car_not_in_the_goo_wins() -> void:
	await _start()
	await _running()
	_goo(a)
	_goo(b)
	assert_array(ended).is_empty()
	_goo(c)
	for i in 4:
		await get_tree().physics_frame
	assert_array(ended).is_not_empty()
	assert_str(String(ended[0][0])).is_equal("sumo")
	assert_object(sumo.standings()[0]).is_same(d)


## The one that went in latest is ahead of the rest: that is what settles a floor vanishing
## under the last two.
func test_out_later_ranks_ahead() -> void:
	await _start()
	await _running()
	_goo(a)
	_goo(b)
	_goo(c)
	for i in 4:
		await get_tree().physics_frame
	var order := sumo.standings()
	assert_object(order[0]).is_same(d) # still in
	assert_object(order[1]).is_same(c) # in last
	assert_object(order[2]).is_same(b)
	assert_object(order[3]).is_same(a)


## A whole ring going at once drops two cars in on the same tick; the one less far under the
## surface got there later, so it ranks ahead (D167).
func test_two_cars_in_on_one_tick_are_told_apart_by_depth() -> void:
	await _start()
	await _running()
	_goo(a)
	_goo(b)
	# Both are under the surface on this tick, but c is deeper, so d held on longer.
	c.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, sumo.layout.hazard_y - 8.0, 0.0)))
	d.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(6.0, sumo.layout.hazard_y - 2.0, 0.0)))
	sumo._check_goo()
	assert_bool(c.out).is_true()
	assert_bool(d.out).is_true()
	assert_float(sumo.out_depth(c)).is_greater(sumo.out_depth(d))
	var order := sumo.standings()
	assert_object(order[0]).override_failure_message("the shallower car should rank ahead").is_same(d)
	assert_object(order[1]).is_same(c)


func test_results_carry_the_tier_and_how_long_each_lasted() -> void:
	await _start()
	await _running()
	for i in 60:
		await get_tree().physics_frame
	_goo(a)
	_goo(b)
	_goo(c)
	for i in 4:
		await get_tree().physics_frame
	var rows: Array = ended[0][1]
	assert_int(rows.size()).is_equal(4)
	var won: Dictionary = rows[0]
	assert_bool(won.out).is_false()
	assert_int(int(won.tier)).is_equal(1) # it never left the top platform
	var first_in: Dictionary = rows[3]
	assert_bool(first_in.out).is_true()
	assert_float(float(first_in.lasted)).is_greater(0.0)


## No Reset in sumo (D219): the key does nothing, so a car on its roof waits for its own righting.
func test_a_reset_request_does_nothing_in_sumo() -> void:
	await _start()
	await _running()
	var at := Vector3(4.0, sumo.layout.floor_y_of(0) + 1.5, 0.0)
	a.vehicle.reset_to(Transform3D(Basis(Vector3.FORWARD, PI), at))
	for i in 30:
		await get_tree().physics_frame
	var was := a.vehicle.global_position
	(a as SessionPlayer).controller.reset_requested.emit()
	await get_tree().physics_frame
	assert_bool(a.out).is_false()
	assert_float(a.vehicle.global_basis.y.y).override_failure_message("it was set upright").is_less(0.0)
	assert_float(a.vehicle.global_position.distance_to(was)).is_less(0.5)


func test_the_pause_menu_has_no_reset_row() -> void:
	await _start()
	await _running()
	var p := a as SessionPlayer
	s._open_pause(p)
	var menu := p.overlay as PauseMenu
	var texts: Array = menu._buttons.filter(func(b: Control) -> bool: return b is Button).map(func(b: Button) -> String: return b.text)
	menu.resumed.emit()
	assert_bool(texts.has("Resume")).is_true()
	assert_bool(texts.has("Reset car")).is_false()


## Only the safety net below the whole pit calls reset_car() now, and off the platforms there is
## nowhere to put a car back: it goes in.
func test_nothing_tows_a_car_that_was_shoved_off() -> void:
	await _start()
	await _running()
	a.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, sumo.layout.hazard_y + 2.0, 0.0)))
	for i in 2:
		await get_tree().physics_frame
	a.reset_car()
	assert_bool(a.out).is_true()


func test_the_ram_lunges_the_car_and_spends_its_charge() -> void:
	await _start()
	await _running()
	a.vehicle.linear_velocity = a.vehicle.global_basis.z * 8.0
	for i in 2:
		await get_tree().physics_frame
	assert_float(sumo.charge(a)).is_equal_approx(1.0, 0.01)
	assert_bool(sumo.ram(a)).is_true()
	assert_float(sumo.charge(a)).is_less(0.05)
	# Not again until it has charged back up.
	assert_bool(sumo.ram(a)).is_false()


func test_a_car_too_slow_to_shove_cannot_ram() -> void:
	await _start()
	await _running()
	a.vehicle.linear_velocity = Vector3.ZERO
	for i in 2:
		await get_tree().physics_frame
	assert_bool(sumo.ram(a)).is_false()
	assert_float(sumo.charge(a)).is_equal_approx(1.0, 0.01)


func test_a_sumo_match_hides_the_race_hud_and_flies_no_flags() -> void:
	await _start()
	await _running()
	for id in ["timing", "delta", "position", "standings", "flags"]:
		assert_bool(id in SumoControl.HUD_HIDDEN).override_failure_message(id).is_true()
	for r in s.racers:
		assert_str(r.flag).is_equal("")
		assert_bool(r.laps).is_false()
## Launches `a` off the edge of the top platform, cut to `top_r`, going `out` m/s outward and
## `round` m/s round the edge, pitching at `pitch` rad/s (and facing in, rolling backwards, with
## `backwards`); brakes once it lands (a driver would), and reports the fall: the tier it ends on,
## its rebounds and how soon it is planted (D219).
func _fall(top_r: float, out: float, round := 0.0, pitch := 0.0, settle_s := 3.0, backwards := false) -> Dictionary:
	var lay := sumo.layout
	lay.secs = 1e6 # nothing shrinks under the test
	lay.tiers[0].start = top_r
	lay.tiers[0].radius = top_r
	sumo.builder.refresh()
	for r: Racer in [b, c, d]:
		r.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(-4.0 + 4.0 * [b, c, d].find(r), lay.floor_y_of(0) + 0.1, -6.0)))
	var d0 := Vector3.RIGHT
	var face := (-d0 if backwards else d0) if round == 0.0 else Vector3.BACK
	var basis := Basis(Vector3.UP.cross(face), Vector3.UP, face)
	var v := a.vehicle
	v.reset_to(Transform3D(basis, d0 * (top_r - 0.2) + Vector3.UP * (lay.floor_y_of(0) + 0.15)), d0 * out + Vector3.BACK * round)
	v.angular_velocity = basis.x * pitch
	v.throttle = 0.0
	v.steer = 0.0
	var landed := -1.0
	var t := 0.0
	var rises: Array[float] = []
	var lift := INF
	var planted := 0
	var planted_at := -1.0
	var travel := float(v.platform.suspension.front.travel_m)
	while t < 8.0:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var com := a.com()
		var wheels := 0
		for w: Dictionary in v.sim.get_telemetry().wheels:
			wheels += 1 if w.contact else 0
		if landed < 0.0:
			if wheels > 0 and com.y < lay.floor_y_of(1) + 2.0:
				landed = t
			continue
		if t - landed > 0.25:
			var moving := absf(v.speed()) > 0.8 # at a stop the brake would reverse
			v.brake = 1.0 if moving else 0.0
			v.handbrake = 0.0 if moving else 1.0
		# A rebound: off every wheel, as high as it rises.
		if wheels == 0 and v.wall_impulse == 0.0:
			lift = minf(lift, com.y)
			if rises.size() == 0 or rises[-1] < 0.0:
				rises.append(0.0)
			rises[-1] = maxf(rises[-1], com.y - lift)
		elif lift < INF:
			lift = INF
			rises[-1] = rises[-1] if rises[-1] > 0.02 else -1.0
		if wheels == 4 and absf(v.linear_velocity.y) < 0.3:
			planted += 1
			if planted == 12 and planted_at < 0.0:
				planted_at = t - landed - 11.0 / Engine.physics_ticks_per_second
		else:
			planted = 0
		if planted_at >= 0.0 and t - landed > settle_s:
			break
	return { "landed": landed >= 0.0, "tier": lay.standing_on(a.com()), "rises": rises.filter(func(h: float) -> bool: return h > 0.02),
		"planted": planted_at, "travel": travel }


func _check_caught(f: Dictionary, what: String) -> void:
	assert_bool(f.landed).override_failure_message("%s: never landed" % what).is_true()
	assert_int(int(f.tier)).override_failure_message("%s: ended on tier %d" % [what, int(f.tier) + 1]).is_equal(1)
	assert_bool(a.out).is_false()
	var rises: Array = f.rises
	assert_int(rises.size()).override_failure_message("%s: rebounds %s" % [what, rises]).is_less_equal(3)
	for i in rises.size():
		assert_float(float(rises[i])).override_failure_message("%s: rebounds %s" % [what, rises]).is_less(0.4)
		if i > 0:
			assert_float(float(rises[i])).override_failure_message("%s: rebounds %s" % [what, rises]).is_less_equal(float(rises[i - 1]))
	assert_float(float(f.planted)).override_failure_message("%s: planted after %.2f s" % [what, float(f.planted)]).is_between(0.0, 1.5)


## One fall, one tier (D219): the platform below catches a car shoved off the one above. A hard
## hit plus a ram off a shrunken top platform, one that leaves it nose down, and one going round
## when the ring goes from under it: each lands on the next tier and stays there.
func test_the_platform_below_catches_a_hard_shove() -> void:
	await _start(3)
	await _running()
	_check_caught(await _fall(16.0, 9.0), "hit plus ram")


func test_the_platform_below_catches_a_car_falling_nose_down() -> void:
	await _start(3)
	await _running()
	_check_caught(await _fall(16.0, 7.0, 0.0, -2.0), "nose down")


func test_the_platform_below_catches_a_car_the_ring_went_from_under() -> void:
	await _start(3)
	await _running()
	_check_caught(await _fall(24.0, 0.3, 8.0), "ring went")


## A gentle roll off the edge (backwards, as a car shoved off nose first would) still lands, and
## the car drives away as it would anywhere.
func test_a_car_rolling_off_lands_and_drives_away() -> void:
	await _start(3)
	await _running()
	var f := await _fall(24.0, 3.0, 0.0, 0.0, 1.0, true)
	_check_caught(f, "roll off")
	var v := a.vehicle
	v.handbrake = 0.0
	v.brake = 0.0
	v.throttle = 1.0
	for i in 120 * 2:
		await get_tree().physics_frame
	assert_float(absf(v.speed())).override_failure_message("speed %.1f" % v.speed()).is_greater(4.0)
	assert_int(sumo.layout.standing_on(a.com())).is_equal(1)


## The drift setting (D181, D220). The Sumo class's own numbers are already Drift -- the kart
## layer's slide with the boost zeroed -- so this is what Off does to them.
func test_the_drift_setting_leaves_the_slide_and_takes_the_boost() -> void:
	await _start(1, "lava", false, "drift")
	assert_bool(s.drift_allowed).is_true()
	assert_bool(a.vehicle.drift_allowed).is_true()
	for seconds: float in (s.arcade.drift.boost_s as Array):
		assert_float(seconds).override_failure_message("plain Drift should give no boost").is_equal(0.0)


## Drift + boost is gone: Drift and Off are left, and an event saved with the boost (a playlist,
## an older server) reads as Drift.
func test_the_drift_setting_is_drift_or_off() -> void:
	assert_array(RaceEvent.CHOICES.sumo_drift).contains_exactly_in_any_order(["drift", "off"])
	assert_array(EventForms.DRIFTS.map(func(d: Array) -> String: return d[0])).contains_exactly_in_any_order(["drift", "off"])
	var e := RaceEvent.from_dict(RaceEvent.sumo().to_dict().merged({ "sumo_drift": "boost" }, true))
	assert_str(e.sumo_drift).is_equal("drift")


## Mean yaw rate (rad/s) over 0.8 s of full steer at 15 km/h, drifting or not; and whether the
## drift took.
func _turn(drifting: bool) -> Array:
	var v := a.vehicle
	v.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, sumo.layout.floor_y_of(0) + 0.05, -8.0)), Vector3(0, 0, 15.0 / 3.6))
	for i in 20:
		v.throttle = clampf((15.0 / 3.6 - v.speed()) * 0.8 + 0.3, 0.0, 1.0)
		await get_tree().physics_frame
	v.steer = 1.0
	v.drift = drifting
	var yaw := 0.0
	var took := false
	for i in 96:
		v.throttle = clampf((15.0 / 3.6 - v.speed()) * 0.8 + 0.3, 0.0, 1.0)
		await get_tree().physics_frame
		yaw += absf(v.angular_velocity.y) / 96.0
		took = took or v.drifting()
	v.drift = false
	v.steer = 0.0
	v.throttle = 0.0
	return [yaw, took]


## A quick pivot from 15 km/h (D220): the drift starts there, and turns far faster than the steering
## alone does.
func test_the_drift_pivots_from_15_kmh() -> void:
	await _start()
	await _running()
	var plain := await _turn(false)
	var drift := await _turn(true)
	assert_bool(drift[1]).override_failure_message("the drift never started").is_true()
	assert_float(float(drift[0])).override_failure_message("yaw %.2f drifting, %.2f plain" % [drift[0], plain[0]]).is_greater(3.0 * float(plain[0]))


## Bot `b`, at its best, going 8 m/s at `at` heading +z with `a` 7 m behind it and the other two
## parked well ahead: whether it pivot-drifts round within 0.75 s.
func _bot_pivots(at: Vector3) -> bool:
	var lay := sumo.layout
	lay.secs = 1e6
	var y := lay.floor_y_of(0) + 0.05
	(b.driver as SumoAI).skill = 100.0
	b.driver.process_mode = Node.PROCESS_MODE_INHERIT
	b.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(at.x, y, at.z)), Vector3(0, 0, 8.0))
	a.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(at.x, y, at.z - 7.0)))
	c.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(-at.x - 3.0, y, at.z + 18.0)))
	d.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(-at.x + 3.0, y, at.z + 18.0)))
	for i in 90:
		await get_tree().physics_frame
		if b.vehicle.drifting():
			return true
	return false


## Bots drift too (D220): one with its target behind it swings round in a pivot; one near the edge
## heads in instead.
func test_a_bot_pivots_round_to_a_car_behind_it() -> void:
	await _start()
	await _running()
	assert_bool(await _bot_pivots(Vector3(0.0, 0.0, -2.0))).override_failure_message("no drift").is_true()


func test_a_bot_near_the_edge_does_not_drift() -> void:
	await _start()
	await _running()
	assert_bool(await _bot_pivots(Vector3(17.0, 0.0, -2.0))).override_failure_message("drifted by the edge").is_false()


func test_a_bot_does_not_drift_with_the_drift_off() -> void:
	await _start(2, "lava", false, "off")
	await _running()
	assert_bool(await _bot_pivots(Vector3(0.0, 0.0, -2.0))).is_false()


func test_the_drift_setting_can_take_the_button_away() -> void:
	await _start(1, "lava", false, "off")
	# The layer stays on -- the shove, the bounce and the righting are the class's -- but no car
	# gets the drift button, and the handbrake is left alone (VehicleController).
	assert_bool(s.arcade.is_empty()).is_false()
	assert_bool(s.drift_allowed).is_false()
	for r in s.racers:
		assert_bool(r.vehicle.drift_allowed).override_failure_message("%s still had the drift" % r.display_name).is_false()
