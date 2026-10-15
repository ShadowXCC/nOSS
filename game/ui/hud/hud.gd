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
## The racer this HUD follows, and the session's race control (position, flags, standings).
var racer: Racer
var race: RaceControl
## The player's camera (where the close-car arrows point from).
var camera: Camera3D
## The player's colours (docs/ACCESSIBILITY.md §2).
var palette: Dictionary = Palette.PRESETS.default

## HUD elements that can be hidden on their own, and the presets (docs/ACCESSIBILITY.md §6).
const ELEMENTS := [["speed", "Speed and gear"], ["timing", "Lap times"], ["delta", "Delta"], ["position", "Position"],
	["standings", "Standings"], ["flags", "Flags"], ["assists", "Active assists"], ["car", "Car name"]]
const PRESETS := {
	"full": [],
	"minimal": ["timing", "delta", "standings", "assists", "car"],
	"off": ["speed", "timing", "delta", "position", "standings", "flags", "assists", "car"],
}

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
var _badge := _label(34)
var _position := _label(60)
var _gaps := _label(26, DIM)
var _standings := _label(24)
var _flag := FlagPanel.new()
var _lights := Lights.new()
var _delta_bar := DeltaBar.new()
var _slip := SlipIcons.new()
var _arrows := Arrows.new()
var _captions := _label(32)
var _caption_lines: Array = [] # [text, seconds left]
var _hidden := {}
var _show_slip := false
var _show_arrows := false
var _reduce_flashing := false
var _grinds := 0
## The start lights show green this long when they go out (or at a rolling start's green).
const GO_SHOW_S := 1.0
var _go_time := 0.0
var _race_phase := -1
## F3 toggles a frame-rate readout.
var show_fps := false
var high_contrast := false
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
	_place(_fps, Vector2(1, 0), Vector2(-260, 76), HORIZONTAL_ALIGNMENT_RIGHT, 220)
	_place(_badge, Vector2(1, 0), Vector2(-140, 24), HORIZONTAL_ALIGNMENT_CENTER, 100)
	_badge.visible = false
	_place(_position, Vector2(1, 0), Vector2(-420, 16), HORIZONTAL_ALIGNMENT_RIGHT, 260)
	_place(_gaps, Vector2(1, 0), Vector2(-460, 100), HORIZONTAL_ALIGNMENT_RIGHT, 420)
	_place(_standings, Vector2(1, 0), Vector2(-460, 150), HORIZONTAL_ALIGNMENT_RIGHT, 420)
	_standings.autowrap_mode = TextServer.AUTOWRAP_OFF
	_standings.offset_bottom = _standings.offset_top + 34.0 * 6
	_fps.offset_top = 280
	_fps.offset_bottom = 310
	for c: Control in [_flag, _lights, _delta_bar, _slip, _arrows]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
	_slip.anchor_left = 1.0
	_slip.anchor_right = 1.0
	_slip.anchor_top = 1.0
	_slip.anchor_bottom = 1.0
	_slip.offset_left = -560
	_slip.offset_right = -480
	_slip.offset_top = -230
	_slip.offset_bottom = -120
	_slip.visible = false
	_arrows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_place(_captions, Vector2(0.5, 1), Vector2(-700, -200), HORIZONTAL_ALIGNMENT_CENTER, 1400)
	_captions.offset_bottom = _captions.offset_top + 100
	_captions.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_captions.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE
	_flag.anchor_left = 0.5
	_flag.anchor_right = 0.5
	_flag.offset_left = -170
	_flag.offset_right = 170
	_flag.offset_top = 150
	_flag.offset_bottom = 214
	_lights.anchor_left = 0.5
	_lights.anchor_right = 0.5
	_lights.anchor_top = 0.22
	_lights.anchor_bottom = 0.22
	_lights.offset_left = -260
	_lights.offset_right = 260
	_lights.offset_bottom = 110
	_delta_bar.anchor_left = 0.5
	_delta_bar.anchor_right = 0.5
	_delta_bar.offset_left = -200
	_delta_bar.offset_right = 200
	_delta_bar.offset_top = 104
	_delta_bar.offset_bottom = 134


