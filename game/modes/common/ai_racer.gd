class_name AiRacer
extends Racer
## A computer driver in a track session (AI-01): a Racer with a RacingAI and no view. Numbered
## after the four player numbers, so "5" and up on the map and standings are always AI.

## Short original names, one per AI grid slot.
const NAMES := ["Vega", "Rook", "Juno", "Kestrel", "Orin", "Sable", "Tamsin", "Pike",
		"Lark", "Mira", "Dax", "Wren", "Cato", "Nova", "Ash"]
const COLOR := Color(0.78, 0.8, 0.84)

## 0-100 (docs/GAMEMODES.md §0).
var skill := 80.0
## Its paint job (CarVisual.random_paint, D128): picked when its car first comes, or the
## server's (online); null until then.
var paint: Variant = null


func _init() -> void:
	name = "Ai"


## `index`: 0 for the first AI.
func configure(index: int, ai_skill: float) -> void:
	number = 5 + index
	display_name = NAMES[index % NAMES.size()]
	name = "Ai%d" % number
	color = COLOR
	skill = ai_skill
	is_human = false


func _car_changed() -> void:
	if vehicle == null or vehicle.visual == null or vehicle.package == null:
		return
	if paint == null:
		paint = CarVisual.random_paint(vehicle.package.paint)
	vehicle.visual.apply_choice(paint)


func _make_driver() -> Node:
	var ai := super() as RacingAI
	ai.skill = skill
	return ai
