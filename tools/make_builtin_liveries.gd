extends Node
## Makes the built-in cars' stock liveries (docs/VEHICLE_PACKAGE.md §12):
## content/liveries/noss_box.json, noss_open.json and noss_kart.json. Players and AI on a built-in
## car wear its one. No base paint, and every colour is linked to the car's paint (primary,
## secondary, contrast), so presets, AI paint and online colours show through. Laid out with the
## Fitting Bay's own livery edits, so every layer sits on the body:
##   tools/godot.sh --headless res://tools/make_builtin_liveries.tscn

const CARS := ["noss_box", "noss_open", "noss_kart"]
const OUT := "res://content/liveries/%s.json"


func _ready() -> void:
	for car: String in CARS:
		var pkg := PackageLoader.load_package("res://content/cars/" + car)
		var draft := FittingDraft.from_package(pkg)
		pkg.free_scenes()
		draft.liveries = []
		draft.worn = ""
		draft.id = String(pkg.manifest.id)
		var e := LiveryEdit.new(draft)
		e.new_livery()
		var l := e.livery()
		l.erase("base")
		l.id = car.replace("_", "-") + "-stock"
		l.name = "Stock"
		draft.editing = l.id
		draft.worn = l.id
		call("_" + car, e)
		var out := LiveryData.clean(l)
		out.car = { "id": draft.id, "model": String(pkg.manifest.files["model/body.glb"]), "name": String(pkg.manifest.name) }
		out = LiveryData.clean(out)
		var f := FileAccess.open(OUT % car, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  ", true) + "\n")
		f.close()
		print("%s: %d layers" % [car, out.layers.size()])
		draft.free_scene()
	get_tree().quit()


## Adds `shape` on `side` at (along, height) metres, `size` its longer side, `stretch` width
## over height, turned `turn` degrees, in `color`; mirrored onto the other side when `mirror`.
func _layer(e: LiveryEdit, kind: String, shape: String, side: String, along: float, height: float, size: float,
		stretch: float, color: String, mirror := false, turn := 0.0, depth := 0.0) -> Dictionary:
	e.side = side
	e.add(kind, shape)
	e.place_side(side)
	e.slide("along", along)
	e.slide("height", height)
	if turn != 0.0:
		e.set_turn(turn)
	e.set_stretch(stretch)
	e.set_size(size)
	if depth > 0.0:
		e.set_depth(depth)
	e.set_value("color", color)
	if mirror:
		e.set_value("mirror", true)
	return e.current()


func _noss_box(e: LiveryEdit) -> void:
	# Twin stripes nose to tail over the hood, roof and boot.
	var stripes := _layer(e, "shape", "stripes", "top", 0.0, 0.0, 4.5, 4.5 / 0.72, "secondary", false, 90.0, 0.7)
	stripes.params = [0.09, 0.62]
	# A roundel with the race number on each door, and speed lines on the front wings.
	_layer(e, "shape", "ellipse", "left", -0.15, 0.6, 0.6, 1.0, "contrast", true)
	_layer(e, "number", "", "left", -0.15, 0.6, 0.46, 1.15, "primary", true)
	var lines := _layer(e, "shape", "speed_lines", "left", 1.2, 0.5, 0.9, 2.6, "secondary", true)
	lines.params = [0.25, 0.6]


func _noss_open(e: LiveryEdit) -> void:
	# A stripe down the middle, a number on the nose and the sidepods.
	var stripe := _layer(e, "shape", "stripes", "top", 0.2, 0.0, 4.2, 4.2 / 0.26, "secondary", false, 90.0, 0.6)
	stripe.params = [0.0, 0.5]
	_layer(e, "shape", "ellipse", "left", -0.55, 0.42, 0.42, 1.0, "contrast", true)
	_layer(e, "number", "", "left", -0.55, 0.42, 0.32, 1.15, "primary", true)
	_layer(e, "number", "", "top", 1.75, 0.0, 0.3, 1.15, "contrast", false, 90.0)
	var chev := _layer(e, "shape", "chevrons", "left", 0.45, 0.4, 0.5, 2.5, "secondary", true)
	chev.params = [0.3, 0.4]


func _noss_kart(e: LiveryEdit) -> void:
	# A number plate on the nose (read from in front) and on each side pod.
	_layer(e, "shape", "rect", "top", 0.78, 0.0, 0.3, 1.25, "contrast", false, 180.0, 0.25).params = [0.4, 0.0]
	_layer(e, "number", "", "top", 0.78, 0.0, 0.2, 1.15, "primary", false, 180.0, 0.25)
	_layer(e, "shape", "rect", "left", -0.25, 0.22, 0.3, 1.4, "contrast", true, 0.0, 0.2).params = [0.4, 0.0]
	_layer(e, "number", "", "left", -0.25, 0.22, 0.18, 1.15, "primary", true, 0.0, 0.2)
	var stripe := _layer(e, "shape", "stripes", "left", 0.25, 0.22, 0.5, 3.0, "secondary", true)
	stripe.params = [0.1, 0.4]
