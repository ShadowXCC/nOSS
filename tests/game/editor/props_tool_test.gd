extends GdUnitTestSuite
## The Props tool (EDT-03): placing and moving a prop, scattering and erasing with a brush, each
## one undo; scatter keeps off the road.

const DIR := "user://tests/props_tool"


func before() -> void:
	Settings.use_folder(DIR)


func after() -> void:
	Game.track_draft = null
	Settings.use_folder("user://")


func _hit(p: Vector3) -> Dictionary:
	return { "hit": true, "position": p, "normal": Vector3.UP, "collider": null }


func _ev(kind: String, p: Vector3) -> Dictionary:
	return { "kind": kind, "screen": Vector2(-50, -50), "hit": _hit(p), "shift": false, "alt": false, "crosshair": false }


func test_place_move_scatter_and_erase() -> void:
	var d := TrackTemplates.make("oval")
	Game.track_draft = d
	var e := TrackEditor.new()
	add_child(e)
	await get_tree().process_frame
	e.show_tool("Props")
	var tool: EditorTool = e.tool
	# Place a tent, then drag it: one move.
	tool.set("prop", "tent")
	tool.pointer(_ev("press", Vector3(0, 0, 0)))
	tool.pointer(_ev("release", Vector3(0, 0, 0)))
	assert_int(d.layout.props.items.size()).is_equal(1)
	tool.set("_moving", true)
	for x in [5.0, 10.0, 20.0]:
		tool.pointer(_ev("drag", Vector3(x, 0, 0)))
	tool.pointer(_ev("release", Vector3(20, 0, 0)))
	assert_float(float(d.layout.props.items[0].p[0])).is_equal(20.0)
	assert_str(d.undo()).is_equal("Move prop")
	assert_float(float(d.layout.props.items[0].p[0])).is_equal(0.0)
	# Scatter pines in the infield for a second: one action; none on the road.
	tool.set("mode", "scatter")
	tool.set("radius", 60.0)
	tool.pointer(_ev("press", Vector3(0, 0, 0)))
	for k in 20:
		tool.tick(1.0 / 15.0)
	tool.pointer(_ev("release", Vector3(0, 0, 0)))
	var xf := d.scatter_of("tree_pine")
	assert_int(xf.size() / 4).is_greater(20)
	var t := d.track()
	for k in range(0, xf.size(), 4):
		var proj := t.project(Vector3(xf[k], 0, xf[k + 1]))
		assert_float(absf(proj.lateral)).is_greater(6.0 + 1.1)
	# Erase them where the brush goes.
	tool.set("mode", "erase")
	tool.pointer(_ev("press", Vector3(0, 0, 0)))
	tool.tick(1.0 / 15.0)
	tool.pointer(_ev("release", Vector3(0, 0, 0)))
	assert_int(d.scatter_of("tree_pine").size()).is_less(xf.size())
	assert_str(d.undo()).is_equal("Erase")
	assert_int(d.scatter_of("tree_pine").size()).is_equal(xf.size())
	assert_str(d.undo()).is_equal("Scatter")
	assert_int(d.scatter_of("tree_pine").size()).is_equal(0)
	e.queue_free()
	await get_tree().process_frame