## The player's tag ("P2") in their colour, on a dark plate so it reads on any colour.
func set_player(tag: String, color: Color, show: bool) -> void:
	_badge.text = tag
	_badge.visible = show
	var plate := StyleBoxFlat.new()
	plate.bg_color = color
	plate.set_corner_radius_all(6)
	plate.set_content_margin_all(4)
	_badge.add_theme_stylebox_override("normal", plate)
	_badge.add_theme_color_override("font_color", Color.BLACK)
	_badge.add_theme_constant_override("outline_size", 0)
	_badge.accessibility_name = "Player %s" % tag.substr(1)


## Re-reads the player's HUD options (docs/ACCESSIBILITY.md §2): font, and high contrast
## (solid plates behind text, thicker outlines).
func apply_profile(profile: PlayerProfile) -> void:
	theme = UiKit.theme_with(String(profile.data.get("font", "retro")))
	high_contrast = bool(profile.data.get("high_contrast", false))
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0, 0, 0, 0.82)
	plate.set_corner_radius_all(4)
	plate.content_margin_left = 8
	plate.content_margin_right = 8
	for l: Label in [_speed, _unit, _gear, _lap, _time, _last, _best, _delta, _message, _assists, _car, _fps, _position, _gaps, _standings]:
		var size := l.get_theme_font_size("font_size")
		if high_contrast:
			l.add_theme_stylebox_override("normal", plate)
			l.add_theme_constant_override("outline_size", maxi(6, size / 5))
		else:
			l.remove_theme_stylebox_override("normal")
			l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	_rpm.high_contrast = high_contrast
	_flag.high_contrast = high_contrast
	_delta_bar.high_contrast = high_contrast
	_reduce_flashing = bool(profile.data.get("reduce_flashing", false))
	_lights.reduce_flashing = _reduce_flashing
	palette = Palette.of(profile)
	_rpm.palette = palette
	_rpm.reduce_flashing = _reduce_flashing
	_rpm.shift_light = bool(profile.data.get("shift_light", true))
	_flag.palette = palette
	_delta_bar.palette = palette
	_slip.palette = palette
	_assists.add_theme_color_override("font_color", palette.warn)
	_show_slip = bool(profile.data.get("slip_indicator", false))
	_show_arrows = bool(profile.data.get("sound_arrows", false))
	_hidden.clear()
	for id: String in PRESETS.get(String(profile.data.get("hud_preset", "full")), []):
		_hidden[id] = true
	var extra: Variant = profile.data.get("hud_hidden", [])
	if extra is Array:
		for id: Variant in extra:
			_hidden[String(id)] = true
	for item: Array in [["speed", [_speed, _unit, _gear, _rpm]], ["timing", [_time, _last, _best]], ["car", [_car]]]:
		for c: CanvasItem in item[1]:
			c.visible = not _hidden.has(item[0])
	queue_redraw()


## Whether a HUD element is shown (not hidden by the player's preset or choice).
func shows(id: String) -> bool:
	return not _hidden.has(id)


## A spoken line, also shown as text (docs/ACCESSIBILITY.md §3: nothing is voice-only).
func caption(text: String, seconds := 3.5) -> void:
	_caption_lines.append([text, seconds])
	if _caption_lines.size() > 2:
		_caption_lines.pop_front()
	_captions.text = "\n".join(PackedStringArray(_caption_lines.map(func(l: Array) -> String: return l[0])))


## Spotter: cars alongside on the left and right (edge markers).
func set_spotter(left: bool, right: bool) -> void:
	_arrows.left_car = left
	_arrows.right_car = right


func show_message(text: String, seconds := 2.0) -> void:
	_message.text = text
	_message_timer = seconds


