class_name BayPreview
extends SubViewportContainer
## The Fitting Bay's 3D view: the car as the game will draw it (a CarVisual on a copy of the
## draft's model, fitted to the chosen platform) standing on a floor, with overlays for the
## step being edited. Orbit with the mouse (drag, wheel) or a pad (right stick, shoulders).

const OVERLAY_ALPHA := 0.55

var viewport := SubViewport.new()
var camera := Camera3D.new()
var visual: CarVisual
var fitted: Fitting.Result
## Which overlays to show: forward, wheels, envelope, cockpit.
var overlays := {}
## orbit, eye, hood or bumper.
var view := "orbit"

var _car_root := Node3D.new()
var _overlay_root := Node3D.new()
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(-14.0)
var _distance := 7.0
var _target := Vector3(0, 0.6, 0)
var _dragging := false


func _ready() -> void:
	stretch = true
	focus_mode = Control.FOCUS_NONE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	add_child(viewport)
	var style := StyleProfile.load_profile(StyleProfile.DEFAULT)
	viewport.add_child(style.create_environment())
	viewport.add_child(style.create_sun())
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.32, 0.33, 0.35)
	floor_material.roughness = 0.9
	plane.material = floor_material
	floor.mesh = plane
	viewport.add_child(floor)
	viewport.add_child(_car_root)
	viewport.add_child(_overlay_root)
	camera.fov = 50.0
	camera.near = 0.02
	viewport.add_child(camera)
	_update_camera()


## Draws `draft` fitted to `platform`. With rebuild false only the overlays change.
func show_draft(draft: FittingDraft, platform: Dictionary, rebuild := true) -> void:
	fitted = Fitting.fit(platform, draft.fit)
	if rebuild or visual == null:
		if visual:
			visual.free()
			visual = null
		if draft.scene:
			var pkg := VehiclePackage.new()
			pkg.fit = draft.fit
			pkg.paint = draft.paint
			pkg.manifest = draft.info()
			pkg.lods.append(draft.scene.duplicate() as Node3D)
			visual = CarVisual.create(pkg, fitted)
			_car_root.add_child(visual)
			for i in visual.wheel_count():
				visual.set_wheel(i, 0.0, 0.0, 0.0)
	# The vehicle frame's ground sits on the floor.
	_car_root.position.y = -fitted.ground_y
	_overlay_root.position.y = -fitted.ground_y
	_target = Vector3(0.0, fitted.ground_y + fitted.envelope.size.y * 0.45, fitted.envelope.get_center().z)
	_distance = clampf(fitted.envelope.size.z * 1.6, 3.0, 20.0) if view == "orbit" and _distance == 7.0 else _distance
	_build_overlays(draft)
	_update_camera()


## Renders the car at a fixed 3/4 angle for the garage (512x288 PNG). Empty when headless.
func thumbnail() -> PackedByteArray:
	if DisplayServer.get_name() == "headless" or visual == null:
		return PackedByteArray()
	var shot := SubViewport.new()
	shot.size = Vector2i(1024, 576)
	shot.world_3d = viewport.find_world_3d()
	shot.msaa_3d = Viewport.MSAA_4X
	shot.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.fov = 40.0
	shot.add_child(cam)
	add_child(shot)
	_overlay_root.visible = false
	var length := fitted.envelope.size.z
	var focus := Vector3(0.0, fitted.ground_y + fitted.envelope.size.y * 0.4, fitted.envelope.get_center().z) + _car_root.position
	var dir := Vector3(sin(deg_to_rad(35.0)), 0.32, cos(deg_to_rad(35.0))).normalized()
	cam.look_at_from_position(focus + dir * length * 1.75, focus)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := shot.get_texture().get_image()
	_overlay_root.visible = true
	shot.queue_free()
	if image == null or image.is_empty():
		return PackedByteArray()
	image.resize(512, 288, Image.INTERPOLATE_LANCZOS)
	return image.save_png_to_buffer()


