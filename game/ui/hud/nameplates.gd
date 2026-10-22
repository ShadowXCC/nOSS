class_name Nameplates
extends Control
## Other players' names over their cars (D119, D199): in every mode, on each player's HUD, so the
## cars that are people are known at a glance (online and splitscreen; bots and police get none).
## Each tag shows the name and how far on a dark plate with a stripe in their colour, and a
## triangle under it pointing down at the car. Tags show through walls, fade with distance and go
## beyond RANGE_M or off screen. A HUD element ("nametags") the player can hide.

const RANGE_M := 400.0
const FONT_SIZE := 26
## Over the car's roof (m): where the triangle's tip points.
const LIFT_M := 0.5
## The triangle under the plate (px at 1080p, scaled with the HUD).
const ARROW_W := 20.0
const ARROW_H := 12.0

var session: TrackSession
## Whose HUD this is (their car has no tag here).
var player: SessionPlayer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


## The tags to draw now, far to near: {racer, tip (this control's coordinates), distance, text,
## alpha, color}.
func entries() -> Array[Dictionary]:
	var tags: Array[Dictionary] = []
	var cam := player.cameras.camera if player and player.cameras else null
	if cam == null or not cam.is_inside_tree() or not player.hud.shows("nametags"):
		return tags
	# How far from the player's car, or from the camera while it is out of play (a drag pass
	# watched from under the strip, a sumo match from over the arena).
	var in_play := player.vehicle != null and not (player.waiting or player.parked or player.out)
	var me := player.vehicle.global_position if in_play else cam.global_position
	var view := get_viewport_rect()
	# The camera gives viewport pixels; the HUD is scaled by the player's HUD size.
	var to_local := get_global_transform_with_canvas().affine_inverse()
	var imperial := Settings.units == "imperial"
	for r in session.racers:
		if r == player or not (r.is_human or r is SessionPlayer) or r.waiting or r.parked or r.out:
			continue
		var v := r.vehicle
		if v == null or not is_instance_valid(v) or not v.visible: # hidden: left the session
			continue
		var at := anchor(v)
		var d := me.distance_to(v.global_position)
		if d > RANGE_M or cam.is_position_behind(at):
			continue
		var p := cam.unproject_position(at)
		if not view.has_point(p):
			continue
		var shown := "%d ft" % roundi(d * 3.28084) if imperial else "%d m" % roundi(d)
		tags.append({ "racer": r, "tip": to_local * p, "distance": d, "text": "%s  %s" % [r.display_name, shown],
			"alpha": clampf(1.2 - d / RANGE_M, 0.6 if player.hud.high_contrast else 0.25, 1.0), "color": r.color })
	tags.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance > b.distance)
	return tags


## Where a car's tag points: just over its roof, straight up from its middle.
static func anchor(v: Vehicle) -> Vector3:
	if v.fitted == null:
		return v.global_position + Vector3.UP * 2.2
	var box := v.fitted.envelope
	return v.global_transform * box.get_center() + Vector3.UP * (box.size.y / 2.0 + LIFT_M)


func _draw() -> void:
	var font := get_theme_default_font()
	var plate := 0.82 if player and player.hud.high_contrast else 0.55
	for tag in entries():
		var a: float = tag.alpha
		var tip: Vector2 = tag.tip
		var text_size := font.get_string_size(tag.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var box_size := text_size + Vector2(26.0, 8.0)
		var box := Rect2(tip - Vector2(box_size.x / 2.0, ARROW_H + box_size.y), box_size)
		draw_rect(box, Color(0, 0, 0, plate * a))
		draw_rect(Rect2(box.position, Vector2(6.0, box.size.y)), Color(tag.color, a))
		draw_string(font, box.position + Vector2(16.0, text_size.y), tag.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, a))
		# The triangle, from the plate down to the car, edged so a pale colour still reads.
		var arrow := PackedVector2Array([tip + Vector2(-ARROW_W / 2.0, -ARROW_H), tip + Vector2(ARROW_W / 2.0, -ARROW_H), tip])
		draw_colored_polygon(arrow, Color(tag.color, a))
		arrow.append(arrow[0])
		draw_polyline(arrow, Color(0, 0, 0, 0.8 * a), 2.0)