func show_delta(delta: float) -> void:
	if is_nan(delta):
		return
	_delta.text = ("+%.2f" if delta >= 0.0 else "-%.2f") % absf(delta)
	_delta.add_theme_color_override("font_color", palette.bad if delta >= 0.0 else palette.good)
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
		if t.get("esc", false):
			active.append("SC")
		# A refused gear change grinds; the message says why (never sound alone).
		var grinds := int(t.get("grinds", 0))
		if grinds > _grinds:
			show_message("Clutch", 1.0)
		_grinds = grinds
		_assists.text = "  ".join(active)
		_assists.visible = not _assists.text.is_empty() and shows("assists") # no empty plate in high contrast
		_slip.visible = _show_slip and shows("speed")
		if _slip.visible:
			_slip.wheels = t.wheels
	_update_race(delta)
	if timer:
		var session := race.session_text(racer) if race and racer else ""
		_lap.text = session if session else ("Lap %d" % timer.lap if timer.lap > 0 else "Out lap")
		_time.text = format_time(timer.lap_time) + ("" if timer.valid else "  ✕")
		_time.add_theme_color_override("font_color", TEXT if timer.valid else palette.bad)
		_last.text = "Last  " + (format_time(timer.last_lap) if timer.last_lap >= 0.0 else "-")
		_best.text = "Best  " + (format_time(timer.best_lap) if timer.best_lap >= 0.0 else "-")
		if timer.wrong_way:
			show_message("Wrong way", 0.2)
	_lap.visible = shows("timing") or (race != null and race.kind == "race")
	_update_captions(delta)
	_update_arrows()
	_fps.visible = show_fps
	if show_fps:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
	_delta_timer -= delta
	_delta.visible = _delta_timer > 0.0 and shows("delta")
	_message_timer -= delta
	_message.visible = _message_timer > 0.0


## Position, gaps, standings, flag, lights and the live delta (race sessions).
func _update_race(delta := 0.0) -> void:
	var racing := race != null and racer != null and race.kind in ["race", "practice", "qualifying"]
	_position.visible = racing and shows("position")
	_gaps.visible = racing and race.kind == "race" and shows("position")
	_standings.visible = racing and shows("standings")
	_flag.flag = racer.flag if racer and shows("flags") else ""
	var phase := race.phase if race else -1
	if phase == RaceControl.Phase.RUNNING and _race_phase in [RaceControl.Phase.COUNTDOWN, RaceControl.Phase.FORMATION]:
		_go_time = GO_SHOW_S
	_race_phase = phase
	_go_time -= delta
	_lights.count = race.light_count if race else RaceControl.LIGHTS
	_lights.go = _go_time > 0.0
	_lights.lit = race.lights if phase == RaceControl.Phase.COUNTDOWN else _lights.count if _lights.go else 0
	_lights.visible = _lights.lit > 0
	var syncing := race.sync_text() if race else ""
	if syncing:
		show_message(syncing, 0.2)
	var live := timer.live_delta() if timer else NAN
	_delta_bar.visible = not is_nan(live) and shows("delta")
	if not is_nan(live):
		_delta_bar.delta = live
	if not racing:
		return
	var order := race.standings()
	var me := order.find(racer)
	_position.text = "P%d/%d" % [me + 1, order.size()]
	var lines := PackedStringArray()
	var shown := {}
	for i in order.size():
		if i < 3 or absi(i - me) <= 1:
			shown[i] = true
	var last := -1
	for i in order.size():
		if not shown.has(i):
			continue
		if last >= 0 and i > last + 1:
			lines.append("…")
		var r: Racer = order[i]
		var tag := "%d %s" % [i + 1, r.display_name if r.display_name.length() <= 10 else r.display_name.substr(0, 10)]
		if race.kind != "race" and r.timer.best_lap > 0.0:
			tag += "  " + format_time(r.timer.best_lap)
		lines.append(("» " if r == racer else "") + tag)
		last = i
	_standings.text = "\n".join(lines)
	if race.kind == "race" and race.phase in [RaceControl.Phase.RUNNING, RaceControl.Phase.CHECKERED]:
		var gaps := PackedStringArray()
		if me > 0:
			gaps.append("▲ %s  -%.1f" % [order[me - 1].display_name, absf(race.gap_seconds(racer, order[me - 1]))])
		if me + 1 < order.size():
			gaps.append("▼ %s  +%.1f" % [order[me + 1].display_name, absf(race.gap_seconds(order[me + 1], racer))])
		_gaps.text = "   ".join(gaps)
	else:
		_gaps.text = ""


