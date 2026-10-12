class_name ModelImport
extends RefCounted
## Brings a GLB, glTF or FBX file into the Fitting Bay (docs/VEHICLE_PACKAGE.md §7 step 1,
## PKG-02), or a scene into the track editor (Track Fitting, with SceneTrack.LIMITS). A GLB that
## already passes the checks is kept byte for byte. Anything else
## (FBX, .gltf with separate files, external or WebP textures, oversized textures) is
## re-exported through Godot into a plain GLB. Either way the result is parsed again, so the
## Fitting Bay sees exactly the scene the game will load. Parsing runs on a worker thread.

const EXTENSIONS := ["glb", "gltf", "fbx"]
## Source files can be bigger than packages: an FBX or a .gltf shrinks when packed.
const MAX_SOURCE_BYTES := 200 << 20
const TIMEOUT_S := 90.0
## A whole scene takes longer.
const SCENE_TIMEOUT_S := 180.0
## Compressed geometry Godot can't decode.
const UNSUPPORTED := {
	"KHR_draco_mesh_compression": "Draco", "EXT_meshopt_compression": "meshopt", "KHR_meshopt_compression": "meshopt",
}


class Result:
	var path := ""
	var error := ""
	## The GLB to store as model/body.glb.
	var glb := PackedByteArray()
	## That GLB, parsed. Owned by whoever takes the result.
	var scene: Node3D
	## True if the source was converted rather than kept as it was.
	var converted := false
	var triangles := 0
	var notes := PackedStringArray()

	func ok() -> bool:
		return error.is_empty()


## Imports on a worker thread; `on_done` gets the Result on the main thread.
static func import_async(path: String, on_done: Callable, limits := PackageLoader.DEFAULT_LIMITS, timeout_s := TIMEOUT_S) -> void:
	var job := _Job.new()
	job.on_done = on_done
	job.task = WorkerThreadPool.add_task(func() -> void:
		var result := import_file(path, limits)
		job.finish.call_deferred(result), true, "Import " + path.get_file())
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.create_timer(timeout_s, true, false, true).timeout.connect(job.time_out.bind(path))


## Blocking import. Check ok() on the result. `limits`: a car's (PackageLoader) or a scene's.
static func import_file(path: String, limits := PackageLoader.DEFAULT_LIMITS) -> Result:
	var r := Result.new()
	r.path = path
	var os_path := ProjectSettings.globalize_path(path)
	var ext := os_path.get_extension().to_lower()
	if ext not in EXTENSIONS:
		r.error = "Pick a .glb, .gltf or .fbx file"
		return r
	if not FileAccess.file_exists(os_path):
		r.error = "File not found"
		return r
	var f := FileAccess.open(os_path, FileAccess.READ)
	var size := f.get_length() if f else 0
	if f == null or size > MAX_SOURCE_BYTES:
		r.error = "File too large" if f else "Can't read the file"
		return r
	f.close()

	var scene: Node3D
	if ext == "glb":
		var bytes := FileAccess.get_file_as_bytes(os_path)
		var info: Dictionary = NossPackage.inspect_glb(bytes)
		if not info.ok:
			r.error = "Not a valid GLB: " + String(info.error)
			return r
		var gltf: Variant = JSON.parse_string(info.json)
		if gltf is Dictionary:
			r.error = _unsupported(gltf)
			if r.error:
				return r
		var check := PackageLoader.check_glb(bytes, limits)
		if check.error.is_empty():
			r.glb = bytes # already a clean package model: keep it exactly
		else:
			scene = _parse_glb(bytes, os_path.get_base_dir() + "/") # external textures sit next to the file
	elif ext == "gltf":
		var gltf: Variant = JSON.parse_string(FileAccess.get_file_as_string(os_path))
		if not gltf is Dictionary:
			r.error = "Not a valid glTF file"
			return r
		r.error = _unsupported(gltf)
		if r.error:
			return r
		scene = _parse_file(GLTFDocument.new(), GLTFState.new(), os_path)
	else:
		scene = _parse_file(FBXDocument.new(), FBXState.new(), os_path)

	if r.glb.is_empty():
		if scene == null:
			r.error = "Model failed to load"
			return r
		r.converted = true
		r.glb = export_glb(scene, limits)
		scene.free()
		if r.glb.is_empty():
			r.error = "Model failed to convert"
			return r
	var check := PackageLoader.check_glb(r.glb, limits)
	if check.error:
		r.error = "Model can't be used: " + check.error
		return r
	r.triangles = check.triangles
	if check.triangles > int(limits.max_lod0_triangles):
		r.error = "Too many triangles: %d" % check.triangles
		return r
	r.scene = _parse_glb(r.glb, "")
	if r.scene == null:
		r.error = "Model failed to load"
	return r


