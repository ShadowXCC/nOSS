class_name Fitting
extends RefCounted
## Mounts a package's fit.json on a platform (docs/PLATFORMS.md §4.1, §4.3): scale if the
## wheelbase is out of range (or past the platform's `fit.wheelbase_max_m`: a car on a kart class
## comes down to a kart's size, D150), clamp the track, clamp the collision envelope.
## The vehicle body's frame is the fitted model frame: +Y up, +Z forward, +X left, metres.


## Result of fit(). Positions are in the vehicle body frame.
class Result:
	var scale := 1.0
	## Model transform from fit.json, with the fitting scale applied.
	var model_xform := Transform3D.IDENTITY
	var wheels: Array[Dictionary] = [] # {id, axle, side, center: Vector3, radius, width, shift, drop}
	var wheelbase := 0.0
	var track := 0.0
	var ground_y := 0.0
	## Ride height (fit.json body_lift_m, scaled): the wheels sit this much lower on the body.
	var body_lift := 0.0
	## Collision box (clamped), and the unclamped model bounds.
	var envelope := AABB()
	var model_bounds := AABB()
	var eye_point := Vector3.ZERO
	## Hood and bumper camera positions.
	var hood := Vector3.ZERO
	var bumper := Vector3.ZERO
	## Player-facing notes such as "Scaled to 92%" or "Wheels moved 4 cm in".
	var notes := PackedStringArray()
	## "normal" or "strict" (physics on the reference geometry, docs/PLATFORMS.md §4.2).
	var mode := "normal"
	## Wheels the sim drives, one per wheel of the platform's layout (§4.4):
	## {axle (1 = front), side, center: Vector3, radius, visual_radius}.
	var physics_wheels: Array[Dictionary] = []
	## Per model wheel (fit.json order), the physics wheels whose motion it shows.
	var wheel_map: Array[PackedInt32Array] = []


## True if a model of `family` (from its manifest) may mount `platform` (docs/PLATFORMS.md §4.4).
static func compatible(platform: Dictionary, family: String) -> bool:
	return family in platform.get("accepts_families", [platform.get("family", "")])


static func fit(platform: Dictionary, fit_data: Dictionary, mode := "normal") -> Result:
	var r := Result.new()
	r.mode = mode
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
	var fit_max := float(platform.get("fit", {}).get("wheelbase_max_m", INF))
	if wheelbase > fit_max and fit_max < float(lb.max):
		r.scale = maxf(fit_max, float(lb.min)) / wheelbase
		r.notes.append("Kart size (%d%%)" % roundi(r.scale * 100.0))
	elif wheelbase > 0.0 and (wheelbase < lb.min or wheelbase > lb.max):
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

	# Ride height: the body rises on its wheels, so they (and the ground) sit lower on it.
	r.body_lift = float(fit_data.get("body_lift_m", 0.0)) * r.scale
	for w: Dictionary in fit_data.wheels:
		var c: Vector3 = Transform3D(Basis.from_scale(Vector3.ONE * r.scale), Vector3.ZERO) * centers[w.id]
		var side_shift := shift if w.side == "L" else -shift if w.side == "R" else 0.0
		c.x += side_shift
		c.y -= r.body_lift
		r.wheels.append({
			"id": w.id, "axle": int(w.axle), "side": w.side, "center": c,
			"radius": float(w.radius) * r.scale * float(mt.scale), "width": float(w.width) * r.scale * float(mt.scale),
			"shift": side_shift, "drop": r.body_lift,
		})
	# The ground is where the driven wheels touch down (_physics_wheels; the sim uses the same
	# plane). A fit.json ground line that disagrees is overruled.
	var declared := r.scale * (base * Vector3(0, float(fit_data.ground_y), 0)).y - r.body_lift
	r.ground_y = declared
	_physics_wheels(r, platform)
	if absf(r.ground_y - declared) > 0.01:
		r.notes.append("Ground moved %d cm" % roundi(absf(r.ground_y - declared) * 100.0))

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

	# Hood and bumper cameras from fit.json, or placed from the eye point and the nose.
	var cams: Dictionary = fit_data.get("cameras") if fit_data.get("cameras") is Dictionary else {}
	r.hood = r.model_xform * _vec(cams.hood) if cams.get("hood") is Array \
			else Vector3(center.x, r.eye_point.y - 0.12, lerpf(r.eye_point.z, r.model_bounds.end.z, 0.62))
	r.bumper = r.model_xform * _vec(cams.bumper) if cams.get("bumper") is Array \
			else Vector3(center.x, r.ground_y + 0.42, r.model_bounds.end.z + 0.03)

	if mode == "strict":
		# The reference box, where the model is.
		var ref_size := Vector3(_mid(limits.width), _mid(limits.height), _mid(limits.length))
		r.envelope = AABB(Vector3(center.x - ref_size.x / 2.0, r.model_bounds.position.y, center.z - ref_size.z / 2.0), ref_size)
	return r


