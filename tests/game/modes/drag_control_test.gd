extends GdUnitTestSuite
## Drag passes (D168-D174) with four cars on a generated strip: two run at a time and the rest
## wait parked; the burnout heats the tires, the tree counts down and leaving early is a red
## light; shifts are graded against the mode's own needle, perfect ones chain and missed ones
## bog; over-revving blows an engine but top gear costs nothing; the centreline loses a pass; the
## ladder draws pairs, hands out byes and eliminates one car a pass; and the results carry the
## round, the reaction and the time.

var s: TrackSession
var drag: DragControl
var a: Racer
var b: Racer
var c: Racer
var d: Racer
var ended := []


func before() -> void:
	Settings.use_folder("user://tests/drag_control")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _start(length := 402, boost := 1) -> void:
	Players.clear()
	ended = []
	s = TrackSession.new()
	s.platform_id = "official.drag.street"
	s.event = RaceEvent.drag(length, boost)
	s.event.ai_count = 3
	s.event.ai_cars = "builtin"
	s.drag_seed = 11
	add_child(s)
	for i in 900:
		if s.racers.size() == 4 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	for r in s.racers:
		r.driver.process_mode = Node.PROCESS_MODE_DISABLED
	s.race.session_ended.connect(func(kind: String, rows: Array) -> void: ended.append([kind, rows]))
	drag = s.drag
	# These tests are about what a pass does, not about pressing Ready on the card that holds it
	# for its drivers (D177); the tests below that are about the card turn the gate back on.
	drag.ready_gate = false
	a = s.racers[0]
	b = s.racers[1]
	c = s.racers[2]
	d = s.racers[3]


func after_test() -> void:
	if s and is_instance_valid(s):
		s.queue_free()
	await get_tree().process_frame


## Waits until the session is running and the first pass has set itself up.
func _pass_set_up() -> void:
	for i in 120 * 6:
		if s.race.phase == RaceControl.Phase.RUNNING and not drag.cars.is_empty():
			return
		await get_tree().physics_frame


## Hurries the pass along to `target`: whatever the phase it is in is waiting for, it has waited
## long enough. It stops before forcing the phase it was asked for.
func _to_phase(target: int) -> void:
	await _pass_set_up()
	for i in 120 * 20:
		if drag.phase == target:
			return
		drag.phase_time = 99.0
		await get_tree().physics_frame


## Through the burnout, the staging and the tree, to the green.
func _to_green() -> void:
	await _to_phase(DragControl.Phase.RUN)


func test_the_strip_is_generated_with_no_track_file() -> void:
	await _start(805)
	assert_str(s.track_path).is_equal(TrackSession.DEFAULT_TRACK) # never loaded
	assert_object(drag.layout).is_instanceof(DragLayout)
	assert_float(drag.layout.length_m).is_equal_approx(805.0, 0.01)
	# The shutdown is as long again as the strip, within its bounds, and ends in sand.
	assert_float(drag.layout.shutdown_m).is_equal_approx(DragLayout.SHUTDOWN_MAX_M, 0.01)
	assert_float(drag.layout.trap_z()).is_less(drag.layout.end_z())
	# Two lanes either side of the centreline.
	assert_float(drag.layout.lane_x(0)).is_less(0.0)
	assert_float(drag.layout.lane_x(1)).is_greater(0.0)


func test_two_cars_run_and_the_rest_wait_parked() -> void:
	await _start()
	await _pass_set_up()
	assert_int(drag.cars.size()).is_equal(2)
	var waiting := s.racers.filter(func(r: Racer) -> bool: return r.parked)
	assert_int(waiting.size()).is_equal(2)
	for r: Racer in waiting:
		assert_bool(r.vehicle.visible).override_failure_message("%s still shown" % r.display_name).is_false()
		assert_bool(r.waiting).is_true()
	# The two in the pass are in their own lanes, facing down the strip.
	var lanes := drag.cars.map(func(r: Racer) -> int: return int(drag.run_of(r).lane))
	assert_array(lanes).contains_exactly_in_any_order([0, 1])


