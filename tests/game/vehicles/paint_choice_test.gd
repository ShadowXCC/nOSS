extends GdUnitTestSuite
## AI paint jobs (Changes.md, D128): one of the car's presets or its own paint, at random; a stock
## colour when it has no presets; choices from elsewhere (a server) are cleaned first.

const PAINT := {
	"presets": [
		{ "name": "Red", "primary": "#C2261D", "secondary": "#F2F2F2", "finish": "solid" },
		{ "name": "Blue", "primary": "#1F4FB5", "finish": "pearl" },
	],
	"slots": { "primary": { "color": "#E8B71A", "finish": "metallic", "materials": ["Paint_Primary"] } },
}


func test_picks_presets_or_its_own_paint() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 200:
		var c := CarVisual.random_paint(PAINT, rng)
		seen[JSON.stringify(c)] = true
	assert_int(seen.size()).is_equal(3)
	assert_bool(seen.has("{}")).is_true() # its own paint
	assert_bool(seen.has(JSON.stringify({ "primary": "#C2261D", "secondary": "#F2F2F2", "finish": "solid" }))).is_true()


func test_no_presets_gives_stock_colours() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var colours := {}
	for i in 100:
		var c := CarVisual.random_paint({ "presets": [], "slots": PAINT.slots }, rng)
		assert_bool(CarVisual.STOCK_COLORS.any(func(s: Array) -> bool: return s[0] == c.primary)).is_true()
		assert_bool(CarVisual.FINISHES.has(c.finish)).is_true()
		colours[c.primary] = true
	assert_int(colours.size()).is_greater(6)
	assert_str(String(CarVisual.random_paint({}).get("primary", ""))).is_not_empty()


func test_clean_paint_drops_bad_values() -> void:
	assert_dict(CarVisual.clean_paint("red")).is_empty()
	assert_dict(CarVisual.clean_paint({ "primary": "#11223344556677", "secondary": 5, "finish": "glitter", "name": "#FFFFFF" })).is_empty()
	assert_dict(CarVisual.clean_paint({ "primary": "#112233", "finish": "chrome", "x": "nope" })).is_equal({ "primary": "#112233", "finish": "chrome" })
	var many := {}
	for i in 10:
		many["slot%d" % i] = "#FFFFFF"
	assert_int(CarVisual.clean_paint(many).size()).is_equal(CarVisual.CHOICE_SLOTS)


func test_apply_choice_paints_the_slots() -> void:
	var pkg := PackageLoader.load_package("res://content/cars/noss_box")
	var platform := PlatformLoader.load_official("official.track.gt").platform
	var visual: CarVisual = auto_free(CarVisual.create(pkg, Fitting.fit(platform, pkg.fit)))
	var primary: ShaderMaterial = visual._paint.primary
	var secondary: ShaderMaterial = visual._paint.secondary
	var before: Color = secondary.get_shader_parameter("paint_color")
	visual.apply_choice({ "primary": "#1F4FB5", "finish": "matte" })
	assert_object(primary.get_shader_parameter("paint_color")).is_equal(Color.html("#1F4FB5"))
	assert_float(primary.get_shader_parameter("roughness")).is_equal(0.75)
	assert_object(secondary.get_shader_parameter("paint_color")).is_equal(before)
	# Its own paint: nothing changes.
	visual.apply_choice({})
	assert_object(primary.get_shader_parameter("paint_color")).is_equal(Color.html("#1F4FB5"))
	pkg.free_scenes()
