extends GdUnitTestSuite
## The Garage (docs/VEHICLE_PACKAGE.md §8, PKG-05, docs/UI_FLOW.md §8): its file operations
## (list, duplicate, paint, copy sound, delete), then its pages: the grid, a car's page, Paint,
## Copy sound to and Delete. Cars made here are removed again. The pages open on the built-in
## cars where the tab doesn't matter: they're small, quick on the turntable.

const BOX := "res://content/cars/noss_box"

var _made: Array[String] = []
var _old_size: Vector2i
var _on_scene := Callable()


func before_test() -> void:
	_old_size = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720) # headless windows start at 64 x 64


func after_test() -> void:
	for path in _made:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_made.clear()
	get_tree().root.size = _old_size
	get_tree().root.content_scale_factor = 1.0
	Game.hold_scenes = false
	if _on_scene.is_valid() and Game.scene_requested.is_connected(_on_scene):
		Game.scene_requested.disconnect(_on_scene)
	_on_scene = Callable()
	Game.bay_from = ""
	Game.bay_car = ""


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



## A car's page (docs/UI_FLOW.md §8): confirm on its card opens it over the grid (which hides),
## the turntable goes with it, its actions are rows (a built-in car's Paint, Sound and Delete off),
## and cancel comes back to its card. Only the grid's prompt bar shows Tabs.
func test_a_car_opens_its_page_and_back_comes_to_its_card() -> void:
	var g := await _garage(BOX)
	assert_object(_focused()).is_same(g.grid.cards[g.grid.selected])
	assert_str(String(g.grid.cars[g.grid.selected].path)).is_equal(BOX)
	assert_array(g.grid.prompt_bar.entries()).contains([["tabs", "Tabs"]])
	await _push("ui_accept")
	var page := g.stack.top() as CarPage
	assert_object(page).is_not_null()
	assert_str(page._crumb_label.text).is_equal("Garage › nOSS Box")
	assert_str(page.title).is_equal("nOSS Box")
	assert_bool(g.grid.is_visible_in_tree()).is_false()
	assert_bool(page.is_ancestor_of(g.preview)).is_true()
	assert_array(page.prompt_bar.entries()).not_contains([["tabs", "Tabs"]])
	var off: Array = page.body.get_children().filter(func(b: Node) -> bool: return b is Button and (b as Button).disabled) \
		.map(func(b: Button) -> String: return b.text)
	assert_array(off).contains_exactly(["Paint", "Sound", "Delete"])
	# Down through the enabled rows to Back.
	var seen: Array[String] = [(_focused() as Button).text]
	for i in 5:
		await _push("ui_down")
		seen.append((_focused() as Button).text)
	assert_array(seen).contains_exactly(["Drive", "Edit", "Duplicate", "Copy sound to…", "Export…", "Back"])
	await _push("ui_cancel")
	assert_object(g.stack.top()).is_same(g.grid)
	assert_object(_focused()).is_same(g.grid.cards[g.grid.selected])
	assert_bool(g.grid.is_ancestor_of(g.preview)).is_true()
	await _close(g)


## Keyboard and controller round the grid page: up from the top row to the tabs, down from them to
## the New car card; down from the last row to Fitting Bay, Back (left of it), and round to the tabs.
func test_the_grid_links_the_tabs_the_cards_and_the_bar() -> void:
	var g := await _garage(BOX) # Built-in: the New car card and three cars
	var grid := g.grid
	assert_object(grid.grid.get_child(0)).is_same(grid.new_card)
	grid.cards[0].grab_focus()
	await _push("ui_up")
	assert_object(_focused()).is_same(grid.tab_row.button())
	await _push("ui_down")
	assert_object(_focused()).is_same(grid.new_card)
	grid.cards[-1].grab_focus()
	await _push("ui_down")
	assert_object(_focused()).is_same(grid.bay_button)
	await _push("ui_left")
	assert_object(_focused()).is_same(grid.back_button)
	await _push("ui_down")
	assert_object(_focused()).is_same(grid.tab_row.button())
	await _push("ui_up")
	assert_object(_focused()).is_same(grid.back_button)
	await _close(g)


