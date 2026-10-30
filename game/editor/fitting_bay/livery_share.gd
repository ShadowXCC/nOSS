class_name LiveryShare
extends RefCounted
## Moving liveries between cars and files (docs/VEHICLE_PACKAGE.md §12): a .nosslivery file
## written or read, or a livery copied from another garage car. On the same model a livery goes
## over as it is; on another it's fitted: every layer is moved by where it was in the first car's
## bounds to the same place in this car's, then cast back onto the body along its normal.

const EXTENSION := ".nosslivery"


## The hash of a model's bytes, as a package's manifest lists it ("sha256:…").
static func model_hash(glb: PackedByteArray) -> String:
	return "sha256:" + PlatformLoader.sha256_hex(glb) if not glb.is_empty() else ""


## A livery as written to a file: cleaned, with the car it's on and its frame.
static func for_file(livery: Dictionary, car: Dictionary, frame: Dictionary) -> PackedByteArray:
	var l := livery.duplicate(true)
	l.car = car
	l.frame = frame
	return LiveryData.to_bytes(LiveryData.clean(l))


## A livery read from a file at `path`, cleaned; {} if it isn't one (or is too big).
static func read_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > LiveryData.MAX_IMPORT_BYTES:
		return {}
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return LiveryData.parse(bytes)


## `livery` made for this car: [livery (a new id), fitted (true if it came from another model)].
## `car`: this car's {id, model, name}; `frame`: its LiveryData.frame_of(); `raycast`: the body
## along a ray in its model space (LiveryEdit.raycast_model).
static func fit(livery: Dictionary, car: Dictionary, frame: Dictionary, raycast: Callable) -> Array:
	var l := livery.duplicate(true)
	l.id = PackageWriter.new_uuid()
	var same := String(livery.get("car", {}).get("model", "")) == String(car.get("model", "")) and String(car.get("model", "")) != ""
	var fitted := not same and livery.has("frame")
	if fitted:
		var src := LiveryData.frame(livery)
		var dst := LiveryData.frame({ "frame": frame })
		var src_xf: Transform3D = src[0]
		var dst_xf: Transform3D = dst[0]
		var src_box: AABB = src[1]
		var dst_box: AABB = dst[1]
		var k := dst_box.size / src_box.size.max(Vector3.ONE * 1e-6)
		var to_dst := dst_xf.affine_inverse()
		for layer: Dictionary in l.layers:
			var at := src_xf * _v(layer.at)
			at = dst_box.position + (at - src_box.position) * k
			var normal := ((src_xf.basis * _v(layer.normal)) / k).normalized()
			var right := (src_xf.basis * _v(layer.right)) * k
			right = (right - normal * right.dot(normal)).normalized()
			# Sizes (in metres, then this model's units) stretch with the car along the layer's own axes.
			var src_scale := src_xf.basis.get_scale().x
			var dst_scale := dst_xf.basis.get_scale().x
			var w := float(layer.size[0]) * src_scale * ((src_xf.basis * _v(layer.right)).normalized() * k).length()
			var h := float(layer.size[1]) * src_scale * ((src_xf.basis * _v(layer.normal).cross(_v(layer.right))).normalized() * k).length()
			layer.size = [w / dst_scale, h / dst_scale]
			layer.depth = float(layer.depth) * src_scale / dst_scale * (k.x + k.y + k.z) / 3.0
			var model_at := to_dst * at
			var model_n := (to_dst.basis * normal).normalized()
			layer.at = _a(model_at)
			layer.normal = _a(model_n)
			layer.right = _a((to_dst.basis * right).normalized())
			# Back onto the body: cast in along the normal from outside it.
			var reach := float(layer.depth) * 4.0 + dst_box.size.length() / dst_scale * 0.5
			var hit: Dictionary = raycast.call(model_at + model_n * reach, -model_n)
			if not hit.is_empty():
				layer.at = _a(hit.position)
	l.car = car
	l.frame = frame
	return [LiveryData.clean(l), fitted]


static func _v(a: Variant) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _a(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