func _build_overlays(draft: FittingDraft) -> void:
	for child in _overlay_root.get_children():
		child.free()
	var e := fitted.envelope
	if overlays.get("forward", false):
		var arrow := _arrow(Color(0.95, 0.75, 0.1, 0.9))
		arrow.position = Vector3(0.0, 0.01 + fitted.ground_y, e.end.z + 0.6)
		_overlay_root.add_child(arrow)
	if overlays.get("envelope", false):
		_overlay_root.add_child(_box_lines(e, Color(0.3, 0.8, 1.0)))
	if overlays.get("wheels", false):
		for w in fitted.wheels:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.outer_radius = w.radius * 1.05
			torus.inner_radius = w.radius * 0.88
			torus.material = _material(Color(0.2, 0.9, 1.0, OVERLAY_ALPHA))
			ring.mesh = torus
			ring.rotation.z = PI / 2.0
			ring.position = w.center
			_overlay_root.add_child(ring)
	if overlays.get("cockpit", false):
		_overlay_root.add_child(_dot(fitted.eye_point, Color(0.2, 1.0, 0.3)))
		for item: Array in [["hood", Color(1.0, 0.55, 0.1)], ["bumper", Color(1.0, 0.2, 0.8)]]:
			var p: Variant = camera_point(draft, item[0])
			if p != null:
				_overlay_root.add_child(_dot(p, item[1]))


## A camera position (vehicle frame) from fit.json, or null.
func camera_point(draft: FittingDraft, which: String) -> Variant:
	var cams: Dictionary = draft.fit.get("cameras", {})
	var p: Variant = cams.get(which)
	if p is Array:
		return fitted.model_xform * Vector3(p[0], p[1], p[2])
	return null


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_distance = maxf(_distance * 0.9, 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance = minf(_distance * 1.1, 40.0)
		_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.008
		_pitch = clampf(_pitch - mm.relative.y * 0.006, deg_to_rad(-85.0), deg_to_rad(10.0))
		view = "orbit"
		_update_camera()


func _process(delta: float) -> void:
	# A pad's right stick turns the view, the shoulders zoom.
	var x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var zoom := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(x) > 0.2 or absf(y) > 0.2 or absf(zoom) > 0.2:
		_yaw -= x * delta * 2.0
		_pitch = clampf(_pitch - y * delta * 1.5, deg_to_rad(-85.0), deg_to_rad(10.0))
		_distance = clampf(_distance * (1.0 - zoom * delta), 1.0, 40.0)
		view = "orbit"
		_update_camera()


func set_view(new_view: String, draft: FittingDraft) -> void:
	view = new_view
	if view == "orbit" or fitted == null:
		_update_camera()
		return
	var p: Variant = fitted.eye_point if view == "eye" else camera_point(draft, view)
	if p == null:
		view = "orbit"
		_update_camera()
		return
	var at := (p as Vector3) + _car_root.position
	camera.fov = 70.0
	camera.look_at_from_position(at, at + Vector3(0, -0.05, 1.0))


func _update_camera() -> void:
	if view != "orbit":
		return
	camera.fov = 50.0
	var target := _target + _car_root.position
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	camera.look_at_from_position(target + dir * _distance, target)


static func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.no_depth_test = true
	m.render_priority = 1
	return m


static func _dot(at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	sphere.material = _material(c)
	mi.mesh = sphere
	mi.position = at
	return mi


## A flat arrow on the floor pointing +Z.
static func _arrow(c: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(-0.15, 0, 0), Vector3(0.15, 0, 0), Vector3(0.15, 0, 0.6), Vector3(-0.15, 0, 0), Vector3(0.15, 0, 0.6), Vector3(-0.15, 0, 0.6),
			Vector3(-0.4, 0, 0.6), Vector3(0.4, 0, 0.6), Vector3(0, 0, 1.1)]:
		st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(c)
	mi.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mi


static func _box_lines(box: AABB, c: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners := []
	for i in 8:
		corners.append(box.position + box.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
	for pair in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(corners[pair[0]])
		im.surface_add_vertex(corners[pair[1]])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = _material(c)
	return mi
