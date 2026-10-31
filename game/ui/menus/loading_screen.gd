class_name LoadingScreen
extends Control
## Shown while a track loads off the main thread (NFR-04): what's loading, read out once. Then the
## garage cars in its traffic (D246), with a bar for how far they've got (not read out).

var text := "Loading track"

var _label: Label
var _bar: Control


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 24)
	add_child(box)
	_label = UiKit.label(text, 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	box.add_child(_label)
	_bar = UiKit.progress()
	_bar.visible = false
	box.add_child(_bar)


## Garage cars load now (`batch`, kept here till it's done): said once, the bar shows how far.
func load_garage(batch: GaragePreload) -> void:
	text = "Loading garage cars"
	if _label:
		_label.text = text
		_bar.visible = true
	else:
		ready.connect(func() -> void: _bar.visible = true, CONNECT_ONE_SHOT)
	batch.progressed.connect(func(done: int, of: int) -> void:
		if _bar:
			UiKit.set_progress(_bar, float(done) / maxi(of, 1)))
	add_child(batch)
