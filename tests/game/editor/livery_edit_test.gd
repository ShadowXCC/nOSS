extends GdUnitTestSuite
## Livery edits in the Fitting Bay (docs/VEHICLE_PACKAGE.md §12): liveries made, copied, worn
## and deleted; layers added onto the body, placed in metres, ordered and grouped; mirror copies
## that still read; and undo, with a slider's drag one step.

var _draft: FittingDraft
var _edit: LiveryEdit


func before_test() -> void:
	var result := ModelImport.import_file("res://tests/fixtures/models/kenney/sedan-sports.glb")
	_draft = FittingDraft.from_import(result)
	_draft.paint.slots = { "primary": { "materials": ["colormap"], "color": "#E8B71A", "finish": "metallic" } }
	_edit = LiveryEdit.new(_draft)


func after_test() -> void:
	_draft.free_scene()


func test_liveries() -> void:
	assert_str(_edit.new_livery()).is_equal("Livery added")
	var first: String = _draft.editing
	assert_str(_draft.worn).is_equal(first)
	assert_dict(_edit.livery().base).is_not_empty()
	_edit.rename("Stripes")
	assert_str(_edit.livery().name).is_equal("Stripes")
	_edit.copy_livery()
	assert_int(_draft.liveries.size()).is_equal(2)
	assert_str(_edit.livery().name).is_equal("Stripes copy")
	assert_str(_draft.worn).is_equal(first) # still wears the first
	_edit.wear("")
	assert_str(_draft.worn).is_empty()
	_edit.delete_livery()
	assert_int(_draft.liveries.size()).is_equal(1)
	assert_str(_draft.editing).is_equal(first)


## A new layer lands on the body, on the side picked, the size asked for.
func test_layers_go_on_the_body() -> void:
	assert_str(_edit.add("shape", "chevrons")).is_equal("Chevrons added")
	assert_int(_edit.layers().size()).is_equal(1)
	var p := _edit.placement()
	assert_str(p.side).is_equal("left")
	assert_float(p.size).is_equal_approx(0.5, 0.001)
	# On the body: a ray from just outside along the normal meets it right there.
	var base := _edit.car_xform()
	var at := base * LiveryEdit._v(_edit.current().at)
	var n := (base.basis * LiveryEdit._v(_edit.current().normal)).normalized()
	var hit := _edit.raycast(at + n * 2.0, -n)
	assert_vector(hit.position).is_equal_approx(at, Vector3.ONE * 0.001)
	assert_str(_edit.place_side("top")).is_equal("On the top")
	assert_str(_edit.placement().side).is_equal("top")
	_edit.set_size(1.0)
	_edit.set_stretch(2.0)
	p = _edit.placement()
	assert_float(p.size).is_equal_approx(1.0, 0.001)
	assert_float(p.stretch).is_equal_approx(2.0, 0.001)
	_edit.set_turn(30.0)
	assert_float(_edit.placement().turn).is_equal_approx(30.0, 0.1)
	_edit.set_flip("across")
	assert_str(_edit.placement().flip).is_equal("across")
	assert_float(_edit.placement().turn).is_equal_approx(30.0, 0.1)


func test_slide_along_the_side() -> void:
	_edit.add("shape", "rect")
	var before: float = _edit.placement().along
	_edit.slide("along", before + 0.5)
	assert_float(_edit.placement().along).is_equal_approx(before + 0.5, 0.01)
	# Still on the body.
	var base := _edit.car_xform()
	var at := base * LiveryEdit._v(_edit.current().at)
	var n := (base.basis * LiveryEdit._v(_edit.current().normal)).normalized()
	assert_vector(_edit.raycast(at + n * 2.0, -n).position).is_equal_approx(at, Vector3.ONE * 0.001)


## A slider's drag is one undo step; a different change is another.
func test_undo_merges_a_drag() -> void:
	_edit.add("shape", "rect")
	for v in [0.6, 0.7, 0.8, 0.9]:
		_edit.set_size(v)
	_edit.set_value("color", "#FF0000")
	assert_str(_edit.undo()).is_equal("Undone: Color")
	assert_float(_edit.placement().size).is_equal_approx(0.9, 0.001)
	assert_str(_edit.undo()).is_equal("Undone: Size")
	assert_float(_edit.placement().size).is_equal_approx(0.5, 0.001)
	assert_str(_edit.undo()).is_equal("Undone: Rectangle added")
	assert_int(_edit.layers().size()).is_equal(0)
	assert_str(_edit.redo()).is_equal("Redone: Rectangle added")
	assert_int(_edit.layers().size()).is_equal(1)
	assert_bool(_draft.liveries_unsaved()).is_true()


