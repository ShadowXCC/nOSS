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


func _start(tiers := 2, hazard := "lava", pillar := false) -> void:
	Players.clear()
	ended = []
	s = TrackSession.new()
	s.platform_id = "official.sumo.standard"
	s.event = RaceEvent.sumo(tiers, hazard)
	s.event.sumo_pillar = pillar
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


func test_a_reset_on_a_platform_sets_the_car_down_again() -> void:
	await _start()
	await _running()
	# Still on a platform (stuck, or on its roof): put it back, don't put it out.
	a.reset_car()
	assert_bool(a.out).is_false()
	assert_int(sumo.layout.tier_at(a.com())).is_equal(0)


func test_nothing_tows_a_car_that_was_shoved_off() -> void:
	await _start()
	await _running()
	# Off the platforms there is nowhere to put it back: a reset puts it in the goo.
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
