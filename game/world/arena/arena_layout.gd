class_name ArenaLayout
extends RefCounted
## An arena (type "arena", D138): the road's closed spline is its outline, a flat floor with a
## wall round it. Spawn points and item box clusters are placed, or automatic: a ring of spawns
## part way out, facing the middle; a cluster in the middle and four half way out.

const DEFAULTS := { "floor": "asphalt", "wall": "tyres", "wall_m": 1.2, "spawns": [], "boxes": [] }
const AUTO_SPAWNS := 12
const SPAWN_RING := 0.6
const CLUSTER_BOXES := 4
const CLUSTER_RADIUS_M := 2.0
const CLUSTER_RING := 0.5
## Spawns and boxes keep this far from the wall.
const WALL_MARGIN_M := 1.5

## The track it's on, held weakly: the track holds this (its kart or arena), so a strong link
## back would keep both for ever.
var track: TrackData:
	get:
		return _track.get_ref() if _track else null
	set(value):
		_track = weakref(value) if value else null
var _track: WeakRef
var settings := {}
## The outline in the ground plane (x, z), counter-clockwise.
var outline := PackedVector2Array()
var floor_y := 0.0
var centre := Vector2.ZERO
var area := 0.0
var spawns: Array[Transform3D] = []
## [{p: Vector3 (the cluster's middle, on the floor), count}]
var clusters: Array[Dictionary] = []


static func build(t: TrackData, own: Dictionary) -> ArenaLayout:
	var a := ArenaLayout.new()
	a.track = t
	a.settings = DEFAULTS.duplicate(true)
	for key: String in own:
		a.settings[key] = own[key]
	var ys := 0.0
	for p in t.samples:
		a.outline.append(Vector2(p.x, p.z))
		ys += p.y
	if a.outline.size() < 3:
		return a
	a.floor_y = ys / t.samples.size()
	if Geometry2D.is_polygon_clockwise(a.outline):
		a.outline.reverse()
	a._measure()
	a._spawns()
	a._clusters()
	return a


## Inside the outline, at least `margin` from the wall.
func inside(pos: Vector3, margin := 0.0) -> bool:
	var p := Vector2(pos.x, pos.z)
	if outline.size() < 3 or not Geometry2D.is_point_in_polygon(p, outline):
		return false
	return margin <= 0.0 or wall_distance(p) >= margin


## Distance from `p` (x, z) to the nearest stretch of wall.
func wall_distance(p: Vector2) -> float:
	var best := INF
	var n := outline.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, outline[i], outline[(i + 1) % n])
		best = minf(best, p.distance_to(q))
	return best


## Where the outline is from the middle, looking along `dir` (x, z): its distance.
func reach(dir: Vector2) -> float:
	var far := centre + dir.normalized() * 100000.0
	var best := INF
	var n := outline.size()
	for i in n:
		var hit: Variant = Geometry2D.segment_intersects_segment(centre, far, outline[i], outline[(i + 1) % n])
		if hit is Vector2:
			best = minf(best, centre.distance_to(hit))
	return best if best < INF else 0.0


## The box clusters as rows of points (KartLayout.rows).
func box_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in clusters:
		var points := PackedVector3Array()
		var n := int(c.count)
		for j in n:
			var a := TAU * j / n
			points.append(c.p + Vector3(cos(a), 0, sin(a)) * CLUSTER_RADIUS_M + Vector3.UP * KartLayout.BOX_HEIGHT_M)
		out.append({ "points": points })
	return out


func _measure() -> void:
	# Area and centroid (shoelace).
	var n := outline.size()
	var sum_a := 0.0
	var c := Vector2.ZERO
	for i in n:
		var p := outline[i]
		var q := outline[(i + 1) % n]
		var cross := p.x * q.y - q.x * p.y
		sum_a += cross
		c += (p + q) * cross
	area = absf(sum_a) / 2.0
	centre = c / (3.0 * sum_a) if absf(sum_a) > 1e-6 else outline[0]


func _spawns() -> void:
	var own: Array = settings.spawns
	if not own.is_empty():
		for s: Dictionary in own:
			var p: Array = s.p
			spawns.append(Transform3D(Basis(Vector3.UP, deg_to_rad(float(s.get("yaw_deg", 0.0)))), Vector3(p[0], floor_y, p[2])))
		return
	for i in AUTO_SPAWNS:
		var a := TAU * i / AUTO_SPAWNS
		var dir := Vector2(cos(a), sin(a))
		var at := centre + dir * reach(dir) * SPAWN_RING
		var to_middle := (centre - at).normalized()
		# +Z toward the middle.
		spawns.append(Transform3D(Basis(Vector3.UP, atan2(to_middle.x, to_middle.y)), Vector3(at.x, floor_y, at.y)))


func _clusters() -> void:
	var own: Array = settings.boxes
	if not own.is_empty():
		for b: Dictionary in own:
			var p: Array = b.p
			clusters.append({ "p": Vector3(p[0], floor_y, p[2]), "count": int(b.get("count", CLUSTER_BOXES)) })
		return
	clusters.append({ "p": Vector3(centre.x, floor_y, centre.y), "count": CLUSTER_BOXES })
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var dir := Vector2(cos(a), sin(a))
		var at := centre + dir * reach(dir) * CLUSTER_RING
		clusters.append({ "p": Vector3(at.x, floor_y, at.y), "count": CLUSTER_BOXES })
