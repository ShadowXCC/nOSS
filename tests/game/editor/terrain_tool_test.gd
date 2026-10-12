extends GdUnitTestSuite
## The Terrain and Paint tools (EDT-02): a stroke is one exact undo; the road follows a hill
## raised under it; painting changes what the wheels read.

const DIR := "user://tests/terrain_tool"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Game.track_draft = null
	Settings.use_folder("user://")


func _editor(d: TrackDraft) -> TrackEditor:
	Game.track_draft = d
	var e := TrackEditor.new()
	add_child(e)
	return e


func _stroke(e: TrackEditor, at: Vector3, seconds: float) -> void:
	var hit := { "hit": true, "position": at, "normal": Vector3.UP, "collider": null }
	e.tool.pointer({ "kind": "press", "screen": Vector2(-50, -50), "hit": hit, "shift": false, "alt": false, "crosshair": false })
	var t := 0.0
	while t < seconds:
		e.tool.tick(1.0 / 30.0)
		t += 1.0 / 30.0
	e.tool.pointer({ "kind": "release", "screen": Vector2(-50, -50), "hit": hit, "shift": false, "alt": false, "crosshair": false })


func test_a_raised_hill_lifts_the_road_and_undoes_exactly() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Terrain")
	var t0 := d.track()
	var at := t0.samples[t0.seg_first[0]] # the road's end at point 0
	var before := d.terrain.field.get_base()
	(e.tool as BrushTool).radius = 60.0
	_stroke(e, at, 1.0)
	var t1 := d.track()
	var i: int = t1.project(at).index
	assert_float(t1.samples[i].y).is_greater(t0.samples[t0.project(at).index].y + 0.5) # the road came up with it
	assert_float(t1.samples[i].y - d.terrain.height_at(t1.samples[i].x, t1.samples[i].z)).is_between(0.0, 0.2) # on its bed
	assert_str(d.undo()).is_equal("Shape ground")
	assert_bool(d.terrain.field.get_base() == before).is_true()
	e.queue_free()
	await get_tree().process_frame


func test_paint_changes_what_wheels_read() -> void:
	var d := TrackTemplates.make("oval")
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Paint")
	(e.tool as BrushTool).radius = 15.0
	e.tool.set("layer", 3) # gravel
	var spot := Vector3(0, 0, 0) # the oval's infield
	_stroke(e, spot, 1.0)
	assert_int(d.terrain.surface_map().surface_at(0.0, 0.0)).is_equal(VehicleSim.SURFACE_GRAVEL)
	assert_str(d.undo()).is_equal("Paint ground")
	assert_int(d.terrain.surface_map(true).surface_at(0.0, 0.0)).is_equal(VehicleSim.SURFACE_GRASS)
	e.queue_free()
	await get_tree().process_frame


func test_fit_terrain_to_the_track() -> void:
	var d := TrackTemplates.make("oval")
	d.terrain = TerrainData.create(Vector2(-128, -128), Vector2i(1, 1))
	d._track = null
	var e := _editor(d)
	await get_tree().process_frame
	e.show_tool("Terrain")
	e.tool.call("_fit")
	assert_bool(d.terrain.area().has_point(Vector2(250, 0))).is_true()
	assert_str(d.undo()).is_equal("Fit terrain to track")
	assert_int(d.terrain.chunks().x).is_equal(1)
	e.queue_free()
	await get_tree().process_frame
