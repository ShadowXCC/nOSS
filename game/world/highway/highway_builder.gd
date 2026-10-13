class_name HighwayBuilder
extends RefCounted
## What a highway adds to its roads (D106, D107), for the RoadBuilder: lane markings on the
## carriageways and ramps, the median barrier and lamps along it, tunnels, signs before the
## exits, portal mouths (where ramps go into and come out of the city) and crash cushions at the
## gores.

const LINE_WIDTH := RoadBuilder.LINE_WIDTH
const LINE_UP := RoadBuilder.LINE_UP
const DASH_ON := RoadBuilder.DASH_ON
const DASH_OFF := RoadBuilder.DASH_OFF
const LAMP_EVERY_M := 60.0
const LAMP_H := 11.0
const LAMP_REACH := 3.5
const TUNNEL_H := 6.5
const TUNNEL_WALL := 0.6
## Signs this far before each exit (and crossover).
const SIGN_BEFORE_M := [1000.0, 400.0]
const GANTRY_H := 6.8
const PORTAL_H := 6.0
const PORTAL_DEPTH_M := 30.0
## Median barrier [height, thickness] by type.
const MEDIAN := { "concrete": [1.0, 0.6], "armco": [0.75, 0.3], "fence": [2.0, 0.12] }

var road: RoadBuilder
var track: TrackData
var highway: HighwayLayout
## Building one of the highway's ramps (null: the main road).
var ramp: RampData


func _init(rb: RoadBuilder, layout: HighwayLayout, r: RampData = null) -> void:
	road = rb
	track = rb.track
	highway = layout
	ramp = r


## True where `side` (+1 left, -1 right) of sample `k` is open to another road: a ramp's mouth on
## the main road, or a ramp's inner side where it's attached (no barrier, parapet or run-off).
func gapped(k: int, side: float) -> bool:
	if ramp:
		return side > 0.0 and (k < ramp.gore_head or k > ramp.gore_tail)
	return highway.gap(k, side)


# --- lines ---------------------------------------------------------------------------------


## The markings between samples i and j: on the main road a solid line by the median and by the
## outer shoulder (dashed across ramp mouths) and dashed lines between lanes; on a ramp its lane
## edges (none while it's a sliver beside the road) and the line between its lanes.
func lines(b: MeshBatch, i: int, j: int) -> void:
	var dash := fmod(track.distances[i], DASH_ON + DASH_OFF) <= DASH_ON
	if ramp:
		var shoulder := RampData.SHOULDER_M
		var inner_ok := i >= ramp.head_count and j < ramp.tail_start
		for side: float in [1.0, -1.0]:
			if side > 0.0 and not inner_ok:
				continue
			if track.half_l[i] - shoulder > 1.0 and track.half_l[j] - shoulder > 1.0:
				_line(b, i, j, side * (track.half_l[i] - shoulder), side * (track.half_l[j] - shoulder))
		if ramp.lanes > 1 and dash and inner_ok:
			_line(b, i, j, 0.0, 0.0)
		return
	for dir: int in [1, -1]:
		var s := float(-dir)
		var outer := highway.inner + highway.lanes * highway.lane_m
		_line(b, i, j, s * highway.inner, s * highway.inner)
		if dash or not (highway.gap(i, s) or highway.gap(j, s)):
			_line(b, i, j, s * outer, s * outer)
		if dash:
			for m in range(1, highway.lanes):
				var lat := s * (highway.inner + m * highway.lane_m)
				_line(b, i, j, lat, lat)


