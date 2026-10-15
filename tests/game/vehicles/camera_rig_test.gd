extends GdUnitTestSuite
## The chase camera's heading follows the car, and stays a clean direction when the car is turned
## right round at once (a reset) or has stood still long enough for the camera to catch up.


func _rig() -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	add_child(rig)
	rig.set_process(false) # driven by hand below
	rig.vehicle = auto_free(Vehicle.new()) # at rest, out of the tree
	return rig


func _facing(yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)


func test_turned_round_and_at_rest() -> void:
	var rig := _rig()
	for i in 300: # long enough to catch up exactly
		rig._chase(_facing(0.0), 1.0 / 60.0, false, 0.0, {})
	assert_bool(rig._yaw_dir.is_normalized()).is_true()
	assert_float(rig._yaw_dir.distance_to(Vector3(0, 0, 1))).is_less(1e-4)
	# Turned right round: the camera swings straight behind it.
	rig._chase(_facing(PI), 1.0 / 60.0, false, 0.0, {})
	assert_bool(rig._yaw_dir.is_normalized()).is_true()
	assert_float(rig._yaw_dir.distance_to(Vector3(0, 0, -1))).is_less(1e-4)
	# A quarter turn: followed smoothly, not snapped.
	rig._chase(_facing(PI / 2.0), 1.0 / 60.0, false, 0.0, {})
	assert_bool(rig._yaw_dir.is_normalized()).is_true()
	assert_float(rig._yaw_dir.distance_to(Vector3(0, 0, -1))).is_less(0.2)


## Free look (Changes.md): the right stick turns the chase camera round the car and the cockpit
## view, and the view swings back to the camera when the stick is let go.
func test_free_look_turns_and_comes_back() -> void:
	var rig := _rig()
	var input := PlayerInput.new()
	input.profile = PlayerProfile.create("look")
	input.devices.assign([{ "kind": "gamepad", "key": "pad:test#7", "name": "Test pad", "id": 7, "guid": "test" }])
	input.rebuild()
	rig.input = input
	_stick(JOY_AXIS_RIGHT_X, 1.0)
	for i in 120:
		rig.update_look(1.0 / 60.0)
		rig._chase(_facing(0.0), 1.0 / 60.0, false, 0.0, {})
	assert_float(rig._look.x).is_equal_approx(deg_to_rad(CameraRig.LOOK_CHASE[0]), 0.01)
	# The car faces +Z, so its right is -X: the camera looks that way, from its left.
	var forward := -rig.camera.global_transform.basis.z
	assert_float(forward.x).is_less(-0.5)
	assert_float(rig.camera.global_position.x).is_greater(0.0)
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	for i in 60:
		rig.update_look(1.0 / 60.0)
	assert_float(rig._look.length()).is_less(0.01)
	# A fixed camera turns its head: looking right is towards its own +X, up towards +Y.
	rig._look = Vector2(PI / 2.0, 0.0)
	assert_float((rig._looked(Basis()) * Vector3.FORWARD).distance_to(Vector3.RIGHT)).is_less(1e-4)
	rig._look = Vector2(0.0, 0.3)
	assert_float((rig._looked(Basis()) * Vector3.FORWARD).y).is_greater(0.2)
	# Without a player (a remote car's camera) there's no free look.
	rig.input = null
	rig._look = Vector2(1.0, 0.0)
	for i in 60:
		rig.update_look(1.0 / 60.0)
	assert_float(rig._look.length()).is_less(0.01)


static func _stick(axis: int, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 7
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)
	Input.flush_buffered_events()
