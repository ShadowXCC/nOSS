class_name PackageLoader
extends RefCounted
## Loads .noss packages: zip checks, hashes, schemas and limits first, then glTF parsing
## (docs/VEHICLE_PACKAGE.md §9-10, PKG-01, PKG-08). load_package() blocks; use load_async()
## from gameplay so parsing stays off the main thread (NFR-04).

## Defaults from docs/VEHICLE_PACKAGE.md §9. Servers can only lower them.
const DEFAULT_LIMITS := {
	"max_zip_bytes": 50 << 20,
	"max_total_bytes": 150 << 20,
	"max_entries": 512,
	"max_lod0_triangles": 500_000,
	"max_nodes": 2000,
	"max_materials": 128,
	"max_texture_size": 4096,
	"max_texture_bytes": 256 << 20,
	"max_sound_bytes": 10 << 20,
	"max_sound_samples": 32,
}
const TIMEOUT_S := 30.0
const GARAGE_DIR := "user://garage/"
const OFFICIAL_CARS_DIR := "res://content/cars/"

## glTF extensions a package may use. Others (Draco, meshopt, WebP, BasisU) are rejected:
## Godot can't decode some of them, and package images must be PNG or JPEG.
const GLTF_EXTENSIONS := [
	"GODOT_single_root", "KHR_lights_punctual", "KHR_materials_clearcoat", "KHR_materials_emissive_strength",
	"KHR_materials_ior", "KHR_materials_pbrSpecularGlossiness", "KHR_materials_sheen",
	"KHR_materials_specular", "KHR_materials_transmission", "KHR_materials_unlit",
	"KHR_materials_volume", "KHR_mesh_quantization", "KHR_texture_transform",
]
const AUDIO_TYPES := ["ogg", "wav"]
const COMPONENT_BYTES := { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 }
const TYPE_COMPONENTS := { "SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16 }


## Every package the player can pick: official content first, then the garage.
static func list_available() -> PackedStringArray:
	var paths := PackedStringArray()
	for dir in DirAccess.get_directories_at(OFFICIAL_CARS_DIR):
		paths.append(OFFICIAL_CARS_DIR + dir)
	var garage := DirAccess.get_files_at(GARAGE_DIR) if DirAccess.dir_exists_absolute(GARAGE_DIR) else PackedStringArray()
	for file in garage:
		if file.ends_with(".noss"):
			paths.append(GARAGE_DIR + file)
	return paths


## Manifest only, for listings. Not validated: loading the package does that.
static func read_manifest(path: String) -> Dictionary:
	var bytes := PackedByteArray()
	if DirAccess.dir_exists_absolute(path):
		bytes = FileAccess.get_file_as_bytes(path.path_join("manifest.json"))
	else:
		var zip := ZIPReader.new()
		if zip.open(path) == OK:
			if zip.file_exists("manifest.json"):
				bytes = zip.read_file("manifest.json")
			zip.close()
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if bytes.size() < 65536 and not bytes.is_empty() else null
	return data if data is Dictionary else {}


## Loaded packages kept for load_shared(): path -> VehiclePackage, or the callbacks waiting for it.
static var _shared := {}


## Like load_async(), but each path loads once while the cache lives: every caller gets its
## own copy of the model scenes, sharing meshes and textures (a grid of AI cars on one model).
## Paint and brake lights are per car (CarVisual uses its own material overrides).
static func load_shared(path: String, on_done: Callable, opts := {}) -> void:
	var key := path + "|" + String(opts.get("models", "all")) + ("|partial" if opts.get("partial", false) else "")
	var entry: Variant = _shared.get(key)
	if entry is VehiclePackage:
		on_done.call_deferred(_copy(entry))
		return
	if entry is Array:
		entry.append(on_done)
		return
	_shared[key] = [on_done]
	load_async(path, func(pkg: VehiclePackage) -> void:
		var waiting: Variant = _shared.get(key)
		if not waiting is Array:
			pkg.free_scenes() # the cache was cleared meanwhile
			return
		if pkg.ok():
			_shared[key] = pkg
		else:
			_shared.erase(key)
		for callback: Callable in waiting:
			callback.call(_copy(pkg) if pkg.ok() else pkg), {}, opts)


## Frees the cached packages' scenes (copies already handed out stay).
static func clear_shared() -> void:
	for entry: Variant in _shared.values():
		if entry is VehiclePackage:
			entry.free_scenes()
	_shared.clear()


static func _copy(pkg: VehiclePackage) -> VehiclePackage:
	var c := VehiclePackage.new()
	c.path = pkg.path
	c.hash = pkg.hash
	c.manifest = pkg.manifest
	c.fit = pkg.fit
	c.paint = pkg.paint
	c.sound = pkg.sound
	c.triangles = pkg.triangles
	c.load_ms = pkg.load_ms
	c.error = pkg.error
	c.tier = pkg.tier
	c.sound_streams = pkg.sound_streams
	for lod in pkg.lods:
		c.lods.append(lod.duplicate() as Node3D)
	return c


## Loads on a worker thread; `on_done` gets the VehiclePackage on the main thread.
static func load_async(path: String, on_done: Callable, limits := {}, opts := {}) -> void:
	var job := _Job.new()
	job.on_done = on_done
	job.task = WorkerThreadPool.add_task(func() -> void:
		var pkg := load_package(path, limits, opts)
		job.finish.call_deferred(pkg), true, "Load " + path.get_file())
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.create_timer(TIMEOUT_S, true, false, true).timeout.connect(job.time_out.bind(path))


## Validates and parses a package. Check `ok()` on the result. `opts`:
## - models: "all" (LOD0 and its LODs), "smallest" (only the smallest LOD, a quick preview) or
##   "none" (data only: physics needs fit.json, not the model; servers and bots)
## - partial: files the load doesn't read may be missing (a car still downloading). Only the
##   files read are checked against the manifest; they were checked on download too.
static func load_package(path: String, limits := {}, opts := {}) -> VehiclePackage:
	var t0 := Time.get_ticks_msec()
	var pkg := VehiclePackage.new()
	pkg.path = path
	var lim := DEFAULT_LIMITS.duplicate()
	for key: String in limits:
		if lim.has(key):
			lim[key] = mini(lim[key], limits[key])
	var source := PackageSource.open(path, lim)
	if source.error:
		pkg.error = source.error
		return pkg
	pkg.error = _read_data(source, pkg, lim, opts)
	if pkg.ok():
		pkg.error = _load_models(source, pkg, lim, _models_to_load(source, pkg.manifest, String(opts.get("models", "all"))))
	source.close()
	if not pkg.ok():
		pkg.free_scenes()
	pkg.load_ms = Time.get_ticks_msec() - t0
	return pkg


## Manifest, hashes, fit, paint and sound. Returns an error or "".
static func _read_data(source: PackageSource, pkg: VehiclePackage, lim: Dictionary, opts := {}) -> String:
	if not source.has("manifest.json"):
		return "No manifest.json"
	var manifest_bytes := source.read("manifest.json")
	var manifest: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not manifest is Dictionary:
		return "manifest.json isn't valid JSON"
	var errors := JsonSchema.validate(manifest, JsonSchema.load_schema("package"))
	if not errors.is_empty():
		return "manifest.json: " + errors[0]
	pkg.manifest = manifest
	pkg.hash = "sha256:" + PlatformLoader.sha256_hex(manifest_bytes)

	var listed: Dictionary = manifest.files
	for file in source.files():
		if file != "manifest.json" and not listed.has(file):
			return "File not in manifest: " + file
	var partial: bool = opts.get("partial", false)
	var needed := {}
	for file in ["fit.json", "paint.json", "sound/profile.json"]:
		needed[file] = true
	for file in _models_to_load(source, manifest, String(opts.get("models", "all"))):
		needed[file] = true
	var sound_bytes := 0
	var sound_samples := 0
	for file: String in listed:
		if not source.has(file):
			if partial and not needed.has(file):
				continue
			return "Missing file: " + file
		if file.begins_with("sound/") and file.get_extension() in AUDIO_TYPES:
			sound_bytes += source.size_of(file)
			sound_samples += 1
	if sound_bytes > lim.max_sound_bytes or sound_samples > lim.max_sound_samples:
		return "Sound pack too large"
	# Hash every file before using any of them (a partial load: every file it reads).
	for file: String in listed:
		if partial and (not needed.has(file) or not source.has(file)):
			continue
		if "sha256:" + PlatformLoader.sha256_hex(source.read(file)) != listed[file]:
			return "Hash mismatch: " + file

	for item: Array in [["fit.json", "fit"], ["paint.json", "paint"]]:
		var data: Variant = JSON.parse_string(source.read(item[0]).get_string_from_utf8())
		if not data is Dictionary:
			return item[0] + " isn't valid JSON"
		errors = JsonSchema.validate(data, JsonSchema.load_schema(item[1]))
		if not errors.is_empty():
			return "%s: %s" % [item[0], errors[0]]
		pkg.set(item[1], data)
	if source.has("sound/profile.json"):
		var sound: Variant = JSON.parse_string(source.read("sound/profile.json").get_string_from_utf8())
		if not sound is Dictionary:
			return "sound/profile.json isn't valid JSON"
		errors = JsonSchema.validate(sound, JsonSchema.load_schema("sound"))
		if not errors.is_empty():
			return "sound/profile.json: " + errors[0]
		pkg.sound = sound
		var err := _read_recordings(source, pkg, opts)
		if err:
			return err
	return ""


## Own recordings (AV-06): every one the profile names must be in the package; they're decoded
## here, off the main thread. A partial package (recordings not sent, D80) plays its base profile.
static func _read_recordings(source: PackageSource, pkg: VehiclePackage, opts: Dictionary) -> String:
	var named := recordings(pkg.sound)
	if named.is_empty():
		return ""
	var missing := named.keys().filter(func(rel: String) -> bool: return not source.has("sound/" + rel))
	if not missing.is_empty():
		if not opts.get("partial", false):
			return "Missing recording: " + String(missing[0])
		pkg.sound = without_recordings(pkg.sound)
		return ""
	if not opts.get("audio", true):
		return ""
	for rel: String in named:
		var stream := SoundImport.stream(source.read("sound/" + rel), rel.get_extension(), named[rel])
		if stream == null:
			return "Recording can't be played: " + rel
		pkg.sound_streams[rel] = stream
	return ""


## The recordings a sound profile names: path -> loops (layers, limiter, turbo) or not (one-shots).
static func recordings(sound: Dictionary) -> Dictionary:
	var out := {}
	for layer: Dictionary in sound.get("layers", []):
		for sample: Dictionary in layer.get("samples", []):
			for kind in ["on", "off"]:
				if sample.get(kind) is String:
					out[sample[kind]] = true
	var extras: Dictionary = sound.get("extras", {})
	for key in ["limiter", "turbo"]:
		if extras.get(key) is String:
			out[extras[key]] = true
	for key in ["start", "blowoff"]:
		if extras.get(key) is String:
			out[extras[key]] = false
	for rel: Variant in extras.get("backfire", []):
		if rel is String:
			out[rel] = false
	var tires: Variant = sound.get("tires")
	if tires is Dictionary and tires.get("recording") is String:
		out[tires.recording] = true
	return out


## The profile with its own recordings taken out (a tuned built-in is left).
static func without_recordings(sound: Dictionary) -> Dictionary:
	var out := sound.duplicate(true)
	for key in ["layers", "extras", "rpm_idle", "rpm_max"]:
		out.erase(key)
	if out.get("tires") is Dictionary:
		(out.tires as Dictionary).erase("recording")
	return out


## LOD0 is model/body.glb, then model/lod1.glb, lod2… while they exist.
static func model_files(source: PackageSource) -> PackedStringArray:
	var files := PackedStringArray(["model/body.glb"])
	var n := 1
	while source.has("model/lod%d.glb" % n):
		files.append("model/lod%d.glb" % n)
		n += 1
	return files


## The model files a load reads: LOD0 and its LODs, only the smallest one there is, or none.
static func _models_to_load(source: PackageSource, manifest: Dictionary, models: String) -> PackedStringArray:
	match models:
		"none":
			return PackedStringArray()
		"smallest":
			var listed := ContentStore.model_files(manifest.get("files", {}))
			for i in range(listed.size() - 1, -1, -1):
				if source.has(listed[i]):
					return PackedStringArray([listed[i]])
			return PackedStringArray(["model/body.glb"])
	return model_files(source)


static func _load_models(source: PackageSource, pkg: VehiclePackage, lim: Dictionary, files: PackedStringArray) -> String:
	var buffers: Array[PackedByteArray] = []
	var texture_bytes := 0.0
	pkg.tier = "full" if files.has("model/body.glb") and files.size() == model_files(source).size() else "preview" if not files.is_empty() else "data"
	for file in files:
		var bytes := source.read(file)
		var check := check_glb(bytes, lim)
		if check.error:
			return "%s: %s" % [file, check.error]
		texture_bytes += check.texture_bytes
		if file == files[0]:
			pkg.triangles = check.triangles
			if check.triangles > lim.max_lod0_triangles:
				return "Too many triangles: %d" % check.triangles
		buffers.append(bytes)
	if texture_bytes > lim.max_texture_bytes:
		return "Textures too large: %d MB" % int(texture_bytes / 1048576.0)

	for bytes in buffers:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_buffer(bytes, "", state) != OK:
			return "Model failed to parse"
		_add_mipmaps(state)
		var scene := doc.generate_scene(state) as Node3D
		if scene == null:
			return "Model has no scene"
		_strip(scene)
		pkg.lods.append(scene)
	return ""


## Structure and limit checks on a GLB, before Godot parses it.
## Returns {error, triangles, texture_bytes}.
static func check_glb(bytes: PackedByteArray, lim: Dictionary) -> Dictionary:
	var out := { "error": "", "triangles": 0, "texture_bytes": 0.0 }
	var info: Dictionary = NossPackage.inspect_glb(bytes)
	if not info.ok:
		out.error = info.error
		return out
	var gltf: Variant = JSON.parse_string(info.json)
	if not gltf is Dictionary:
		out.error = "bad glTF JSON"
		return out
	out.error = _check_gltf(gltf, info, bytes, lim, out)
	return out


static func _check_gltf(gltf: Dictionary, info: Dictionary, bytes: PackedByteArray, lim: Dictionary, out: Dictionary) -> String:
	if gltf.get("asset", {}).get("version") != "2.0":
		return "not glTF 2.0"
	for key in ["extensionsUsed", "extensionsRequired"]:
		for ext: String in gltf.get(key, []):
			if ext not in GLTF_EXTENSIONS:
				return "glTF extension not allowed: " + ext
	if gltf.get("nodes", []).size() > lim.max_nodes:
		return "too many nodes"
	if gltf.get("materials", []).size() > lim.max_materials:
		return "too many materials"

	var buffers: Array = gltf.get("buffers", [])
	for buffer: Dictionary in buffers:
		if buffer.has("uri"):
			return "external buffers not allowed"
	if buffers.size() > 1 or (buffers.size() == 1 and buffers[0].get("byteLength", 0) > info.bin_length):
		return "buffer doesn't fit the BIN chunk"
	var views: Array = gltf.get("bufferViews", [])
	for view: Dictionary in views:
		if int(view.get("buffer", -1)) != 0 or view.get("byteOffset", 0) + view.get("byteLength", 0) > info.bin_length:
			return "buffer view out of bounds"

	var accessors: Array = gltf.get("accessors", [])
	for acc: Dictionary in accessors:
		var elem: int = COMPONENT_BYTES.get(int(acc.get("componentType", 0)), 0) * TYPE_COMPONENTS.get(acc.get("type", ""), 0)
		if elem == 0:
			return "bad accessor type"
		if acc.has("bufferView"):
			var vi := int(acc.bufferView)
			if vi < 0 or vi >= views.size():
				return "bad accessor view"
			var view: Dictionary = views[vi]
			var stride: int = view.get("byteStride", elem)
			var need: int = acc.get("byteOffset", 0) + (int(acc.get("count", 0)) - 1) * stride + elem
			if acc.get("count", 0) > 0 and need > view.get("byteLength", 0):
				return "accessor out of bounds"

	for mesh: Dictionary in gltf.get("meshes", []):
		for prim: Dictionary in mesh.get("primitives", []):
			var mode := int(prim.get("mode", 4))
			var source_index: Variant = prim.get("indices", prim.get("attributes", {}).get("POSITION"))
			if source_index == null or int(source_index) >= accessors.size():
				return "primitive without vertices"
			var count := int(accessors[int(source_index)].get("count", 0))
			out.triangles += count / 3 if mode == 4 else maxi(count - 2, 0) if mode in [5, 6] else 0

	for image: Dictionary in gltf.get("images", []):
		if image.has("uri") or not image.has("bufferView"):
			return "external images not allowed"
		if image.get("mimeType") not in ["image/png", "image/jpeg"]:
			return "images must be PNG or JPEG"
		var view: Dictionary = views[int(image.bufferView)] if int(image.bufferView) < views.size() else {}
		var start: int = info.bin_offset + view.get("byteOffset", 0)
		var size: Vector2i = NossPackage.image_size(bytes.slice(start, start + mini(view.get("byteLength", 0), 65536)))
		if size == Vector2i.ZERO:
			return "unreadable image"
		if size.x > lim.max_texture_size or size.y > lim.max_texture_size:
			return "texture larger than %d" % lim.max_texture_size
		out.texture_bytes += size.x * size.y * 4
	return ""


## Runtime glTF textures come without mipmaps, which shimmer at a distance.
static func _add_mipmaps(state: GLTFState) -> void:
	for texture in state.get_images():
		if texture is ImageTexture:
			var image := texture.get_image()
			if image and not image.is_compressed() and not image.has_mipmaps():
				image.generate_mipmaps()
				texture.set_image(image)


## Drops cameras and animation players a model may carry.
static func _strip(scene: Node) -> void:
	for node in scene.find_children("*", "Camera3D", true, false) + scene.find_children("*", "AnimationPlayer", true, false):
		node.get_parent().remove_child(node)
		node.free()


class _Job:
	var task := -1
	var on_done: Callable
	var done := false

	func finish(pkg: VehiclePackage) -> void:
		WorkerThreadPool.wait_for_task_completion(task)
		if done:
			pkg.free_scenes() # timed out earlier
			return
		done = true
		if not on_done.is_valid(): # whoever asked is gone (left the screen meanwhile)
			pkg.free_scenes()
			return
		on_done.call(pkg)

	func time_out(path: String) -> void:
		if done:
			return
		done = true
		var pkg := VehiclePackage.new()
		pkg.path = path
		pkg.error = "Load timed out"
		if on_done.is_valid():
			on_done.call(pkg)
