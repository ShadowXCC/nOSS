class_name SumoPanel
extends Control
## A sumo match's HUD (D162, docs/ACCESSIBILITY.md): how many cars are left, which platform this
## one is on, how much of the platform is left, and the ram boost's charge as a bar and a word.
## Nothing relies on colour alone, and the warning before a platform steps is a word, not a flash.

var palette: Dictionary = Palette.PRESETS.default
var calm := false
var _cars := Label.new()
var _tier := Label.new()
var _ram := Label.new()
var _bar := ColorRect.new()
var _bar_back := ColorRect.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	offset_left = 40
	offset_top = 210
	offset_right = 600
	offset_bottom = 420
	for row: Array in [[_cars, 40, Vector2(0, 0)], [_tier, 30, Vector2(0, 54)], [_ram, 28, Vector2(0, 128)]]:
		var l: Label = row[0]
		l.add_theme_font_size_override("font_size", row[1])
		l.add_theme_color_override("font_color", Hud.TEXT)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 8)
		l.position = row[2]
		l.size = Vector2(480, row[1] + 10)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	for r: ColorRect in [_bar_back, _bar]:
		r.position = Vector2(0, 104)
		r.size = Vector2(240, 8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
	_bar_back.color = Color(1, 1, 1, 0.2)


## `left`: cars still in, of `total`. `tier`: the platform this car is on (0 is the top; -1 in
## the air or gone), of `tiers`. `shrink`: how much of that platform is left, 0..1. `charge`: the
## ram boost, 0..1. `warn`: the platform is about to lose a ring. `out`: this car is out.
func show_sumo(left: int, total: int, tier: int, tiers: int, shrink: float, charge: float, warn: bool, out: bool) -> void:
	_cars.text = "Out" if out else "%d left" % left
	_cars.add_theme_color_override("font_color", Hud.DIM if out else Hud.TEXT)
	if out:
		_tier.text = ""
	elif tier < 0:
		_tier.text = "Falling"
	else:
		var size := "Shrinking" if warn else "%d%%" % roundi(clampf(shrink, 0.0, 1.0) * 100.0)
		_tier.text = ("Tier %d/%d  ·  %s" % [tier + 1, tiers, size]) if tiers > 1 else size
	var ready := charge >= 1.0
	_bar.visible = not out
	_bar_back.visible = not out
	_bar.size.x = 240.0 * clampf(charge, 0.0, 1.0)
	_bar.color = palette.get("item_speed", Color.ORANGE)
	_ram.text = "" if out else ("Ram ready" if ready else "Ram")
	_ram.add_theme_color_override("font_color", Hud.TEXT if ready else Hud.DIM)
	accessibility_name = "%s. %s%s" % [_cars.text, _tier.text, (". " + _ram.text) if _ram.text else ""]


func cars_text() -> String:
	return _cars.text


func tier_text() -> String:
	return _tier.text


func ram_text() -> String:
	return _ram.text
