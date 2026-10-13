class_name RampTemplates
extends RefCounted
## Ready-made ramps (D107): an exit into a portal, an entry out of one, an interchange (an exit
## and an entry, one side of a diamond, their two tunnel mouths side by side), and a crossover
## that leaves one carriageway, climbs over the road in a teardrop and joins the other. A portal
## serves one ramp: its mouth lines up with the ramp's end. Each is laid
## out in the road's frame where it leaves (as if the road ran straight on); the checks catch a
## ramp that cuts into a bending road. Distances are along the road, metres from its point 0.

const TAPER_M := 200.0
## The crossover's loop: radius past the road's outer edge, and its height over the road.
const LOOP_CLEAR_M := 30.0
const FLYOVER_Y := 7.5


## An exit leaving direction `dir` at `at_m`, ending in a new portal `portal_id`.
## Returns {ramp, portal}.
static func exit(t: TrackData, h: Dictionary, dir: int, at_m: float, id: String, portal_id: String, name := "") -> Dictionary:
	var c := _out(h)
	var frame := _frame(t, dir, at_m + dir * TAPER_M)
	var pts := [_at(frame, 60.0, c + 4.0), _at(frame, 140.0, c + 18.0)]
	var end := _at(frame, 260.0, c + 55.0)
	var heading: Vector3 = (end - pts[1]).normalized()
	var portal := _portal(portal_id, name, end, -heading)
	return { "ramp": { "id": id, "name": name, "kind": "exit", "from": { "dir": dir, "at_m": _m(t, at_m) }, "to": { "portal": portal_id },
		"points": pts.map(_point) }, "portal": portal }


## An entry from a new portal `portal_id`, joining direction `dir` (merged by `at_m`).
static func entry(t: TrackData, h: Dictionary, dir: int, at_m: float, id: String, portal_id: String, name := "") -> Dictionary:
	var c := _out(h)
	var frame := _frame(t, dir, at_m - dir * TAPER_M)
	var pts := [_at(frame, -140.0, c + 18.0), _at(frame, -60.0, c + 4.0)]
	var start := _at(frame, -260.0, c + 55.0)
	var heading: Vector3 = (pts[0] - start).normalized()
	var portal := _portal(portal_id, name, start, heading)
	return { "ramp": { "id": id, "name": name, "kind": "entry", "from": { "portal": portal_id }, "to": { "dir": dir, "at_m": _m(t, at_m) },
		"points": pts.map(_point) }, "portal": portal }


## An exit from direction `dir` at `at_m` into a portal, and an entry out of a second portal 60 m
## on, back onto the same carriageway further along: [exit taper 200 m, out 260 m, back 260 m,
## entry taper 200 m], about 980 m of road. Returns {ramps: [exit, entry], portals: [out, in]}.
static func interchange(t: TrackData, h: Dictionary, dir: int, at_m: float, prefix: String, name := "") -> Dictionary:
	var e := exit(t, h, dir, at_m, prefix + "_off", prefix + "_out", name)
	var join_m := at_m + dir * (2.0 * TAPER_M + 580.0)
	var on := entry(t, h, dir, join_m, prefix + "_on", prefix + "_in", name)
	return { "ramps": [e.ramp, on.ramp], "portals": [e.portal, on.portal] }


## A crossover from direction `dir` at `at_m` to the other direction: out to the right, a
## teardrop over the road, and back in on the far side going the other way. Returns {ramp}.
static func crossover(t: TrackData, h: Dictionary, dir: int, at_m: float, id: String, name := "") -> Dictionary:
	var c := _out(h)
	var frame := _frame(t, dir, at_m + dir * TAPER_M)
	var r := c + LOOP_CLEAR_M
	var loop_at := 170.0
	var pts := [_at(frame, 60.0, c + 6.0, 1.2), _at(frame, 130.0, c + 20.0, 3.4)]
	# Round the loop, turning left over the road: from the right side heading on, to the far side
	# heading back.
	for step in range(0, 7):
		var a := PI * step / 6.0
		var y := FLYOVER_Y - 2.9 * absf(cos(a))
		pts.append(_at(frame, loop_at + r * sin(a), r * cos(a), y))
	pts.append_array([_at(frame, 130.0, -(c + 20.0), 3.4), _at(frame, 60.0, -(c + 6.0), 1.2)])
	# It has merged into the other carriageway TAPER_M past where it rejoins (at along 20).
	var to_m := at_m + dir * TAPER_M + dir * (20.0 - TAPER_M)
	# Crossovers are for players changing direction; traffic stays on its carriageway.
	return { "ramp": { "id": id, "name": name, "kind": "link", "from": { "dir": dir, "at_m": _m(t, at_m) },
		"to": { "dir": -dir, "at_m": _m(t, to_m) }, "traffic": false, "points": pts.map(_point) } }


## The ramp's centre, just out: past the road's outer edge by half a 1-lane ramp.
static func _out(h: Dictionary) -> float:
	return TrackFormat.highway_half(h) + (float(TrackFormat.RAMP_DEFAULTS.lane_m) + 2.0 * RampData.SHOULDER_M) / 2.0


## The road's frame at `d`, seen from direction `dir`: origin on the centreline, forward the way
## that carriageway drives, right towards its outer edge.
static func _frame(t: TrackData, dir: int, d: float) -> Dictionary:
	var x := t.transform_at(fposmod(d, t.length))
	return { "o": x.origin, "f": x.basis.z * dir, "r": -x.basis.x * dir }


static func _at(frame: Dictionary, along: float, out: float, y := 0.0) -> Vector3:
	var p: Vector3 = frame.o + frame.f * along + frame.r * out
	p.y = y
	return p


static func _point(p: Vector3) -> Dictionary:
	var out := { "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)] }
	if absf(p.y) > 0.01:
		out.height = "set"
	return out


static func _portal(id: String, name: String, at: Vector3, out_of: Vector3) -> Dictionary:
	return { "id": id, "name": name if name else id.capitalize(), "p": [snappedf(at.x, 0.01), 0.0, snappedf(at.z, 0.01)],
		"yaw_deg": snappedf(rad_to_deg(atan2(out_of.x, out_of.z)), 0.1) }


static func _m(t: TrackData, d: float) -> float:
	return snappedf(fposmod(d, t.length), 0.1)