func test_the_tree_counts_down_and_holds_the_cars() -> void:
	await _start()
	await _pass_set_up()
	# No lights of RaceControl's own down a strip: the tree is the countdown (D169).
	assert_int(s.race.light_count).is_equal(0)
	# A burnout needs the car loose; the staging takes it back and holds it.
	assert_int(drag.phase).is_equal(DragControl.Phase.BURNOUT)
	await _to_phase(DragControl.Phase.TREE)
	for r: Racer in drag.cars:
		assert_bool(r.held).override_failure_message("%s loose before the green" % r.display_name).is_true()
	await _to_green()
	assert_int(drag.phase).is_equal(DragControl.Phase.RUN)
	for r: Racer in drag.cars:
		assert_bool(r.held).is_false()


func test_the_burnout_heats_the_tires_and_can_be_overcooked() -> void:
	await _start()
	await _pass_set_up()
	assert_int(drag.phase).is_equal(DragControl.Phase.BURNOUT)
	# Nothing, the best heat, and far too much.
	assert_float(DragControl._heat_grip(0.0)).is_equal_approx(0.0, 0.001)
	assert_float(DragControl._heat_grip(DragControl.HEAT_BEST_S)).is_equal_approx(1.0, 0.001)
	assert_float(DragControl._heat_grip(DragControl.HEAT_MAX_S * 2.0)).is_less(0.0)
	# Throttle against the brake is what heats them.
	var r: Racer = drag.cars[0]
	r.vehicle.throttle = 1.0
	r.vehicle.brake = 1.0
	var before := float(drag.run_of(r).heat)
	for i in 30:
		await get_tree().physics_frame
	assert_float(float(drag.run_of(r).heat)).is_greater(before)


func test_leaving_before_the_green_is_a_red_light() -> void:
	await _start()
	await _to_phase(DragControl.Phase.TREE)
	var r: Racer = drag.cars[0]
	drag.launch(r)
	assert_str(String(drag.run_of(r).foul)).is_equal("red")
	assert_bool(bool(drag.run_of(r).done)).is_true()


func test_the_reaction_is_timed_from_the_green() -> void:
	await _start()
	await _to_green()
	var r: Racer = drag.cars[0]
	drag.phase_time = 0.21
	drag.launch(r)
	assert_float(float(drag.run_of(r).reaction)).is_equal_approx(0.21, 0.001)
	assert_str(String(drag.run_of(r).foul)).is_empty()


func test_a_perfect_shift_surges_and_a_missed_one_bogs() -> void:
	await _start()
	await _to_green()
	var r: Racer = drag.cars[0]
	var state: Dictionary = drag.run_of(r)
	var graded := []
	drag.shift_graded.connect(func(_r: Racer, grade: String, _gear: int) -> void: graded.append(grade))
	# In the window: perfect, which chains and surges.
	await _shift_at(r, state, float(DragControl.WINDOWS[0][0]))
	assert_array(graded).contains_exactly(["perfect"])
	assert_int(int(state.chain)).is_equal(1)
	assert_float(float(state.surge)).is_greater(0.0)
	# A shift puts the needle back near the bottom of the next gear.
	assert_float(float(state.needle)).is_less_equal(DragControl.NEEDLE_AFTER_SHIFT + 0.01)
	# Nowhere near it: missed, which bogs and breaks the chain.
	await _shift_at(r, state, 0.1)
	assert_array(graded).contains_exactly(["perfect", "miss"])
	assert_int(int(state.chain)).is_equal(0)
	assert_float(float(state.bog)).is_greater(0.0)


## Shifts up with the needle put at `needle`, and waits for DragControl to see it and grade it.
## The sim starts a shift during its own step, so the grade lands on the tick after the call.
func _shift_at(r: Racer, state: Dictionary, needle: float) -> void:
	for i in 60:
		if not r.vehicle.sim.is_shifting():
			break
		await get_tree().physics_frame
	state.needle = needle
	r.vehicle.sim.shift(1)
	for i in 20:
		await get_tree().physics_frame
		if bool(state.shifting):
			return


