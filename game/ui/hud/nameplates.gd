class_name Nameplates
extends Control
## Other players' names over their cars (docs/GAMEMODES.md §3, D119): on highways, so players
## going the other way are known across the barrier. Each plate shows the name and how far;
## plates fade with distance and go beyond RANGE_M or off screen.

const RANGE_M := 400.0
const FONT_SIZE := 26

var session: TrackSession
## Whose HUD this is (their car has no plate here).
var player: SessionPlayer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := player.cameras.camera if player and player.cameras else null
	if cam == null or not cam.is_inside_tree():
		return
	var font := get_theme_default_font()
	var me := player.vehicle.global_position if player.vehicle else cam.global_position
	for r in session.racers:
		if r == player or r.vehicle == null or not is_instance_valid(r.vehicle) or not (r.is_human or r is SessionPlayer) or r.waiting:
			continue
		var at := r.vehicle.global_position + Vector3.UP * 2.2
		var d := me.distance_to(at)
		if d > RANGE_M or cam.is_position_behind(at):
			continue
		var p := cam.unproject_position(at)
		var view := get_viewport_rect()
		if not view.has_point(p):
			continue
		var text := "%s  %d m" % [r.display_name, roundi(d)]
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
		var alpha := clampf(1.2 - d / RANGE_M, 0.25, 1.0)
		var box := Rect2(p - Vector2(size.x / 2.0 + 10.0, size.y + 4.0), size + Vector2(20.0, 8.0))
		draw_rect(box, Color(0, 0, 0, 0.55 * alpha))
		draw_rect(Rect2(box.position, Vector2(6.0, box.size.y)), Color(r.color, alpha))
		draw_string(font, box.position + Vector2(14.0, size.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, alpha))
