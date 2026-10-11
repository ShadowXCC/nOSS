class_name SetupMenu
extends Control
## Car setup (PLT-04): the values the class lets you tune, as sliders that step with left and
## right. Changes apply when the menu closes, and are saved for this class and track.

signal closed

## Menu name and how its value reads, per tunable path: [label, hint, format, scale].
## The shown value is value × scale.
const NAMES := {
	"gearbox.final_drive": ["Final drive", "Higher: quicker, lower top speed", "%.2f", 1.0],
	"gearbox.ratios": ["Gear %d", "Higher: quicker in this gear", "%.2f", 1.0],
	"brakes.bias_front": ["Brake balance", "More front: steadier, less turn-in", "%d%% front", 100.0],
	"suspension.front.freq_hz": ["Front springs", "Stiffer: sharper, less grip on bumps", "%.2f Hz", 1.0],
	"suspension.rear.freq_hz": ["Rear springs", "Stiffer: more rotation", "%.2f Hz", 1.0],
	"suspension.roll_stiffness_front_share": ["Roll balance", "More front: more understeer", "%d%% front", 100.0],
	"aero.cl_a_front": ["Front wing", "More: more front grip, more drag", "%.2f", -1.0],
	"aero.cl_a_rear": ["Rear wing", "More: more rear grip, more drag", "%.2f", -1.0],
	"differential.power_lock": ["Diff lock", "More: better traction, more understeer", "%d%%", 100.0],
}
const SECTIONS := { "gearbox": "Gearing", "brakes": "Brakes", "suspension": "Suspension", "aero": "Aero", "differential": "Differential" }

var setup: Setup
var _rows: Array = []
var _sliders := {} # [path, gear] -> [slider, label]
var _list: VBoxContainer


func _ready() -> void:
	theme = UiKit.theme_for(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var list := UiKit.panel(self, "Setup", 900)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	list.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var section := ""
	for path in setup.paths():
		var top := path.get_slice(".", 0)
		if top != section:
			section = top
			var heading := UiKit.label(SECTIONS.get(top, top.capitalize()), 26)
			heading.modulate = UiKit.ACCENT
			_list.add_child(heading)
		if setup.is_per_gear(path):
			var ratios: Array = setup.get_value(path)
			for g in ratios.size():
				_add_row(path, g)
		else:
			_add_row(path, -1)
	if setup.paths().is_empty():
		_list.add_child(UiKit.label("No setup changes in this class"))
	var reset := UiKit.button("Reset", func() -> void:
		setup.reset()
		_refresh(), "Back to the class's own values")
	var back := UiKit.button("Back", func() -> void: closed.emit())
	list.add_child(reset)
	list.add_child(back)
	_rows.append(reset)
	_rows.append(back)
	UiKit.chain_focus(_rows)


func _add_row(path: String, gear: int) -> void:
	var info: Array = NAMES.get(path, [path, "", "%.2f", 1.0])
	var title: String = info[0] % (gear + 1) if gear >= 0 else info[0]
	var r: Dictionary = setup.allowed[path]
	var shown_scale: float = info[3]
	var row := HBoxContainer.new()
	var l := UiKit.label(title)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.accessibility_name = title
	s.accessibility_description = info[1]
	# Shown values: wings count downforce up, so their sliders run the other way.
	var a := float(r.min) * shown_scale
	var b := float(r.max) * shown_scale
	s.min_value = minf(a, b)
	s.max_value = maxf(a, b)
	s.step = float(r.step) * absf(shown_scale)
	s.custom_minimum_size = Vector2(260, 48)
	var value := Label.new()
	value.custom_minimum_size = Vector2(150, 0)
	row.add_child(s)
	row.add_child(value)
	_list.add_child(row)
	_rows.append(row)
	_sliders[[path, gear]] = [s, value, info]
	_show(path, gear)
	s.value_changed.connect(func(v: float) -> void:
		if gear >= 0:
			setup.set_gear(path, gear, v / shown_scale)
		else:
			setup.set_value(path, v / shown_scale)
		_show(path, gear))


## Shows the setup's value (after clamping and ordering) on its slider.
func _show(path: String, gear: int) -> void:
	var entry: Array = _sliders[[path, gear]]
	var s: HSlider = entry[0]
	var label: Label = entry[1]
	var info: Array = entry[2]
	var v: Variant = setup.get_value(path)
	var raw := float(v[gear]) if gear >= 0 else float(v)
	var shown := raw * float(info[3])
	s.set_value_no_signal(shown)
	var text: String = info[2] % (roundi(shown) if String(info[2]).contains("%d") else shown)
	label.text = text
	# Screen readers hear the value as it reads on screen ("Brake balance: 62% front").
	s.accessibility_name = "%s: %s" % [(info[0] as String) % (gear + 1) if gear >= 0 else info[0], text]


func _refresh() -> void:
	for key: Array in _sliders:
		_show(key[0], key[1])


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
