extends GdUnitTestSuite
## A note for the start (P1's "Garage cars: 20/27 (video memory)", D247): "Go", said on the same
## HUD line as the car comes in, used to cover it at once. It waits for the car and comes a second
## after Go; with the car in already, a second from then.


class Noting extends Racer:
	var said: Array[String] = []

	func notify(text: String, _seconds := 2.0, _kind := "") -> void:
		said.append(text)

	func _spawn(_pkg: VehiclePackage) -> void:
		vehicle = Vehicle.new()


func test_the_note_comes_after_go() -> void:
	var r: Noting = auto_free(Noting.new())
	r.set_physics_process(false)
	add_child(r)
	r.note_after_go("Garage cars: 20/27 (video memory)")
	assert_array(r.said).is_empty() # no car yet
	r._on_car_loaded(VehiclePackage.new())
	assert_array(r.said).is_equal(["Go"])
	await get_tree().create_timer(0.5).timeout
	assert_array(r.said).is_equal(["Go"]) # Go has its second
	await get_tree().create_timer(0.7).timeout
	assert_array(r.said).is_equal(["Go", "Garage cars: 20/27 (video memory)"])
	r.note_after_go("Again")
	await get_tree().create_timer(1.2).timeout
	assert_str(r.said.back()).is_equal("Again")
	r.vehicle.free()
