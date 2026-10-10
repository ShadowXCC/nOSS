class_name Hud
extends Control
## In-race HUD (docs/ART_AUDIO.md §5): speed, gear, RPM bar with shift light, lap timing and
## short messages. Text is short (NFR-06) and no cue relies on colour alone: deltas carry a
## sign, assists show their name.

const GOOD := Color(0.35, 0.9, 0.45)
const BAD := Color(1.0, 0.4, 0.35)
const TEXT := Color(0.97, 0.97, 0.95)
const DIM := Color(0.75, 0.75, 0.78)

var vehicle: Vehicle
var timer: LapTimer

var _speed := _label(96)
var _unit := _label(28, DIM)
var _gear := _label(72)
var _rpm := RpmBar.new()
var _lap := _label(34)
var _time := _label(48)
var _last := _label(28, DIM)
var _best := _label(28, DIM)
var _delta := _label(44)
var _message := _label(56)
var _assists := _label(26, Color(1.0, 0.8, 0.3))
var _car := _label(26, DIM)
var _fps := _label(24, DIM)
## F3 toggles a frame-rate readout.
var show_fps := false
var _delta_timer := 0.0
var _message_timer := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_speed, Vector2(1, 1), Vector2(-420, -220), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	_place(_unit, Vector2(1, 1), Vector2(-110, -150), HORIZONTAL_ALIGNMENT_LEFT, 100)
	_place(_gear, Vector2(1, 1), Vector2(-110, -240), HORIZONTAL_ALIGNMENT_CENTER, 80)
	_rpm.anchor_left = 1.0
	_rpm.anchor_right = 1.0
	_rpm.anchor_top = 1.0
	_rpm.anchor_bottom = 1.0
	_rpm.offset_left = -460
	_rpm.offset_right = -40
	_rpm.offset_top = -100
	_rpm.offset_bottom = -74
	_rpm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rpm)
	_place(_assists, Vector2(1, 1), Vector2(-460, -62), HORIZONTAL_ALIGNMENT_LEFT, 420)
	_place(_lap, Vector2(0, 0), Vector2(40, 28), HORIZONTAL_ALIGNMENT_LEFT, 400)
	_place(_time, Vector2(0, 0), Vector2(40, 66), HORIZONTAL_ALIGNMENT_LEFT, 400)
	_place(_last, Vector2(0, 0), Vector2(40, 128), HORIZONTAL_ALIGNMENT_LEFT, 400)
	_place(_best, Vector2(0, 0), Vector2(40, 162), HORIZONTAL_ALIGNMENT_LEFT, 400)
	_place(_delta, Vector2(0.5, 0), Vector2(-200, 40), HORIZONTAL_ALIGNMENT_CENTER, 400)
	_place(_message, Vector2(0.5, 0.3), Vector2(-500, 0), HORIZONTAL_ALIGNMENT_CENTER, 1000)
	_place(_car, Vector2(0, 1), Vector2(40, -60), HORIZONTAL_ALIGNMENT_LEFT, 800)
	_place(_fps, Vector2(1, 0), Vector2(-260, 28), HORIZONTAL_ALIGNMENT_RIGHT, 220)


func show_message(text: String, seconds := 2.0) -> void:
	_message.text = text
	_message_timer = seconds


func show_delta(delta: float) -> void:
	if is_nan(delta):
		return
	_delta.text = ("+%.2f" if delta >= 0.0 else "-%.2f") % absf(delta)
	_delta.add_theme_color_override("font_color", BAD if delta >= 0.0 else GOOD)
	_delta_timer = 3.0


func set_car_name(text: String) -> void:
	_car.text = text


func _process(delta: float) -> void:
	if vehicle and is_instance_valid(vehicle):
		var sim := vehicle.sim
		_speed.text = Settings.speed_text(sim.get_speed())
		_unit.text = Settings.speed_unit()
		var gear := sim.get_gear()
		_gear.text = "R" if gear < 0 else "N" if gear == 0 else str(gear)
		var redline := float(vehicle.platform.engine.redline_rpm)
		_rpm.value = sim.get_rpm() / float(vehicle.platform.engine.limiter_rpm)
		_rpm.shift_at = redline * 0.96 / float(vehicle.platform.engine.limiter_rpm)
		var t := sim.get_telemetry()
		var active := PackedStringArray()
		if t.tcs:
			active.append("TCS")
		if t.abs:
			active.append("ABS")
		_assists.text = "  ".join(active)
	if timer:
		_lap.text = "Lap %d" % timer.lap if timer.lap > 0 else "Out lap"
		_time.text = format_time(timer.lap_time) + ("" if timer.valid else "  ✕")
		_time.add_theme_color_override("font_color", TEXT if timer.valid else BAD)
		_last.text = "Last  " + (format_time(timer.last_lap) if timer.last_lap >= 0.0 else "-")
		_best.text = "Best  " + (format_time(timer.best_lap) if timer.best_lap >= 0.0 else "-")
		if timer.wrong_way:
			show_message("Wrong way", 0.2)
	_fps.visible = show_fps
	if show_fps:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
	_delta_timer -= delta
	_delta.visible = _delta_timer > 0.0
	_message_timer -= delta
	_message.visible = _message_timer > 0.0


static func format_time(t: float) -> String:
	if t < 0.0:
		return "-"
	var minutes := int(t / 60.0)
	return "%d:%06.3f" % [minutes, t - minutes * 60.0]


func _label(size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	return l


func _place(l: Label, anchor: Vector2, offset: Vector2, align: HorizontalAlignment, width: float) -> void:
	l.anchor_left = anchor.x
	l.anchor_right = anchor.x
	l.anchor_top = anchor.y
	l.anchor_bottom = anchor.y
	l.offset_left = offset.x
	l.offset_top = offset.y
	l.offset_right = offset.x + width
	l.offset_bottom = offset.y + l.get_theme_font_size("font_size") * 1.4
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


## RPM bar with a shift light: the bar turns into a flashing "SHIFT" block near the redline.
class RpmBar:
	extends Control
	var value := 0.0
	var shift_at := 0.9
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.55))
		var segments := 24
		var w := size.x / segments
		for i in segments:
			var f := float(i + 1) / segments
			if f > value + 0.001:
				break
			var c := Color(0.85, 0.85, 0.85)
			if f > shift_at:
				c = Color(1.0, 0.25, 0.2)
			elif f > shift_at - 0.15:
				c = Color(1.0, 0.75, 0.2)
			draw_rect(Rect2(i * w + 1, 2, w - 2, size.y - 4), c)
		if value >= shift_at and fmod(_t, 0.25) < 0.125:
			draw_rect(r, Color(1, 1, 1, 0.9), false, 3.0)
