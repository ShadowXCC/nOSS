class_name KartPanel
extends Control
## A kart's HUD (D146, docs/ACCESSIBILITY.md): the item held (a swatch in its kind's colour, and
## its name: words carry the meaning), the roulette while it rolls, the uses left of a triple; the
## drift's tier as pips and a word; a bar for a boost; in a battle, lives as pips and a number
## (or "Out") and hits. With Reduce flashing the roulette doesn't cycle through names, it says
## "Rolling". With no items in the event (a time trial, Items off) there's no item line.

const ROLL_HZ := 8.0
const KINDS := {
	"bolt": "item_attack", "seeker": "item_attack", "leader_hunter": "item_attack", "oil_slick": "item_attack", "emp": "item_attack",
	"shield": "item_defend", "nitro": "item_speed", "nitro_x3": "item_speed", "magnet": "item_speed",
}

var palette: Dictionary = Palette.PRESETS.default
var calm := false
## The event has items.
var items := true
var _swatch := ColorRect.new()
var _item := Label.new()
var _drift := Label.new()
var _battle := Label.new()
var _board := Label.new()
var _boost := ColorRect.new()
var _boost_back := ColorRect.new()
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	offset_left = 40
	offset_top = 210
	offset_right = 600
	offset_bottom = 420
	_swatch.size = Vector2(56, 56)
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_swatch)
	for row: Array in [[_item, 40, Vector2(72, 4)], [_drift, 30, Vector2(0, 70)], [_battle, 30, Vector2(0, 132)], [_board, 24, Vector2(0, 172)]]:
		var l: Label = row[0]
		l.add_theme_font_size_override("font_size", row[1])
		l.add_theme_color_override("font_color", Hud.TEXT)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 8)
		l.position = row[2]
		l.size = Vector2(480, row[1] + 10)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	for r: ColorRect in [_boost_back, _boost]:
		r.position = Vector2(0, 116)
		r.size = Vector2(240, 8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
	_boost_back.color = Color(1, 1, 1, 0.2)


## What `racer` holds (`slot`: KartItems.slot) and its kart's flags and state, `delta` on.
func show_kart(slot: Dictionary, flags: int, state: Dictionary, delta: float) -> void:
	_time += delta
	var item: String = slot.item
	if not items:
		_item.text = ""
	elif item != "" and float(slot.roulette) > 0.0:
		if calm:
			_item.text = "Rolling"
		else:
			var names := ItemOdds.ITEMS
			_item.text = ItemOdds.item_name(names[int(_time * ROLL_HZ) % names.size()])
		_swatch.color = Color(1, 1, 1, 0.5)
	elif item != "":
		_item.text = ItemOdds.item_name(item) + ("  (%d left)" % int(slot.count) if ItemOdds.count_of(item) > 1 else "")
		_swatch.color = palette.get(KINDS.get(item, "item_speed"), Color.WHITE)
	else:
		_item.text = "No item"
		_swatch.color = Color(1, 1, 1, 0.15)
	_item.add_theme_color_override("font_color", Hud.TEXT if item != "" else Hud.DIM)
	_swatch.visible = items
	var drifting := flags & (VehicleSim.KART_FLAG_DRIFT_LEFT | VehicleSim.KART_FLAG_DRIFT_RIGHT) != 0
	var tier := (flags >> VehicleSim.KART_FLAG_TIER_SHIFT) & 3
	_drift.text = ("Drift %s  %d" % ["●".repeat(tier) + "○".repeat(3 - tier), tier]) if drifting else ""
	var boost := float(state.get("boost", 0.0))
	_boost.visible = boost > 0.0
	_boost_back.visible = boost > 0.0
	_boost.size.x = 240.0 * clampf(boost / 1.5, 0.0, 1.0)
	_boost.color = palette.get("item_speed", Color.ORANGE)
	accessibility_name = "Item: " + _item.text if items else ""


## A battle's line: lives left (-1: a most-hits match, no lives), hits dealt, out; in a most-hits
## match also the target (0: none), the place and the leaders (`board`: "1 Rook 5 · 2 You 3").
func show_battle(lives: int, hits: int, out: bool, place := 0, karts := 0, target := 0, board := "") -> void:
	if out:
		_battle.text = "Out  ·  Hits %d" % hits
	elif lives >= 0:
		_battle.text = "Lives %s %d  ·  Hits %d" % ["●".repeat(lives) + "○".repeat(maxi(BattleControl.LIVES - lives, 0)), lives, hits]
	else:
		_battle.text = "Hits %d%s  ·  %s of %d" % [hits, " of %d" % target if target > 0 else "", ordinal(place), karts]
	_board.text = board
	accessibility_name = "Item: %s. %s%s" % [_item.text, _battle.text, (". " + board) if board else ""]


## 1st, 2nd, 3rd, 4th...
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


func board_text() -> String:
	return _board.text


func battle_text() -> String:
	return _battle.text


func item_text() -> String:
	return _item.text


func drift_text() -> String:
	return _drift.text