## "My cars | Built-in" (docs/UI_FLOW.md §8): each tab shows only its cars, after the New car card.
## Next tab works from the grid (the focus going to the tab's car), left and right on the tab row
## too (the focus staying there), but not under a car's page. Each tab comes back to the car last
## picked on it. Duplicate on a built-in car's page lands on My cars, on the copy.
func test_the_tabs_split_my_cars_from_the_built_in_ones() -> void:
	var copy := GarageFiles.copy_car(BOX)
	_made.append(copy.path)
	var g := await _garage(copy.path)
	var grid := g.grid
	assert_array(Array(grid.tab_row.tabs)).contains_exactly(["My cars", "Built-in"])
	assert_int(grid.tab).is_equal(GaragePage.MY_CARS)
	assert_bool(grid.cars.all(func(c: Dictionary) -> bool: return not c.official)).is_true()
	assert_str(String(grid.cars[grid.selected].path)).is_equal(copy.path)
	assert_object(_focused()).is_same(grid.cards[grid.selected])

	await _push("ui_tab_next")
	assert_int(grid.tab).is_equal(GaragePage.BUILT_IN)
	assert_bool(grid.cars.all(func(c: Dictionary) -> bool: return c.official)).is_true()
	assert_object(grid.grid.get_child(0)).is_same(grid.new_card)
	assert_object(_focused()).is_same(grid.cards[0])
	await _push("ui_up")
	await _push("ui_left")
	assert_int(grid.tab).is_equal(GaragePage.MY_CARS)
	assert_object(_focused()).is_same(grid.tab_row.button(GaragePage.MY_CARS))
	assert_str(String(grid.cars[grid.selected].path)).is_equal(copy.path) # where it was

	# Under the copy's page the tabs stay put.
	grid.cards[grid.selected].grab_focus()
	await _push("ui_accept")
	await _push("ui_tab_next")
	assert_int(grid.tab).is_equal(GaragePage.MY_CARS)
	await _push("ui_cancel")
	await _push("ui_tab_next")
	assert_int(grid.tab).is_equal(GaragePage.BUILT_IN)

	# Duplicate the box from its page: the grid on My cars, on the copy.
	assert_str(String(grid.cars[grid.selected].path)).is_equal(BOX)
	await _push("ui_accept")
	(g.stack.top() as CarPage)._duplicate()
	var made := String(grid.cars[grid.selected].path)
	_made.append(made)
	assert_object(g.stack.top()).is_same(grid)
	assert_int(grid.tab).is_equal(GaragePage.MY_CARS)
	assert_str(made).starts_with(PackageLoader.GARAGE_DIR)
	assert_str(made).is_not_equal(copy.path)
	assert_str(grid.status.text).is_equal("Copy made")
	await _frames(2)
	assert_object(_focused()).is_same(grid.cards[grid.selected])
	await _close(g)


## The grid has as many columns as fit (docs/UI_FLOW.md §8): 3 at text 1.0, 2 at 1.5 (the pane
## beside it) and at 2.0 (no pane), and no card goes past the body's right edge.
func test_the_grid_has_as_many_columns_as_fit() -> void:
	for scale: float in [1.0, 1.5, 2.0]:
		get_tree().root.content_scale_factor = scale
		var g := await _garage(BOX)
		await _frames(3)
		var want := 3 if scale == 1.0 else 2
		assert_int(g.grid.grid.columns).override_failure_message("text %.1f" % scale).is_equal(want)
		var right := g.grid.scroll().get_global_rect().end.x
		for c: Button in g.grid.cards:
			assert_float(c.get_global_rect().end.x).override_failure_message("text %.1f: %s" % [scale, c.text]).is_less_equal(right + 1.0)
		assert_bool(g.grid.pane_shown()).is_equal(scale < 2.0)
		await _close(g)


## The grid scrolls to follow the focus (Changes.md), with menu text at 1.5 in a window that fits
## one row of cars.
func test_the_grid_scrolls_to_follow_the_focus() -> void:
	get_tree().root.size = Vector2i(1280, 900)
	get_tree().root.content_scale_factor = 1.5
	var g := await _garage(BOX)
	var grid := g.grid
	await _frames(3)
	var scroll := grid.scroll()
	assert_float(grid.grid.size.y).override_failure_message("two rows that fit would never scroll").is_greater(scroll.size.y)
	grid.cards[0].grab_focus()
	await _frames(3)
	assert_int(scroll.scroll_vertical).is_equal(0)
	grid.cards[-1].grab_focus() # on the second row
	await _frames(3)
	assert_int(scroll.scroll_vertical).override_failure_message("the grid did not follow the focus").is_greater(0)
	assert_bool(scroll.get_global_rect().encloses(grid.cards[-1].get_global_rect())) \
		.override_failure_message("the focused card is not in view").is_true()
	grid.cards[0].grab_focus()
	await _frames(3)
	assert_int(scroll.scroll_vertical).is_equal(0)
	await _close(g)


