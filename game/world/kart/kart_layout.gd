class_name KartLayout
extends RefCounted
## A track's kart pieces (D136, D137): stunt pieces along the road (circuits) or anywhere
## (arenas), and the item box rows. A track with no rows of its own gets automatic ones, about
## every third of a lap, so kart plays on any track (docs/GAMEMODES.md §2).

const KINDS := ["boost_pad", "item_row", "jump", "wall_ride", "loop"]
## What an arena can hold; the rest need a road.
const ARENA_KINDS := ["boost_pad", "jump"]
const STUNT_DEFAULTS := {
	"boost_pad": { "lateral_m": 0.0, "length_m": 5.0, "width_m": 3.0, "yaw_deg": 0.0 },
	"item_row": { "count": 0 },
	"jump": { "lateral_m": 0.0, "height_m": 1.4, "length_m": 9.0, "width_m": 0.0, "yaw_deg": 0.0 },
	"wall_ride": { "length_m": 120.0, "side": "left", "height_m": 6.0 },
	"loop": { "radius_m": 9.0, "width_m": 5.0 },
}
## A box floats this high over the road; boxes in a row sit about this far apart.
const BOX_HEIGHT_M := 1.0
const BOX_SPACING_M := 3.0
const BOX_MARGIN_M := 1.5
const AUTO_ROWS := 3
## An automatic row moves to the straightest spot within this of its third, clear of pieces.
const ROW_SEARCH_M := 60.0
const ROW_CLEAR_M := 25.0
const ROW_START_CLEAR_M := 40.0
const MAX_BOXES := 64
## A wall-ride's curve, from the road's edge to vertical.
const WALL_CURVE_M := 3.0
## A loop's two lanes are this far apart beyond its width; the exit lane is blocked this far
## before it (the loop comes down there).
const LOOP_GAP_M := 0.5
const LOOP_DIVIDER_M := 6.0
## Every loop gets a boost pad this far before it, in its entry lane (D137).
const LOOP_PAD_M := 25.0

## The track it's on, held weakly: the track holds this (its kart or arena), so a strong link
## back would keep both for ever.
var track: TrackData:
	get:
		return _track.get_ref() if _track else null
	set(value):
		_track = weakref(value) if value else null
var _track: WeakRef
## "auto", "placed" or "none".
var boxes := "auto"
## Every piece, defaults filled in, with "frame": Transform3D (circuits: the road's frame at
## at_m; arenas: p and yaw). Item rows are pieces too.
var pieces: Array[Dictionary] = []
## Box rows and clusters: [{at_m (circuits), points: PackedVector3Array}].
var rows: Array[Dictionary] = []
var _gap_l := PackedByteArray()
var _gap_r := PackedByteArray()


static func build(t: TrackData, section: Dictionary) -> KartLayout:
	var k := KartLayout.new()
	k.track = t
	k.boxes = String(section.get("boxes", "auto"))
	k._gap_l.resize(t.samples.size())
	k._gap_r.resize(t.samples.size())
	for raw: Dictionary in section.get("stunts", []):
		var p := filled(raw)
		p.frame = k._frame(p)
		k.pieces.append(p)
		if p.kind == "wall_ride":
			k._mark_wall(p)
	for p in k.pieces.duplicate():
		if p.kind == "loop" and p.has("at_m"):
			var pad := filled({ "id": String(p.id) + "_pad", "kind": "boost_pad", "at_m": fposmod(float(p.at_m) - LOOP_PAD_M, t.length),
				"lateral_m": k.loop_lanes(p).x, "auto": true })
			pad.frame = k._frame(pad)
			k.pieces.append(pad)
	k._rows()
	return k


## A piece with its kind's defaults filled in.
static func filled(raw: Dictionary) -> Dictionary:
	var p: Dictionary = STUNT_DEFAULTS.get(String(raw.get("kind", "")), {}).duplicate(true)
	p.merge(raw.duplicate(true), true)
	return p


