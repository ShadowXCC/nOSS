extends GdUnitTestSuite
## Colourblind palettes (ACC-02): in each palette, the colours that must differ stay apart for
## the colour vision it's made for (and the default for normal vision).


func _check(palette_id: String, vision: String) -> PackedStringArray:
	var p: Dictionary = Palette.PRESETS[palette_id]
	var close := PackedStringArray()
	for pair: Array in Palette.MUST_DIFFER:
		var a := Palette.simulate(p[pair[0]], vision)
		var b := Palette.simulate(p[pair[1]], vision)
		var d := Palette.difference(a, b)
		if d < Palette.MIN_DIFFERENCE:
			close.append("%s/%s %.1f" % [pair[0], pair[1], d])
	return close


func test_default_palette_for_normal_vision() -> void:
	assert_array(_check("default", "")).is_empty()


func test_deuteranopia_palette() -> void:
	assert_array(_check("deuteranopia", "deuteranopia")).is_empty()


func test_protanopia_palette() -> void:
	assert_array(_check("protanopia", "protanopia")).is_empty()


func test_tritanopia_palette() -> void:
	assert_array(_check("tritanopia", "tritanopia")).is_empty()


func test_custom_colours_override_roles() -> void:
	var profile := PlayerProfile.create("palette_test", { "palette": "custom", "palette_custom": { "good": "#0000ff", "nonsense": "#123456", "bad": "not a colour" } })
	assert_object(Palette.color(profile, "good")).is_equal(Color("#0000ff"))
	assert_object(Palette.color(profile, "bad")).is_equal(Palette.PRESETS.default.bad)


func test_simulation_matches_known_values() -> void:
	# Pure red and green collapse toward each other for a deuteranope.
	var red := Palette.simulate(Color.RED, "deuteranopia")
	var green := Palette.simulate(Color.GREEN, "deuteranopia")
	assert_float(Palette.difference(red, green)).is_less(Palette.difference(Color.RED, Color.GREEN) * 0.5)
