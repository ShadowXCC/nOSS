extends GdUnitTestSuite
## Battles (D144) on the arena fixture with four karts: they start on the arena's spawns, held
## until three lights go out; a hit takes a life (one per spin-out) and a Shield blocks it; a kart
## with none left is out (a ghost, no items, no EMP); the last one standing wins and the results
## carry lives and hits; a most-hits match ranks by hits, then fewest taken, and ends at its time.

const ARENA := "res://tests/fixtures/tracks/arena_small.json"

var s: TrackSession
var items: KartItems
var battle: BattleControl
var a: Racer
var b: Racer
var c: Racer
var d: Racer
var ended := []


func before() -> void:
	Settings.use_folder("user://tests/battle_control")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func _start(rule: String, minutes := 5) -> void:
	Players.clear()
	ended = []
	s = TrackSession.new()
	s.track_path = ARENA
	s.platform_id = "official.kart.medium"
	s.event = RaceEvent.battle(rule, minutes)
	s.event.ai_count = 3
	s.event.ai_cars = "builtin"
	add_child(s)
	for i in 900:
		if s.racers.size() == 4 and s.racers.all(func(r: Racer) -> bool: return r.vehicle != null and r.driver != null):
			break
		await get_tree().physics_frame
	for r in s.racers:
		r.driver.process_mode = Node.PROCESS_MODE_DISABLED
	s.race.session_ended.connect(func(kind: String, rows: Array) -> void: ended.append([kind, rows]))
	items = s.kart.items
	battle = s.battle
	a = s.racers[0]
	b = s.racers[1]
	c = s.racers[2]
	d = s.racers[3]


func after_test() -> void:
	if s and is_instance_valid(s):
		s.queue_free()
	await get_tree().process_frame


func _running() -> void:
	for i in 120 * 6:
		if s.race.phase == RaceControl.Phase.RUNNING:
			return
		await get_tree().physics_frame


## An item hit, with the grace after the last one over.
func _hit(victim: Racer, attacker: Racer, kind := "bolt") -> void:
	battle._grace.clear()
	items.hit_by(victim, kind, attacker)


func test_karts_start_on_the_spawns_held_until_the_lights() -> void:
	await _start("standing")
	assert_object(battle).is_not_null()
	assert_str(s.race.kind).is_equal("battle")
	var spawns := s.track.arena.spawns
	for r in s.racers:
		assert_bool(r.held).is_true()
		var near := spawns.any(func(x: Transform3D) -> bool: return x.origin.distance_to(r.vehicle.global_position) < 1.5)
		assert_bool(near).override_failure_message("%s not on a spawn" % r.display_name).is_true()
	assert_str(s.race.session_text(a)).is_equal("Ready")
	await _running()
	assert_int(s.race.light_count).is_equal(RaceControl.SHORT_LIGHTS)
	assert_bool(s.racers.any(func(r: Racer) -> bool: return r.held)).is_false()
	assert_str(s.race.session_text(a)).is_equal("5:00")


func test_a_hit_takes_a_life_and_a_shield_blocks_it() -> void:
	await _start("standing")
	await _running()
	items.hit_by(b, "bolt", a)
	assert_int(battle.lives(b)).is_equal(2)
	assert_int(battle.hits(a)).is_equal(1)
	assert_int(battle.taken(b)).is_equal(1)
	# The same spin-out: still two.
	items.hit_by(b, "seeker", c)
	assert_int(battle.lives(b)).is_equal(2)
	assert_int(battle.hits(c)).is_equal(0)
	# A Shield takes the next one.
	battle._grace.clear()
	items.give(b, "shield")
	items.slot(b).roulette = 0.0
	items.use(b)
	items.hit_by(b, "emp", c)
	assert_int(battle.lives(b)).is_equal(2)
	# A kart's own Bolt costs a life but scores for nobody.
	_hit(b, b)
	assert_int(battle.lives(b)).is_equal(1)
	assert_int(battle.hits(b)).is_equal(0)
	assert_int(battle.lives_lost(b)).is_equal(2)