func test_order_and_groups() -> void:
	for shape: String in ["rect", "star", "ring", "stripes"]:
		_edit.add("shape", shape)
	# Star and stripes into a group: they end up together.
	_edit.layer = 1
	assert_str(_edit.set_group(-1)).is_equal("Group 1")
	_edit.layer = 3
	_edit.set_group(1)
	var shapes: Array = _edit.layers().map(func(l: Dictionary) -> String: return l.shape)
	assert_array(shapes).is_equal(["rect", "star", "stripes", "ring"])
	assert_str(_edit.current().shape).is_equal("stripes") # still picked
	assert_str(_edit.reorder("top")).is_equal("On top")
	shapes = _edit.layers().map(func(l: Dictionary) -> String: return l.shape)
	assert_array(shapes).is_equal(["rect", "star", "ring", "stripes"])
	assert_bool(_edit.current().has("group")).is_false() # left its group
	assert_int(_edit.livery().groups.size()).is_equal(1)


## A cut-out in a group reaches its group only; ungrouped it reaches every layer under it.
func test_cut_scope_when_packed() -> void:
	for shape: String in ["rect", "stripes", "rect"]:
		_edit.add("shape", shape)
	_edit.layer = 1
	_edit.set_group(-1)
	_edit.layer = 2
	_edit.set_group(1)
	_edit.set_value("cut", true)
	var packed := LiveryRenderer.pack(_edit.livery(), "primary")
	var d: PackedVector4Array = packed[0]
	assert_float(d[2 * 6 + 5].z).is_equal(1.0)
	_edit.set_group(0)
	packed = LiveryRenderer.pack(_edit.livery(), "primary")
	d = packed[0]
	assert_float(d[2 * 6 + 5].z).is_equal(0.0)


## The whole group moves with the picked layer.
func test_whole_group_moves() -> void:
	_edit.add("shape", "rect")
	_edit.add("shape", "star")
	_edit.layer = 0
	_edit.set_group(-1)
	_edit.layer = 1
	_edit.set_group(1)
	var other: Dictionary = _edit.layers()[0]
	var before := LiveryEdit._v(other.at)
	_edit.whole_group = true
	var p := _edit.placement()
	_edit.slide("height", p.height + 0.2)
	var moved := _edit.car_xform().basis * (LiveryEdit._v(other.at) - before)
	assert_float(moved.y).is_equal_approx(0.2, 0.05)


## A mirror copy sits across the car; text there still reads (not reversed).
func test_mirror_copy() -> void:
	_edit.add("text")
	var src := _edit.current()
	assert_str(_edit.mirror_copy()).is_equal("Mirror copy")
	var copy := _edit.current()
	assert_bool(is_same(copy, src)).is_false()
	var base := _edit.car_xform()
	var a := base * LiveryEdit._v(src.at)
	var b := base * LiveryEdit._v(copy.at)
	assert_float(a.x + b.x).is_equal_approx(2.0 * _edit._mid_x(), 0.001)
	assert_str(_edit.placement().side).is_equal("right")
	assert_float(_edit.placement().turn).is_equal_approx(0.0, 0.5) # upright and reading on the right too
	assert_float(float(copy.size[0])).is_greater(0.0)
	# A shape that doesn't read is mirrored instead.
	_edit.add("shape", "arrow")
	_edit.mirror_copy()
	assert_float(float(_edit.current().size[1])).is_less(0.0)


func test_text_keeps_its_height() -> void:
	_edit.add("text")
	var h := absf(float(_edit.current().size[1]))
	var w := absf(float(_edit.current().size[0]))
	_edit.set_value("text", "nOSS RACING TEAM")
	assert_float(absf(float(_edit.current().size[1]))).is_equal_approx(h, 0.0001)
	assert_float(absf(float(_edit.current().size[0]))).is_greater(w * 2.0)


func test_limits() -> void:
	for i in LiveryData.MAX_LAYERS:
		_edit.add("shape", "rect")
	assert_str(_edit.add("shape", "rect")).is_equal("Too many layers")
	assert_str(_edit.duplicate_layer()).is_equal("Too many layers")


## The history is the draft's: back from a test drive (a new bay, a new LiveryEdit), undo still works.
func test_undo_outlasts_the_bay() -> void:
	_edit.add("shape", "rect")
	_edit = LiveryEdit.new(_draft)
	assert_int(_edit.layer).is_equal(0)
	assert_str(_edit.undo()).is_equal("Undone: Rectangle added")
	assert_int(_edit.layers().size()).is_equal(0)
