class_name SumoPanel
extends Control
## A sumo match's HUD (D162, docs/ACCESSIBILITY.md): how many cars are left, which platform this
## one is on, how much of the platform is left, and the ram boost's charge as a bar and a word.
## Nothing relies on colour alone, and the warning before a platform steps is a word, not a flash.
## In a Team Battle (D234) the top line is this car's team, beside a swatch of its colour, and a
## roster under it counts each team's cars still in, this car's team first.

## How far the rows under the roster move down for it.
const ROSTER_H := 42

var palette: Dictionary = Palette.PRESETS.default
var calm := false
var _cars := Label.new()
var _tier := Label.new()
var _ram := Label.new()
var _bar := ColorRect.new()
var _bar_back := ColorRect.new()
## Team Battle: this car's team (-1: none), its swatch, and the roster ([team, cars in] each).
var _team := -1
var _swatch := ColorRect.new()
var _roster_row := HBoxContainer.new()
var _roster: Array = []


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
	_swatch.position = Vector2(-18, 8)
	_swatch.size = Vector2(10, 36)
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swatch.visible = false
	add_child(_swatch)
	_roster_row.position = Vector2(0, 52)
	_roster_row.add_theme_constant_override("separation", 22)
	_roster_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roster_row.visible = false
	add_child(_roster_row)


## Team Battle (D234): this car's team and every team's cars still in, [[team, count], ...] with
## its own first. Called before show_sumo; -1 (every car for itself) puts the rows back.
func show_teams(team: int, roster: Array) -> void:
	var was := _team >= 0
	_team = team
	_roster = roster
	_swatch.visible = team >= 0
	_swatch.color = SumoTeams.color_of(team)
	_roster_row.visible = team >= 0
	if (team >= 0) != was:
		var down := ROSTER_H if team >= 0 else 0
		_tier.position.y = 54 + down
		_bar.position.y = 104 + down
		_bar_back.position.y = 104 + down
		_ram.position.y = 128 + down
	while _roster_row.get_child_count() < roster.size():
		_roster_row.add_child(_roster_entry())
	for i in _roster_row.get_child_count():
		var entry := _roster_row.get_child(i) as HBoxContainer
		entry.visible = i < roster.size()
		if not entry.visible:
			continue
		var t := int(roster[i][0])
		var n := int(roster[i][1])
		(entry.get_child(0) as ColorRect).color = SumoTeams.color_of(t)
		var l := entry.get_child(1) as Label
		l.text = "%s %d" % [SumoTeams.name_of(t), n]
		entry.modulate.a = 1.0 if n > 0 else 0.45


func _roster_entry() -> HBoxContainer:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 8)
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(8, 26)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	entry.add_child(swatch)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Hud.TEXT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(l)
	return entry


## `left`: cars still in, of `total`. `tier`: the platform this car is on (0 is the top; -1 in
## the air or gone), of `tiers`. `shrink`: how much of that platform is left, 0..1. `charge`: the
## ram boost, 0..1. `warn`: the platform is about to lose a ring. `out`: this car is out.
## `watching`: what an out car is being shown instead of its own (D185). `prompt`: what an out
## player can do, on the ram line (the fast-forward, D220).
func show_sumo(left: int, total: int, tier: int, tiers: int, shrink: float, charge: float, warn: bool, out: bool, watching := "", prompt := "") -> void:
	# Out, how many are left still matters: that is the match you are watching.
	if _team >= 0:
		var mine := "Team %s" % SumoTeams.name_of(_team)
		_cars.text = ("Out  ·  %s" % mine) if out else mine
	else:
		_cars.text = ("Out  ·  %d left" % left) if out else "%d left" % left
	_cars.add_theme_color_override("font_color", Hud.DIM if out else Hud.TEXT)
	if out:
		_tier.text = watching
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
	_ram.text = prompt if out else ("Ram ready" if ready else "Ram")
	_ram.add_theme_color_override("font_color", Hud.TEXT if ready or out else Hud.DIM)
	var roster := ""
	if _team >= 0:
		roster = ". " + ", ".join(PackedStringArray(_roster.map(func(e: Array) -> String:
			return "%s %d" % [SumoTeams.name_of(int(e[0])), int(e[1])])))
	accessibility_name = "%s%s. %s%s" % [_cars.text, roster, _tier.text, (". " + _ram.text) if _ram.text else ""]


func cars_text() -> String:
	return _cars.text


## The roster as shown: "Red 3  ·  Blue 2" ("" with no teams).
func roster_text() -> String:
	if _team < 0:
		return ""
	return "  ·  ".join(PackedStringArray(_roster.map(func(e: Array) -> String:
		return "%s %d" % [SumoTeams.name_of(int(e[0])), int(e[1])])))


func tier_text() -> String:
	return _tier.text


func ram_text() -> String:
	return _ram.text
