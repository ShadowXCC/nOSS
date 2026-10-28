extends GdUnitTestSuite
## Track Fitting (EDT-08, M6 acceptance): the Kenney test circuit (tools/make_kenney_circuit.gd)
## is imported, tagged by the rules and one material choice, its centreline clicked along the
## road, its widths measured and its start and grid set; it checks clean, saves, loads back and
## builds with the surfaces the wheels feel. Water sends a car back; the retro style makes copies.

const DIR := "user://tests/track_fitting"
const FIXTURE := "res://tests/fixtures/tracks/kenney/"
const SAVED := "user://tests/track_fitting/kenney_circuit.nosstrack"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Game.track_draft = null
	Settings.use_folder("user://")


func _sidecar() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE + "centreline.json"))


## Points every `step` m along the sidecar's line: where a player would click.
func _clicks(step := 16.0) -> Array[Vector3]:
	var line: Array = _sidecar().points
	var out: Array[Vector3] = [Vector3(line[0][0], line[0][1], line[0][2])]
	var since := 0.0
	for k in line.size():
		var a := Vector3(line[k][0], line[k][1], line[k][2])
		var b := Vector3(line[(k + 1) % line.size()][0], line[(k + 1) % line.size()][1], line[(k + 1) % line.size()][2])
		var seg := a.distance_to(b)
		var d := step - since
		while d < seg:
			out.append(a.lerp(b, d / seg))
			d += step
		since = seg - (d - step)
	if out[-1].distance_to(out[0]) < step * 0.5:
		out.pop_back()
	return out


func _scene() -> SceneTrack:
	var r := ModelImport.import_file(FIXTURE + "kenney_circuit.glb", SceneTrack.LIMITS)
	assert_str(r.error).is_empty()
	if r.scene:
		r.scene.free()
	var s := SceneTrack.from_glb(r.glb)
	assert_str(s.error()).is_empty()
	return s


## A click on the scene at `p` (as the view's pick would find it).
func _ev(kind: String, s: SceneTrack, p: Vector3) -> Dictionary:
	var hit := s.ray_down(p.x, p.z, p.y + 30.0, false)
	return { "kind": kind, "screen": Vector2(-50, -50), "hit": { "hit": hit.hit, "position": hit.get("position", p), "normal": Vector3.UP, "collider": null },
		"shift": false, "alt": false, "crosshair": false }


func test_the_kenney_circuit_is_fitted_checked_saved_and_loaded() -> void:
	var s := _scene()
	var d := TrackDraft.from_import(s, FIXTURE + "kenney_circuit.glb", "Kenney Circuit")
	Game.track_draft = d
	var e := TrackEditor.new()
	add_child(e)
	await get_tree().process_frame
	assert_bool(e.tools.has("Surfaces")).is_true()
	assert_bool(e.tools.has("Terrain")).is_false()
	# The rules alone: road and grass by their materials. The road's edges (grey, and on the
	# large corners the kit's default material) take their pieces' name (road_...): set apart
	# by hand, each one undo for every material of its name (grey, grey2, ...).
	assert_str(s.material_tag("road")).is_equal("asphalt")
	assert_str(s.material_tag("grass")).is_equal("grass")
	assert_str(s.material_tag("grey")).is_equal("asphalt")
	e.show_tool("Surfaces")
	await get_tree().process_frame
	for c: Control in e._content.find_children("*", "Control", true, false) + e._content.get_children():
		if c.focus_mode != Control.FOCUS_NONE and (c is BaseButton or c is Range or c is LineEdit):
			assert_str(String(c.accessibility_name)).override_failure_message("unnamed %s" % c).is_not_empty()
	e.tool.call("_set_material", "grey", "curb")
	assert_str(s.material_tag("grey")).is_equal("curb")
	assert_str(d.undo()).is_equal("Tag grey")
	assert_str(s.material_tag("grey")).is_equal("asphalt")
	d.redo()
	assert_str(s.material_tag("grey")).is_equal("curb")
	e.tool.call("_set_material", "_defaultMat", "curb")
	# Click along the middle of the road. A grandstand isn't road.
	e.show_tool("Road")
	var road: EditorTool = e.tool
	road.pointer(_ev("press", s, Vector3(-19.8, 0, -32.4)))
	assert_str(e._status.text).is_equal("Not a road surface")
	assert_int(d.points().size()).is_equal(0)
	var line := _sidecar()
	var clicks := _clicks()
	for p in clicks:
		road.call("_select", d.points().size() - 1)
		road.pointer(_ev("press", s, p))
		road.pointer(_ev("release", s, p))
	assert_int(d.points().size()).is_equal(clicks.size())
	var t := d.track()
	assert_str(t.kind).is_equal("centreline")
	assert_float(t.length).is_equal_approx(float(line.length_m), 15.0)
	# Measure widths: the road's edges, wherever the clicked line runs on it (off the middle in
	# the corners), so each side and the whole width.
	e.show_tool("Surfaces")
	e.tool.call("_measure")
	var width := float(line.road_width_m)
	for i in d.points().size():
		var wl := float(TrackFormat.attr(d.layout.road, i, "width_l"))
		var wr := float(TrackFormat.attr(d.layout.road, i, "width_r"))
		assert_float(wl + wr).override_failure_message("point %d: %.1f + %.1f" % [i, wl, wr]).is_equal_approx(width, 1.2)
		assert_float(minf(wl, wr)).override_failure_message("point %d" % i).is_greater(2.5)
	assert_str(d.undo()).is_equal("Measure widths")
	d.redo()
	# The start on the kit's line; a grid for 8.
	d.set_race("start_m", float(line.start_m))
	d.set_race("grid/slots", 8)
	var found := TrackValidator.check(d)
	assert_array(TrackValidator.errors(found)).override_failure_message(str(found)).is_empty()
	# Saved and loaded back: the scene, its tags, the line.
	DirAccess.make_dir_recursive_absolute(DIR)
	DirAccess.remove_absolute(SAVED)
	assert_bool(d.save(SAVED).ok).is_true()
	var pkg := TrackLoader.load_package(SAVED)
	assert_str(pkg.error).is_empty()
	assert_object(pkg.scene).is_not_null()
	assert_str(pkg.scene.material_tag("grey")).is_equal("curb")
	assert_str(pkg.track.kind).is_equal("centreline")
	assert_float(pkg.track.length).is_equal_approx(t.length, 0.5)
	assert_float(pkg.track.half_l[10] + pkg.track.half_r[10]).is_equal_approx(width, 1.2)
	# Built: what the wheels feel, by tag; no road of its own.
	var built := TrackBuilder.build(pkg.track, null, { "scene": pkg.scene })
	var asphalt := built.get_node("Scene_asphalt") as StaticBody3D
	assert_int(int(asphalt.get_meta(&"noss_surface"))).is_equal(TrackFormat.surface_id("asphalt"))
	assert_object(built.get_node_or_null("Scene_curb")).is_not_null()
	assert_object(built.get_node_or_null("Scene")).is_not_null()
	assert_array(built.find_children("Seg_*", "", true, false)).is_empty()
	built.free()
	pkg.scene.free_scene()
	e.queue_free()
	await get_tree().process_frame
	s.free_scene()


