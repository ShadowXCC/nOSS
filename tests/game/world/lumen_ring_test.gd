extends GdUnitTestSuite
## The Lumen Ring (D121): the built-in highway comes again the same from its generator (made
## with the editor's commands), passes the checks, and has what its plan says: about 8 km, the
## ramps, a tunnel, a viaduct, runs and traps both ways, a city round it. It's offered as a
## highway, never as a circuit.

const DIR := "res://content/tracks/lumen_ring"


func test_the_generator_makes_the_committed_ring() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/manifest.json"))
	var d: TrackDraft = (load("res://tools/make_lumen_ring.gd") as GDScript).call("build")
	var t := d.track()
	assert_str(t.layout_hash).is_equal(String(manifest.layout))
	assert_array(TrackValidator.errors(TrackValidator.check(d))).is_empty()


func test_the_ring_has_what_its_plan_says() -> void:
	var pkg := TrackLoader.load_package(DIR, {}, { "terrain": false })
	assert_bool(pkg.ok()).is_true()
	var t := pkg.track
	assert_str(t.type).is_equal("highway")
	assert_bool(t.builtin).is_true()
	assert_float(t.length).is_between(8000.0, 8600.0)
	var h := t.highway
	assert_array(Array(h.errors)).is_empty()
	assert_int(h.ramps.size()).is_equal(16)
	assert_int(h.portals.size()).is_equal(12)
	# A crossover from each side, two each way; three interchanges each way.
	for dir: int in [1, -1]:
		assert_int(h.ramps.filter(func(r: RampData) -> bool: return r.kind == "link" and int(r.from.dir) == dir).size()).is_equal(2)
		assert_int(h.ramps.filter(func(r: RampData) -> bool: return r.kind == "exit" and int(r.from.dir) == dir).size()).is_equal(3)
		assert_int(h.traps.filter(func(x: Dictionary) -> bool: return x.dir == dir).size()).is_equal(2)
	assert_int(h.runs.size()).is_equal(3)
	assert_bool(h.zones.any(func(z: Dictionary) -> bool: return z.tunnel and z.name == "Cathedral Tunnel")).is_true()
	var lifted := 0.0
	var tightest := 0.0
	for k in t.samples.size():
		tightest = maxf(tightest, absf(t.curvature[k]))
		if t.samples[k].y > 3.0:
			lifted += t.samples[k].distance_to(t.samples[(k + 1) % t.samples.size()])
	assert_float(lifted).is_greater(1000.0)
	assert_float(1.0 / tightest).is_greater(280.0)
	var towers := 0
	for g: Dictionary in t.raw.props.scatter:
		if String(g.prop).begins_with("tower_"):
			towers += (g.xf as Array).size() / 4
	assert_int(towers).is_equal(600)


func test_it_is_offered_as_a_highway_only() -> void:
	var highways := TrackLibrary.list(false, false, "highway").map(func(e: Dictionary) -> String: return e.id)
	var circuits := TrackLibrary.list(false, false, "circuit").map(func(e: Dictionary) -> String: return e.id)
	assert_array(highways).contains(["lumen_ring"])
	assert_array(circuits).not_contains(["lumen_ring"])
