extends Node
## The M6 acceptance build (ROADMAP M6: "a 3 km circuit can be built from scratch"): a track made
## headless with the editor's own commands (TrackDraft), the way the tools make it, then checked:
##   1. 14 points, scaled to make about 3 km
##   2. a hill shaped under the road (its bed cut in), a banked corner, gravel run-off and armco
##   3. dirt painted in, about 1500 trees scattered, grandstands and a pit building
##   4. a 16-car grid, 3 sectors and an AI pin
##   5. no validation errors
##   6. saved, then loaded back the same (content and layout hashes, length)
## Prints "TRACK_CHECK <file>" for tools/track_check.sh, which then races it (race_check) and sends
## it to a fresh bot online (net_check). Runs as a scene so the autoloads are there:
##   tools/godot.sh --headless res://tests/editor/track_check.tscn -- [--out=<file.nosstrack>]

const LENGTH_M := 3000.0
const TREES := 1500
## The circuit's shape (x, z), scaled to LENGTH_M.
const SHAPE := [
	Vector2(-500, 300), Vector2(-150, 330), Vector2(200, 300), Vector2(450, 240), Vector2(560, 120), Vector2(540, -60),
	Vector2(420, -170), Vector2(230, -150), Vector2(80, -230), Vector2(-100, -260), Vector2(-300, -200), Vector2(-420, -80),
	Vector2(-560, 20), Vector2(-600, 180),
]

var opts := { "out": "user://tests/track_check/acceptance_ring.nosstrack" }
var _fails: Array[String] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_run.call_deferred()


