extends GdUnitTestSuite
## Garage file operations (docs/VEHICLE_PACKAGE.md §8, PKG-05): list, duplicate, paint,
## copy sound, delete. Cars made here are removed again.

var _made: Array[String] = []


func after_test() -> void:
	for path in _made:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_made.clear()


func test_list_has_built_in_cars() -> void:
	var cars := GarageFiles.list()
	var box: Array = cars.filter(func(c: Dictionary) -> bool: return c.path == "res://content/cars/noss_box")
	assert_int(box.size()).is_equal(1)
	assert_bool(box[0].official).is_true()
	assert_int(box[0].triangles).is_greater(1000)


func test_duplicate_paint_sound_delete() -> void:
	var copy := GarageFiles.copy_car("res://content/cars/noss_box")
	assert_str(copy.error).is_empty()
	_made.append(copy.path)
	var m := PackageLoader.read_manifest(copy.path)
	assert_str(m.name).is_equal("nOSS Box copy")
	assert_str(m.id).is_not_equal("6e0c6a51-5d0f-4a2b-9a52-3b1f0d7c2e11")

	var paint: Dictionary = JSON.parse_string(GarageFiles.read_files(copy.path)["paint.json"].get_string_from_utf8())
	paint.slots.primary.color = "#123456"
	var painted := GarageFiles.update(copy.path, { "paint.json": PackageWriter.canonical_json(paint).to_utf8_buffer() })
	assert_bool(painted.ok).is_true()
	assert_int(int(PackageLoader.read_manifest(copy.path).version)).is_equal(2)

	var other := GarageFiles.copy_car(copy.path)
	_made.append(other.path)
	var tuned := { "schema": "noss.sound/1", "base": "flat6", "tweaks": { "pitch": 1.1 } }
	GarageFiles.update(copy.path, { "sound/profile.json": PackageWriter.canonical_json(tuned).to_utf8_buffer() })
	assert_bool(GarageFiles.copy_sound(copy.path, other.path).ok).is_true()
	var pkg := PackageLoader.load_package(other.path)
	assert_str(pkg.sound.base).is_equal("flat6")
	pkg.free_scenes()

	assert_str(GarageFiles.delete("res://content/cars/noss_box")).is_equal("Built-in cars can't be deleted")
	assert_str(GarageFiles.delete(other.path)).is_empty()
	assert_bool(FileAccess.file_exists(other.path)).is_false()


func test_editing_keeps_lods_and_thumbnail() -> void:
	var result := ModelImport.import_file("res://tests/fixtures/models/kenney/kart-oobi.glb")
	var draft := FittingDraft.from_import(result)
	draft.edit_path = PackageLoader.GARAGE_DIR + "test_kart_%s.noss" % draft.id.left(8)
	var packed := draft.pack(PackedByteArray([137, 80, 78, 71]))
	_made.append(draft.edit_path)
	draft.free_scene()
	assert_bool(packed.ok).is_true()
	var pkg := PackageLoader.load_package(draft.edit_path)
	var edit := FittingDraft.from_package(pkg)
	pkg.free_scenes()
	assert_int(edit.kept_lods.size()).is_greater(0)
	edit.car_name = "Renamed"
	var files := edit.files(true)
	assert_bool(files.has("model/lod1.glb")).is_true()
	assert_bool(files["model/lod1.glb"] == edit.kept_lods["model/lod1.glb"]).is_true()
	assert_bool(files.has("thumb.png")).is_true()
	edit.free_scene()


func _push(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		get_tree().root.push_input(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _focused() -> Control:
	return get_tree().root.gui_get_focus_owner()


## Keyboard and controller (Changes.md): confirm on a car goes to its actions, left/right step
## through the enabled ones, back returns to the car; down from the last row reaches Back.
## Paint's Save and Cancel stay on screen.
func test_keys_reach_the_actions_and_paint_fits() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 720) # headless windows start at 64 x 64
	var copy := GarageFiles.copy_car("res://content/cars/noss_box")
	_made.append(copy.path)
	var g := Garage.new()
	add_child(g)
	for i in 4:
		await get_tree().process_frame
	g._cards[0].grab_focus()
	await get_tree().process_frame
	await _push("ui_accept")
	assert_object(_focused()).is_same(g._actions[0])
	assert_str((g._actions[0] as Button).text).is_equal("Drive")
	await _push("ui_right")
	assert_object(_focused()).is_same(g._actions[1])
	await _push("ui_cancel")
	assert_object(_focused()).is_same(g._cards[0])
	g._cards[-1].grab_focus()
	await _push("ui_down")
	assert_object(_focused()).is_same(g._back_button)
	# Paint on the copy: Save is on screen.
	var at := g._cars.find_custom(func(c: Dictionary) -> bool: return c.path == copy.path)
	g._cards[at].grab_focus()
	await _push("ui_accept")
	g._paint()
	for i in 3:
		await get_tree().process_frame
	var save: Button = g._overlay.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return UiKit.text_of(b) == "Save")[0]
	assert_bool(Rect2(Vector2.ZERO, g.size).encloses(save.get_global_rect())).is_true()
	g._close_overlay()
	g._preview.clear()
	g.queue_free()
	await get_tree().process_frame
	root.size = old_size
