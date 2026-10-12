class_name TrackLoader
extends RefCounted
## Loads tracks (docs/TRACK_EDITOR.md §5, R4): a .nosstrack zip, an unpacked folder (built-in
## tracks, drafts, downloads) or a bare track.json. Nothing is used before it's checked: the zip's
## directory and sizes before anything is decompressed, every file against the manifest's hash,
## the schemas, image sizes before decoding. Godot resources and scripts are never loaded.

## Caller limits can only lower these (a server's cap).
const LIMITS := { "ceiling": "track", "max_zip_bytes": 100 << 20, "max_total_bytes": 250 << 20, "max_entries": 512 }
const MAX_MANIFEST := 64 << 10
const MAX_IMAGE := 1024
const TIMEOUT_S := 60.0


## `opts.terrain` false: skip the terrain (the track's centreline only, for lists and checks).
static func load_package(path: String, limits := {}, opts := {}) -> TrackPackage:
	var started := Time.get_ticks_usec()
	var pkg := TrackPackage.new()
	pkg.path = path
	pkg.error = _load(pkg, path, _limits(limits), opts)
	pkg.load_ms = (Time.get_ticks_usec() - started) / 1000.0
	return pkg


## Loads on a worker; `on_done` (TrackPackage) runs on the main thread (or gets "Load timed out").
static func load_async(owner: Node, path: String, on_done: Callable, limits := {}, opts := {}) -> void:
	WorkerJob.start(owner, func() -> TrackPackage: return load_package(path, limits, opts), on_done, TIMEOUT_S,
		func() -> TrackPackage:
			var pkg := TrackPackage.new()
			pkg.path = path
			pkg.error = "Load timed out"
			return pkg)


## A package's manifest, unchecked (lists): {} if there isn't one.
static func read_manifest(path: String) -> Dictionary:
	if path.ends_with(".json"):
		return {}
	var source := PackageSource.open(path, LIMITS)
	if source.error or not source.has("manifest.json") or source.size_of("manifest.json") > MAX_MANIFEST:
		source.close()
		return {}
	var m: Variant = JSON.parse_string(source.read("manifest.json").get_string_from_utf8())
	source.close()
	return m if m is Dictionary else {}


static func _limits(limits: Dictionary) -> Dictionary:
	var out := LIMITS.duplicate()
	for key: String in limits:
		if key != "ceiling" and out.has(key) and int(limits[key]) < int(out[key]):
			out[key] = int(limits[key])
	return out


static func _load(pkg: TrackPackage, path: String, lim: Dictionary, opts: Dictionary) -> String:
	if path.ends_with(".json"):
		return _load_json(pkg, path)
	var source := PackageSource.open(path, lim)
	if source.error:
		source.close()
		return source.error
	var err := _read(pkg, source, lim, opts)
	source.close()
	return err


## A bare track.json: noss.track/1, or /0 (upgraded); flat ground.
static func _load_json(pkg: TrackPackage, path: String) -> String:
	if not FileAccess.file_exists(path):
		return "No track at " + path
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return "Not a track file"
	if data.get("schema") == TrackFormat.LEGACY:
		data = TrackFormat.upgrade_v0(data)
	var err := TrackFormat.validate(data)
	if err:
		return "track.json: " + err
	pkg.layout = data
	pkg.track = TrackData.from_dict(data)
	pkg.track.builtin = path.begins_with("res://")
	return ""


static func _read(pkg: TrackPackage, source: PackageSource, lim: Dictionary, opts: Dictionary) -> String:
	if not source.has("manifest.json"):
		return "No manifest"
	if source.size_of("manifest.json") > MAX_MANIFEST:
		return "Manifest too large"
	var manifest_bytes := source.read("manifest.json")
	var manifest: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not manifest is Dictionary:
		return "manifest.json isn't valid JSON"
	var errors := JsonSchema.validate(manifest, JsonSchema.load_schema("track_package"))
	if not errors.is_empty():
		return "manifest.json: " + errors[0]
	pkg.manifest = manifest
	pkg.hash = "sha256:" + PlatformLoader.sha256_hex(manifest_bytes)
	var listed: Dictionary = manifest.files
	for rel in source.files():
		if rel != "manifest.json" and not listed.has(rel):
			return "Unlisted file: " + rel
	var total := 0
	for rel: String in listed:
		if not source.has(rel):
			return "Missing file: " + rel
		total += source.size_of(rel)
	if total > int(lim.max_total_bytes):
		return "Track too large"
	# Every file is hashed before any is used.
	var files := {}
	for rel: String in listed:
		var bytes := source.read(rel)
		if "sha256:" + PlatformLoader.sha256_hex(bytes) != listed[rel]:
			return "Hash mismatch: " + rel
		files[rel] = bytes
	var layout: Variant = JSON.parse_string((files["track.json"] as PackedByteArray).get_string_from_utf8())
	if not layout is Dictionary:
		return "track.json isn't valid JSON"
	var err := TrackFormat.validate(layout)
	if err:
		return "track.json: " + err
	pkg.layout = layout
	for image: Array in [["thumb.png", "thumb"], ["minimap.png", "minimap"]]:
		if files.has(image[0]):
			var size := NossPackage.image_size(files[image[0]])
			if size.x < 1 or size.x > MAX_IMAGE or size.y > MAX_IMAGE:
				return image[0] + " too large"
			pkg.set(image[1], files[image[0]])
	var ground: Dictionary = layout.get("ground", {})
	if ground.has("terrain") and opts.get("terrain", true):
		var loaded := TerrainData.from_files(files)
		if loaded.has("error"):
			return String(loaded.error)
		pkg.terrain = loaded.terrain
	if layout.get("scene") is Dictionary and opts.get("scene", true):
		var tag_data: Variant = JSON.parse_string((files.get("scene/tags.json", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
		if not tag_data is Dictionary:
			return "scene/tags.json isn't valid JSON"
		var why := SceneTrack.validate_tags(tag_data)
		if why:
			return "scene/tags.json: " + why
		var scene_limits := SceneTrack.LIMITS.duplicate()
		for key: String in lim:
			if scene_limits.has(key) and int(lim[key]) < int(scene_limits[key]):
				scene_limits[key] = int(lim[key])
		pkg.scene = SceneTrack.from_glb(files.get("scene/scene.glb", PackedByteArray()), tag_data, scene_limits)
		if not pkg.scene.ok():
			return pkg.scene.error()
	pkg.track = TrackData.from_dict(layout, pkg.terrain.ground_height() if pkg.terrain else Callable())
	pkg.track.builtin = pkg.path.begins_with("res://")
	if pkg.terrain:
		pkg.terrain.conform(pkg.track)
	return ""
