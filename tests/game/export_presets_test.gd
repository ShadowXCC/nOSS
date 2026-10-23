extends GdUnitTestSuite
## What the exports carry (export_presets.cfg, D200). Godot imports PNGs as textures and leaves
## the PNG itself out unless a filter adds it, but a track package hashes and reads its own
## bytes: without them a hilly built-in track says "Missing file" in every build.


func test_every_preset_carries_the_built_in_tracks_files() -> void:
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	var presets := Array(cfg.get_sections()).filter(func(s: String) -> bool: return s.begins_with("preset.") and s.count(".") == 1)
	assert_array(presets).is_not_empty()
	var imported := 0
	for dir in DirAccess.get_directories_at("res://content/tracks"):
		var root := "res://content/tracks".path_join(dir)
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("manifest.json")))
		for rel: String in manifest.files:
			if not FileAccess.file_exists(root.path_join(rel) + ".import"):
				continue # not imported: exported as it is
			imported += 1
			var path := root.path_join(rel).trim_prefix("res://")
			for section: String in presets:
				var filters := Array(String(cfg.get_value(section, "include_filter", "")).split(",", false))
				var kept := filters.any(func(f: String) -> bool: return path.matchn(f.strip_edges()))
				assert_bool(kept).override_failure_message("%s leaves out %s" % [cfg.get_value(section, "name"), path]).is_true()
	assert_int(imported).is_greater(0)
