class_name PlayerView
extends SubViewportContainer
## One player's view (docs/ARCHITECTURE.md §6): a SubViewport showing the shared world through
## the player's camera, with their HUD and menus on top.
## - 2D is laid out for 1080p and scaled to the view, then by the player's HUD scale (HUD) or
##   text scale (menus), so the same HUD and menus fit any split.
## - Only mouse events come in from the window. The player's own menu navigation is pushed in
##   by Players (PlayerSlot.menu_target), so each view has its own focus.
## - Render scale and anti-aliasing follow the graphics preset, times the auto-resolution
##   factor. Brightness is the player's (a copy of the world's environment on the camera).

const REF := Vector2(1920, 1080)
## Room a menu needs; the text scale stops growing menus past it. (The 2D space itself is
## always at least REF.)
const MIN_SPACE := Vector2(1100, 900)

var slot: PlayerSlot
var viewport := SubViewport.new()
## Full-rect roots for the HUD and for this player's menus.
var hud_root := Control.new()
var overlay_root := Control.new()
## Set by auto resolution (ViewManager), 0.5..1.
var render_scale := 1.0:
	set(v):
		render_scale = v
		apply_graphics()

var _hud_layer := CanvasLayer.new()
var _overlay_layer := CanvasLayer.new()
var _world_env: Environment
var _env: Environment
var _camera: Camera3D


func _init() -> void:
	name = "PlayerView"
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	viewport.name = "Viewport"
	viewport.gui_embed_subwindows = true # popups stay in this view and get its input
	viewport.audio_listener_enable_3d = true
	viewport.physics_object_picking = false
	add_child(viewport)
	_hud_layer.layer = 1
	_overlay_layer.layer = 2
	viewport.add_child(_hud_layer)
	viewport.add_child(_overlay_layer)
	for root: Control in [hud_root, overlay_root]:
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.name = "Hud"
	overlay_root.name = "Menus"
	_hud_layer.add_child(hud_root)
	_overlay_layer.add_child(overlay_root)
	resized.connect(_fit)


func _ready() -> void:
	apply_graphics()
	_fit()


## Raw keys and buttons never reach the view; menus get the player's own navigation instead.
func _propagate_input_event(event: InputEvent) -> bool:
	return event is InputEventMouse


func set_listener(on: bool) -> void:
	viewport.audio_listener_enable_3d = on


## Adds a 3D node (the player's camera rig) to this view.
func add_3d(node: Node3D) -> void:
	viewport.add_child(node)


## Camera to put the player's brightness on; `world_env` is the scene's environment.
func set_camera(camera: Camera3D, world_env: Environment) -> void:
	_camera = camera
	_world_env = world_env
	apply_profile()


## Re-reads the player's HUD scale, text scale and brightness.
func apply_profile() -> void:
	_fit()
	if _camera == null or slot == null:
		return
	var b := float(slot.profile.data.get("brightness", 1.0))
	if is_equal_approx(b, 1.0) or _world_env == null:
		_camera.environment = null
		return
	if _env == null:
		_env = _world_env.duplicate()
		_env.adjustment_enabled = true
	_env.adjustment_brightness = b
	_camera.environment = _env


func apply_graphics() -> void:
	Settings.apply_graphics(viewport, render_scale)


## Scale of the 2D layout relative to 1080p.
func base_scale() -> float:
	return minf(size.x / REF.x, size.y / REF.y) if size.x > 0.0 and size.y > 0.0 else 1.0


func _fit() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var base := base_scale()
	viewport.size_2d_override = Vector2i((size / base).round())
	viewport.size_2d_override_stretch = true
	var space := size / base
	var hud := clampf(float(slot.profile.data.get("hud_scale", 1.0)), 0.5, 2.0) if slot else 1.0
	var text := clampf(float(slot.profile.data.get("text_scale", 1.0)), 1.0, 2.0) if slot else 1.0
	_place(hud_root, space, hud)
	# Menus grow with the text scale, as far as they still fit.
	_place(overlay_root, space, minf(text, minf(space.x / MIN_SPACE.x, space.y / MIN_SPACE.y)))


static func _place(root: Control, space: Vector2, factor: float) -> void:
	factor = maxf(factor, 0.25)
	root.position = Vector2.ZERO
	root.scale = Vector2(factor, factor)
	root.size = space / factor
