class_name PaintPage
extends MenuPage
## A car's colours (docs/UI_FLOW.md §8): its presets, then each paint slot's colour and finish, on
## the turntable as they change. Save writes them into the car; Back leaves it as it was.

var garage: Garage
## The car (a package path), and its name for the crumbs.
var path := ""
var car_name := ""
## Its paint.json, being changed.
var paint: Dictionary
var status: Label

var _was: Dictionary # as it was, for Back
var _saved := false


func _ready() -> void:
	title = "Paint"
	crumbs = ["Garage", car_name, "Paint"]
	back_hint = "Without saving"
	_was = paint.duplicate(true)
	super._ready()
	closed.connect(func() -> void:
		if not _saved:
			_apply(_was))


func _build() -> void:
	_fill()
	add_action(UiKit.button("Save", _save, "Save the paint"))
	status = GaragePage._status_line()
	add_footer(status)
	var box := VBoxContainer.new()
	set_pane(box)
	garage.lend_preview(self, box)


func _fill() -> void:
	for preset: Dictionary in paint.get("presets", []):
		add_row(UiKit.button(String(preset.name), _use_preset.bind(preset), "Its colours on every slot"))
	for slot: String in paint.slots:
		var data: Dictionary = paint.slots[slot]
		add_row(UiKit.color(slot.capitalize() + " colour", Color.html(data.color), func(c: Color) -> void:
			data.color = "#" + c.to_html(false).to_upper()
			_apply(paint)))
		add_row(UiKit.spinner(slot.capitalize() + " finish", FittingBay.FINISHES, data.finish, func(v: String) -> void:
			data.finish = v
			_apply(paint)))


## The preset's colours on every slot it names; the rows show them, the focus stays on it.
func _use_preset(preset: Dictionary) -> void:
	for slot: String in paint.slots:
		if preset.has(slot):
			paint.slots[slot].color = preset[slot]
		if preset.has("finish") and slot == "primary":
			paint.slots[slot].finish = preset.finish
	_apply(paint)
	var chosen := String(preset.name)
	rebuild_rows(_fill, func() -> Control:
		for c in _rows:
			if c is Button and (c as Button).text == chosen:
				return c
		return null)


## Shows `p` on the turntable's car.
func _apply(p: Dictionary) -> void:
	var visual := garage.preview.visual if is_instance_valid(garage.preview) else null
	if visual == null:
		return
	for slot: String in p.get("slots", {}):
		var data: Dictionary = p.slots[slot]
		visual.set_paint(slot, Color.html(data.color), data.finish)


func _save() -> void:
	var result := GarageFiles.update(path, { "paint.json": PackageWriter.canonical_json(paint).to_utf8_buffer() })
	if not result.ok:
		status.text = String(result.error)
		return
	_saved = true
	garage.grid.reload(path) # its version went up
	closed.emit()
	garage.say("Paint saved")
