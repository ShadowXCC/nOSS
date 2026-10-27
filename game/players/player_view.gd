class_name PlayerView
extends SubViewportContainer
## One player's view (docs/ARCHITECTURE.md §6): a SubViewport showing the shared world through
## the player's camera, with their HUD and menus on top.
## - 2D is laid out for 1080p and scaled to the view, then by the player's HUD scale (HUD) or
##   text scale (menus), so the same HUD and menus fit any split.
## - Only mouse events come in from the window. The player's own menu navigation is pushed in
##   by Players (PlayerSlot.menu_target). Godot has one focus per OS window, so the view
##   remembers its own (Players.track_focus) and draws its own focus cursor.
## - Render scale and anti-aliasing follow the graphics preset, times the auto-resolution
##   factor. Brightness is the player's (a copy of the world's environment on the camera, kept in
##   step with the sky by EnvDirector).

const REF := Vector2(1920, 1080)
## Room a menu needs; menus shrink below it, and the text scale stops growing them past it.
const MIN_SPACE := Vector2(1100, 700)

var slot: PlayerSlot
## Size the 2D content is laid out for (a full view: 1080p; a Players screen card: card size).
var reference := REF:
	set(v):
		reference = v
		_fit()
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
var _cursor := FocusCursor.new()
## The player's brightness (their profile's).
var brightness := 1.0

var _world_env: Environment
var _env: Environment
var _camera: Camera3D
var _flash := 0.0


func _init() -> void:
	name = "PlayerView"
	add_to_group(&"player_views")
	# Paused, the window only hands clicks to controls that can process: the view keeps taking
	# them for its menus, while the world in it (camera rig) pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.process_mode = Node.PROCESS_MODE_PAUSABLE
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
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
	_cursor.viewport = viewport
	_overlay_layer.add_child(_cursor)
	Players.track_focus(viewport)
	resized.connect(_fit)


## Menus in this view are read out with this player's narration setting.
func watch_narration() -> void:
	Narrator.watch(viewport, slot.profile if slot else null)


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


## Re-reads the player's HUD scale, text scale and brightness. The view keeps its own copy of
## the scene's environment (EnvDirector keeps it in step with the sky, D153), with the player's
## brightness and, in storms, their own lightning.
func apply_profile() -> void:
	_fit()
	if _camera == null or slot == null:
		return
	if _world_env == null:
		_camera.environment = null
		return
	if _env == null:
		_env = _world_env.duplicate()
		_env.adjustment_enabled = true
	brightness = float(slot.profile.data.get("brightness", 1.0))
	_apply_brightness()
	_camera.environment = _env


## This view's environment (null before its camera is set).
func environment() -> Environment:
	return _env


## A lightning flash on this view: 0 none, up to about 1 (EnvDirector, D153).
func set_flash(amount: float) -> void:
	if not is_equal_approx(amount, _flash):
		_flash = amount
		_apply_brightness()


func _apply_brightness() -> void:
	if _env:
		_env.adjustment_brightness = brightness * (1.0 + _flash)


func apply_graphics() -> void:
	Settings.apply_graphics(viewport, render_scale)


## Scale of the 2D layout relative to its reference. A half-height or half-width view gets a
## bigger HUD than a quarter (the mean of the two ratios), as long as it still fits.
func base_scale() -> float:
	if size.x <= 0.0 or size.y <= 0.0:
		return 1.0
	var rx := size.x / reference.x
	var ry := size.y / reference.y
	if reference != REF:
		return minf(rx, ry)
	return minf(sqrt(rx * ry), minf(size.x / MIN_SPACE.x, size.y / MIN_SPACE.y))


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
	_place(overlay_root, space, minf(text, minf(space.x / MIN_SPACE.x, space.y / MIN_SPACE.y)) if reference == REF else 1.0)


static func _place(root: Control, space: Vector2, factor: float) -> void:
	factor = maxf(factor, 0.25)
	root.position = Vector2.ZERO
	root.scale = Vector2(factor, factor)
	root.size = space / factor


## This view's focus, drawn whether or not the view holds the window's real focus.
class FocusCursor:
	extends Control

	var viewport: Viewport
	var _rect := Rect2()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		var c := Players.focus_of(viewport)
		if c and c.has_meta(&"focus_box"): # a page's slider: round its whole row (UiKit.page_row)
			c = c.get_meta(&"focus_box") as Control
		var r := c.get_global_rect() if c and not c is LineEdit else Rect2()
		if r != _rect:
			_rect = r
			queue_redraw()

	func _draw() -> void:
		if _rect.has_area():
			draw_rect(_rect.grow(2.0), UiKit.ACCENT, false, 4.0)
