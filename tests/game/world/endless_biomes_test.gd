extends GdUnitTestSuite
## The endless biomes' registry (D156, D221): a data file for every native biome, every prop they
## scatter offered by the editor's scatter brush (unknown ones would be left out without a word),
## the schemas' biome lists in step with the road generator's, and every global a shader
## reads declared in project.godot (or no world material would compile).


func test_every_biome_has_its_file() -> void:
	for id: String in NossRoadGen.biome_ids():
		assert_bool(FileAccess.file_exists(EndlessBiomes.DIR + id + ".json")).override_failure_message(id).is_true()
		assert_str(String(EndlessBiomes.find(id).get("id", ""))).is_equal(id)
	assert_dict(EndlessBiomes.find("moon")).is_empty()
	assert_dict(EndlessBiomes.find("")).is_empty()


func test_every_scattered_prop_is_a_scatter_prop() -> void:
	for b: Dictionary in EndlessBiomes.all():
		for spec: Dictionary in b.get("scatter", []):
			var id := String(spec.prop)
			assert_bool(PropLibrary.TYPES.has(id)).override_failure_message("%s: %s" % [b.id, id]).is_true()
			assert_bool(bool(PropLibrary.TYPES.get(id, {}).get("scatter", false))).override_failure_message("%s: %s" % [b.id, id]).is_true()


func test_the_schemas_list_every_biome() -> void:
	var ids := Array(NossRoadGen.biome_ids())
	var biome: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/schemas/endless_biome.schema.json"))
	assert_array(biome.properties.id.enum).is_equal(ids)
	var track: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/schemas/track.schema.json"))
	assert_array(track.properties.environment.properties.biome.enum).is_equal(ids)


func test_every_shader_global_is_declared() -> void:
	var found := 0
	for path in _shaders("res://game"):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var l := line.strip_edges()
			if not l.begins_with("global uniform"):
				continue
			var global_name := l.get_slice(" ", 3).trim_suffix(";")
			found += 1
			assert_bool(ProjectSettings.has_setting("shader_globals/" + global_name)).override_failure_message("%s: %s" % [path, global_name]).is_true()
	assert_int(found).is_greater(5)


func _shaders(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gdshader"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_shaders(dir.path_join(d)))
	return out