func test_over_revving_blows_the_engine_but_top_gear_is_safe() -> void:
	await _start()
	await _to_green()
	var r: Racer = drag.cars[0]
	var state: Dictionary = drag.run_of(r)
	r.vehicle.sim.select_gear(1)
	r.vehicle.throttle = 1.0
	state.needle = 1.0
	# Long enough past the end of the needle and the engine lets go.
	for i in 300:
		drag._advance_needle(r, state, 1.0 / 60.0)
		if bool(state.blown):
			break
	assert_bool(bool(state.blown)).override_failure_message("never blew up").is_true()
	# In top gear there is nothing to shift into, so sitting there costs nothing.
	var top: int = (r.vehicle.platform.gearbox.ratios as Array).size()
	r.vehicle.sim.select_gear(top)
	for i in 60:
		if r.vehicle.sim.get_gear() == top:
			break
		await get_tree().physics_frame
	assert_int(r.vehicle.sim.get_gear()).is_equal(top)
	state.blown = false
	state.strain = 0.0
	state.needle = 1.0
	for i in 300:
		drag._advance_needle(r, state, 1.0 / 60.0)
	assert_bool(bool(state.blown)).override_failure_message("top gear blew up").is_false()


func test_crossing_the_centreline_loses_the_pass() -> void:
	await _start()
	await _to_green()
	var r: Racer = drag.cars[0]
	var lane := int(drag.run_of(r).lane)
	# Over the middle, into the other lane.
	var over := -drag.layout.lane_x(lane)
	r.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(over, drag.layout.floor_y, 50.0)))
	for i in 10:
		await get_tree().physics_frame
	assert_str(String(drag.run_of(r).foul)).is_equal("centreline")


func test_a_boost_spends_one_charge_and_only_while_running() -> void:
	await _start(402, 2)
	await _pass_set_up()
	var r: Racer = drag.cars[0]
	assert_int(int(drag.run_of(r).boosts)).is_equal(2)
	# Not before the green.
	assert_bool(drag.use_boost(r)).is_false()
	await _to_green()
	assert_bool(drag.use_boost(r)).is_true()
	assert_int(int(drag.run_of(r).boosts)).is_equal(1)
	assert_float(float(drag.run_of(r).boost)).is_greater(0.0)
	assert_bool(drag.use_boost(r)).is_true()
	assert_int(int(drag.run_of(r).boosts)).is_equal(0)
	assert_bool(drag.use_boost(r)).is_false()


func test_boost_can_be_turned_off_for_everyone() -> void:
	await _start(402, 0)
	await _to_green()
	var r: Racer = drag.cars[0]
	assert_int(int(drag.run_of(r).boosts)).is_equal(0)
	assert_bool(drag.use_boost(r)).is_false()


func test_through_the_lights_times_the_pass_from_the_launch() -> void:
	await _start(201)
	await _to_green()
	var r: Racer = drag.cars[0]
	var state: Dictionary = drag.run_of(r)
	drag.phase_time = 0.2
	drag.launch(r)
	drag.phase_time = 8.2
	r.vehicle.reset_to(Transform3D(Basis.IDENTITY, Vector3(drag.layout.lane_x(int(state.lane)), drag.layout.floor_y, 210.0)))
	for i in 5:
		await get_tree().physics_frame
	# The reaction is its own number; the time is from the launch, and the crossing settles who won.
	assert_float(float(state.reaction)).is_equal_approx(0.2, 0.001)
	assert_float(float(state.et)).is_greater(0.0)
	assert_float(float(state.et)).is_less(float(state.crossed))
	assert_bool(bool(state.done)).is_true()
	assert_dict(drag.row(r)).contains_keys(["reaction", "et", "trap", "round"])


func test_the_ladder_draws_pairs_and_byes() -> void:
	var ladder := DragLadder.new()
	var field: Array[Racer] = []
	for i in 5:
		var r := Racer.new()
		r.display_name = "C%d" % i
		r.number = i
		field.append(r)
	ladder.seed_field(field, 42)
	# Five cars: three byes, so the round after the first is a clean four.
	assert_int(ladder.pairs.size()).is_equal(4)
	var byes := ladder.pairs.filter(func(p: Array) -> bool: return p[1] == null)
	assert_int(byes.size()).is_equal(3)
	# A bye does not run a pass; the first real pair comes up.
	var first := ladder.current()
	assert_int(first.size()).is_equal(2)
	# Four passes eliminate four of the five.
	var guard := 0
	while not ladder.finished() and guard < 20:
		guard += 1
		var cars := ladder.current()
		if cars.is_empty():
			break
		ladder.record(cars, cars[0], {})
	assert_bool(ladder.finished()).is_true()
	assert_int(ladder.passes.size()).is_equal(4)
	assert_int(ladder.out_in.size()).is_equal(4)
	assert_object(ladder.winner).is_not_null()
	# The winner leads the standings and the car that went out first is last.
	var order := ladder.standings(field)
	assert_object(order[0]).is_equal(ladder.winner)