## The New car card (a "+" its picture) and Fitting Bay open the bay from the grid; Downloads is gone.
func test_new_car_and_fitting_bay_open_the_bay() -> void:
	var asked := _hold_scenes()
	var g := await _garage(BOX)
	var grid := g.grid
	assert_str(grid.new_card.text).is_equal("New car")
	assert_str(grid.new_card.accessibility_name).is_equal("New car") # the "+" is its picture
	assert_str(grid.new_card.accessibility_description).is_equal("Import a model in the Fitting Bay")
	assert_object(grid.new_card.icon).is_not_null()
	assert_str(grid.bay_button.text).is_equal("Fitting Bay")
	assert_str(grid.bay_button.accessibility_description).is_equal("Import and fit your own car")
	assert_str(grid.back_button.accessibility_description).is_equal("Back to the main menu")
	var texts := g.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	assert_array(texts).not_contains(["Downloads"])
	grid.new_card.grab_focus()
	await _push("ui_accept")
	grid.bay_button.grab_focus()
	await _push("ui_accept")
	assert_array(asked).contains_exactly(["FittingBay", "FittingBay"])
	assert_str(Game.bay_from).is_equal("garage")
	assert_str(Game.bay_car).is_empty()
	await _close(g)


## Edit on a car's page opens the bay from that page ("car"), on its Import step with the car as
## the draft.
func test_edit_opens_the_bay_from_the_car_page() -> void:
	var copy := GarageFiles.copy_car(BOX)
	_made.append(copy.path)
	var asked := _hold_scenes()
	var g := await _garage(copy.path)
	await _push("ui_accept")
	var page := g.stack.top() as CarPage
	page.body.get_children().filter(func(b: Node) -> bool: return b is Button and (b as Button).text == "Edit")[0].pressed.emit()
	for i in 300:
		if not asked.is_empty():
			break
		await get_tree().process_frame
	assert_array(asked).contains_exactly(["FittingBay"])
	assert_str(Game.bay_from).is_equal("car")
	assert_str(Game.bay_car).is_equal(copy.path)
	assert_str((Game.bay_draft as FittingDraft).edit_path).is_equal(copy.path)
	(Game.bay_draft as FittingDraft).free_scene()
	Game.bay_draft = null
	await _close(g)


## Exit and Back go back where the bay came from: the Garage's grid (on the car being fitted), that
## car's page when a car's page opened it (the car it came from, when nothing was saved), else the
## main menu.
func test_the_bay_goes_back_where_it_came_from() -> void:
	var asked: Array[String] = []
	var went: Array = []
	var on_scene := func(scene_name: String, scene: Node) -> void:
		asked.append(scene_name)
		if scene is Garage:
			went.append([(scene as Garage).start_car, (scene as Garage).start_page])
	Game.scene_requested.connect(on_scene)
	Game.hold_scenes = true
	DirAccess.make_dir_recursive_absolute("user://tests/writer")
	for case: Array in [["garage", "user://tests/writer/bay_back.noss"], ["car", ""], [""]]:
		Game.open_fitting_bay("", "", case[0])
		Game.bay_car = BOX if case[0] == "car" else ""
		var bay := FittingBay.new()
		bay.draft = FittingDraft.from_import(ModelImport.import_file("res://tests/fixtures/models/kenney/kart-oobi.glb"))
		bay.draft.edit_path = case[1] if case.size() > 1 else ""
		add_child(bay)
		await get_tree().process_frame
		var crumbs := bay.find_child("Crumbs", true, false) as Label
		assert_str(crumbs.text).is_equal("Fitting Bay" if case[0] == "" else "Garage › Fitting Bay")
		if case[0] == "garage": # the Exit button
			var exit: Button = bay.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Exit")[0]
			assert_str(exit.accessibility_description).is_equal("Back to the Garage")
			exit.pressed.emit()
		else: # Back
			await _push("ui_cancel")
		bay.queue_free()
		await get_tree().process_frame
	assert_array(asked).contains_exactly(["FittingBay", "Garage", "FittingBay", "Garage", "FittingBay", "TitleScreen"])
	assert_array(went).contains_exactly([["user://tests/writer/bay_back.noss", ""], [BOX, "car"]])
	Game.scene_requested.disconnect(on_scene)


## Back from a bay a car's page opened: the grid with that car's page over it.
func test_the_garage_can_open_on_a_cars_page() -> void:
	var g := Garage.new()
	g.start_car = BOX
	g.start_page = "car"
	add_child(g)
	await _frames(4)
	var page := g.stack.top() as CarPage
	assert_object(page).is_not_null()
	assert_str(page.path).is_equal(BOX)
	assert_int(g.grid.tab).is_equal(GaragePage.BUILT_IN)
	await _push("ui_cancel")
	assert_object(g.stack.top()).is_same(g.grid)
	assert_object(_focused()).is_same(g.grid.cards[g.grid.selected])
	assert_str(String(g.grid.cars[g.grid.selected].path)).is_equal(BOX)
	await _close(g)


