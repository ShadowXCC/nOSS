extends GdUnitTestSuite
## The police up close (D192), on states alone: a PIT lines up on the target's rear wheels, turns
## in towards it, then backs off; a blocker never slows below its floor; a tail at level 1 keeps
## off; a ram steers towards the target (the old one steered away).

const HALF := Vector2(2.3, 0.95)


## A car at `pos` going +z at `speed`.
func _car(pos: Vector3, speed: float) -> Dictionary:
	return { "pos": pos, "fwd": Vector3(0, 0, 1), "vel": Vector3(0, 0, speed), "speed": speed, "half": HALF }


func test_a_pit_lines_up_then_turns_in_then_backs_off() -> void:
	var b := PoliceBrain.new()
	b.level = 4
	b.role = "pit"
	b.side = 1.0 # from the target's left (+x, going +z)
	var target := _car(Vector3.ZERO, 30.0)
	# Well behind: it closes up on the left, not turning in yet.
	var c := b.decide(_car(Vector3(2.0, 0, -15.0), 30.0), target, 1.0 / 120.0)
	assert_int(b.pit).is_equal(PoliceBrain.Pit.ALIGN)
	assert_float(b.last_want).is_greater(30.0)
	# Lined up: its nose by the target's rear wheels, alongside on the left, the same speed.
	var nose := -HALF.x * 0.6 - HALF.x * 0.6
	var beside := HALF.y * 2.0 + 0.3
	c = b.decide(_car(Vector3(beside, 0, nose), 30.0), target, 1.0 / 120.0)
	assert_int(b.pit).is_equal(PoliceBrain.Pit.TURN)
	# Turning in: steering right, into the target (+ is right).
	c = b.decide(_car(Vector3(beside, 0, nose), 30.0), target, 1.0 / 120.0)
	assert_float(float(c.steer)).is_greater(0.3)
	# Then it backs off, and later lines up again.
	for i in int(PoliceBrain.PIT_TURN_S * 120.0) + 2:
		b.decide(_car(Vector3(beside, 0, nose), 30.0), target, 1.0 / 120.0)
	assert_int(b.pit).is_equal(PoliceBrain.Pit.BACK_OFF)
	assert_float(b.last_want).is_less(30.0)
	for i in int(PoliceBrain.PIT_BACK_S * 120.0) + 2:
		b.decide(_car(Vector3(beside, 0, -20.0), 27.0), target, 1.0 / 120.0)
	assert_int(b.pit).is_equal(PoliceBrain.Pit.ALIGN)


func test_from_the_right_a_pit_turns_left() -> void:
	var b := PoliceBrain.new()
	b.level = 5
	b.role = "pit"
	b.side = -1.0
	var nose := -HALF.x * 1.2
	var beside := HALF.y * 2.0 + 0.3
	var target := _car(Vector3.ZERO, 25.0)
	b.decide(_car(Vector3(-beside, 0, nose), 25.0), target, 1.0 / 120.0)
	var c := b.decide(_car(Vector3(-beside, 0, nose), 25.0), target, 1.0 / 120.0)
	assert_int(b.pit).is_equal(PoliceBrain.Pit.TURN)
	assert_float(float(c.steer)).is_less(-0.3)


func test_a_blocker_gets_ahead_and_never_slows_below_its_floor() -> void:
	var b := PoliceBrain.new()
	b.level = 3
	b.role = "block"
	b.side = 1.0
	var target := _car(Vector3.ZERO, 30.0)
	# Behind: it goes by, quicker, out to its side.
	b.decide(_car(Vector3(0, 0, -10.0), 30.0), target, 1.0 / 120.0)
	assert_float(b.last_want).is_greater(30.0)
	# Just ahead: slower than the target, but not below the floor however the target slows.
	for ts: float in [30.0, 10.0, 3.0]:
		b.decide(_car(Vector3(0, 0, 8.0), ts), _car(Vector3.ZERO, ts), 1.0 / 120.0)
		assert_float(b.last_want).is_less(ts + 0.001)
		assert_float(b.last_want).is_greater_equal(ts * PoliceBrain.BLOCK_FLOOR - 0.001)


func test_no_contact_at_level_one() -> void:
	assert_bool(PoliceTuning.at(1).roles.any(func(r: String) -> bool: return PoliceTuning.contact(r))).is_false()
	var b := PoliceBrain.new()
	b.level = 1
	b.role = PoliceTuning.role(1, 0)
	var target := _car(Vector3.ZERO, 30.0)
	# Right on its bumper: it drops back.
	b.decide(_car(Vector3(0, 0, -5.5), 30.0), target, 1.0 / 120.0)
	assert_float(b.last_want).is_less(30.0)
	# Well back: it closes, to a few lengths.
	b.decide(_car(Vector3(0, 0, -30.0), 30.0), target, 1.0 / 120.0)
	assert_float(b.last_want).is_greater(30.0)


func test_a_ram_steers_at_the_target() -> void:
	var b := PoliceBrain.new()
	b.level = 2
	b.role = "ram"
	b.side = 1.0
	# The target ahead and to the right (-x going +z): steer right (+).
	var c := b.decide(_car(Vector3(0, 0, -12.0), 30.0), _car(Vector3(-3.0, 0, 0), 30.0), 1.0 / 120.0)
	assert_float(float(c.steer)).is_greater(0.0)
	c = b.decide(_car(Vector3(0, 0, -12.0), 30.0), _car(Vector3(3.0, 0, 0), 30.0), 1.0 / 120.0)
	assert_float(float(c.steer)).is_less(0.0)


func test_more_heat_more_units_harder() -> void:
	for level in range(1, 5):
		var a := PoliceTuning.at(level)
		var b := PoliceTuning.at(level + 1)
		assert_int(int(b.units)).is_equal(int(a.units) + 1)
		assert_int((b.roles as Array).size()).is_equal(int(b.units))
		assert_float(float(b.closing_mps)).is_greater(float(a.closing_mps))
		assert_float(float(b.max_factor)).is_greater(float(a.max_factor))
		assert_float(float(b.sight_m)).is_greater(float(a.sight_m))
	assert_float(float(PoliceTuning.at(2).spikes_s)).is_equal(0.0)
	assert_float(float(PoliceTuning.at(3).spikes_s)).is_greater(0.0)
	assert_bool(PoliceTuning.at(3).roadblock).is_false()
	assert_bool(PoliceTuning.at(4).roadblock).is_true()
	assert_bool("block" in PoliceTuning.at(2).roles).is_true()
	assert_bool("pit" in PoliceTuning.at(4).roles).is_true()
