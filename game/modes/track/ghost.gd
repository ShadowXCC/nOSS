class_name Ghost
extends RefCounted
## A recorded lap (docs/GAMEMODES.md §1 "Time trial"): the car's position, rotation, velocity
## and steering 30 times a second, plus who drove it, in what, and how. Replayed with Hermite
## interpolation (positions and velocities), so it moves smoothly at any speed. Saved as JSON
## with the samples packed into base64 floats; files from elsewhere are checked before use.

const SCHEMA := "noss.ghost/1"
const RATE := 30.0
## Floats per sample: t, position (3), rotation (4), velocity (3), steer, speed.
const STRIDE := 13
## Longest lap a ghost may hold (30 minutes).
const MAX_SAMPLES := 54000

## Packed samples, STRIDE floats each.
var data := PackedFloat32Array()
## time, driver, car (path, hash, name), platform (id, hash), track, version, assists, setup,
## game_speed, date.
var meta := {}


func sample_count() -> int:
	return data.size() / STRIDE


func duration() -> float:
	return data[(sample_count() - 1) * STRIDE] if sample_count() > 0 else 0.0


func clear() -> void:
	data.clear()


## Adds the car's state at lap time `t`.
func record(t: float, xform: Transform3D, velocity: Vector3, steer: float) -> void:
	if sample_count() >= MAX_SAMPLES:
		return
	var q := xform.basis.get_rotation_quaternion()
	data.append_array(PackedFloat32Array([t, xform.origin.x, xform.origin.y, xform.origin.z,
		q.x, q.y, q.z, q.w, velocity.x, velocity.y, velocity.z, steer, velocity.length()]))


## The car at lap time `t`: {xform, steer, speed}. Clamped to the recorded lap.
func sample_at(t: float) -> Dictionary:
	var n := sample_count()
	if n == 0:
		return {}
	var i := clampi(_find(t), 0, maxi(n - 2, 0))
	var j := mini(i + 1, n - 1)
	var t0 := data[i * STRIDE]
	var t1 := data[j * STRIDE]
	var span := maxf(t1 - t0, 1e-4)
	var u := clampf((t - t0) / span, 0.0, 1.0)
	var p0 := _vec(i, 1)
	var p1 := _vec(j, 1)
	var v0 := _vec(i, 8)
	var v1 := _vec(j, 8)
	var pos := Motion.hermite(p0, v0, p1, v1, span, u)
	var q := _quat(i).slerp(_quat(j), u)
	return {
		"xform": Transform3D(Basis(q), pos),
		"steer": lerpf(data[i * STRIDE + 11], data[j * STRIDE + 11], u),
		"speed": lerpf(data[i * STRIDE + 12], data[j * STRIDE + 12], u),
	}


func to_dict() -> Dictionary:
	return { "schema": SCHEMA, "meta": meta, "samples": Marshalls.raw_to_base64(data.to_byte_array()) }


## A ghost from a file's contents, or null if it isn't a sound ghost (wrong schema, too long,
## times going backwards, numbers out of reach).
static func from_dict(d: Dictionary) -> Ghost:
	if d.get("schema") != SCHEMA or not d.get("samples") is String or not d.get("meta") is Dictionary:
		return null
	var text: String = d.samples
	if text.length() > MAX_SAMPLES * STRIDE * 4 * 4 / 3 + 16:
		return null
	var g := Ghost.new()
	g.data = Marshalls.base64_to_raw(text).to_float32_array()
	if g.data.size() % STRIDE != 0 or g.sample_count() < 2:
		return null
	var last := -1.0
	for k in g.sample_count():
		var t := g.data[k * STRIDE]
		if not is_finite(t) or t < last:
			return null
		last = t
		for c in range(1, STRIDE):
			if not is_finite(g.data[k * STRIDE + c]) or absf(g.data[k * STRIDE + c]) > 1e6:
				return null
	g.meta = d.meta
	return g


func save(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


static func load_file(path: String) -> Ghost:
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path).size() > 8 << 20:
		return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(d) if d is Dictionary else null


func _find(t: float) -> int:
	# Samples are evenly spaced in time, near enough: start there and walk.
	var n := sample_count()
	var i := clampi(int(t * RATE), 0, n - 1)
	while i > 0 and data[i * STRIDE] > t:
		i -= 1
	while i + 1 < n and data[(i + 1) * STRIDE] <= t:
		i += 1
	return i


func _vec(i: int, at: int) -> Vector3:
	var k := i * STRIDE + at
	return Vector3(data[k], data[k + 1], data[k + 2])


func _quat(i: int) -> Quaternion:
	var k := i * STRIDE + 4
	return Quaternion(data[k], data[k + 1], data[k + 2], data[k + 3]).normalized()