func _update_captions(delta: float) -> void:
	if _caption_lines.is_empty():
		_captions.visible = false
		return
	for line: Array in _caption_lines:
		line[1] -= delta
	var before := _caption_lines.size()
	_caption_lines = _caption_lines.filter(func(l: Array) -> bool: return l[1] > 0.0)
	if _caption_lines.size() != before:
		_captions.text = "\n".join(PackedStringArray(_caption_lines.map(func(l: Array) -> String: return l[0])))
	_captions.visible = not _caption_lines.is_empty()


## Close cars out of view (sound direction, docs/ACCESSIBILITY.md §3): an arrow at the edge.
func _update_arrows() -> void:
	_arrows.dirs.clear()
	if not _show_arrows or camera == null or racer == null or racer.vehicle == null or racer.session == null:
		_arrows.queue_redraw()
		return
	var me := racer.vehicle.global_position
	var cam_basis := camera.global_basis
	_arrows.sirens.clear()
	_arrows.incoming.clear()
	if racer.session.kart:
		# A Seeker or the Leader Hunter coming for this player (D146).
		for e: Dictionary in racer.session.kart.entities.list.values():
			if e.target == racer and e.kind in ["seeker", "leader_hunter"] and (e.pos as Vector3).distance_to(me) < Arrows.SIREN_RANGE_M:
				var local_e := cam_basis.inverse() * ((e.pos as Vector3) - me)
				_arrows.incoming.append([Vector2(local_e.x, local_e.z).normalized(), "Hunter" if e.kind == "leader_hunter" else "Seeker"])
	for r in racer.session.racers:
		if r == racer or r.vehicle == null or r.waiting:
			continue
		var to := r.vehicle.global_position - me
		var siren := r.vehicle.siren and to.length() < Arrows.SIREN_RANGE_M
		if to.length() > Arrows.RANGE_M and not siren:
			continue
		var local := cam_basis.inverse() * to # camera: -Z forward, +X right
		var dir := Vector2(local.x, local.z) # screen: +y down = behind
		if siren:
			_arrows.sirens.append(dir.normalized()) # heard wherever it is
			continue
		if local.z < -to.length() * 0.6:
			continue # well in front, in view
		_arrows.dirs.append(dir.normalized())
	_arrows.queue_redraw()


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


