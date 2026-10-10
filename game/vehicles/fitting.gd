class_name Fitting
extends RefCounted
## Mounts a package's fit.json on a platform (docs/PLATFORMS.md §4.1, §4.3): scale if the
## wheelbase is out of range, clamp the track, clamp the collision envelope.
## The vehicle body's frame is the fitted model frame: +Y up, +Z forward, +X left, metres.


## Result of fit(). Positions are in the vehicle body frame.
class Result:
	var scale := 1.0
	## Model transform from fit.json, with the fitting scale applied.
	var model_xform := Transform3D.IDENTITY
	var wheels: Array[Dictionary] = [] # {id, axle, side, center: Vector3, radius, width, shift}
	var wheelbase := 0.0
	var track := 0.0
	var ground_y := 0.0
	## Collision box (clamped), and the unclamped model bounds.
	var envelope := AABB()
	var model_bounds := AABB()
	var eye_point := Vector3.ZERO
	## Player-facing notes such as "Scaled to 92%" or "Wheels moved 4 cm in".
	var notes := PackedStringArray()


static func fit(platform: Dictionary, fit_data: Dictionary) -> Result:
	var r := Result.new()
	var geo: Dictionary = platform.geometry
	var mt: Dictionary = fit_data.model_transform
	var rot: Array = mt.rotation_deg
	var base := Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2]))).scaled(Vector3.ONE * float(mt.scale)),
		_vec(mt.offset_m))

	# 1. Measure in the model's own transform.
	var centers := {}
	for w: Dictionary in fit_data.wheels:
		centers[w.id] = base * _vec(w.center)
	var front: Array = fit_data.wheels.filter(func(w: Dictionary) -> bool: return int(w.axle) == 1)
	var rear: Array = fit_data.wheels.filter(func(w: Dictionary) -> bool: return int(w.axle) == _last_axle(fit_data))
	var wheelbase := _mean_z(front, centers) - _mean_z(rear, centers)
	var track := _mean_track(fit_data.wheels, centers)

	# 2. Uniform scale if the wheelbase is out of range.
	var lb: Dictionary = geo.wheelbase_m
	if wheelbase > 0.0 and (wheelbase < lb.min or wheelbase > lb.max):
		r.scale = clampf(wheelbase, lb.min, lb.max) / wheelbase
		r.notes.append("Scaled to %d%%" % roundi(r.scale * 100.0))
	r.model_xform = Transform3D(Basis.from_scale(Vector3.ONE * r.scale), Vector3.ZERO) * base
	r.wheelbase = wheelbase * r.scale
	track *= r.scale

	# 3. Clamp the track by moving wheels along the axle.
	var tb: Dictionary = geo.track_m
	var shift := 0.0
	if track > 0.0 and (track < tb.min or track > tb.max):
		shift = (clampf(track, tb.min, tb.max) - track) / 2.0
		r.notes.append("Wheels moved %d cm %s" % [roundi(absf(shift) * 100.0), "out" if shift > 0.0 else "in"])
		track = clampf(track, tb.min, tb.max)
	r.track = track

	for w: Dictionary in fit_data.wheels:
		var c: Vector3 = Transform3D(Basis.from_scale(Vector3.ONE * r.scale), Vector3.ZERO) * centers[w.id]
		var side_shift := shift if w.side == "L" else -shift if w.side == "R" else 0.0
		c.x += side_shift
		r.wheels.append({
			"id": w.id, "axle": int(w.axle), "side": w.side, "center": c,
			"radius": float(w.radius) * r.scale * float(mt.scale), "width": float(w.width) * r.scale * float(mt.scale),
			"shift": side_shift,
		})
	r.ground_y = r.scale * (base * Vector3(0, float(fit_data.ground_y), 0)).y

	# 4. Envelope: model bounds, clamped to the platform's box (§4.3).
	var env: Dictionary = fit_data.envelope
	r.model_bounds = r.model_xform * AABB(_vec(env.min), _vec(env.max) - _vec(env.min))
	var size := r.model_bounds.size
	var limits: Dictionary = geo.envelope_m
	var clamped := Vector3(
		clampf(size.x, limits.width[0], limits.width[1]),
		clampf(size.y, limits.height[0], limits.height[1]),
		clampf(size.z, limits.length[0], limits.length[1]))
	var center := r.model_bounds.get_center()
	r.envelope = AABB(Vector3(center.x - clamped.x / 2.0, r.model_bounds.position.y, center.z - clamped.z / 2.0), clamped)

	if fit_data.get("eye_point") is Array:
		r.eye_point = r.model_xform * _vec(fit_data.eye_point)
	else:
		# Auto: driver's side, a little behind the middle, below the roof.
		r.eye_point = Vector3(r.track * 0.22, r.model_bounds.end.y - 0.18, center.z - 0.1)
	return r


static func _last_axle(fit_data: Dictionary) -> int:
	var last := 1
	for w: Dictionary in fit_data.wheels:
		last = maxi(last, int(w.axle))
	return last


static func _mean_z(wheels: Array, centers: Dictionary) -> float:
	var total := 0.0
	for w: Dictionary in wheels:
		total += centers[w.id].z
	return total / maxf(wheels.size(), 1)


## Average distance between left and right hub centers over the axles that have both.
static func _mean_track(wheels: Array, centers: Dictionary) -> float:
	var sum := 0.0
	var count := 0
	for left: Dictionary in wheels:
		if left.side != "L":
			continue
		for right: Dictionary in wheels:
			if right.side == "R" and right.axle == left.axle:
				sum += centers[left.id].x - centers[right.id].x
				count += 1
	return sum / count if count else 0.0


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
