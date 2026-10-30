extends GdUnitTestSuite
## Sharing liveries (docs/VEHICLE_PACKAGE.md §12): a file out and back in; on the same model a
## livery goes over as it is, on another it's fitted and every layer lands on the new body; a
## car's export never takes its liveries with it.

const BOX := "res://content/cars/noss_box"
const DIR := "user://tests/livery_share/"

var _draft: FittingDraft
var _edit: LiveryEdit


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var result := ModelImport.import_file("res://tests/fixtures/models/kenney/sedan-sports.glb")
	_draft = FittingDraft.from_import(result)
	_draft.paint.slots = { "primary": { "materials": ["colormap"], "color": "#E8B71A", "finish": "metallic" } }
	_edit = LiveryEdit.new(_draft)
	_edit.add("shape", "chevrons")
	_edit.add("number")
	_edit.place_side("top")


func after_test() -> void:
	_draft.delete_draft() # a bay saved it as it showed it
	_draft.free_scene()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)


func _car() -> Dictionary:
	return { "id": _draft.id, "model": LiveryShare.model_hash(_draft.model_bytes()), "name": _draft.car_name }


func test_a_file_out_and_back() -> void:
	var path := DIR + "stripes" + LiveryShare.EXTENSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(LiveryShare.for_file(_edit.livery(), _car(), LiveryData.frame_of(_draft.fit)))
	f.close()
	var back := LiveryShare.read_file(path)
	assert_int(back.layers.size()).is_equal(2)
	assert_str(String(back.car.model)).starts_with("sha256:")
	assert_bool(back.has("frame")).is_true()
	# Junk and oversized files are refused.
	f = FileAccess.open(DIR + "junk.nosslivery", FileAccess.WRITE)
	f.store_string("{\"schema\": \"noss.paint/1\"}")
	f.close()
	assert_dict(LiveryShare.read_file(DIR + "junk.nosslivery")).is_empty()
	f = FileAccess.open(DIR + "big.nosslivery", FileAccess.WRITE)
	f.store_string(" ".repeat(LiveryData.MAX_IMPORT_BYTES + 1))
	f.close()
	assert_dict(LiveryShare.read_file(DIR + "big.nosslivery")).is_empty()


## The same model: the layers go over as they are (a new id).
func test_the_same_model() -> void:
	var src := LiveryData.clean(_edit.livery())
	src.car = _car()
	src.frame = LiveryData.frame_of(_draft.fit)
	var result := LiveryShare.fit(src, _car(), LiveryData.frame_of(_draft.fit), _edit.raycast_model)
	var l: Dictionary = result[0]
	assert_bool(result[1]).is_false()
	assert_str(l.id).is_not_equal(src.id)
	assert_array(l.layers[0].at).is_equal(src.layers[0].at)


## Another model: fitted by the two cars' bounds and cast back onto the body, each layer still
## on the side it was on.
func test_another_model_is_fitted() -> void:
	var src := LiveryData.clean(_edit.livery())
	src.car = _car()
	src.frame = LiveryData.frame_of(_draft.fit)
	var pkg := PackageLoader.load_package(BOX)
	var box := FittingDraft.from_package(pkg)
	pkg.free_scenes()
	var box_edit := LiveryEdit.new(box)
	var box_car := { "id": String(pkg.manifest.id), "model": String(pkg.manifest.files["model/body.glb"]), "name": "Box" }
	var result := LiveryShare.fit(src, box_car, LiveryData.frame_of(box.fit), box_edit.raycast_model)
	assert_bool(result[1]).is_true()
	var l: Dictionary = result[0]
	assert_int(l.layers.size()).is_equal(2)
	var sides := []
	for layer: Dictionary in l.layers:
		var at := LiveryEdit._v(layer.at)
		var n := LiveryEdit._v(layer.normal)
		var hit := box_edit.raycast_model(at + n * 0.5, -n)
		assert_vector(hit.position).is_equal_approx(at, Vector3.ONE * 0.002)
		sides.append(LiveryEdit.nearest_side(n))
	assert_array(sides).is_equal(["left", "top"])
	box.free_scene()


## The bay's Import: a file from another car is fitted, worn and edited.
func test_the_bay_imports_a_file() -> void:
	var path := DIR + "in" + LiveryShare.EXTENSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	var other := { "id": "someone-else", "model": "sha256:00", "name": "Other" }
	f.store_buffer(LiveryShare.for_file(_edit.livery(), other, LiveryData.frame_of(_draft.fit)))
	f.close()
	var bay := FittingBay.new()
	bay.draft = _draft
	add_child(bay)
	bay._show_step("Livery")
	var before := _draft.liveries.size()
	bay._livery_ui.import_file(path)
	assert_int(_draft.liveries.size()).is_equal(before + 1)
	assert_str(bay._status.text).is_equal("Fitted to this car")
	assert_str(_draft.worn).is_equal(_draft.liveries[-1].id)
	assert_str(_draft.liveries[-1].name).is_equal("Livery 2")
	bay._livery_ui.import_file(DIR + "nothing.json")
	assert_str(bay._status.text).starts_with("Not a livery")
	bay._leave()
	bay.draft = null
	Game.bay_draft = null
	bay.free()


## A car's Export is the package as it is: its liveries stay at home.
func test_export_leaves_liveries_out() -> void:
	var was := LiveryStore.root
	LiveryStore.root = "user://tests/livery_share_store/"
	var copy := GarageFiles.copy_car(BOX)
	var id := String(PackageLoader.read_manifest(copy.path).id)
	var l := LiveryData.new_livery("Kept", { "id": id })
	LiveryStore.save_car(id, [l], l.id)
	var dest := DIR + "box.noss"
	assert_bool(GarageFiles.export_car(copy.path, dest).ok).is_true()
	var a := ZIPReader.new()
	a.open(copy.path)
	var b := ZIPReader.new()
	b.open(dest)
	assert_array(Array(b.get_files())).is_equal(Array(a.get_files()))
	assert_bool(b.read_file("manifest.json") == a.read_file("manifest.json")).is_true()
	a.close()
	b.close()
	GarageFiles.delete(copy.path)
	LiveryStore.root = was
