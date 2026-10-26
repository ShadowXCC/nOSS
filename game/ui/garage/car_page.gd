class_name CarPage
extends MenuPage
## A car in the Garage (docs/UI_FLOW.md §8): drive it, edit it in the Fitting Bay, paint it, tune
## its sound, copy it, give another car its sound, export it or delete it, with the car turning
## in the pane. Built-in cars can be driven, copied, exported and edited as a copy.

var garage: Garage
## The car (a package path).
var path := ""
var status: Label

var _car: Dictionary
var _details: VBoxContainer


func _ready() -> void:
	_car = garage.car(path)
	title = car_name()
	crumbs = ["Garage", car_name()]
	back_hint = "Back to the Garage"
	super._ready()


func car_name() -> String:
	return String(_car.manifest.name)


func _build() -> void:
	var official: bool = _car.official
	for row: Array in [
		["Drive", _drive, "Pick a class and drive this car"],
		["Edit", _edit.bind(""), "Open in the Fitting Bay" + (" as a copy" if official else "")],
		["Paint", _paint, "Change its colours"],
		["Sound", _edit.bind("Sound"), "Tune its engine and tire sounds"],
		["Duplicate", _duplicate, "Make a copy in the garage"],
		["Copy sound to…", _copy_sound, "Give another car these sounds"],
		["Export…", _export, "Write this car out as a .noss file"],
		["Delete", _delete, "Delete this car"],
	]:
		var b := add_row(UiKit.button(row[0], row[1], row[2])) as Button
		if official and row[0] in ["Paint", "Sound", "Delete"]:
			b.disabled = true
			b.focus_mode = Control.FOCUS_NONE
	status = GaragePage._status_line()
	add_footer(status)
	var box := VBoxContainer.new()
	set_pane(box)
	_details = VBoxContainer.new()
	box.add_child(_details)
	_show_details()
	visibility_changed.connect(_on_shown)
	garage.lend_preview(self, box)
	garage.show_car(path, true)


## Back on top (a page over it closed): its details again (Paint and Copy sound count its version up).
func _on_shown() -> void:
	if is_visible_in_tree() and not garage.car(path).is_empty():
		_car = garage.car(path)
		_show_details()


func _show_details() -> void:
	for child in _details.get_children():
		child.queue_free()
	for line in Garage.details(_car):
		var l := UiKit.label(line, 26)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_details.add_child(l)


func _drive() -> void:
	var classes := ClassPage.new()
	classes.car = path
	classes.picked.connect(func(id: String) -> void:
		garage.clear_car()
		Game.start_free_drive(path, id))
	open_over(classes)


func _edit(step: String) -> void:
	status.text = "Loading"
	PackageLoader.load_async(path, _on_edit_loaded.bind(step))


func _on_edit_loaded(pkg: VehiclePackage, step: String) -> void:
	if not is_inside_tree() or not pkg.ok():
		if is_inside_tree():
			status.text = "Car failed to load"
		pkg.free_scenes()
		return
	var draft := FittingDraft.from_package(pkg)
	pkg.free_scenes()
	Game.bay_draft = draft
	garage.open_bay(path, step if step else "Import")


func _paint() -> void:
	var files := GarageFiles.read_files(path)
	var paint: Variant = JSON.parse_string((files.get("paint.json", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if not paint is Dictionary or (paint.get("slots", {}) as Dictionary).is_empty():
		status.text = "This car has no paint slots. Set them in the Fitting Bay."
		return
	var page := PaintPage.new()
	page.garage = garage
	page.path = path
	page.car_name = car_name()
	page.paint = paint
	open_over(page)


## A copy in the garage: back on the grid, on the copy (My cars).
func _duplicate() -> void:
	var result := GarageFiles.copy_car(path)
	if not result.ok:
		status.text = String(result.error)
		return
	closed.emit()
	garage.grid.reload(String(result.path))
	garage.say("Copy made")


func _copy_sound() -> void:
	var page := CopySoundPage.new()
	page.garage = garage
	page.path = path
	page.car_name = car_name()
	open_over(page)


## Writes the car out as a .noss anywhere the player picks, to share by hand or back up.
func _export() -> void:
	UiKit.save_dialog(self, "Export " + car_name(), ".noss", car_name(), func(dest: String) -> void:
		var result := GarageFiles.export_car(path, dest)
		status.text = "Exported to " + dest.get_file() if result.ok else String(result.error))


func _delete() -> void:
	var ask := ConfirmPage.new()
	ask.title = "Delete %s?" % car_name()
	ask.crumbs = ["Garage", car_name(), "Delete"]
	ask.no_text = "Keep"
	ask.no_hint = "Leave it"
	ask.yes_text = "Delete"
	ask.yes_hint = "Delete it now"
	ask.confirmed.connect(func() -> void:
		garage.clear_car()
		var err := GarageFiles.delete(path)
		garage.stack.close(self) # this page and the question: back on the grid
		garage.grid.reload()
		garage.say(err if err else "Deleted"))
	open_over(ask)