## The flag shown to this player: an icon and its word, never colour alone
## (docs/ACCESSIBILITY.md §2). Checkered and blue get patterns too.
class FlagPanel:
	extends Control
	const WORDS := { "green": "Green", "yellow": "Yellow", "blue": "Blue", "checkered": "Finish" }
	var palette: Dictionary = Palette.PRESETS.default
	var flag := "":
		set(value):
			if value != flag:
				flag = value
				visible = flag != ""
				accessibility_name = "%s flag" % WORDS.get(flag, "")
				queue_redraw()
	var high_contrast := false

	func _init() -> void:
		visible = false
		accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE

	func _draw() -> void:
		if flag == "":
			return
		var plate := Rect2(Vector2.ZERO, size)
		draw_rect(plate, Color(0, 0, 0, 0.9 if high_contrast else 0.6))
		var icon := Rect2(Vector2(10, 8), Vector2(size.y * 1.3, size.y - 16))
		var c: Color = palette.get("flag_" + flag, Color.WHITE)
		if flag == "checkered":
			var n := 4
			var cell := icon.size / Vector2(n * 1.5, n)
			for x in int(n * 1.5):
				for y in n:
					draw_rect(Rect2(icon.position + Vector2(x, y) * cell, cell), Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
		else:
			draw_rect(icon, c)
			if flag == "blue":
				# A diagonal stripe, so blue doesn't rely on its colour.
				draw_line(icon.position + Vector2(0, icon.size.y), icon.position + Vector2(icon.size.x, 0), palette.flag_yellow, 6.0)
		draw_rect(icon, Color.WHITE, false, 2.0)
		var font := get_theme_default_font()
		var fs := 34
		draw_string_outline(font, Vector2(icon.end.x + 16, size.y * 0.5 + fs * 0.35), WORDS.get(flag, ""), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.BLACK)
		draw_string(font, Vector2(icon.end.x + 16, size.y * 0.5 + fs * 0.35), WORDS.get(flag, ""), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## Start lights (five for a race, three for an online start), red one per second, then all
## green for a moment when they go out. They never flash; with Reduce flashing they're also
## dimmer against the plate.
class Lights:
	extends Control
	var lit := 0:
		set(value):
			if value != lit:
				lit = value
				accessibility_name = "Go" if go else "%d of %d" % [lit, count]
				queue_redraw()
	var go := false:
		set(value):
			if value != go:
				go = value
				accessibility_name = "Go" if go else "%d of %d" % [lit, count]
				queue_redraw()
	var count := 5:
		set(value):
			if value != count:
				count = value
				queue_redraw()
	var reduce_flashing := false

	func _init() -> void:
		accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.75))
		var r := size.y * 0.36
		for i in count:
			var center := Vector2(size.x * (i + 0.5) / float(count), size.y * 0.5)
			var on := i < lit
			var col := (Color(0.15, 0.85, 0.25) if go else Color(0.95, 0.12, 0.1)) if on else Color(0.2, 0.2, 0.22)
			if on and reduce_flashing:
				col = col.darkened(0.3)
			draw_circle(center, r, col)
			draw_arc(center, r, 0.0, TAU, 32, Color.WHITE, 2.0)


