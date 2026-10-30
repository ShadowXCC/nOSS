extends GdUnitTestSuite
## Where liveries are kept (docs/VEHICLE_PACKAGE.md §12): per car, in order, with the worn one;
## copied with a car and deleted with it; never outside the liveries folder.

const ROOT := "user://tests/liveries/"
const CAR := "0b7a4c1e-1111-4a2b-9a52-3b1f0d7c2e11"
const OTHER := "0b7a4c1e-2222-4a2b-9a52-3b1f0d7c2e11"

var _was := ""


func before_test() -> void:
	_was = LiveryStore.root
	LiveryStore.root = ROOT
	_clear()


func after_test() -> void:
	_clear()
	LiveryStore.root = _was


func _clear() -> void:
	for car in [CAR, OTHER]:
		LiveryStore.delete_car(car)


func _livery(livery_name: String, layers := 1) -> Dictionary:
	var l := LiveryData.new_livery(livery_name, { "id": CAR, "name": "Test car" })
	for i in layers:
		l.layers.append(LiveryData.new_layer("shape", Vector3(0, i, 0), Vector3.UP, Vector3.RIGHT, Vector2.ONE, "chevrons"))
	return LiveryData.clean(l)


func test_save_list_and_wear() -> void:
	var a := _livery("A")
	var b := _livery("B", 3)
	assert_str(LiveryStore.save_car(CAR, [b, a], a.id)).is_empty()
	var listed := LiveryStore.list(CAR)
	assert_int(listed.size()).is_equal(2)
	assert_str(listed[0].name).is_equal("B")
	assert_int(listed[0].layers.size()).is_equal(3)
	assert_str(LiveryStore.index(CAR).worn).is_equal(a.id)
	assert_str(LiveryStore.worn_stored(CAR).name).is_equal("A")
	# Plain paint, and a livery taken out of the list loses its file.
	assert_str(LiveryStore.save_car(CAR, [b], "")).is_empty()
	assert_dict(LiveryStore.worn_stored(CAR)).is_empty()
	assert_bool(FileAccess.file_exists(ROOT + CAR + "/" + a.id + ".json")).is_false()
	assert_int(LiveryStore.list(CAR).size()).is_equal(1)


func test_worn_must_be_one_of_them() -> void:
	var a := _livery("A")
	LiveryStore.save_car(CAR, [a], "not-in-the-list")
	assert_str(LiveryStore.index(CAR).worn).is_empty()


func test_copy_and_delete_with_the_car() -> void:
	var a := _livery("A")
	LiveryStore.save_car(CAR, [a], a.id)
	assert_str(LiveryStore.copy_car(CAR, OTHER)).is_empty()
	assert_str(LiveryStore.worn_stored(OTHER).name).is_equal("A")
	LiveryStore.delete_car(CAR)
	assert_bool(DirAccess.dir_exists_absolute(ROOT + CAR)).is_false()
	assert_int(LiveryStore.list(OTHER).size()).is_equal(1)
	# Saving none removes the folder.
	LiveryStore.save_car(OTHER, [], "")
	assert_bool(DirAccess.dir_exists_absolute(ROOT + OTHER)).is_false()


## A car id from a hostile package can't reach outside the folder.
func test_bad_car_ids() -> void:
	assert_str(LiveryStore.save_car("../escape", [_livery("A")], "")).is_not_empty()
	assert_bool(DirAccess.dir_exists_absolute("user://tests/escape")).is_false()
	assert_int(LiveryStore.list("../../garage").size()).is_equal(0)


## A file that isn't its name's livery, or isn't one at all, is skipped.
func test_stray_files_are_skipped() -> void:
	var a := _livery("A")
	LiveryStore.save_car(CAR, [a], "")
	var f := FileAccess.open(ROOT + CAR + "/junk.json", FileAccess.WRITE)
	f.store_string("{\"nope\": 1}")
	f.close()
	var other := _livery("B")
	f = FileAccess.open(ROOT + CAR + "/wrong-name.json", FileAccess.WRITE)
	f.store_buffer(LiveryData.to_bytes(other))
	f.close()
	assert_int(LiveryStore.list(CAR).size()).is_equal(1)


func test_ai_picks_a_saved_livery() -> void:
	var pkg := VehiclePackage.new()
	pkg.manifest = { "id": CAR }
	assert_dict(LiveryStore.pick_for_ai(pkg)).is_empty()
	var a := _livery("A")
	var b := _livery("B")
	LiveryStore.save_car(CAR, [a, b], "")
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		seen[LiveryStore.pick_for_ai(pkg, rng).name] = true
	assert_int(seen.size()).is_equal(2)


func test_net_blob_has_a_cap() -> void:
	var small := LiveryStore.net_blob(_livery("A"))
	assert_int(small.size()).is_greater(0)
	assert_dict(LiveryData.parse(small, LiveryData.MAX_NET_BYTES)).is_not_empty()
	var big := _livery("Big", 100)
	for l: Dictionary in big.layers:
		l.kind = "text"
		l.text = "W".repeat(32)
		l.font = LiveryData.DEFAULT_FONT
		l.erase("shape")
		l.erase("params")
	assert_int(LiveryData.to_bytes(LiveryData.clean(big)).size()).is_less(LiveryData.MAX_NET_BYTES)


func test_builtin_cars_are_known() -> void:
	assert_bool(LiveryStore.is_builtin("6e0c6a51-5d0f-4a2b-9a52-3b1f0d7c2e11")).is_true()
	assert_bool(LiveryStore.is_builtin(CAR)).is_false()
