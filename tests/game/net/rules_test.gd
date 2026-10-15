extends GdUnitTestSuite
## Server rules and caps (MP-06, PLT-09, D87): plausibility checks, rules applied to a session,
## and a server's own platform.

const CUSTOM := "user://tests/net_rules/platforms/"


func before() -> void:
	Settings.use_folder("user://tests/net_rules")
	ContentStore.root = "user://tests/net_rules/cache"


func after() -> void:
	ContentStore.root = "user://cache/content/"
	Players.clear()
	Settings.use_folder("user://")


func _state(t: float, pos: Vector3, vel: Vector3, flags := 0) -> CarState:
	var s := CarState.new()
	s.id = 3
	s.time = t
	s.xform = Transform3D(Basis.IDENTITY, pos)
	s.velocity = vel
	s.flags = flags
	return s


func test_plausibility() -> void:
	var gt := PlatformLoader.load_official("official.track.gt").platform
	var track := TrackData.load_file("res://content/tracks/proving_ground/track.json")
	var p := Plausibility.for_platform(gt, track)
	assert_float(p.top_speed).is_between(60.0, 110.0)
	assert_float(p.ideal_lap).is_greater(30.0)
	# An honest car: nothing.
	var t := 10.0
	var pos := Vector3(-200, 0, 0)
	for i in 60:
		t += 1.0 / 30.0
		pos += Vector3(40.0 / 30.0, 0, 0)
		assert_array(Array(p.check(_state(t, pos, Vector3(40, 0, 0)), t, track))).is_empty()
	# Landing off a crest: a jolt up and down is no flag; the same along the ground is.
	for vel: Vector3 in [Vector3(40, -8, 0), Vector3(40, 0, 0)]:
		t += 1.0 / 30.0
		pos += Vector3(40.0 / 30.0, 0, 0)
		assert_array(Array(p.check(_state(t, pos, vel), t, track))).is_empty()
	t += 1.0 / 30.0
	pos += Vector3(40.0 / 30.0, 0, 0)
	assert_array(Array(p.check(_state(t, pos, Vector3(50, 0, 0)), t, track))).contains(["acceleration"])
	# A knock (a wall) stops a car hard: no flag; a "knock" that speeds it up is still one.
	var k := Plausibility.for_platform(gt, track)
	var kt := 30.0
	assert_array(Array(k.check(_state(kt, pos, Vector3(40, 0, 0)), kt, track))).is_empty()
	assert_array(Array(k.check(_state(kt + 0.033, pos + Vector3(1.0, 0, 0), Vector3(5, 0, 0), CarState.FLAG_KNOCK), kt + 0.033, track))).is_empty()
	assert_array(Array(k.check(_state(kt + 0.066, pos + Vector3(1.2, 0, 0), Vector3(5, 0, 0)), kt + 0.066, track))).is_empty()
	var cheat := Plausibility.for_platform(gt, track)
	assert_array(Array(cheat.check(_state(kt, pos, Vector3(10, 0, 0)), kt, track))).is_empty()
	assert_array(Array(cheat.check(_state(kt + 0.033, pos + Vector3(0.4, 0, 0), Vector3(20, 0, 0), CarState.FLAG_KNOCK), kt + 0.033, track))).contains(["acceleration"])
	# Too fast, too far, wrong clock.
	assert_array(Array(p.check(_state(t + 0.033, pos + Vector3(1.3, 0, 0), Vector3(200, 0, 0)), t + 0.033, track))).contains(["speed"])
	assert_array(Array(p.check(_state(t + 0.066, pos + Vector3(60, 0, 0), Vector3(40, 0, 0)), t + 0.066, track))).contains(["teleport"])
	assert_array(Array(p.check(_state(t + 3.0, pos, Vector3(40, 0, 0)), t + 0.1, track))).contains(["clock"])
	# A reset that lands 100 m ahead along the track.
	var placed := _state(t + 0.2, pos + Vector3(100, 0, 0), Vector3.ZERO, CarState.FLAG_TELEPORT)
	assert_array(Array(p.check(placed, t + 0.2, track))).contains(["reset ahead"])
	# Strikes: three within the window.
	var q := Plausibility.new()
	assert_bool(q.strike(PackedStringArray(["speed"]), 0.0)).is_false()
	assert_bool(q.strike(PackedStringArray(["speed"]), 20.0)).is_false() # the first expired
	assert_bool(q.strike(PackedStringArray(["speed", "teleport"]), 21.0)).is_true()
	assert_str(q.reasons()).contains("teleport")
	assert_bool(p.check_lap(p.ideal_lap * 0.9)).is_true()
	assert_bool(p.check_lap(p.ideal_lap * 1.05)).is_false()


func test_rules_narrow_a_session() -> void:
	var s: TrackSession = auto_free(TrackSession.new())
	for n: Node in [s.views, s.field, s.race]: # members not in the tree yet
		n.free()
	s.platform = PlatformLoader.load_official("official.track.gt")
	s.mode = GameModes.mode_for("official.track.gt")
	s._apply_server_rules({ "assists": ["abs", "racing_line"], "tuning": "lock", "fitting": "strict", "hotswap": "never" })
	assert_array(AssistRules.allowed(s.platform.platform, s.mode)).contains_exactly_in_any_order(["abs", "racing_line"])
	assert_array(s.mode.tuning.allow).is_empty()
	assert_str(s.fitting_mode).is_equal("strict")
	assert_str(s.hotswap_rule).is_equal("never")
	# The official mode itself is untouched.
	assert_array(GameModes.mode_for("official.track.gt").get("tuning", {}).get("allow", ["*"])).is_not_empty()


func test_a_servers_own_platform() -> void:
	ContentStore.clear()
	DirAccess.make_dir_recursive_absolute(CUSTOM)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/platforms/track/gt.platform.json"))
	data.id = "tester.fast_gt"
	data.name = "Fast GT"
	var path := PlatformLoader.USER_DIR + "tester.fast_gt" + PlatformLoader.SUFFIX
	DirAccess.make_dir_recursive_absolute(PlatformLoader.USER_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var cfg := ServerConfig.defaults()
	cfg.rotation[0]["class"] = "tester.fast_gt"
	assert_bool(cfg.platform(0).ok()).is_false() # custom platforms are off by default
	cfg.caps.custom_platforms = true
	var r := cfg.platform(0)
	assert_str(r.platform.get("name", "")).is_equal("Fast GT")
	# A client gets it by hash into its cache, and uses that copy.
	assert_bool(Net.platform_result("tester.fast_gt", r.hash).ok()).is_false()
	assert_str(ContentStore.put_file("platforms", r.hash, FileAccess.get_file_as_bytes(path))).is_empty()
	assert_bool(Net.platform_result("tester.fast_gt", r.hash).ok()).is_true()
	# An official class from a server must be the same file as here.
	var gt := PlatformLoader.load_official("official.track.gt")
	assert_bool(Net.platform_result("official.track.gt", gt.hash).ok()).is_true()
	assert_bool(Net.platform_result("official.track.gt", "sha256:" + "0".repeat(64)).ok()).is_false()
	DirAccess.remove_absolute(path)
