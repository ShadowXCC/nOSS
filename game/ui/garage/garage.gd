class_name Garage
extends Control
## The garage (docs/VEHICLE_PACKAGE.md §8, PKG-05, docs/UI_FLOW.md §8): its pages on their own
## MenuStack. The grid of cars first (GaragePage, with its Traffic cars mode); a car's page over
## it (CarPage: drive, edit, paint, sound, duplicate, copy sound, export, delete); Paint, Copy
## sound to and Delete over that. One turntable shows the car, in the pane of whichever page is up.

## Wait this long after the focus stops moving before loading a car for the turntable, so
## arrowing past big cars doesn't load each.
const FIT_DELAY := 0.15

## The car to pick when the garage opens (back from the Fitting Bay), on its tab; empty: the
## first of the player's own cars, or of the built-in ones when they have none.
var start_car := ""
## "car": open start_car's page over the grid (back from a bay that page's Edit or Sound opened);
## "traffic": open in Traffic cars (dev, --garage=traffic).
var start_page := ""

var stack: MenuStack
var grid: GaragePage
## The one turntable, lent to the page that's up (lend_preview()).
var preview: BayPreview
## Every car: {path, official, manifest, triangles, thumbnail (Texture2D or null)}.
var cars: Array[Dictionary] = []

var _loading := "" # the car the turntable has, or is loading
var _wanted := "" # the car to load once the focus has stayed put
var _timer: Timer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.content_scale_factor = Players.menu_text_scale() # Menu text, as on the main menu
	var bg := ColorRect.new()
	bg.color = UiKit.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	preview = BayPreview.new()
	preview.turntable = true
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = FIT_DELAY
	_timer.timeout.connect(_load_wanted)
	add_child(_timer)
	reload_cars()
	stack = MenuStack.new()
	stack.emptied.connect(func() -> void:
		clear_car()
		Game.go_title())
	add_child(stack)
	grid = GaragePage.new()
	grid.garage = self
	stack.push(grid)
	if start_page == "car" and not car(start_car).is_empty():
		grid.open_car(start_car)
	elif start_page == "traffic":
		grid.set_traffic_mode(true)


func _exit_tree() -> void:
	get_tree().root.content_scale_factor = 1.0


## The cars again, from the files.
func reload_cars() -> void:
	cars = GarageFiles.list()


## The car at `path`, or {}.
func car(path: String) -> Dictionary:
	var i := cars.find_custom(func(c: Dictionary) -> bool: return c.path == path)
	return cars[i] if i >= 0 else {}


## Puts the turntable at the top of `box`, in `page`'s pane: now, and each time `page` shows again
## (a page over it closed), so it turns in whichever page is up.
func lend_preview(page: Control, box: VBoxContainer) -> void:
	var take := func() -> void:
		if not page.is_visible_in_tree() or preview.get_parent() == box:
			return
		if preview.get_parent():
			preview.reparent(box, false)
		else:
			box.add_child(preview)
		box.move_child(preview, 0)
	page.visibility_changed.connect(take)
	take.call()


## Shows the car at `path` on the turntable: once the focus has stayed put for FIT_DELAY, or `now`.
func show_car(path: String, now := false) -> void:
	_wanted = path
	if now:
		_timer.stop()
		_load_wanted()
	else:
		_timer.start()


## No car on the turntable (the New car card; leaving).
func clear_car() -> void:
	_timer.stop()
	_wanted = ""
	_loading = ""
	preview.clear()


## Says `text` on the page that's up (its status line).
func say(text: String) -> void:
	var top := stack.top() if stack else null
	var line: Variant = top.get(&"status") if top else null
	if line is Label:
		(line as Label).text = text


## Opens the Fitting Bay: from the grid (New car, Fitting Bay), or from `car_path`'s page on
## `step` (its draft in Game.bay_draft).
func open_bay(car_path := "", step := "") -> void:
	clear_car()
	Game.bay_car = car_path
	Game.open_fitting_bay("", step, "car" if car_path else "garage")


func _load_wanted() -> void:
	if _wanted == _loading:
		return
	preview.clear()
	_loading = _wanted
	if _loading:
		# A method, not a lambda: a lambda's freed owner isn't always seen before the call, and the
		# garage may be gone by the time the car is in.
		PackageLoader.load_async(_loading, _on_car_loaded)


func _on_car_loaded(pkg: VehiclePackage) -> void:
	if not is_inside_tree() or _loading != pkg.path:
		pkg.free_scenes()
		return
	if not pkg.ok():
		say("Car failed to load")
		return
	var entry := car(pkg.path)
	preview.show_package(pkg, platform_for(String(pkg.manifest.get("family", ""))))
	if not entry.is_empty() and entry.thumbnail == null:
		_render_thumbnail(pkg.path)


## A car without a thumbnail gets one from the turntable view, unless another car was picked
## meanwhile.
func _render_thumbnail(path: String) -> void:
	await get_tree().process_frame
	var png: PackedByteArray = await preview.thumbnail()
	if png.is_empty() or _loading != path:
		return
	GarageFiles.cache_thumbnail(path, png)
	var entry := car(path)
	if not entry.is_empty():
		entry.thumbnail = GarageFiles.thumbnail(path)
		grid.set_thumbnail(path, entry.thumbnail)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(preview) and preview.get_parent() == null:
		preview.free() # never lent to a page


## A platform that can show a car of `family` (for the turntable's fit).
static func platform_for(family: String) -> Dictionary:
	for mode in GameModes.list():
		for r in GameModes.classes(mode):
			if Fitting.compatible(r.platform, family):
				return r.platform
	return PlatformLoader.load_official(TrackSession.DEFAULT_PLATFORM).platform


static func family_name(family: String) -> String:
	return { "car": "Car", "open": "Open-wheel", "truck": "Truck", "moto": "Motorbike" }.get(family, family)


static func thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(-3)
	return s + out


## "Car · CC0-1.0 · 1,450 triangles"
static func details(entry: Dictionary) -> PackedStringArray:
	var m: Dictionary = entry.manifest
	return PackedStringArray([
		"By %s · version %d" % [m.author, int(m.get("version", 1))],
		"%s · %s · %s triangles" % [family_name(m.family), m.license, thousands(entry.triangles)],
	])
