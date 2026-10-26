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


func test_with_id_finds_only_the_players_cars() -> void:
	var box := PackageLoader.read_manifest("res://content/cars/noss_box")
	assert_str(GarageFiles.with_id(String(box.id))).is_empty() # built-in cars don't count
	assert_str(GarageFiles.with_id("")).is_empty()
	var copy := GarageFiles.copy_car("res://content/cars/noss_box")
	_made.append(String(copy.path))
	assert_str(GarageFiles.with_id(String(copy.manifest.id))).is_equal(String(copy.path))


func test_export_writes_a_file_that_loads() -> void:
	var dest := "user://tests/writer/exported_box.noss"
	DirAccess.make_dir_recursive_absolute("user://tests/writer")
	_made.append(dest)
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	var result := GarageFiles.export_car("res://content/cars/noss_box", dest)
	assert_str(String(result.error)).is_empty()
	var pkg := PackageLoader.load_package(dest)
	assert_str(pkg.error).is_empty()
	assert_str(pkg.manifest.name).is_equal("nOSS Box")
	pkg.free_scenes()
	# A built-in folder and the file exported from it are the same car, version and all.
	assert_str(String(PackageLoader.read_manifest(dest).id)).is_equal(String(PackageLoader.read_manifest("res://content/cars/noss_box").id))


## Keyboard and controller (Changes.md): confirm on a car goes to its actions, left/right step
## through the enabled ones, back returns to the car; down from the last row reaches the Fitting
## Bay and Back, then round to the tabs and the New car card. Paint's Save and Cancel stay on
## screen.
func test_keys_reach_the_actions_and_paint_fits() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 720) # headless windows start at 64 x 64
	var copy := GarageFiles.copy_car("res://content/cars/noss_box")
	_made.append(copy.path)
	var g := Garage.new()
	g.start_car = "res://content/cars/noss_box" # the built-in cars: small, quick on the turntable
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
	assert_object(_focused()).is_same(g._bay_button)
	await _push("ui_down")
	assert_object(_focused()).is_same(g._back_button)
	await _push("ui_down")
	assert_object(_focused()).is_same(g._tabs.button())
	await _push("ui_down")
	assert_object(_focused()).is_same(g._new_card)
	await _push("ui_up")
	await _push("ui_up")
	assert_object(_focused()).is_same(g._back_button)
	await _push("ui_up")
	assert_object(_focused()).is_same(g._bay_button)
	# Paint on the copy (on My cars): Save is on screen.
	g._reload(copy.path)
	await get_tree().process_frame
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


## The car grid scrolls to follow the focus (Changes.md): on a pad or the keyboard the focus is
## the only thing that moves, so without this a car below the fold gets focused off screen and
## the list never comes with it.
func test_the_car_grid_scrolls_to_follow_the_focus() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 520)
	root.content_scale_factor = 1.5 # menu text at 1.5: the canvas is 720 high, room for one row of cars
	var g := Garage.new()
	g.start_car = "res://content/cars/noss_box" # Built-in: the New car card and three cars, two rows
	add_child(g)
	for i in 4:
		await get_tree().process_frame
	var scroll := g._grid.get_parent() as ScrollContainer
	# The fix: Godot only brings the focused control into view when this is on.
	assert_bool(scroll.follow_focus).is_true()
	assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_int(g._grid.get_child_count()).override_failure_message("one row of cars would never scroll").is_greater(Garage.COLUMNS)

	g._cards[0].grab_focus()
	for i in 3:
		await get_tree().process_frame
	assert_int(scroll.scroll_vertical).is_equal(0)
	# The last card is on a later row: the grid has to scroll down to it.
	g._cards[-1].grab_focus()
	for i in 3:
		await get_tree().process_frame
	assert_int(scroll.scroll_vertical).override_failure_message("the grid did not follow the focus").is_greater(0)
	assert_bool(scroll.get_global_rect().encloses(g._cards[-1].get_global_rect())) \
		.override_failure_message("the focused card is not in view").is_true()
	# And back up again, so the first row is still reachable.
	g._cards[0].grab_focus()
	for i in 3:
		await get_tree().process_frame
	assert_int(scroll.scroll_vertical).is_equal(0)

	# Let the turntable's package loads land while the garage is still here: freeing it with one
	# in flight leaves PackageLoader calling back into a node that is going away.
	g._preview.clear()
	for i in 8:
		await get_tree().process_frame
	g.queue_free()
	await get_tree().process_frame
	root.size = old_size
	root.content_scale_factor = 1.0