func on_arena() -> bool:
	return track.type == "arena"


## True where a wall-ride stands instead of the barrier.
func gap(k: int, side: float) -> bool:
	if k < 0 or k >= _gap_l.size():
		return false
	return (_gap_l if side > 0.0 else _gap_r)[k] != 0


## Every box, world positions (centres).
func box_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for r in rows:
		out.append_array(r.points)
	return out


func _frame(p: Dictionary) -> Transform3D:
	if on_arena() or p.has("p"):
		var at: Array = p.get("p", [0, 0, 0])
		return Transform3D(Basis(Vector3.UP, deg_to_rad(float(p.get("yaw_deg", 0.0)))), Vector3(at[0], at[1], at[2]))
	return track.transform_at(float(p.get("at_m", 0.0)), float(p.get("lateral_m", 0.0)))


func _mark_wall(p: Dictionary) -> void:
	var side := 1.0 if p.side == "left" else -1.0
	var from := float(p.at_m)
	var steps := int(ceil(float(p.length_m) / TrackData.SAMPLE_M)) + 1
	for s in steps + 1:
		var k := track.index_at(from + s * TrackData.SAMPLE_M)
		(_gap_l if side > 0.0 else _gap_r)[k] = 1


# --- loops ---------------------------------------------------------------------------------

## A loop's entry and exit lanes: laterals on the road, the entry on its left half.
func loop_lanes(p: Dictionary) -> Vector2:
	var i := track.index_at(float(p.at_m))
	var centre := (track.half_l[i] - track.half_r[i]) / 2.0
	var half := float(p.width_m) / 2.0 + LOOP_GAP_M / 2.0
	return Vector2(centre + half, centre - half)


## A point on a loop's ribbon centre, t from 0 (entry, on the road) to 1 (exit, on the road).
func loop_point(p: Dictionary, t: float, lateral := 0.0) -> Vector3:
	var f: Transform3D = p.frame
	var lanes := loop_lanes(p)
	var r := float(p.radius_m)
	var a := TAU * t
	var across := lerpf(lanes.x, lanes.y, t) + lateral
	var at := track.transform_at(float(p.at_m), 0.0)
	return at.origin + f.basis.z * (r * sin(a)) + f.basis.y * (r - r * cos(a)) + f.basis.x * across


## The loop `pos` is on and how far round it is ({piece, t}), or {}: in its plane, above the
## road, near the ribbon.
func loop_progress(pos: Vector3) -> Dictionary:
	for p in pieces:
		if p.kind != "loop":
			continue
		var f: Transform3D = p.frame
		var rel := pos - track.transform_at(float(p.at_m)).origin
		var z := rel.dot(f.basis.z)
		var y := rel.dot(f.basis.y)
		var r := float(p.radius_m)
		if absf(z) > r + 1.5 or y < 0.6 or y > 2.0 * r + 1.5:
			continue
		var t := fposmod(atan2(z, r - y), TAU) / TAU
		var on := loop_point(p, t)
		if pos.distance_to(on) > float(p.width_m) + 1.5:
			continue
		return { "piece": p, "t": t }
	return {}


## The loop `distance` (along the road) is at or just before, within `before` m: {} if none.
## Within a loop's reach of `pos` (in it, or turning into or out of it).
func by_a_loop(pos: Vector3) -> bool:
	for p in pieces:
		if p.kind == "loop":
			var at := (p.frame as Transform3D).origin
			if pos.distance_to(at) < 2.0 * float(p.radius_m) + 12.0:
				return true
	return false


func loop_near(distance: float, before := 60.0, after := 0.0) -> Dictionary:
	for p in pieces:
		if p.kind != "loop":
			continue
		var d := _wrapped(float(p.at_m) - distance)
		if d > -float(p.radius_m) - after and d < before:
			return p
	return {}


