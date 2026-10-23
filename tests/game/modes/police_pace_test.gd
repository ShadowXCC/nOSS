extends GdUnitTestSuite
## How hard the police drive (D201), on numbers alone: the speed a unit chases at (capped only at
## heat 1, easing off to RAM_MPS over the target's by CLOSE_M, one that pulled out holding back
## till the target reaches it); when one waiting ahead pulls out and how far ahead it waits; what
## it does up close (blocks, then rams or PITs once passed); and the Interceptor's pace against
## the Super's.

const HALF := Vector2(2.3, 0.95)


## A car at `pos` going +z at `speed`.
func _car(pos: Vector3, speed: float) -> Dictionary:
	return { "pos": pos, "fwd": Vector3(0, 0, 1), "vel": Vector3(0, 0, speed), "speed": speed, "half": HALF }


func test_heat_one_is_capped_and_heat_two_on_is_not() -> void:
	# Far off after a target at 80 m/s on a 30 m/s road.
	assert_float(PoliceBrain.chase_speed(1, 80.0, 1000.0, 30.0, 8.0)).is_equal_approx(30.0 * 1.6, 0.01)
	assert_float(PoliceBrain.chase_speed(2, 80.0, 1000.0, 30.0, 8.0)).is_equal_approx(80.0 + 13.0, 0.01)
	assert_float(PoliceBrain.chase_speed(5, 80.0, 1000.0, 30.0, 8.0)).is_equal_approx(80.0 + 22.0, 0.01)
	# Heat 1 still goes the limit after a slow target.
	assert_float(PoliceBrain.chase_speed(1, 10.0, 1000.0, 30.0, 8.0)).is_equal_approx(30.0, 0.01)


func test_closing_in_it_eases_off() -> void:
	assert_float(PoliceBrain.chase_speed(3, 50.0, PoliceTuning.CLOSE_M, 30.0, 8.0)).is_equal_approx(50.0 + PoliceTuning.RAM_MPS, 0.01)
	# 10 m further: braking at half of 8 m/s^2 over 10 m.
	assert_float(PoliceBrain.chase_speed(3, 50.0, PoliceTuning.CLOSE_M + 10.0, 30.0, 8.0)).is_equal_approx(54.0 + sqrt(80.0), 0.01)


func test_one_that_pulled_out_holds_back_till_the_target_reaches_it() -> void:
	assert_float(PoliceBrain.chase_speed(4, 40.0, 300.0, 30.0, 8.0, true)).is_equal_approx(40.0 * PoliceTuning.LAUNCH_SHARE, 0.01)
	assert_float(PoliceBrain.chase_speed(4, 5.0, 300.0, 30.0, 8.0, true)).is_equal(PoliceTuning.AHEAD_CRAWL_MPS)


func test_when_one_waiting_ahead_pulls_out_and_how_far_ahead_it_waits() -> void:
	# From rest at LAUNCH_ACCEL it's going LAUNCH_SHARE of the player's speed as they reach it.
	for v: float in [30.0, 45.0, 80.0]:
		var t := PoliceTuning.LAUNCH_SHARE * v / PoliceControl.LAUNCH_ACCEL
		assert_float(PoliceControl.launch_gap(v)).is_equal_approx(v * t - 0.5 * PoliceControl.LAUNCH_ACCEL * t * t, 0.5)
	assert_float(PoliceControl.launch_gap(45.0)).is_equal_approx(158.2, 0.5)
	assert_float(PoliceControl.launch_gap(80.0)).is_equal_approx(500.0, 0.5)
	assert_float(PoliceControl.launch_gap(5.0)).is_equal(PoliceControl.LAUNCH_MIN_M)
	assert_float(PoliceControl.launch_gap(45.0, 0.6)).is_greater(PoliceControl.launch_gap(45.0)) # sooner in the wet
	for v: float in [0.0, 30.0, 80.0, 100.0]:
		var ahead := PoliceControl.ahead_m(v)
		assert_float(ahead).is_greater_equal(PoliceControl.AHEAD_MIN_M)
		assert_float(ahead).is_greater_equal(PoliceControl.launch_gap(v) + PoliceControl.AHEAD_WAIT_M)
		assert_float(ahead).is_greater(float(PoliceTuning.at(5).sight_m)) # out of sight