## One physics wheel per wheel of the platform's layout. Platform axle 1 is the model's first
## axle and the platform's last its last; model axles in between are visual only. The ground
## is where these wheels touch down, as the sim works it out. In strict mode the wheels sit at
## the reference wheelbase, track and radius.
static func _physics_wheels(r: Result, platform: Dictionary) -> void:
	var layout: Array = platform.layout.axles
	var geo: Dictionary = platform.geometry
	var model_axles := []
	for w in r.wheels:
		if w.axle not in model_axles:
			model_axles.append(w.axle)
	model_axles.sort()
	var sources := [] # model axle per platform axle
	for a in layout.size():
		var t := float(a) / maxf(layout.size() - 1, 1)
		sources.append(model_axles[roundi(t * (model_axles.size() - 1))])

	var axle_data := []
	for a in layout.size():
		var on_axle: Array = r.wheels.filter(func(w: Dictionary) -> bool: return w.axle == sources[a])
		var d := { "z": 0.0, "y": 0.0, "radius": 0.0, "x_mid": 0.0, "half": -1.0 }
		var lx := []
		var rx := []
		for w: Dictionary in on_axle:
			d.z += w.center.z / on_axle.size()
			d.y += w.center.y / on_axle.size()
			d.radius += w.radius / on_axle.size()
			d.x_mid += w.center.x / on_axle.size()
			if w.side == "L":
				lx.append(w.center.x)
			elif w.side == "R":
				rx.append(w.center.x)
		if not lx.is_empty() and not rx.is_empty():
			var left: float = lx.reduce(func(s: float, x: float) -> float: return s + x, 0.0) / lx.size()
			var right: float = rx.reduce(func(s: float, x: float) -> float: return s + x, 0.0) / rx.size()
			d.half = (left - right) / 2.0
			d.x_mid = (left + right) / 2.0
		axle_data.append(d)
	# An axle without a left/right pair (a centre wheel) takes another axle's track.
	for d: Dictionary in axle_data:
		if d.half < 0.0:
			var paired := axle_data.filter(func(o: Dictionary) -> bool: return o.half >= 0.0)
			d.half = paired[0].half if not paired.is_empty() else float(geo.track_m.ref) / 2.0
	# The mean of the physics wheels' hub height less radius (a false wheel up on the roof, or a
	# raised middle axle, can't lift it).
	var contact := 0.0
	var count := 0
	for a in layout.size():
		var n := int(layout[a].wheels)
		contact += (axle_data[a].y - axle_data[a].radius) * n
		count += n
	if count > 0:
		r.ground_y = contact / count

	var strict := r.mode == "strict"
	var z_mid: float = (axle_data[0].z + axle_data[-1].z) / 2.0
	for a in layout.size():
		var d: Dictionary = axle_data[a]
		var z: float = d.z
		var half: float = d.half
		var radius: float = d.radius
		var y: float = d.y
		if strict:
			var t := float(a) / maxf(layout.size() - 1, 1)
			z = z_mid + float(geo.wheelbase_m.ref) * (0.5 - t)
			half = float(geo.track_m.ref) / 2.0
			radius = float(geo.wheel_radius_m.ref)
			y = r.ground_y + radius
		var sides := ["L", "R"] if int(layout[a].wheels) == 2 else ["C"]
		for side: String in sides:
			var x: float = d.x_mid + (half if side == "L" else -half if side == "R" else 0.0)
			r.physics_wheels.append({
				"axle": a + 1, "side": side, "center": Vector3(x, y, z), "radius": radius, "visual_radius": d.radius,
			})

	# Each model wheel shows the physics wheel on its side of the matching (or nearest) axle.
	for w in r.wheels:
		var best := 0
		for a in layout.size():
			if absf(axle_data[a].z - w.center.z) < absf(axle_data[best].z - w.center.z):
				best = a
		var mapped := PackedInt32Array()
		for j in r.physics_wheels.size():
			var pw: Dictionary = r.physics_wheels[j]
			if pw.axle == best + 1 and (pw.side == w.side or pw.side == "C" or w.side == "C"):
				mapped.append(j)
		r.wheel_map.append(mapped)


static func _mid(range_: Array) -> float:
	return (float(range_[0]) + float(range_[1])) / 2.0


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
