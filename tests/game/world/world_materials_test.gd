extends GdUnitTestSuite
## World materials and the weather (D153): paved surfaces (roads, curbs, paint) take snow as a
## dusting and shine when wet, the verges take it as a sheet; a highway's tunnels keep both off
## their road and lines.

const FIXTURE := "res://tests/fixtures/tracks/highway_ring_small.json"


func test_paved_surfaces_are_dusted_and_the_verges_are_not() -> void:
	for id: int in [VehicleSim.SURFACE_ASPHALT, VehicleSim.SURFACE_CONCRETE, VehicleSim.SURFACE_CURB, VehicleSim.SURFACE_PAINT]:
		var m := WorldMaterials.surface(id)
		assert_float(_param(m, "snow_dust", 0.0)).override_failure_message("surface %d" % id).is_equal(1.0)
		assert_float(_param(m, "wet_shine", 0.0)).is_equal(1.0)
		assert_object(m.get_shader_parameter("snow_noise")).is_not_null()
	for id: int in [VehicleSim.SURFACE_GRASS, VehicleSim.SURFACE_GRAVEL, VehicleSim.SURFACE_DIRT, VehicleSim.SURFACE_SAND, VehicleSim.SURFACE_SNOW]:
		assert_float(_param(WorldMaterials.surface(id), "snow_dust", 0.0)).override_failure_message("surface %d" % id).is_equal(0.0)
	# Lines are paint on the road, so they're dusted with it rather than turning white.
	assert_float(_param(WorldMaterials.paint("paint_yellow", Color(0.93, 0.72, 0.12)), "snow_dust", 0.0)).is_equal(1.0)


func test_the_dust_has_specks_and_patches() -> void:
	var img := RetroTextures.snow_dust().get_image()
	assert_bool(img.has_mipmaps()).is_true()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			lo = Vector2(minf(lo.x, c.r), minf(lo.y, c.g))
			hi = Vector2(maxf(hi.x, c.r), maxf(hi.y, c.g))
	assert_float(hi.x - lo.x).is_greater(0.6)
	assert_float(hi.y - lo.y).is_greater(0.6)


func test_a_sheltered_material_keeps_the_weather_off() -> void:
	var road := WorldMaterials.surface(VehicleSim.SURFACE_ASPHALT)
	var dry := WorldMaterials.sheltered(road)
	assert_object(WorldMaterials.sheltered(road)).is_same(dry)
	assert_float(_param(road, "weathered", 1.0)).is_equal(1.0)
	assert_float(_param(dry, "weathered", 1.0)).is_equal(0.0)
	assert_float(_param(dry, "snow_dust", 0.0)).is_equal(1.0) # otherwise the same road


func test_a_highway_tunnel_keeps_its_road_and_lines_dry() -> void:
	var root := TrackBuilder.build(TrackData.load_file(FIXTURE))
	for node_name in ["RoadSheltered", "LinesSheltered", "Highway/PortalFloors"]:
		var mi := root.get_node_or_null(node_name) as MeshInstance3D
		assert_object(mi).override_failure_message(node_name).is_not_null()
		assert_float(_param(mi.material_override, "weathered", 1.0)).override_failure_message(node_name).is_equal(0.0)
	for node_name in ["Road", "Lines"]:
		assert_float(_param((root.get_node(node_name) as MeshInstance3D).material_override, "weathered", 1.0)).is_equal(1.0)
	# Still the same road to drive on.
	assert_int(int(root.get_node("RoadShelteredBody").get_meta(&"noss_surface"))).is_equal(VehicleSim.SURFACE_ASPHALT)
	root.free()


func _param(m: Material, key: String, fallback: float) -> float:
	var v: Variant = (m as ShaderMaterial).get_shader_parameter(key)
	return fallback if v == null else float(v)