## Paint (docs/UI_FLOW.md §8): a page over the car's, its Save in the action bar on screen. Back
## leaves the car as it was; Save writes it and says so on the car's page.
func test_paint_saves_or_leaves_the_car_as_it_was() -> void:
	var copy := GarageFiles.copy_car(BOX)
	_made.append(copy.path)
	var g := await _garage(copy.path)
	await _push("ui_accept")
	var car := g.stack.top() as CarPage
	car._paint()
	await _frames(2)
	var paint := g.stack.top() as PaintPage
	assert_object(paint).is_not_null()
	assert_str(paint._crumb_label.text).is_equal("Garage › nOSS Box copy › Paint")
	var save: Button = paint._action_list[0]
	assert_str(save.text).is_equal("Save")
	assert_bool(Rect2(Vector2.ZERO, paint.size).encloses(save.get_global_rect())).is_true()
	var was := _paint_file(copy.path)
	var finish := _row(paint, "Primary finish")
	finish.grab_focus()
	await _push("ui_right")
	assert_str(String(paint.paint.slots.primary.finish)).is_not_equal(String(was.slots.primary.finish))
	await _push("ui_cancel")
	assert_object(g.stack.top()).is_same(car)
	assert_dict(_paint_file(copy.path)).is_equal(was)

	car._paint()
	await _frames(2)
	paint = g.stack.top() as PaintPage
	_row(paint, "Primary finish").grab_focus()
	await _push("ui_right")
	paint._action_list[0].pressed.emit()
	assert_object(g.stack.top()).is_same(car)
	assert_str(car.status.text).is_equal("Paint saved")
	assert_str(String(_paint_file(copy.path).slots.primary.finish)).is_not_equal(String(was.slots.primary.finish))
	assert_int(int(PackageLoader.read_manifest(copy.path).version)).is_equal(2)
	await _close(g)


## Delete asks first (Keep has the focus, cancel keeps the car); Delete takes it and goes back to
## the grid.
func test_delete_asks_first() -> void:
	var copy := GarageFiles.copy_car(BOX)
	_made.append(copy.path)
	var g := await _garage(copy.path)
	await _push("ui_accept")
	var car := g.stack.top() as CarPage
	car._delete()
	await _frames(2)
	var ask := g.stack.top() as ConfirmPage
	assert_str(ask.title).is_equal("Delete nOSS Box copy?")
	assert_str((_focused() as Button).text).is_equal("Keep")
	await _push("ui_cancel")
	assert_object(g.stack.top()).is_same(car)
	assert_bool(FileAccess.file_exists(copy.path)).is_true()
	car._delete()
	await _frames(2)
	(g.stack.top() as ConfirmPage).confirmed.emit()
	assert_object(g.stack.top()).is_same(g.grid)
	assert_bool(FileAccess.file_exists(copy.path)).is_false()
	assert_str(g.grid.status.text).is_equal("Deleted")
	await _close(g)


## Copy sound to lists the player's other cars only: not this one, not the built-in ones.
func test_copy_sound_lists_only_the_players_other_cars() -> void:
	var from := GarageFiles.copy_car(BOX)
	var to := GarageFiles.copy_car(BOX)
	_made.append_array([from.path, to.path])
	var g := await _garage(from.path)
	await _push("ui_accept")
	var car := g.stack.top() as CarPage
	car._copy_sound()
	await _frames(2)
	var page := g.stack.top() as CopySoundPage
	var names: Array = page.body.get_children().filter(func(b: Node) -> bool: return b is Button).map(func(b: Button) -> String: return b.text)
	assert_int(names.count("nOSS Box copy")).is_equal(1) # the other copy, not this one
	assert_array(names).not_contains(["nOSS Box", "nOSS Kart", "nOSS Open"])
	page._copy(to.path, "nOSS Box copy")
	assert_object(g.stack.top()).is_same(car)
	assert_str(car.status.text).is_equal("Sound copied to nOSS Box copy")
	await _close(g)


## A Garage open on `start` (built-in cars: small and quick on the turntable).
func _garage(start: String) -> Garage:
	var g := Garage.new()
	g.start_car = start
	add_child(g)
	await _frames(4)
	return g


## Lets the turntable's package loads land while the garage is still here, then frees it.
func _close(g: Garage) -> void:
	g.clear_car()
	await _frames(8)
	g.queue_free()
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Screen changes reported, not made: their names land in the array returned.
func _hold_scenes() -> Array[String]:
	var asked: Array[String] = []
	_on_scene = func(scene_name: String, _scene: Node) -> void: asked.append(scene_name)
	Game.scene_requested.connect(_on_scene)
	Game.hold_scenes = true
	return asked


func _row(page: MenuPage, prefix: String) -> Control:
	for c in page._rows:
		var target := UiKit._focus_target(c)
		if target and String(target.accessibility_name).begins_with(prefix):
			return target
	return null


static func _paint_file(path: String) -> Dictionary:
	return JSON.parse_string((GarageFiles.read_files(path)["paint.json"] as PackedByteArray).get_string_from_utf8())