## Where a tow puts a kart that fell at `distance` (D132): before a loop, in its entry lane, if
## it fell near one (the road under a loop is no place to land); else on the road there.
func tow_spot(distance: float) -> Transform3D:
	var loop := loop_near(distance, float(STUNT_DEFAULTS.loop.radius_m) + LOOP_DIVIDER_M + 15.0, 10.0)
	if not loop.is_empty():
		var back := float(loop.at_m) - float(loop.radius_m) - LOOP_DIVIDER_M - 20.0
		return track.transform_at(fposmod(back, track.length), loop_lanes(loop).x)
	return track.transform_at(distance)


## Pins for the racing line (D143): into a loop's entry lane before it, out of its exit lane
## after.
func ai_pins() -> Array:
	var out := []
	for p in pieces:
		if p.kind != "loop":
			continue
		var lanes := loop_lanes(p)
		var at := float(p.at_m)
		out.append({ "at_m": fposmod(at - 50.0, track.length), "offset_m": lanes.x })
		out.append({ "at_m": fposmod(at - 3.0, track.length), "offset_m": lanes.x })
		out.append({ "at_m": fposmod(at + 15.0, track.length), "offset_m": lanes.y })
	return out


# --- item boxes ----------------------------------------------------------------------------

func _rows() -> void:
	if on_arena():
		if track.arena and boxes != "none":
			rows = track.arena.box_rows()
		return
	if boxes == "none" or track.samples.size() < 3:
		return
	for p in pieces:
		if p.kind == "item_row":
			rows.append(_row(float(p.at_m), int(p.count)))
	if boxes == "auto" and rows.is_empty():
		for i in AUTO_ROWS:
			var want := track.start_m + track.length * (i + 0.5) / AUTO_ROWS
			rows.append(_row(_row_spot(want), 0))


## The straightest spot within ROW_SEARCH_M of `want`, clear of pieces and the start line.
func _row_spot(want: float) -> float:
	var best := want
	var best_cost := INF
	var step := 4.0
	for s in range(-int(ROW_SEARCH_M / step), int(ROW_SEARCH_M / step) + 1):
		var d := fposmod(want + s * step, track.length)
		if _near_piece(d, ROW_CLEAR_M) or absf(_wrapped(d - track.start_m)) < ROW_START_CLEAR_M:
			continue
		var cost := 0.0
		for o in [-10.0, -5.0, 0.0, 5.0, 10.0]:
			cost += absf(track.curvature[track.index_at(d + o)])
		cost += absf(s) * 1e-5 # nearer its third breaks ties
		if cost < best_cost:
			best_cost = cost
			best = d
	return best


func _row(at: float, count: int) -> Dictionary:
	var i := track.index_at(at)
	var left := track.half_l[i] - BOX_MARGIN_M
	var right := track.half_r[i] - BOX_MARGIN_M
	var n := count if count > 0 else clampi(roundi((left + right) / BOX_SPACING_M), 3, 5)
	var points := PackedVector3Array()
	for j in n:
		var lat := lerpf(left, -right, (j + 0.5) / n)
		var x := track.transform_at(at, lat)
		points.append(x.origin + x.basis.y * BOX_HEIGHT_M)
	return { "at_m": at, "points": points }


func _near_piece(d: float, clear: float) -> bool:
	for p in pieces:
		if not p.has("at_m"):
			continue
		var reach := clear + _extent(p)
		if absf(_wrapped(d - float(p.at_m) - _extent(p) * (1.0 if p.kind == "wall_ride" else 0.0))) < reach:
			return true
	return false


## How far a piece reaches along the road from its at_m (half its length; a wall-ride's runs
## forward, so its middle is length/2 on).
func _extent(p: Dictionary) -> float:
	match String(p.kind):
		"wall_ride":
			return float(p.length_m) / 2.0
		"loop":
			return float(p.radius_m) + LOOP_DIVIDER_M
		"jump", "boost_pad":
			return float(p.length_m) / 2.0
	return 0.0


func _wrapped(d: float) -> float:
	var half := track.length / 2.0
	return fposmod(d + half, track.length) - half