func _run() -> void:
	seed(1) # the same trees every time
	Settings.use_folder("user://tests/track_check")
	var t0 := Time.get_ticks_msec()
	var d := TrackDraft.blank("Acceptance Ring", Vector2i(6, 5))
	_road(d)
	_shape(d)
	_dress(d)
	_race(d)
	var built_ms := Time.get_ticks_msec() - t0
	var t := d.track()
	print("track_check: %.2f km, %d points, %d trees, built in %d ms" % [t.length / 1000.0, d.points().size(), d.scatter_of("tree_pine").size() / 4, built_ms])
	# 5. Clean.
	var found := TrackValidator.check(d)
	for p: Dictionary in found:
		print("  %s: %s" % [p.level, p.text])
	if not TrackValidator.errors(found).is_empty():
		_fails.append("validation errors")
	# 6. Saved and loaded back the same.
	var out := String(opts.out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	DirAccess.remove_absolute(out)
	var t1 := Time.get_ticks_msec()
	var saved := d.save(out)
	if not saved.ok:
		_fails.append("save: " + String(saved.error))
	else:
		var pkg := TrackLoader.load_package(out)
		print("  saved %.1f MB in %d ms; loaded in %.0f ms" % [FileAccess.get_file_as_bytes(out).size() / 1048576.0, Time.get_ticks_msec() - t1 - int(pkg.load_ms), pkg.load_ms])
		if not pkg.ok():
			_fails.append("load: " + pkg.error)
		else:
			if pkg.hash != TrackLibrary.manifest_hash(out):
				_fails.append("content hash changed")
			if pkg.track.layout_hash != t.layout_hash:
				_fails.append("layout changed")
			if absf(pkg.track.length - t.length) > 0.5:
				_fails.append("length changed: %.1f vs %.1f" % [pkg.track.length, t.length])
			if pkg.layout.props.scatter.is_empty() or pkg.terrain == null:
				_fails.append("props or terrain missing")
	if absf(t.length - LENGTH_M) > 300.0:
		_fails.append("length %.0f m" % t.length)
	for f in _fails:
		print("FAIL " + f)
	if _fails.is_empty():
		print("TRACK_CHECK " + ProjectSettings.globalize_path(out))
		print("PASS")
	get_tree().quit(0 if _fails.is_empty() else 1)


## 1. Points around the shape, then scaled so the lap is LENGTH_M.
func _road(d: TrackDraft) -> void:
	for p: Vector2 in SHAPE:
		d.add_point(d.points().size(), Vector3(p.x, 0, p.y))
	var k := LENGTH_M / d.track().length
	for i in d.points().size():
		var p: Array = d.points()[i].p
		d.move_point(i, Vector3(p[0] * k, 0, p[2] * k))


## 2. A hill the road climbs over (raised, then the road's bed is cut in when it's built), a
## banked corner, gravel run-off and armco where the road runs fastest into a corner.
func _shape(d: TrackDraft) -> void:
	var t := d.track()
	var field := d.terrain.field
	var at := t.samples[t.seg_first[8]]
	var rect := field.rect_around(Vector2(at.x, at.z), 160.0)
	var before := field.region_get(rect)
	for k in 30:
		field.brush(0, Vector2(at.x, at.z), 160.0, 0.5, 0.6, 0.0, 0.03, 1)
	d.terrain_stroke(rect, before, field.region_get(rect))
	# Bank the corner at point 4 into the turn (positive raises the left edge).
	var turn := t.curvature[t.seg_first[4]]
	d.set_attr(PackedInt32Array([3, 4, 5]), "bank_deg", -8.0 if turn > 0.0 else 8.0)
	d.set_attr(PackedInt32Array([3, 4]), "runoff_l", "gravel")
	d.set_attr(PackedInt32Array([3, 4]), "runoff_r", "gravel")
	d.set_attr(PackedInt32Array([5, 6]), "barrier_l", "armco")
	d.set_attr(PackedInt32Array([5, 6]), "barrier_r", "armco")


## 3. Dirt in the infield, trees around, grandstands and a pit building by the start.
func _dress(d: TrackDraft) -> void:
	var field := d.terrain.field
	var middle := Vector2.ZERO
	var rect := field.rect_around(middle, 120.0)
	var before := field.splat_region_get(rect)
	field.paint(TerrainData.LAYERS.find("dirt"), middle, 120.0, 1.0, 0.5)
	d.paint_stroke(rect, before, field.splat_region_get(rect))
	var builder := PropBuilder.new(d.track(), d.terrain)
	var xf := PackedFloat32Array()
	var seed_ := 1
	while xf.size() / 4 < TREES and seed_ < 400:
		var spot := Vector2(randf_range(-800, 800), randf_range(-600, 600))
		xf.append_array(builder.scatter_points("tree_pine", spot, 60.0, 1.0, seed_, Vector2(0.8, 1.3), xf))
		seed_ += 1
	var trees := Array(xf.slice(0, TREES * 4)).map(func(v: float) -> float: return snappedf(v, 0.01))
	d.set_scatter_live("tree_pine", trees)
	d.scatter_stroke("tree_pine", [], trees)
	# By the start straight (points 0 to 1): grandstands outside, the pits inside.
	var t := d.track()
	var s := t.transform_at(t.distances[t.seg_first[0]] + 120.0)
	for k in 2:
		var at := s.origin + s.basis.z * (k * 60.0) + s.basis.x * (t.half_l[0] + 30.0)
		d.add_prop({ "prop": "grandstand", "p": TrackDraft._vec(at), "yaw_deg": rad_to_deg(atan2(s.basis.z.x, s.basis.z.z)), "scale": 1.0, "ground": true, "size": [13.0, 9.9, 50.0] })
	var pits := s.origin + s.basis.z * 30.0 - s.basis.x * (t.half_r[0] + 30.0)
	d.add_prop({ "prop": "pit_building", "p": TrackDraft._vec(pits), "yaw_deg": rad_to_deg(atan2(s.basis.z.x, s.basis.z.z)), "scale": 1.0, "ground": true })


## 4. The start on the first straight, 16 slots, 3 even sectors, and the line pinned in one corner.
func _race(d: TrackDraft) -> void:
	var t := d.track()
	var start := t.distances[t.seg_first[0]] + 200.0
	d.set_race("start_m", snappedf(start, 0.1))
	d.set_race("grid/slots", 16)
	d.set_race("sectors_m", [snappedf(fposmod(start + t.length / 3.0, t.length), 0.1), snappedf(fposmod(start + t.length * 2.0 / 3.0, t.length), 0.1)])
	var apex := t.distances[t.seg_first[10]]
	var c := RacingLine.corridor_at(d.track(), apex)
	d.set_race("ai/pins", [{ "at_m": snappedf(apex, 0.1), "offset_m": snappedf(c.x * 0.5, 0.1) }])
