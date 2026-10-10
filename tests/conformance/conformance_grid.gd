extends RefCounted
## Fitted geometries for the conformance runner (docs/PLATFORMS.md §5): wheelbase x track x
## wheel radius at {min, ref, max} of the platform's ranges, plus edge cases that go through
## Fitting's scaling and clamping. Each config carries a synthetic fit.json.

const GROUND_Y := -0.15
const LEVELS := ["min", "ref", "max"]


## [{id, wheelbase, track, radius, fit}], the reference config first. `quick` keeps the
## reference and the four wheelbase/track corners.
static func configs(platform: Dictionary, quick := false) -> Array[Dictionary]:
	var geo: Dictionary = platform.geometry
	var out: Array[Dictionary] = [_config(platform, "ref", "ref", "ref")]
	for l: String in LEVELS:
		for t: String in LEVELS:
			for r: String in LEVELS:
				if l == "ref" and t == "ref" and r == "ref":
					continue
				if quick and (r != "ref" or l == "ref" or t == "ref"):
					continue
				out.append(_config(platform, l, t, r))
	if quick:
		return out
	var lr: float = geo.wheelbase_m.ref
	var tr: float = geo.track_m.ref
	var rr: float = geo.wheel_radius_m.ref
	# Too small: Fitting scales it up to the minimum wheelbase.
	out.append(_extra(platform, "scaled_small", 0.8 * geo.wheelbase_m.min, 0.8 * tr, 0.8 * tr, 0.8 * rr))
	# Too wide: Fitting moves the wheels in.
	out.append(_extra(platform, "track_clamped", lr, 1.1 * geo.track_m.max, 1.1 * geo.track_m.max, rr))
	# Front and rear tracks differ, as on most real cars.
	out.append(_extra(platform, "asym_track", lr, 1.04 * tr, 0.96 * tr, rr))
	# fit.json's ground line is 3 cm off from where the wheels touch down.
	out.append(_extra(platform, "ground_off", lr, tr, tr, rr, 0.03))
	return out


static func _config(platform: Dictionary, l: String, t: String, r: String) -> Dictionary:
	var geo: Dictionary = platform.geometry
	var id := "ref" if l == "ref" and t == "ref" and r == "ref" else "L%s_T%s_r%s" % [l, t, r]
	var track: float = geo.track_m[t]
	return _extra(platform, id, geo.wheelbase_m[l], track, track, geo.wheel_radius_m[r])


static func _extra(platform: Dictionary, id: String, wheelbase: float, track_front: float, track_rear: float, radius: float, hub_lift := 0.0) -> Dictionary:
	return {
		"id": id, "wheelbase": wheelbase, "track": (track_front + track_rear) / 2.0, "radius": radius,
		"fit": synthetic_fit(platform, wheelbase, track_front, track_rear, radius, hub_lift),
	}


## A fit.json for a box car with four wheels at the given geometry, ground at GROUND_Y.
## `hub_lift` raises the hubs above where fit.json's ground line says they should be.
static func synthetic_fit(platform: Dictionary, wheelbase: float, track_front: float, track_rear: float, radius: float, hub_lift := 0.0) -> Dictionary:
	var env: Dictionary = platform.geometry.envelope_m
	var length := (float(env.length[0]) + float(env.length[1])) / 2.0
	var width := (float(env.width[0]) + float(env.width[1])) / 2.0
	var height := (float(env.height[0]) + float(env.height[1])) / 2.0
	var zf := wheelbase / 2.0 + 0.1
	var zr := zf - wheelbase
	var y := GROUND_Y + radius + hub_lift
	var wheels := []
	for w: Array in [["LF", 1, "L", track_front, zf], ["RF", 1, "R", track_front, zf], ["LR", 2, "L", track_rear, zr], ["RR", 2, "R", track_rear, zr]]:
		var x: float = w[3] / 2.0 * (1.0 if w[2] == "L" else -1.0)
		wheels.append({ "id": w[0], "axle": w[1], "side": w[2], "center": [x, y, w[4]], "radius": radius, "width": 0.25 })
	return {
		"schema": "noss.fit/1",
		"model_transform": { "scale": 1.0, "rotation_deg": [0.0, 0.0, 0.0], "offset_m": [0.0, 0.0, 0.0] },
		"ground_y": GROUND_Y,
		"wheel_mode": "model",
		"wheels": wheels,
		"envelope": {
			"min": [-width / 2.0, GROUND_Y, 0.1 - length / 2.0],
			"max": [width / 2.0, GROUND_Y + height, 0.1 + length / 2.0],
		},
	}