## Live delta to the best lap: a bar from the middle (left = faster, right = slower) with the
## value as signed text, so it never relies on colour.
class DeltaBar:
	extends Control
	const RANGE_S := 2.0
	var delta := 0.0:
		set(value):
			delta = value
			queue_redraw()
	var high_contrast := false
	var palette: Dictionary = Palette.PRESETS.default

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.9 if high_contrast else 0.5))
		var mid := size.x * 0.5
		var f := clampf(delta / RANGE_S, -1.0, 1.0)
		var w := absf(f) * mid
		var c: Color = palette.bad if delta > 0.0 else palette.good
		draw_rect(Rect2(mid if f > 0.0 else mid - w, 4, w, size.y - 8), c)
		draw_line(Vector2(mid, 0), Vector2(mid, size.y), Color.WHITE, 2.0)
		var text := ("+%.2f" if delta >= 0.0 else "-%.2f") % absf(delta)
		var font := get_theme_default_font()
		var x := size.x + 12
		draw_string_outline(font, Vector2(x, size.y - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 5, Color.BLACK)
		draw_string(font, Vector2(x, size.y - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)


## Slip indicator (docs/ACCESSIBILITY.md §3): the four tires, filled when sliding and crossed
## when locked, so it doesn't rely on colour.
class SlipIcons:
	extends Control
	const SLIDE_SPEED := 2.5
	const LOCK_RATIO := -0.25
	var wheels: Array = []:
		set(value):
			wheels = value
			queue_redraw()
	var palette: Dictionary = Palette.PRESETS.default

	func _draw() -> void:
		var n := mini(wheels.size(), 4)
		var cell := Vector2(size.x / 2.0, size.y / 2.0)
		for i in n:
			var w: Dictionary = wheels[i]
			# Wheels 0-1 are the front pair (left, right), 2-3 the rear.
			var at := Vector2((1 - (i % 2)) * cell.x, (i / 2) * cell.y)
			var r := Rect2(at + cell * 0.2, cell * 0.6)
			var locked := bool(w.contact) and float(w.slip_ratio) < LOCK_RATIO
			var sliding := bool(w.contact) and float(w.slip_speed) > SLIDE_SPEED
			if sliding or locked:
				draw_rect(r, palette.slip)
			draw_rect(r, Color.WHITE, false, 2.0)
			if locked:
				draw_line(r.position, r.end, Color.BLACK, 3.0)
				draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color.BLACK, 3.0)


## Edge arrows toward close cars out of view, and spotter markers for cars alongside.
class Arrows:
	extends Control
	const RANGE_M := 15.0
	## A siren is shown from this far (D115): a hollow arrow marked "Siren".
	const SIREN_RANGE_M := 300.0
	var dirs: Array[Vector2] = []
	var sirens: Array[Vector2] = []
	## Items coming for this player (kart): [[direction, "Seeker"]], drawn like sirens.
	var incoming: Array = []
	var left_car := false:
		set(value):
			if value != left_car:
				left_car = value
				queue_redraw()
	var right_car := false:
		set(value):
			if value != right_car:
				right_car = value
				queue_redraw()

	func _draw() -> void:
		var center := size / 2.0
		for d in dirs:
			# Where the ray from the centre leaves the screen, a little inside.
			var t := minf((size.x / 2.0 - 40.0) / maxf(absf(d.x), 1e-3), (size.y / 2.0 - 40.0) / maxf(absf(d.y), 1e-3))
			var tip := center + d * t
			var side := Vector2(-d.y, d.x) * 18.0
			draw_colored_polygon(PackedVector2Array([tip + d * 22.0, tip - d * 10.0 + side, tip - d * 10.0 - side]), Color(1, 1, 1, 0.85))
		var font := get_theme_default_font()
		for hollow: Array in sirens.map(func(v: Vector2) -> Array: return [v, "Siren"]) + incoming:
			var d: Vector2 = hollow[0]
			var label: String = hollow[1]
			var t := minf((size.x / 2.0 - 70.0) / maxf(absf(d.x), 1e-3), (size.y / 2.0 - 70.0) / maxf(absf(d.y), 1e-3))
			var tip := center + d * t
			var side := Vector2(-d.y, d.x) * 26.0
			var points := PackedVector2Array([tip + d * 32.0, tip - d * 14.0 + side, tip - d * 14.0 - side, tip + d * 32.0])
			draw_polyline(points, Color(1, 1, 1, 0.95), 5.0)
			var at := tip - d * 50.0 - Vector2(36.0, -10.0)
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color.BLACK)
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		for item: Array in [[left_car, 0.0, "◀ Car"], [right_car, size.x - 26.0, "Car ▶"]]:
			if not item[0]:
				continue
			var x: float = item[1]
			draw_rect(Rect2(x, size.y * 0.3, 26.0, size.y * 0.4), Color(1, 1, 1, 0.8))
			var text_x := x + 34.0 if x == 0.0 else x - 120.0
			draw_string_outline(font, Vector2(text_x, size.y * 0.5), item[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color.BLACK)
			draw_string(font, Vector2(text_x, size.y * 0.5), item[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)


## RPM bar with a shift light: the bar turns into a flashing "SHIFT" block near the redline.
class RpmBar:
	extends Control
	## Flashes 2.5 times a second (under the 3 per second cap); with Reduce flashing it stays
	## lit instead, at lower contrast.
	const FLASH_HZ := 2.5
	var value := 0.0
	var shift_at := 0.9
	var high_contrast := false
	var shift_light := true
	var reduce_flashing := false
	var palette: Dictionary = Palette.PRESETS.default
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.95 if high_contrast else 0.55))
		if high_contrast:
			draw_rect(r.grow(2.0), Color.WHITE, false, 2.0)
		var segments := 24
		var w := size.x / segments
		for i in segments:
			var f := float(i + 1) / segments
			if f > value + 0.001:
				break
			var c := Color(0.85, 0.85, 0.85)
			if f > shift_at:
				c = palette.line_brake
			elif f > shift_at - 0.15:
				c = palette.warn
			draw_rect(Rect2(i * w + 1, 2, w - 2, size.y - 4), c)
		if shift_light and value >= shift_at:
			if reduce_flashing:
				draw_rect(r, Color(1, 1, 1, 0.6), false, 3.0)
			elif fmod(_t * FLASH_HZ, 1.0) < 0.5:
				draw_rect(r, Color(1, 1, 1, 0.9), false, 3.0)
