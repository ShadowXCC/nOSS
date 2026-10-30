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
## Its livery (LiveryStore.pick_for_ai: one saved for its car, or a built-in's stock one; {} for
## none), and the car it was picked for: picked when that car first comes, or kept (a cup).
var livery: Variant = null
var livery_car := ""


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


## A livery for its car, and paint: the car's presets or a stock colour (D128) only under a
## livery without its own base paint.
func _dress() -> void:
	var car_id := String(vehicle.package.manifest.get("id", ""))
	if livery == null or livery_car != car_id:
		livery = LiveryStore.pick_for_ai(vehicle.package)
		livery_car = car_id
	var l: Dictionary = Racer.stress_livery() if Game.dev.has("livery-stress") else livery
	if not l.has("base"):
		if paint == null:
			paint = CarVisual.random_paint(vehicle.package.paint)
		vehicle.visual.apply_choice(paint)
	vehicle.visual.apply_livery(l, str(number))


func _make_driver() -> Node:
	var ai := super()
	if "skill" in ai:
		ai.skill = skill
	return ai
