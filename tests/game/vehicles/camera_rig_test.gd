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