func test_off_the_road_and_untagged_are_errors() -> void:
	var s := _scene()
	var d := TrackDraft.from_import(s, FIXTURE + "kenney_circuit.glb")
	for p in _clicks():
		d.add_point(d.points().size(), s.ray_down(p.x, p.z, 30.0).position, {})
	# Nothing tagged to drive on.
	var none := SceneTrack.default_tags()
	none.rules = []
	d.set_scene_tags(none)
	assert_array(TrackValidator.errors(TrackValidator.check(d))).contains(["No surfaces tagged"])
	# Only grass tagged: the road under the line is untagged.
	for m: Array in s.materials():
		if m[0] == "grass":
			for name: String in m[2]:
				none.materials[name] = "grass"
	d.set_scene_tags(none)
	var errors := TrackValidator.errors(TrackValidator.check(d))
	assert_bool(errors.any(func(t: String) -> bool: return t.begins_with("Road surface not tagged at"))).override_failure_message(str(errors)).is_true()
	s.free_scene()


func test_water_and_the_retro_style() -> void:
	var s := _scene()
	var t := s.tags.duplicate(true)
	for m: Array in s.materials():
		if m[0] == "grass":
			for name: String in m[2]:
				t.materials[name] = "water"
	t.style = "retro"
	s.set_tags(t)
	assert_int(s.water_boxes().size()).is_greater(0)
	var root := Node3D.new()
	s.build(root)
	var water := root.find_children("Water*", "Area3D", false, false)
	assert_int(water.size()).is_greater(0)
	assert_bool((water[0] as Area3D).has_meta(&"noss_water")).is_true()
	assert_int((water[0] as Area3D).collision_mask & Vehicle.LAYER_VEHICLES).is_not_equal(0) # it sees cars
	assert_object(root.get_node_or_null("Scene_grass")).is_null() # water isn't ground
	# Retro: the shown scene's materials are copies, sharp; the scene's own are left alone.
	var shown := root.get_node("Scene") as Node3D
	var mi: MeshInstance3D = shown.find_children("*", "MeshInstance3D", true, false)[0]
	var copy := mi.get_surface_override_material(0) as BaseMaterial3D
	assert_object(copy).is_not_null()
	assert_int(copy.texture_filter).is_equal(BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
	var own := (s.scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_active_material(0) as BaseMaterial3D
	assert_int(own.texture_filter).is_not_equal(BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
	root.free()
	s.free_scene()