## A scene as a package GLB: everything visible, textures within the size limit. Returns
## empty bytes if the export fails or the result is still too large.
static func export_glb(scene: Node3D, limits := PackageLoader.DEFAULT_LIMITS) -> PackedByteArray:
	for node in [scene] + scene.find_children("*", "Node3D", true, false):
		(node as Node3D).visible = true # a hidden node would require KHR_node_visibility
	_limit_textures(scene, int(limits.max_texture_size))
	for format in ["PNG", "JPEG"]:
		var doc := GLTFDocument.new()
		doc.image_format = format
		doc.lossy_quality = 0.9
		var state := GLTFState.new()
		if doc.append_from_scene(scene, state) != OK:
			return PackedByteArray()
		var bytes := doc.generate_buffer(state)
		if bytes.size() <= int(limits.max_zip_bytes):
			return bytes
	return PackedByteArray()


static func _unsupported(gltf: Dictionary) -> String:
	for ext: String in gltf.get("extensionsRequired", []):
		if UNSUPPORTED.has(ext):
			return "%s compression isn't supported. Re-export without it." % UNSUPPORTED[ext]
	return ""


static func _parse_glb(bytes: PackedByteArray, base_dir: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(bytes, base_dir, state) != OK:
		return null
	return _scene(doc, state)


static func _parse_file(doc: GLTFDocument, state: GLTFState, os_path: String) -> Node3D:
	if doc.append_from_file(os_path, state) != OK:
		return null
	return _scene(doc, state)


static func _scene(doc: GLTFDocument, state: GLTFState) -> Node3D:
	PackageLoader._add_mipmaps(state)
	var scene := doc.generate_scene(state) as Node3D
	if scene:
		PackageLoader._strip(scene)
	return scene


## Downscales any texture bigger than `limit`.
static func _limit_textures(scene: Node3D, limit: int) -> void:
	var seen := {}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			for prop in ["albedo_texture", "normal_texture", "metallic_texture", "roughness_texture", "emission_texture", "ao_texture"]:
				var tex := m.get(prop) as ImageTexture
				if tex == null or seen.has(tex):
					continue
				seen[tex] = true
				var image := tex.get_image()
				if image and maxi(image.get_width(), image.get_height()) > limit:
					var k := float(limit) / maxi(image.get_width(), image.get_height())
					if image.is_compressed():
						image.decompress()
					image.resize(maxi(1, int(image.get_width() * k)), maxi(1, int(image.get_height() * k)), Image.INTERPOLATE_LANCZOS)
					tex.set_image(image)


class _Job:
	var task := -1
	var on_done: Callable
	var done := false

	func finish(result: Result) -> void:
		WorkerThreadPool.wait_for_task_completion(task)
		if done:
			if result.scene:
				result.scene.free() # timed out earlier
			return
		done = true
		if not WorkerJob.alive(on_done): # whoever asked is gone (left the screen meanwhile)
			if result.scene:
				result.scene.free()
			return
		on_done.call(result)

	func time_out(path: String) -> void:
		if done:
			return
		done = true
		var result := Result.new()
		result.path = path
		result.error = "Import timed out"
		if WorkerJob.alive(on_done):
			on_done.call(result)
