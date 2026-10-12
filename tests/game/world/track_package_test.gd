extends GdUnitTestSuite
## Track packages (EDT-07, docs/TRACK_EDITOR.md §5): the built-in folder, .nosstrack round
## trips with terrain, the checks before anything is used, and the track library.

const DIR := "user://tests/track_packages/"


func before() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	TrackLibrary.user_dir = DIR


func after() -> void:
	TrackLibrary.user_dir = "user://tracks/"
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))


## A small terrain track's files: a loop over a raised hill, painted.
static func terrain_track(id := "") -> Dictionary:
	var d := RoadBuilderTest.loop_track(1500.0, "ground")
	d.id = id if id else "test_loop"
	var terrain := TerrainData.around(Rect2(-350, -200, 700, 400), 150.0)
	terrain.field.brush(0, Vector2(290, 0), 120.0, 8.0, 0.8, 0.0, 0.0, 0)
	terrain.field.paint(3, Vector2(0, 0), 40.0, 1.0, 0.5)
	d.ground = { "terrain": "terrain/meta.json" }
	var files := terrain.to_files()
	files["track.json"] = PackageWriter.canonical_json(d).to_utf8_buffer()
	return files


func _info(id := "") -> Dictionary:
	var info := { "name": "Test Loop", "author": "tests", "license": "CC0-1.0" }
	if id:
		info.id = id
	return info


func test_the_built_in_track_loads_from_its_folder() -> void:
	var pkg := TrackLoader.load_package(TrackLibrary.DEFAULT)
	assert_str(pkg.error).is_empty()
	assert_bool(pkg.builtin()).is_true()
	assert_str(pkg.hash).is_equal(TrackLibrary.manifest_hash(TrackLibrary.DEFAULT))
	assert_int(pkg.track.samples.size()).is_equal(TrackGoldenTest.SAMPLES)
	assert_str(pkg.track.record_key()).is_equal("proving_ground")
	assert_object(pkg.terrain).is_null()
	assert_str(TrackLibrary.resolve("proving_ground")).is_equal(TrackLibrary.DEFAULT)
	assert_str(TrackLibrary.resolve(pkg.hash)).is_equal(TrackLibrary.DEFAULT)


func test_a_terrain_track_round_trips() -> void:
	var path := DIR.path_join("loop.nosstrack")
	DirAccess.remove_absolute(path)
	var files := terrain_track()
	var r := TrackWriter.write(path, _info(), files)
	assert_str(String(r.error)).is_empty()
	var pkg := TrackLoader.load_package(path)
	assert_str(pkg.error).is_empty()
	assert_object(pkg.terrain).is_not_null()
	assert_str(pkg.manifest.kind).is_equal("road")
	assert_float(float(pkg.manifest.length_m)).is_between(1300.0, 1800.0)
	var p := pkg.track.samples[pkg.track.project(Vector3(290, 0, 0)).index]
	assert_float(p.y).is_greater(3.0) # over the hill
	assert_float(p.y - pkg.terrain.height_at(p.x, p.z)).is_between(0.0, 0.2)
	assert_str(pkg.track.record_key()).starts_with("test_loop-")
	# The same again: unchanged. Changed: version 2.
	var again := TrackWriter.write(path, _info(String(r.manifest.id)), files)
	assert_bool(again.unchanged).is_true()
	var d: Dictionary = JSON.parse_string((files["track.json"] as PackedByteArray).get_string_from_utf8())
	d.road.points[2].p[0] = float(d.road.points[2].p[0]) + 20.0
	files["track.json"] = PackageWriter.canonical_json(d).to_utf8_buffer()
	var changed := TrackWriter.write(path, _info(String(r.manifest.id)), files)
	assert_int(int(changed.manifest.version)).is_equal(2)
	assert_str(TrackLoader.load_package(path).track.record_key()).is_not_equal(pkg.track.record_key())
	# Another track can't take the file.
	assert_str(String(TrackWriter.write(path, _info(), files).error)).is_equal("Another track uses that file")
	# It's in the library, by id and by hash.
	var listed := TrackLibrary.list()
	assert_bool(listed.any(func(e: Dictionary) -> bool: return e.path == path)).is_true()
	assert_str(TrackLibrary.resolve(String(r.manifest.id))).is_equal(path)
	assert_str(TrackLibrary.resolve(TrackLibrary.manifest_hash(path))).is_equal(path)
	assert_str(TrackLibrary.label(TrackLibrary.entry(path))).starts_with("Test Loop · 1.")


func test_files_are_checked_before_use() -> void:
	var files := terrain_track()
	var folder := DIR.path_join("tampered")
	assert_str(TrackWriter.write_folder(folder, _info(), files)).is_empty()
	assert_str(TrackLoader.load_package(folder).error).is_empty()
	# Changed after hashing.
	var f := FileAccess.open(folder.path_join("track.json"), FileAccess.READ_WRITE)
	f.seek(10)
	f.store_8(65)
	f.close()
	assert_str(TrackLoader.load_package(folder).error).is_equal("Hash mismatch: track.json")
	# A file the manifest doesn't list.
	assert_str(TrackWriter.write_folder(folder, _info(), files)).is_empty()
	var extra := FileAccess.open(folder.path_join("extra.json"), FileAccess.WRITE)
	extra.store_string("{}")
	extra.close()
	assert_str(TrackLoader.load_package(folder).error).is_equal("Unlisted file: extra.json")
	DirAccess.remove_absolute(folder.path_join("extra.json"))
	# A huge thumbnail.
	files["thumb.png"] = Image.create(2048, 64, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	assert_str(TrackWriter.write_folder(folder, _info(), files)).is_empty()
	assert_str(TrackLoader.load_package(folder).error).is_equal("thumb.png too large")
	for rel in ["track.json", "manifest.json", "thumb.png", "terrain/meta.json", "terrain/height.png", "terrain/splat_0.png", "terrain/splat_1.png"]:
		DirAccess.remove_absolute(folder.path_join(rel))


func test_tracks_may_be_bigger_than_cars() -> void:
	# 55 MB of noise: over the car ceiling (50 MB), under the track one (100 MB).
	var path := DIR.path_join("big.zip")
	var zip := ZIPPacker.new()
	zip.open(path)
	zip.start_file("model/noise.png")
	zip.write_file(Crypto.new().generate_random_bytes(55 << 20))
	zip.close_file()
	zip.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	assert_bool(NossPackage.inspect_zip(bytes, {}).ok).is_false()
	assert_bool(NossPackage.inspect_zip(bytes, { "ceiling": "track" }).ok).is_true()
	assert_bool(NossPackage.inspect_zip(bytes, { "ceiling": "track", "max_zip_bytes": 40 << 20 }).ok).is_false() # a server's cap
	DirAccess.remove_absolute(path)
