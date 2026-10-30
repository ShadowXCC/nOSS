extends GdUnitTestSuite
## Liveries in races (docs/VEHICLE_PACKAGE.md §12): players wear theirs, AI a saved one for its
## car or a built-in's stock one (paint presets only under a livery without base paint), numbers
## are each racer's own, cups keep each AI's, and police and ghosts stay plain.

const BOX := "res://content/cars/noss_box"
const ROOT := "user://tests/racer_liveries/"

var _was := ""
var _made: Array[String] = []


func before() -> void:
	Settings.use_folder("user://tests/session_suite")


func after() -> void:
	Players.clear()
	Settings.use_folder("user://")


func before_test() -> void:
	_was = LiveryStore.root
	LiveryStore.root = ROOT


func after_test() -> void:
	for path in _made:
		LiveryStore.delete_car(String(PackageLoader.read_manifest(path).get("id", "")))
		DirAccess.remove_absolute(path)
	_made.clear()
	LiveryStore.root = _was


func _wait_for_cars(s: TrackSession) -> void:
	for i in 600:
		await get_tree().process_frame
		if not s.racers.is_empty() and s.racers.all(func(p: Racer) -> bool: return p.vehicle != null):
			return


func test_built_in_cars_wear_their_stock_livery() -> void:
	Players.clear()
	var s := TrackSession.new()
	s.autodrive = true
	s.ai_racers = 3
	s.ai_builtin_cars = true
	add_child(s)
	await _wait_for_cars(s)
	for r in s.racers:
		var id := String(r.vehicle.package.manifest.id)
		assert_bool(LiveryStore.is_builtin(id)).is_true()
		var stock := LiveryStore.builtin(id)
		assert_str(String(r.vehicle.visual.livery.get("id", ""))).override_failure_message(r.display_name).is_equal(String(stock.id))
		assert_str(r.vehicle.visual.livery_number).is_equal(str(r.number))
		if r is AiRacer:
			# No base paint in a stock livery: the AI's own paint shows under it (D128).
			assert_object((r as AiRacer).paint).is_not_null()
	s.queue_free()
	await get_tree().process_frame


## An AI in a garage car wears one of its saved liveries; one with its own base paint takes no
## preset over it.
func test_ai_in_a_garage_car() -> void:
	var copy := GarageFiles.copy_car(BOX)
	_made.append(copy.path)
	var id := String(PackageLoader.read_manifest(copy.path).id)
	var l := LiveryData.new_livery("Team", { "id": id })
	l.base = { "primary": { "color": "#102030", "finish": "matte" } }
	l.layers.append(LiveryData.new_layer("shape", Vector3(0.9, 0.6, 0.0), Vector3.RIGHT, Vector3.FORWARD, Vector2.ONE, "star"))
	LiveryStore.save_car(id, [LiveryData.clean(l)], "")
	var a := AiRacer.new()
	a.configure(0, 80.0)
	var platform := PlatformLoader.load_official("official.track.gt")
	a.vehicle = Vehicle.create(platform, PackageLoader.load_package(copy.path))
	add_child(a.vehicle)
	a._mounted()
	assert_str(String(a.vehicle.visual.livery.name)).is_equal("Team")
	assert_object(a.paint).is_null()
	var primary: ShaderMaterial = a.vehicle.visual._paint.primary
	assert_str((primary.get_shader_parameter("paint_color") as Color).to_html(false)).is_equal("102030")
	assert_object(primary.shader).is_equal(CarVisual.LIVERY_SHADER)
	# A swap to another car picks again: that car's liveries.
	a.vehicle.mount(PackageLoader.load_package(BOX))
	a._mounted()
	assert_str(a.livery_car).is_equal("6e0c6a51-5d0f-4a2b-9a52-3b1f0d7c2e11")
	assert_str(String(a.vehicle.visual.livery.id)).is_equal(String(LiveryStore.builtin(a.livery_car).id))
	a.vehicle.free()
	a.free()


## Police and ghosts (any racer that isn't a player, an AI or someone online) stay plain.
func test_others_stay_plain() -> void:
	var r := Racer.new()
	var platform := PlatformLoader.load_official("official.track.gt")
	r.vehicle = Vehicle.create(platform, PackageLoader.load_package(BOX))
	add_child(r.vehicle)
	r._mounted()
	assert_dict(r.vehicle.visual.livery).is_empty()
	r.vehicle.free()
	r.free()


## A test drive from the bay wears the draft's livery, not the stored one.
func test_a_test_drive_wears_the_draft() -> void:
	var draft := FittingDraft.new()
	draft.id = "0b7a4c1e-3333-4a2b-9a52-3b1f0d7c2e11"
	var l := LiveryData.new_livery("Draft")
	draft.liveries = [l]
	draft.worn = l.id
	var pkg := VehiclePackage.new()
	pkg.path = draft.draft_dir()
	pkg.manifest = { "id": draft.id }
	var was: Variant = Game.bay_draft
	Game.bay_draft = draft
	assert_str(String(LiveryStore.worn(pkg).name)).is_equal("Draft")
	Game.bay_draft = was
	assert_dict(LiveryStore.worn(pkg)).is_empty()


## A cup keeps each AI's livery from race to race, with its paint.
func test_a_cup_keeps_the_liveries() -> void:
	var cup := CupRun.new()
	var s := TrackSession.new()
	var a := AiRacer.new()
	a.configure(1, 70.0)
	a.platform = PlatformLoader.load_official("official.track.gt")
	a.vehicle = Vehicle.create(a.platform, PackageLoader.load_package(BOX))
	add_child(a.vehicle)
	a._mounted()
	s.racers.append(a)
	cup.keep_roster(s)
	assert_int(cup.roster.size()).is_equal(2)
	assert_str(String(cup.roster[1].livery.id)).is_equal(String(a.livery.id))
	assert_str(String(cup.roster[1].livery_car)).is_equal(a.livery_car)
	a.vehicle.free()
	a.free()
	for n: Node in [s.views, s.field, s.race]:
		n.free() # made with the session, added once it's in the tree
	s.free()