func _line(b: MeshBatch, i: int, j: int, lat_i: float, lat_j: float) -> void:
	var w := LINE_WIDTH / 2.0
	var pi := track.samples[i] + track.ups[i] * LINE_UP
	var pj := track.samples[j] + track.ups[j] * LINE_UP
	var li := track.lefts[i]
	var lj := track.lefts[j]
	b.quad([pi + li * (lat_i + w), pi + li * (lat_i - w), pj + lj * (lat_j - w), pj + lj * (lat_j + w)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


# --- along the main road (per segment) ------------------------------------------------------


## The median barrier along the centreline, samples [first, end] (taking in the next segment's
## first sample, so pieces built apart meet), lamps every LAMP_EVERY_M, and tunnels.
func main_pieces(out: Dictionary, first: int, end: int) -> void:
	var n := track.samples.size()
	var kind := String(highway.settings.get("median_barrier", "concrete"))
	if MEDIAN.has(kind):
		var path := PackedVector3Array()
		for s in range(end - first + 1):
			path.append(track.samples[(first + s) % n])
		var size: Array = MEDIAN[kind]
		road._batch(out, "median:" + kind).wall(path, size[0], size[1])
	if not road.visual:
		_tunnels(out, first, end)
		return
	for i in range(first, end):
		var k := i % n
		var j := (i + 1) % n
		var at := track.distances[k]
		if floori(at / LAMP_EVERY_M) != floori((track.distances[j] if j > 0 else track.length) / LAMP_EVERY_M) and not highway.in_tunnel(at):
			_lamp(out, k)
	_tunnels(out, first, end)


func _lamp(out: Dictionary, k: int) -> void:
	var base := track.samples[k] + Vector3.UP * 1.0
	var level := Basis(track.lefts[k].slide(Vector3.UP).normalized(), Vector3.UP, track.tangents[k].slide(Vector3.UP).normalized())
	var poles := road._batch(out, "lamps")
	poles.box(base + Vector3.UP * (LAMP_H - 1.0) / 2.0, level, Vector3(0.22, LAMP_H - 1.0, 0.22))
	var heads := road._batch(out, "lamp_heads")
	for side: float in [1.0, -1.0]:
		var arm := base + Vector3.UP * (LAMP_H - 1.2) + level.x * side * LAMP_REACH / 2.0
		poles.box(arm, level, Vector3(LAMP_REACH, 0.12, 0.12))
		heads.box(base + Vector3.UP * (LAMP_H - 1.35) + level.x * side * LAMP_REACH, level, Vector3(0.9, 0.18, 0.35))


## Tunnel shells over zones marked tunnel: a wall outside each barrier, a roof, light strips.
func _tunnels(out: Dictionary, first: int, end: int) -> void:
	var n := track.samples.size()
	for i in range(first, end):
		var k := i % n
		var j := (i + 1) % n
		if not (highway.in_tunnel(track.distances[k]) and highway.in_tunnel(track.distances[j])):
			continue
		var tops := {}
		for side: float in [1.0, -1.0]:
			var out_i := road._edge(k, side, (track.runoff_l_m if side > 0.0 else track.runoff_r_m)[k] + TUNNEL_WALL)
			var out_j := road._edge(j, side, (track.runoff_l_m if side > 0.0 else track.runoff_r_m)[j] + TUNNEL_WALL)
			road._batch(out, "tunnel").wall(PackedVector3Array([out_i, out_j]), TUNNEL_H, TUNNEL_WALL)
			tops[side] = [out_i + Vector3.UP * TUNNEL_H, out_j + Vector3.UP * TUNNEL_H]
		var roof := road._batch(out, "tunnel")
		var l: Array = tops[1.0]
		var r: Array = tops[-1.0]
		roof.quad([l[0], r[0], r[1], l[1]], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]) # underside
		var up := Vector3.UP * 0.5
		roof.quad([r[0] + up, l[0] + up, l[1] + up, r[1] + up], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		if road.visual:
			for side: float in [1.0, -1.0]:
				var lat := side * (highway.inner + highway.lanes * highway.lane_m / 2.0)
				var a := track.samples[k] + track.lefts[k] * lat + Vector3.UP * (TUNNEL_H - 0.08)
				var b := track.samples[j] + track.lefts[j] * lat + Vector3.UP * (TUNNEL_H - 0.08)
				var w := track.lefts[k] * 0.3
				road._batch(out, "tunnel_lights").quad([a - w, a + w, b + w, b - w], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


# --- once per highway -------------------------------------------------------------------------


## Signs before exits and crossovers, portal mouths and crash cushions, as a "Highway" node.
func extras() -> Node3D:
	var node := Node3D.new()
	node.name = "Highway"
	var out := {}
	for r in highway.ramps:
		if r.from.has("dir"):
			for before: float in SIGN_BEFORE_M:
				_sign(out, node, r, before)
		if r.head_count > 0:
			_cushion(out, r, r.gore_head)
		if r.tail_start < r.track.samples.size():
			_cushion(out, r, r.gore_tail)
	for p: Dictionary in highway.portals.values():
		_portal(out, p)
	road._add_batches(node, out)
	return node


## A gantry over direction `dir`'s carriageway `before` m ahead of ramp `r`, its sign facing the
## traffic: the ramp's name (a crossover: "Turn back") and the distance.
func _sign(out: Dictionary, node: Node3D, r: RampData, before: float) -> void:
	var dir := int(r.from.dir)
	var d := fposmod(float(r.from.at_m) - dir * before, track.length)
	if highway.in_tunnel(d):
		return
	var k := track.index_at(d)
	var level := Basis(track.lefts[k].slide(Vector3.UP).normalized(), Vector3.UP, (track.tangents[k] * dir).slide(Vector3.UP).normalized())
	var p := track.point_at(d)
	var inner_leg := p + track.lefts[k] * (-dir * (highway.inner - 0.45))
	var edge: float = track.half_r[k] if dir > 0 else track.half_l[k]
	var outer_leg := p + track.lefts[k] * (-dir * (edge + TrackFormat.HIGHWAY_RUNOFF_M + 1.2))
	var gantry := road._batch(out, "gantry")
	for leg in [inner_leg, outer_leg]:
		gantry.box(leg + Vector3.UP * GANTRY_H / 2.0, level, Vector3(0.4, GANTRY_H, 0.4))
	var mid := (inner_leg + outer_leg) / 2.0 + Vector3.UP * GANTRY_H
	gantry.box(mid, level, Vector3(inner_leg.distance_to(outer_leg) + 0.4, 0.4, 0.4))
	if not road.visual:
		return
	# The board over the outer lanes, facing the oncoming traffic (towards -forward).
	var board_at := p + track.lefts[k] * highway.lane_lateral(dir, 0) * 0.85 + Vector3.UP * (GANTRY_H + 1.1)
	road._batch(out, "sign_board").box(board_at + level.z * 0.15, level, Vector3(8.5, 2.8, 0.15))
	var label := Label3D.new()
	label.name = "Sign_%s_%d" % [r.id, int(before)]
	var place := r.name if r.name else ("Turn back" if r.kind == "link" else "Exit")
	label.text = "%s\n%s" % [place, "%d km" % int(before / 1000.0) if before >= 1000.0 else "%d m" % int(before)]
	label.font_size = 72
	label.outline_size = 0
	label.pixel_size = 0.016
	label.modulate = Color(0.95, 0.95, 0.92)
	label.line_spacing = -8.0
	# Label3D shows its text towards +Z: turn it to face the drivers coming.
	label.transform = Transform3D(Basis(-level.x, level.y, -level.z), board_at - level.z * 0.02)
	node.add_child(label)


## A crash cushion at a gore's nose: between the ramp's inner edge at ramp sample `i` and the road.
func _cushion(out: Dictionary, r: RampData, i: int) -> void:
	var t := r.track
	var inner := t.samples[i] + t.lefts[i] * (t.half_l[i] + 1.0)
	var level := Basis(t.lefts[i].slide(Vector3.UP).normalized(), Vector3.UP, t.tangents[i].slide(Vector3.UP).normalized())
	road._batch(out, "cushion").box(inner + Vector3.UP * 0.45, level, Vector3(0.9, 0.9, 3.0), Vector2(1, 1))


## A portal's mouth: a short tunnel behind the ramp's end (along -forward), with a floor, dark
## walls and roof, a back wall, and a concrete face round the opening.
func _portal(out: Dictionary, p: Dictionary) -> void:
	var width := 0.0
	for r in highway.ramps:
		if r.from.get("portal") == p.id or r.to.get("portal") == p.id:
			width = r.width
	if width <= 0.0:
		return
	var f: Vector3 = p.forward
	var right := f.cross(Vector3.UP).normalized()
	var at: Vector3 = p.p
	var level := Basis(right, Vector3.UP, f)
	var half := width / 2.0 + 1.0
	var inside := at - f * PORTAL_DEPTH_M / 2.0
	var shell := road._batch(out, "portal_dark")
	for side: float in [1.0, -1.0]:
		shell.box(inside + right * side * (half + 0.4) + Vector3.UP * PORTAL_H / 2.0, level, Vector3(0.8, PORTAL_H, PORTAL_DEPTH_M))
	shell.box(inside + Vector3.UP * (PORTAL_H + 0.4), level, Vector3(2.0 * half + 1.6, 0.8, PORTAL_DEPTH_M))
	shell.box(at - f * (PORTAL_DEPTH_M + 0.4) + Vector3.UP * PORTAL_H / 2.0, level, Vector3(2.0 * half + 1.6, PORTAL_H, 0.8))
	road._batch(out, "portal_floor").box(inside + Vector3.DOWN * 0.15, level, Vector3(2.0 * half, 0.3, PORTAL_DEPTH_M))
	var face := road._batch(out, "portal")
	face.box(at + Vector3.UP * (PORTAL_H + 1.5) + f * 0.4, level, Vector3(2.0 * half + 4.0, 3.0, 0.8))
	for side: float in [1.0, -1.0]:
		face.box(at + right * side * (half + 1.5) + Vector3.UP * (PORTAL_H / 2.0) + f * 0.4, level, Vector3(2.2, PORTAL_H, 0.8))
