extends GdUnitTestSuite
## Police light bars (D116, ACC-04): with Reduce flashing the bar flashes at most three times a
## second and never goes dark, sampled at 1 kHz for 10 s; the police car's bar is drawn twice, on
## its two layers, and each camera mask shows one.


## Rising edges a second of `values` (brightness, 0..1) sampled every millisecond.
static func _edges_per_s(values: PackedFloat32Array, threshold: float) -> float:
	var edges := 0
	for i in range(1, values.size()):
		if values[i - 1] < threshold and values[i] >= threshold:
			edges += 1
	return edges / (values.size() / 1000.0)


func test_reduce_flashing_is_three_flashes_a_second_at_most() -> void:
	var red := PackedFloat32Array()
	var blue := PackedFloat32Array()
	var both := PackedFloat32Array()
	var lowest := 1.0
	for ms in 10000:
		var p := LightBar.pattern(ms / 1000.0, true)
		red.append(float(p.red))
		blue.append(float(p.blue))
		both.append(maxf(float(p.red), float(p.blue)))
		lowest = minf(lowest, minf(float(p.red), float(p.blue)))
	# Each half's flashes, and the two together (a viewer sees either half come on).
	assert_float(_edges_per_s(red, 0.9) + _edges_per_s(blue, 0.9)).is_less_equal(3.0)
	assert_float(lowest).is_greater(0.3) # lower contrast: never dark
	# The full pattern is faster (that's what Reduce flashing is for).
	var full := PackedFloat32Array()
	for ms in 10000:
		var p := LightBar.pattern(ms / 1000.0, false)
		full.append(maxf(float(p.red), float(p.blue)))
	assert_float(_edges_per_s(full, 0.5)).is_greater(3.0)


func test_the_bar_is_drawn_twice_and_each_camera_sees_one() -> void:
	var pkg := PackageLoader.load_package("res://content/traffic/police")
	var v := Vehicle.create(PlatformLoader.load_official("official.highway.interceptor"), pkg)
	add_child(v)
	# A police model gets its bar (and siren) when it's mounted.
	var bar := v.get_node_or_null(^"LightBar") as LightBar
	assert_object(bar).is_not_null()
	assert_object(v.get_node_or_null(^"Siren")).is_not_null()
	var normal := 0
	var calm := 0
	for mi: MeshInstance3D in v.visual.find_children("lightbar_*", "MeshInstance3D", true, false):
		if mi.name.begins_with("lightbar_base"):
			continue
		if mi.layers == 1 << (LightBar.LAYER_NORMAL - 1):
			normal += 1
		elif mi.layers == 1 << (LightBar.LAYER_CALM - 1):
			calm += 1
	assert_int(normal).is_greater_equal(2)
	assert_int(calm).is_equal(normal)
	var mask := LightBar.cull_mask_for(true, 0xFFFFF)
	assert_int(mask & (1 << (LightBar.LAYER_CALM - 1))).is_not_equal(0)
	assert_int(mask & (1 << (LightBar.LAYER_NORMAL - 1))).is_equal(0)
	mask = LightBar.cull_mask_for(false, mask)
	assert_int(mask & (1 << (LightBar.LAYER_CALM - 1))).is_equal(0)
	assert_int(mask & (1 << (LightBar.LAYER_NORMAL - 1))).is_not_equal(0)
	# Off: dark; on: lit.
	v.light_bar = true
	for i in 30:
		await get_tree().process_frame
	var lit := false
	for m: StandardMaterial3D in bar._calm.red + bar._calm.blue:
		lit = lit or m.emission_energy_multiplier > 0.0
	assert_bool(lit).is_true()
	v.queue_free()