func test_one_from_ahead_blocks_then_takes_the_lead_role_once_passed() -> void:
	var them := _car(Vector3.ZERO, 30.0)
	# Ahead of the target, or alongside: it blocks.
	assert_array(PoliceBrain.ahead_role(_car(Vector3(0, 0, 10), 25.0), them, 2, false, 1.0)).is_equal(["block", false, 1.0])
	assert_array(PoliceBrain.ahead_role(_car(Vector3(3, 0, -2), 25.0), them, 2, false, 1.0)).is_equal(["block", false, 1.0])
	# Passed, on the target's right (-x going +z): it rams at heat 2, from that side, for good.
	assert_array(PoliceBrain.ahead_role(_car(Vector3(-3, 0, -8), 25.0), them, 2, false, 1.0)).is_equal(["ram", true, -1.0])
	assert_array(PoliceBrain.ahead_role(_car(Vector3(0, 0, 10), 25.0), them, 2, true, -1.0)).is_equal(["ram", true, -1.0])
	# At heat 4 a PIT, from the left.
	assert_array(PoliceBrain.ahead_role(_car(Vector3(3, 0, -8), 25.0), them, 4, false, -1.0)).is_equal(["pit", true, 1.0])


## Top speed on the flat: where the drive force in top gear meets drag and rolling resistance (m/s).
func _top_speed(p: Dictionary) -> float:
	var curve: Array = p.engine.torque_curve_nm
	var ratios: Array = p.gearbox.ratios
	var g := float(ratios[ratios.size() - 1]) * float(p.gearbox.final_drive)
	var r := float(p.geometry.wheel_radius_m.ref)
	var m := float(p.mass.kg)
	var cl := absf(float(p.aero.cl_a_front) + float(p.aero.cl_a_rear))
	var lo := 10.0
	var hi := 200.0
	for i in 60:
		var v := (lo + hi) / 2.0
		var rpm := v / r * g * 60.0 / TAU
		var torque := 0.0
		if rpm <= float(p.engine.limiter_rpm):
			for k in curve.size() - 1:
				if rpm >= float(curve[k][0]) and rpm <= float(curve[k + 1][0]):
					torque = lerpf(float(curve[k][1]), float(curve[k + 1][1]), (rpm - float(curve[k][0])) / (float(curve[k + 1][0]) - float(curve[k][0])))
		var resist := 0.5 * 1.225 * float(p.aero.cd_a) * v * v + float(p.tires.rolling_resistance) * (m * 9.81 + 0.5 * 1.225 * cl * v * v)
		if torque * g / r > resist:
			lo = v
		else:
			hi = v
	return lo


func test_the_interceptor_has_the_supers_pace() -> void:
	var cop := PlatformLoader.load_official("official.highway.interceptor")
	var fast := PlatformLoader.load_official("official.highway.super")
	assert_bool(cop.ok() and fast.ok()).is_true()
	var a: Dictionary = cop.platform
	var b: Dictionary = fast.platform
	var pa := GameModes.peak_power_kw(a)
	var pb := GameModes.peak_power_kw(b)
	assert_float(pa / float(a.mass.kg)).is_equal_approx(pb / float(b.mass.kg), pb / float(b.mass.kg) * 0.01)
	assert_float(pa / float(a.aero.cd_a)).is_equal_approx(pb / float(b.aero.cd_a), pb / float(b.aero.cd_a) * 0.01)
	assert_float(float(a.tires.mu_peak)).is_equal(float(b.tires.mu_peak))
	var top := _top_speed(a)
	assert_float(top).is_equal_approx(_top_speed(b), _top_speed(b) * 0.01)
	# Top gear reaches the limiter just past the top speed.
	var ratios: Array = a.gearbox.ratios
	var at_limiter := float(a.engine.limiter_rpm) * TAU / 60.0 * float(a.geometry.wheel_radius_m.ref) / (float(ratios[ratios.size() - 1]) * float(a.gearbox.final_drive))
	assert_float(at_limiter / top).is_between(1.0, 1.03)
