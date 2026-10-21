class_name ScorePanel
extends Control
## Score attack on the HUD (D114, docs/ART_AUDIO.md §5): the banked score; the chain with its
## combo multiplier and a bar for the time left before it banks; the speed step; and a short
## line for each pass ("Close miss +400", "Combo ×4", "Banked 2500", "Lost 1200"). Words carry
## every meaning, colour only adds to it.

const POP_S := 1.4

var _score := Label.new()
var _chain := Label.new()
var _speed := Label.new()
var _pop := Label.new()
var _bar := ColorRect.new()
var _bar_back := ColorRect.new()
var _pop_left := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	offset_left = 40
	offset_top = 210
	offset_right = 560
	offset_bottom = 420
	var y := 0.0
	for row: Array in [[_score, 52], [_chain, 34], [_speed, 26], [_pop, 40]]:
		var l: Label = row[0]
		l.add_theme_font_size_override("font_size", row[1])
		l.add_theme_color_override("font_color", Hud.TEXT)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 8)
		l.position = Vector2(0, y)
		l.size = Vector2(520, row[1] + 10)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		y += row[1] + 14
		if l == _chain:
			for r: ColorRect in [_bar_back, _bar]:
				r.position = Vector2(0, y - 8)
				r.size = Vector2(300, 6)
				r.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(r)
			_bar_back.color = Color(1, 1, 1, 0.2)
			_bar.color = Hud.GOOD
			y += 6
	_speed.add_theme_color_override("font_color", Hud.DIM)
	_pop.accessibility_live = AccessibilityServer.AccessibilityLiveMode.LIVE_POLITE


## Shows `rules` now, the car at `speed_kmh`, `now` on the rules' clock.
func show_rules(rules: ScoreAttack, speed_kmh: float, now: float) -> void:
	_score.text = "Score %d" % rules.banked
	if rules.combo > 0:
		_chain.text = "+%d ×%s" % [rules.chain, _num(rules.multiplier())]
		var left := clampf(1.0 - (now - rules.last_event) / ScoreAttack.COMBO_S, 0.0, 1.0)
		_bar.size.x = 300.0 * left
		_bar.visible = true
		_bar_back.visible = true
	else:
		_chain.text = ""
		_bar.visible = false
		_bar_back.visible = false
	var step := ScoreAttack.speed_multiplier(speed_kmh)
	if rules.paused:
		_speed.text = "Wrong way: no score"
	elif step <= 0.0:
		var least: float = ScoreAttack.SPEED_STEPS.back()[0]
		_speed.text = "Under %s %s: no score" % [Settings.speed_text(least / 3.6), Settings.speed_unit()]
	else:
		_speed.text = "Speed ×%s" % _num(step)


## A line for what just happened (it fades after POP_S).
func pop(news: Dictionary) -> void:
	_pop.text = String(news.text)
	var good := String(news.kind) not in ["lost"]
	_pop.add_theme_color_override("font_color", Hud.GOOD if good else Hud.BAD)
	_pop_left = POP_S
	_pop.modulate.a = 1.0


func _process(delta: float) -> void:
	if _pop_left > 0.0:
		_pop_left -= delta
		_pop.modulate.a = clampf(_pop_left / 0.4, 0.0, 1.0)
		if _pop_left <= 0.0:
			_pop.text = ""


static func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.2f" % x if not is_equal_approx(x * 2.0, roundf(x * 2.0)) else "%.1f" % x
