extends GdUnitTestSuite
## The kart HUD and item assist (D146, ACC-07): the panel names the item once the roulette stops
## and the news says it; with Reduce flashing the roulette reads "Rolling"; a Seeker coming for a
## player shows an arrow and says so; the item assist fires a Bolt at a kart lined up ahead, and
## the results remember it was on.

const FIXTURE := "res://tests/fixtures/tracks/kart_small.json"

var s: TrackSession
var p: SessionPlayer
var ai: Racer


func before() -> void:
	Settings.use_folder("user://tests/kart_hud")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _session(profile_data := {}) -> void:
	Players.clear()
	var slot := Players.primary_slot()
	for key: String in profile_data:
		if key == "assists":
			for a: String in profile_data.assists:
				slot.profile.data.assists[a] = profile_data.assists[a]
		else:
			slot.profile.data[key] = profile_data[key]
	s = TrackSession.new()
	s.track_path = FIXTURE
	s.platform_id = "official.kart.medium"
	s.event = RaceEvent.free_drive()
	s.ai_racers = 1
	add_child(s)
	for i in 900:
		if s.racers.size() == 2 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	p = s.players[0]
	ai = s.racers.filter(func(r: Racer) -> bool: return r != p)[0]
	ai.driver.process_mode = Node.PROCESS_MODE_DISABLED
	_place(ai, -80.0, 0.0)


func after_test() -> void:
	if s:
		s.queue_free()
	await get_tree().process_frame


func _place(r: Racer, at: float, lat: float) -> void:
	var x := s.track.transform_at(fposmod(at, s.track.length), lat)
	r.vehicle.reset_to(x)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _captions() -> Array:
	return p.hud._caption_lines.map(func(l: Array) -> String: return l[0])


func test_the_panel_names_the_item_and_says_it() -> void:
	await _session()
	s.kart.items.give(p, "bolt")
	await _ticks(3)
	var panel: KartPanel = p.hud.get_node("KartPanel")
	assert_object(panel).is_not_null()
	assert_str(panel.item_text()).is_not_equal("Bolt") # still rolling (names going by)
	await _ticks(int(KartItems.ROULETTE_S * 120) + 5)
	assert_str(panel.item_text()).is_equal("Bolt")
	assert_array(_captions()).contains(["Bolt"])
	s.kart.items.use(p)
	await _ticks(2)
	assert_str(panel.item_text()).is_equal("No item")


func test_reduce_flashing_rolls_without_cycling() -> void:
	await _session({ "reduce_flashing": true })
	s.kart.items.give(p, "shield")
	await _ticks(3)
	assert_str((p.hud.get_node("KartPanel") as KartPanel).item_text()).is_equal("Rolling")


func test_a_seeker_coming_shows_an_arrow_and_says_so() -> void:
	await _session({ "sound_arrows": true })
	_place(p, 70.0, 0.0)
	_place(ai, 0.0, 0.0)
	await _ticks(2)
	var at := s.track.transform_at(40.0)
	s.kart.entities.spawn("seeker", ai, at.origin + at.basis.y * 0.6, at.basis.z, p)
	await _ticks(10)
	assert_array(_captions()).contains(["Seeker incoming"])
	assert_array(p.hud._arrows.incoming.map(func(i: Array) -> String: return i[1])).contains(["Seeker"])


func test_the_item_assist_fires_at_a_kart_lined_up() -> void:
	await _session({ "assists": { "item_assist": true } })
	var controller: VehicleController = p.driver
	assert_object(controller.item_policy).is_not_null()
	_place(p, 70.0, 0.0)
	_place(ai, 95.0, 0.0)
	await _ticks(2)
	s.kart.items.give(p, "bolt")
	s.kart.items.slot(p).roulette = 0.0
	var fired := false
	for i in 300:
		await get_tree().physics_frame
		if s.kart.items.item_of(p) == "":
			fired = true
			break
	assert_bool(fired).is_true()
	assert_bool(bool(p.assists_used.get("item_assist", false))).is_true()