## The Fitting Bay opens from the Garage now (docs/UI_FLOW.md §8), not the main menu: its button
## sits under the grid where Downloads was, the "+ New car" card leads the grid, and the bay is
## told it came from the Garage.
func test_the_fitting_bay_opens_from_the_garage() -> void:
	var asked: Array[String] = []
	var on_scene := func(scene_name: String, _scene: Node) -> void: asked.append(scene_name)
	Game.scene_requested.connect(on_scene)
	Game.hold_scenes = true
	var g := Garage.new()
	g.start_car = "res://content/cars/noss_box"
	add_child(g)
	for i in 4:
		await get_tree().process_frame
	assert_str(g._bay_button.text).is_equal("Fitting Bay")
	assert_str(g._bay_button.accessibility_description).is_equal("Import and fit your own car")
	assert_str(g._back_button.accessibility_description).is_equal("Back to the main menu")
	var texts := g.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	assert_array(texts).not_contains(["Downloads"])
	g._bay_button.grab_focus()
	await _push("ui_accept")
	assert_array(asked).contains_exactly(["FittingBay"])
	assert_str(Game.bay_from).is_equal("garage")
	Game.bay_from = ""
	assert_object(g._grid.get_child(0)).is_same(g._new_card)
	assert_str(g._new_card.text).is_equal("New car")
	assert_str(g._new_card.accessibility_name).is_equal("New car") # the "+" is its picture
	assert_object(g._new_card.icon).is_not_null()
	assert_str(g._new_card.accessibility_description).is_equal("Import a model in the Fitting Bay")
	g._new_card.grab_focus()
	await _push("ui_accept")
	assert_array(asked).contains_exactly(["FittingBay", "FittingBay"])
	assert_str(Game.bay_from).is_equal("garage")
	Game.hold_scenes = false
	Game.scene_requested.disconnect(on_scene)
	Game.bay_from = ""
	g._preview.clear()
	for i in 8:
		await get_tree().process_frame
	g.queue_free()
	await get_tree().process_frame


## Exit and Back go back where the bay came from: the Garage (on the car being fitted) when it
## opened the bay, else the main menu as before.
func test_the_bay_goes_back_where_it_came_from() -> void:
	var asked: Array[String] = []
	var picked: Array[String] = []
	var on_scene := func(scene_name: String, scene: Node) -> void:
		asked.append(scene_name)
		if scene is Garage:
			picked.append((scene as Garage).start_car)
	Game.scene_requested.connect(on_scene)
	Game.hold_scenes = true
	DirAccess.make_dir_recursive_absolute("user://tests/writer")
	for from in ["garage", ""]:
		Game.open_fitting_bay("", "", from)
		var bay := FittingBay.new()
		bay.draft = FittingDraft.from_import(ModelImport.import_file("res://tests/fixtures/models/kenney/kart-oobi.glb"))
		bay.draft.edit_path = "user://tests/writer/bay_back.noss"
		add_child(bay)
		await get_tree().process_frame
		if from == "garage": # the Exit button
			var exit: Button = bay.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Exit")[0]
			assert_str(exit.accessibility_description).is_equal("Back to the Garage")
			exit.pressed.emit()
		else: # Back
			await _push("ui_cancel")
		bay.queue_free()
		await get_tree().process_frame
	assert_array(asked).contains_exactly(["FittingBay", "Garage", "FittingBay", "TitleScreen"])
	assert_array(picked).contains_exactly(["user://tests/writer/bay_back.noss"])
	Game.hold_scenes = false
	Game.scene_requested.disconnect(on_scene)
	Game.bay_from = ""