func test_one_car_runs_a_shakedown_and_takes_the_match() -> void:
	var ladder := DragLadder.new()
	var only := Racer.new()
	only.display_name = "Solo"
	var field: Array[Racer] = [only]
	ladder.seed_field(field, 1)
	var cars := ladder.current()
	assert_array(cars).contains_exactly([only])
	ladder.record(cars, only, {})
	assert_bool(ladder.finished()).is_true()
	assert_object(ladder.winner).is_equal(only)


func test_a_match_ends_with_the_ladders_winner_and_its_results() -> void:
	await _start()
	await _pass_set_up()
	# Walk the ladder through by hand: the first car of each pass takes it.
	var guard := 0
	while not drag.ended and guard < 20:
		guard += 1
		var cars := drag.cars.duplicate()
		if cars.is_empty():
			break
		for r: Racer in cars:
			var state: Dictionary = drag.run_of(r)
			state.done = true
			state.crossed = 9.0 + (0.0 if r == cars[0] else 0.5)
			state.et = float(state.crossed)
		drag._to(DragControl.Phase.SETTLE)
		drag.phase_time = DragControl.SETTLE_S + 1.0
		for i in 4:
			await get_tree().physics_frame
	assert_bool(drag.ended).is_true()
	assert_object(drag.ladder.winner).is_not_null()
	assert_int(drag.passes_run).is_equal(3)
	assert_int(ended.size()).is_equal(1)
	var rows: Array = ended[0][1]
	assert_int(rows.size()).is_equal(4)
	assert_object(rows[0].racer).is_equal(drag.ladder.winner)
	assert_int(int(rows[0].round)).is_greater(0)


func test_no_automatic_gearbox_is_allowed_here() -> void:
	await _start()
	var mode := GameModes.mode_for("official.drag.street")
	assert_array(mode.assists.allowed).not_contains(["auto_gearbox"])
	# Nor the assists that drive the car but never shift it.
	assert_array(mode.assists.allowed).not_contains(["autodrive", "auto_throttle", "brake_assist"])
	# A clutch is still allowed, so a pad or keyboard player can drive at all.
	assert_array(mode.assists.allowed).contains(["auto_clutch"])
	var on := AssistRules.effective(null, s.racers[0].vehicle.platform, mode, false, false)
	assert_bool(bool(on.auto_gearbox)).override_failure_message("the automatic came on anyway").is_false()
	assert_bool(bool(on.auto_clutch)).is_true()


func test_the_hud_hides_what_a_strip_has_none_of() -> void:
	await _start()
	assert_array(DragControl.HUD_HIDDEN).contains(["timing", "position", "standings", "flags"])


## The pairs as they stand, by name, to see a restart draw the same ones again.
func _pair_names() -> Array:
	return drag.ladder.pairs.map(func(pair: Array) -> String:
		return "%s/%s" % [pair[0].display_name if pair[0] else "-", pair[1].display_name if pair[1] else "-"])


func test_a_pass_waits_for_its_drivers_to_lock_in() -> void:
	await _start()
	await _pass_set_up()
	# Back to the top of the ladder with the cards on and the player drawn into the first pair.
	drag.ready_gate = true
	drag.reset()
	drag.ladder.pairs = [[a, b], [c, d]]
	drag.ladder.pair_index = 0
	assert_bool(a.is_human).override_failure_message("the first racer is meant to be the player").is_true()
	for i in 120:
		if not drag.armed.is_empty():
			break
		await get_tree().physics_frame
	# The pair is drawn and waiting, but no pass sets up until the driver says they are ready.
	assert_bool(a in drag.armed and b in drag.armed).is_true()
	assert_array(drag.cars).is_empty()
	assert_int(drag.phase).is_equal(DragControl.Phase.IDLE)
	assert_bool(drag.needs_lock_in(a)).is_true()
	assert_bool(drag.needs_lock_in(b)).override_failure_message("a bot is never asked").is_false()
	drag.lock_in(a)
	for i in 10:
		await get_tree().physics_frame
	assert_bool(a in drag.cars and b in drag.cars).is_true()
	assert_array(drag.armed).is_empty()