func test_the_last_one_standing_wins() -> void:
	await _start("standing")
	await _running()
	for victim: Racer in [b, c, d]:
		for i in BattleControl.LIVES:
			_hit(victim, a)
		assert_bool(victim.out).is_true()
		if victim != d:
			assert_bool(ended.is_empty()).is_true()
	# Out: a ghost with no items, out of reach of an EMP.
	assert_int(b.vehicle.kart_bits & CarState.KART_OUT).is_not_zero()
	assert_bool(b.ghosted).is_true()
	items.give(b, "bolt")
	items.slot(b).roulette = 0.0
	items.use(b)
	assert_int(s.kart.entities.count("bolt")).is_zero()
	await get_tree().physics_frame
	assert_int(ended.size()).is_equal(1)
	var rows: Array = ended[0][1]
	assert_str(String(ended[0][0])).is_equal("battle")
	assert_object(rows[0].racer).is_same(a)
	assert_int(int(rows[0].lives)).is_equal(3)
	assert_int(int(rows[0].hits)).is_equal(9)
	# Out last, placed higher.
	assert_object(rows[1].racer).is_same(d)
	assert_object(rows[3].racer).is_same(b)
	assert_bool(bool(rows[3].out)).is_true()


func test_out_karts_are_left_alone() -> void:
	await _start("standing")
	await _running()
	for i in BattleControl.LIVES:
		_hit(b, a)
	assert_bool(b.out).is_true()
	# Its slot is empty and stays so; an EMP next to it doesn't touch it.
	assert_str(items.slot(b).item).is_equal("")
	var at := c.vehicle.global_transform
	b.vehicle.reset_to(Transform3D(at.basis, at.origin + at.basis.x * 4.0))
	items.give(c, "emp")
	items.slot(c).roulette = 0.0
	var taken := battle.taken(b)
	items.use(c)
	assert_int(battle.taken(b)).is_equal(taken)
	assert_int(b.vehicle.kart_flags() & VehicleSim.KART_FLAG_SLOWED).is_zero()
	# Ghosted still after a tow sets it down.
	s.kart.tow(b)
	for i in 120 * 3:
		await get_tree().physics_frame
	assert_bool(b.ghosted).is_true()


func test_most_hits_ranks_by_hits_then_fewest_taken() -> void:
	await _start("hits", 1)
	await _running()
	_hit(b, a)
	_hit(c, a)
	_hit(a, c)
	_hit(b, d)
	# Nobody goes out in a most-hits match.
	for i in 4:
		_hit(b, a)
	assert_bool(b.out).is_false()
	# a 6 hits; c 1 hit, 1 taken; d 1 hit, 0 taken; b none.
	var order := battle.standings()
	assert_array(order).is_equal([a, d, c, b])
	# Behind on hits, better odds (the bands go by it).
	assert_int(battle.lives_lost(b)).is_equal(2)
	assert_int(battle.lives_lost(a)).is_equal(0)
	s.race.clock = 60.0 - 0.02
	for i in 4:
		await get_tree().physics_frame
	assert_int(ended.size()).is_equal(1)
	var rows: Array = ended[0][1]
	assert_object(rows[0].racer).is_same(a)
	assert_int(int(rows[0].lives)).is_equal(-1)
	assert_int(int(rows[0].hits)).is_equal(6)


func test_the_results_read_lives_and_hits() -> void:
	await _start("standing")
	await _running()
	for i in BattleControl.LIVES:
		_hit(b, a)
	var rows := []
	for r in battle.standings():
		var row := { "racer": r, "position": rows.size() + 1, "name": r.display_name, "number": r.number, "car": "nOSS Kart",
			"time": -1.0, "best": 0.0, "laps": 0, "penalty": 0.0, "dnf": false, "gap": "", "flagged": false }
		row.merge(battle.row(r))
		rows.append(row)
	var menu := ResultsMenu.new()
	menu.kind = "battle"
	menu.results = rows
	add_child(menu)
	await get_tree().process_frame
	assert_str(menu.row_text(0)).contains("3 lives")
	assert_str(menu.row_text(0)).contains("3 hits")
	assert_str(menu.row_text(3)).contains("out")
	menu.queue_free()