## "My cars | Built-in" over the grid (docs/UI_FLOW.md §8): each tab shows only its cars, after the
## New car card. Next tab works from the grid (the focus going to the tab's car), left and right on
## the tab row too (the focus staying there), but not while a question is up. Each tab comes back
## to the car last picked on it. A built-in car copied lands on My cars, picked.
func test_the_tabs_split_my_cars_from_the_built_in_ones() -> void:
	var root := get_tree().root
	var old_size := root.size
	root.size = Vector2i(1280, 720)
	var copy := GarageFiles.copy_car("res://content/cars/noss_box")
	_made.append(copy.path)
	var g := Garage.new()
	g.start_car = copy.path
	add_child(g)
	for i in 4:
		await get_tree().process_frame
	assert_array(Array(g._tabs.tabs)).contains_exactly(["My cars", "Built-in"])
	assert_int(g._tabs.current).is_equal(Garage.MY_CARS)
	assert_bool(g._cars.all(func(c: Dictionary) -> bool: return not c.official)).is_true()
	assert_bool(g._cars.any(func(c: Dictionary) -> bool: return c.path == copy.path)).is_true()
	assert_int(g._cards.size()).is_equal(g._cars.size())

	assert_object(_focused()).is_same(g._cards[g._selected])
	await _push("ui_tab_next")
	assert_int(g._tabs.current).is_equal(Garage.BUILT_IN)
	assert_bool(g._cars.all(func(c: Dictionary) -> bool: return c.official)).is_true()
	assert_bool(g._cars.any(func(c: Dictionary) -> bool: return c.path == "res://content/cars/noss_box")).is_true()
	assert_object(g._grid.get_child(0)).is_same(g._new_card)
	assert_object(_focused()).is_same(g._cards[0])
	await _push("ui_up") # the top row leads up to the tabs
	assert_object(_focused()).is_same(g._tabs.button())
	await _push("ui_left")
	assert_int(g._tabs.current).is_equal(Garage.MY_CARS)
	assert_object(_focused()).is_same(g._tabs.button(Garage.MY_CARS))
	assert_str(String(g._cars[g._selected].path)).is_equal(copy.path) # where it was
	await _push("ui_down")
	assert_object(_focused()).is_same(g._new_card)

	# A question over the grid keeps the tabs where they are.
	g._cards[g._cars.find_custom(func(c: Dictionary) -> bool: return c.path == copy.path)].grab_focus()
	await get_tree().process_frame
	g._delete()
	await _push("ui_tab_next")
	assert_int(g._tabs.current).is_equal(Garage.MY_CARS)
	g._close_overlay()
	await get_tree().process_frame
	await _push("ui_tab_next")
	assert_int(g._tabs.current).is_equal(Garage.BUILT_IN)

	# Duplicate a built-in car: the copy is picked on My cars.
	assert_str(String(g._cars[g._selected].path)).is_equal("res://content/cars/noss_box")
	g._duplicate()
	var made := String(g._cars[g._selected].path)
	_made.append(made)
	assert_int(g._tabs.current).is_equal(Garage.MY_CARS)
	assert_str(made).starts_with(PackageLoader.GARAGE_DIR)
	assert_str(made).is_not_equal(copy.path)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(_focused()).is_same(g._cards[g._selected])

	g._preview.clear()
	for i in 8:
		await get_tree().process_frame
	g.queue_free()
	await get_tree().process_frame
	root.size = old_size


## Back from the bay on a built-in car (a test drive of one): the Garage opens on Built-in, on it.
func test_the_garage_opens_on_the_tab_of_its_car() -> void:
	var g := Garage.new()
	g.start_car = "res://content/cars/noss_box"
	add_child(g)
	for i in 4:
		await get_tree().process_frame
	assert_int(g._tabs.current).is_equal(Garage.BUILT_IN)
	assert_str(String(g._cars[g._selected].path)).is_equal("res://content/cars/noss_box")
	g._preview.clear()
	for i in 8:
		await get_tree().process_frame
	g.queue_free()
	await get_tree().process_frame