func test_only_a_pass_of_bots_can_be_hurried_along() -> void:
	await _start()
	await _pass_set_up()
	# A pass with a player in it is the game, not something to skip.
	drag.reset()
	drag.ladder.pairs = [[a, b], [c, d]]
	drag.ladder.pair_index = 0
	await _pass_set_up()
	assert_bool(drag.can_skip()).is_false()
	drag.skip(true)
	assert_bool(drag.skipping).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.01)
	# Two bots: it runs faster, at the same tick rate, so the pass is the sim's own either way.
	drag.reset()
	drag.ladder.pairs = [[c, d]]
	drag.ladder.pair_index = 0
	await _pass_set_up()
	assert_bool(drag.can_skip()).is_true()
	drag.skip(true)
	assert_bool(drag.skipping).is_true()
	assert_float(Engine.time_scale).is_equal_approx(DragControl.SKIP_SPEED, 0.01)
	assert_int(Engine.physics_ticks_per_second).is_equal(TrackSession.PHYSICS_HZ)
	# The clock comes back when the pass is over.
	for r: Racer in drag.cars:
		var state: Dictionary = drag.run_of(r)
		state.done = true
		state.crossed = 9.0
		state.et = 9.0
	drag._to(DragControl.Phase.SETTLE)
	drag.phase_time = DragControl.SETTLE_S + 1.0
	for i in 6:
		await get_tree().physics_frame
	assert_bool(drag.skipping).is_false()
	assert_float(Engine.time_scale).is_equal_approx(1.0, 0.01)


func test_a_restart_runs_the_same_ladder_and_puts_the_waiting_cars_away_again() -> void:
	await _start()
	await _pass_set_up()
	# With no seed set the draw is random, so the one it used is kept for a restart (D179).
	drag.drag_seed = 0
	drag._drawn_seed = 0
	drag.reset()
	var drawn := _pair_names()
	s.race.restart_session()
	await _pass_set_up()
	assert_array(_pair_names()).override_failure_message("the restart drew a different ladder").is_equal(drawn)
	# The cars that were parked before the restart are parked again, not left on the strip: the
	# flag has to be cleared, because _park takes a car that still carries it for put away.
	var waiting := s.racers.filter(func(r: Racer) -> bool: return r not in drag.cars)
	assert_array(waiting).is_not_empty()
	for r: Racer in waiting:
		assert_bool(r.parked).is_true()
		assert_bool(r.vehicle.visible).override_failure_message("%s left standing on the strip" % r.display_name).is_false()
func test_the_pair_being_waited_on_goes_over_the_wire() -> void:
	await _start()
	await _pass_set_up()
	# The record itself: one a car, the lane in its value (DragNet, protocol 9).
	var net := DragNet.new()
	var rec := net._record(DragNet.Ev.ARM, 7, 1.0)
	assert_int(rec.size()).is_equal(DragNet.RECORD)
	assert_int(rec[0]).is_equal(DragNet.Ev.ARM)
	assert_int(rec.decode_u16(1)).is_equal(7)
	assert_float(rec.decode_float(3)).is_equal_approx(1.0, 0.001)
	assert_int(net._record(DragNet.Ev.READY, 7, 0.0)[0]).is_equal(DragNet.Ev.READY)
	net.free()
	# A client takes the pair from it and puts its own driver's card up.
	drag.net_arm([a, b])
	assert_bool(drag.needs_lock_in(a)).is_true()
	assert_bool(drag.needs_lock_in(b)).is_false() # a bot is nobody's card
	# The server takes the client's word for it.
	drag.take_net_ready(a)
	assert_bool(drag.needs_lock_in(a)).is_false()
